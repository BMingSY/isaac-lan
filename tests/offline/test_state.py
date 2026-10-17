"""Semantic state tests execute the same modules embedded in the native extension."""

import struct

from hypothesis import given, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, invariant, rule, run_state_machine_as_test
import pytest

from offline_lua import encode

pytestmark = pytest.mark.state


def test_state_bridge_initializes_with_embedded_portable_modules(lua):
    assert lua.call("state_init") == [True, True, "function", "function", "function"]


@pytest.mark.parametrize(
    "cleared,boss", [(False, False), (False, True), (True, False), (True, True)]
)
def test_combat_arrival_closes_doors_and_only_uncleared_boss_trapdoor(lua, cleared, boss):
    closed, trapdoor, animation, rock = lua.call("room_entry", cleared, boss)
    assert closed == (0 if cleared else 2)
    assert rock == 4
    assert trapdoor == (0 if boss and not cleared else 2)
    assert animation == ("Closed" if boss and not cleared else "Opened")


def inventory_value(resources=None, passive=None, actives=None, souls=0, black=0):
    resources = list(resources or [0, 0, 0, 0, 0])
    if len(resources) == 5:
        resources += [False, False]
    actives = actives or [[0, 0] for _ in range(4)]
    counts = dict(passive or {})
    for item, _ in actives:
        if item:
            counts[item] = counts.get(item, 0) + 1
    return [
        0,
        [[item, count] for item, count in sorted(counts.items()) if count],
        actives,
        [0, 0, 0, 0, 0, 0, 0, souls, black],
        resources,
        [0, 0],
        [0, 0],
        [0, 0],
        False,
        0,
        False,
    ]


def entity(identifier, kind=10, variant=0, subtype=0, parent=0, child=0):
    return [
        identifier,
        kind,
        variant,
        subtype,
        123,
        [100, 100],
        [0, 0],
        [],
        [],
        False,
        parent,
        0,
        child,
        0,
    ]


atoms = st.one_of(
    st.booleans(),
    st.integers(-(2**63), 2**63 - 1),
    st.floats(width=32, allow_nan=False, allow_infinity=False),
    st.text(alphabet=st.characters(exclude_categories=("Cs",)), max_size=30),
)
values = st.recursive(atoms, lambda child: st.lists(child, max_size=6), max_leaves=25)


@pytest.mark.property
@given(value=values)
def test_production_codec_round_trip(lua, value):
    assert lua.call("codec", value) == [value]


@pytest.mark.parametrize(
    "payload",
    [
        b"",
        b"\xff",
        b"\x05\x00\x04x",
        b"\x06\xff\xff",
        b"\x00\x00",
        b"\x04" + struct.pack(">f", float("inf")),
        b"\x04" + struct.pack(">f", float("nan")),
    ],
)
def test_production_decoder_rejects_invalid_state(lua, payload):
    assert lua.call("decode", payload.hex())[0] is False


def test_familiar_growth_survives_native_data_invalidation(lua):
    lua.call("entities_reset")
    first = [entity(i, kind=3, variant=1) for i in range(1, 65)]
    lua.call("entities_apply", "0:1", first)
    grown = first + [entity(65, kind=3, variant=1)]
    result = lua.call("entities_apply", "0:1", grown, False, True)
    assert len([value for value in result[0] if value[1] == 3]) == 65
    assert result[2] == 0
    assert lua.call("entities_apply", "0:1", grown) == result
    lua.call("entities_apply", "0:1", [])
    assert not any(value[1] == 3 for value in lua.call("entities_read")[0])


def test_familiar_pool_releases_obsolete_entities_before_spawning(lua):
    lua.call("entities_reset")
    first = [entity(i, kind=3, variant=1) for i in range(1, 65)]
    lua.call("entities_apply", "0:1", first, False, False, 64)
    for start in (2, 65, 129):
        # The new entity arrives first on the wire; its native allocation must
        # not overwrite an old entity that still belongs to this snapshot.
        current = [entity(i, kind=3, variant=1) for i in range(start, start + 64)][::-1]
        result = lua.call("entities_apply", "0:1", current, False, False, 64)
        assert {v[0] for v in result[0] if v[1] == 3} == set(range(start, start + 64))
        assert lua.call("entities_apply", "0:1", current, False, False, 64) == result


def test_native_effect_pool_eviction_during_view_does_not_abort(lua):
    lua.call("entities_reset")
    values = [entity(i, kind=1000, variant=15) for i in range(1, 66)]
    result = lua.call("entities_apply", "0:1", values, False, False, 64)
    assert len([v for v in result[0] if v[1] == 1000]) == 64
    retained = values[-64:]
    stable = lua.call("entities_apply", "0:1", retained, False, False, 64)
    assert lua.call("entities_apply", "0:1", retained, False, False, 64) == stable


def test_player_tear_eviction_recovers_on_later_view(lua):
    lua.call("entities_reset")
    values = [entity(i, kind=2, parent=-1) for i in range(1, 66)]
    result = lua.call("entities_apply", "0:1", values, False, False, 64)
    assert len([v for v in result[0] if v[1] == 2]) == 64
    assert result[1] == 65, "A missing tear must not be respawned repeatedly in one view"
    # Capacity is available again. A still-authoritative missing tear returns,
    # and repeated state no longer allocates or removes anything.
    retained = values[:32]
    recovered = lua.call("entities_apply", "0:1", retained, False, False, 64)
    assert {v[0] for v in recovered[0] if v[1] == 2} == set(range(1, 33))
    assert lua.call("entities_apply", "0:1", retained, False, False, 64) == recovered
    cleared = lua.call("entities_apply", "0:1", [])
    assert not any(v[1] == 2 for v in cleared[0])


@pytest.mark.parametrize("kind,parent", [(2, 0), (9, -1), (4, -1), (7, -1), (10, 0)])
def test_missing_required_entities_still_fail(lua, kind, parent):
    lua.call("entities_reset")
    values = [entity(i, kind=kind, parent=parent) for i in range(1, 3)]
    with pytest.raises(AssertionError, match="Replica identity missing"):
        lua.call("entities_apply", "0:1", values, False, False, 1)


def test_player_tear_spawn_failure_is_bounded_and_retried_on_next_view(lua):
    lua.call("entities_reset")
    tear = entity(1, kind=2)
    tear[11] = -1  # SpawnerEntity may carry ownership without Parent.
    values = [tear, entity(2)]
    result = lua.call("entities_apply", "0:1", values, False, False, False, 1)
    assert {v[0] for v in result[0]} == {-1, 2, 900}
    assert result[1] == 2
    recovered = lua.call("entities_apply", "0:1", values)
    assert {v[0] for v in recovered[0]} == {-1, 1, 2, 900}
    assert lua.call("entities_apply", "0:1", values) == recovered


def test_missing_linked_tear_and_failed_required_spawn_still_fail(lua):
    lua.call("entities_reset")
    with pytest.raises(AssertionError, match="Replica spawn failed"):
        lua.call("entities_apply", "0:1", [entity(1)], False, False, False, 1)
    lua.call("entities_reset")
    linked = [entity(1, kind=2, parent=-1, child=3), entity(2, kind=2, parent=-1), entity(3)]
    with pytest.raises(AssertionError, match="Replica identity missing"):
        lua.call("entities_apply", "0:1", linked, False, False, 1)


@pytest.mark.property
@given(value=st.lists(atoms, min_size=1, max_size=8), offset=st.integers(0, 500))
def test_production_decoder_rejects_truncated_state(lua, value, offset):
    payload = encode(value)
    assert lua.call("decode", payload[: offset % len(payload)].hex())[0] is False


resource_values = st.tuples(
    st.lists(st.integers(0, 99), min_size=5, max_size=5), st.booleans(), st.booleans()
).map(lambda v: v[0] + list(v[1:]))


@pytest.mark.property
@given(
    resources=resource_values,
    counts=st.lists(st.integers(0, 3), min_size=3, max_size=3),
    active_ids=st.lists(st.sampled_from([0, 2, 4]), min_size=4, max_size=4),
    charges=st.lists(st.integers(0, 12), min_size=4, max_size=4),
    souls=st.integers(0, 12),
    black=st.integers(0, 63),
)
def test_inventory_converges_and_repeated_snapshot_has_no_extra_effect(
    lua, resources, counts, active_ids, charges, souls, black
):
    lua.call("inventory_reset", False)
    mask = black & ((1 << ((souls + 1) // 2)) - 1)
    value = inventory_value(
        resources,
        dict(zip([1, 3, 5], counts)),
        list(map(list, zip(active_ids, charges))),
        souls,
        mask,
    )
    first = lua.call("inventory_apply", value, True)
    assert first[0] == value
    assert lua.call("inventory_apply", value, True) == first


def test_ghost_resources_follow_authority_without_rebuilding_hidden_items(lua):
    before = lua.call("inventory_reset", True)
    value = inventory_value([77, 3, 9, 0, 0], {1: 2})
    value[8] = True
    after = lua.call("inventory_apply", value, True)
    assert after[0][4] == value[4]
    before[0][4] = value[4]
    assert after[0] == before[0]
    assert after[1] == before[1]  # No item mutations on a ghost.
    assert lua.call("inventory_apply", value, True) == after


def test_inventory_changes_replace_prior_items_and_preserve_slot_order(lua):
    lua.call("inventory_reset", False)
    first = inventory_value([50, 4, 7, 2, 3], {1: 2, 3: 1}, [[2, 3], [4, 1], [0, 0], [2, 5]])
    first[5:8] = [[1, 2], [3, 0], [0, 7]]
    assert lua.call("inventory_apply", first, True)[0] == first
    second = inventory_value([12, 1, 0, 0, 0], {3: 3}, [[4, 2], [0, 0], [2, 4], [0, 0]])
    second[0], second[9] = 2, 1
    second[5:8] = [[8, 4], [0, 6], [9, 0]]
    result = lua.call("inventory_apply", second, True)
    assert result[0] == second
    assert lua.call("inventory_apply", second, True) == result


@pytest.mark.property
def test_resource_snapshot_action_sequences(lua):
    class ResourceMachine(RuleBasedStateMachine):
        def __init__(self):
            super().__init__()
            lua.call("inventory_reset", False)
            self.expected = [0, 0, 0, 0, 0, False, False]
            self.previous = inventory_value(self.expected.copy())

        @rule(resources=resource_values)
        def apply_authority(self, resources):
            self.expected = resources
            self.previous = inventory_value(resources.copy())
            lua.call("inventory_apply", self.previous, True)

        @rule()
        def repeat_latest(self):
            before = lua.call("inventory_read")
            assert lua.call("inventory_apply", self.previous, True) == before

        @rule()
        def new_run(self):
            lua.call("inventory_reset", False)
            self.expected = [0, 0, 0, 0, 0, False, False]
            self.previous = inventory_value(self.expected.copy())

        @invariant()
        def resources_match_authority(self):
            assert lua.call("inventory_read")[0][4] == self.expected

    run_state_machine_as_test(ResourceMachine)


def test_entity_links_resolve_forward_references_without_duplicate_allocations(lua):
    lua.call("entities_reset")
    values = [entity(3, parent=2), entity(1, child=2), entity(2, parent=1, child=3)]
    first = lua.call("entities_apply", "0:1", values)
    local = [row for row in first[0] if 0 < row[0] < 900]
    assert [(row[0], row[4], row[6]) for row in local] == [(1, 0, 2), (2, 1, 3), (3, 2, 0)]
    assert first[1:] == [3, 0]
    assert lua.call("entities_apply", "0:1", values) == first


def test_entity_removal_preserves_players_and_other_rooms(lua):
    lua.call("entities_reset")
    lua.call("entities_apply", "0:1", [entity(1), entity(2)])
    result = lua.call("entities_apply", "0:1", [])
    assert [row[0] for row in result[0]] == [-1, 900]
    assert result[1:] == [2, 2]


def test_native_segment_cleanup_cannot_unlink_authoritative_body(lua):
    lua.call("entities_reset")
    values = [entity(1, kind=62, child=2), entity(2, kind=62, subtype=1, parent=1)]
    first = lua.call("entities_apply", "0:1", values, True)
    local = [row for row in first[0] if 0 < row[0] < 900]
    assert [(row[0], row[4], row[6]) for row in local] == [(1, 0, 2), (2, 1, 0)]
    assert first[1:] == [2, 1]
    assert lua.call("entities_apply", "0:1", values, True) == first


def test_empty_collectible_pedestal_never_rolls_a_new_item(lua):
    lua.call("entities_reset")
    values = [entity(1, kind=5, variant=100, subtype=0)]
    first = lua.call("entities_apply", "0:1", values)
    pedestal = next(row for row in first[0] if row[0] == 1)
    assert pedestal[3] == 0 and pedestal[9] == 1
    assert lua.call("entities_apply", "0:1", values) == first


@pytest.mark.property
def test_entity_snapshot_action_sequences(lua):
    class EntityMachine(RuleBasedStateMachine):
        def __init__(self):
            super().__init__()
            lua.call("entities_reset")
            self.expected = []

        @rule(ids=st.sets(st.integers(1, 8), max_size=8), kind=st.sampled_from([10, 11]))
        def replace_room_snapshot(self, ids, kind):
            ordered = sorted(ids)
            self.expected = [
                entity(
                    identifier,
                    kind=kind,
                    parent=ordered[i - 1] if i else 0,
                    child=ordered[i + 1] if i + 1 < len(ordered) else 0,
                )
                for i, identifier in enumerate(ordered)
            ]
            # Spawn children first to exercise two-pass relationship restoration.
            lua.call("entities_apply", "0:1", self.expected[::-1])

        @rule()
        def repeat_latest(self):
            before = lua.call("entities_apply", "0:1", self.expected)
            assert lua.call("entities_apply", "0:1", self.expected) == before

        @invariant()
        def identities_and_links_match_authority(self):
            actual = lua.call("entities_read")[0]
            local = [row for row in actual if 0 < row[0] < 900]
            assert [(row[0], row[1], row[4], row[6]) for row in local] == [
                (row[0], row[1], row[10], row[12]) for row in self.expected
            ]
            assert {-1, 900}.issubset(row[0] for row in actual)

    run_state_machine_as_test(EntityMachine)
