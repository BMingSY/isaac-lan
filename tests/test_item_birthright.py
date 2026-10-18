from copy import deepcopy

import pytest

from item_audit import select_cases
from item_birthright_effects import BIRTHRIGHT_SCENARIOS, birthright_checks
from item_trigger_effects import trigger_recipe


def test_birthright_character_scenarios_select_real_start_and_duration():
    catalog = {
        "items": [
            {
                "key": "collectible:619",
                "kind": "collectible",
                "id": 619,
                "enum": "COLLECTIBLE_BIRTHRIGHT",
                "item_type": 1,
            }
        ]
    }
    cases = select_cases(catalog, contexts=("client-split",))
    assert len({c["trigger_effects"]["character_before"] for c in cases}) >= 20
    assert len({c["key"] for c in cases}) == len(cases)
    for case in cases:
        recipe = trigger_recipe(case)
        assert case["end_tick"] == recipe["end_tick"]
        assert case["slot"] == 1 and case["split"]
    esau = next(c for c in cases if c["scenario"] == "esau")
    assert esau["trigger_effects"]["birthright_twin"]


def check_trial(mode, events):
    checks = {}
    birthright_checks(
        {"birthright_trial": {"mode": mode}},
        {"host": events},
        [],
        lambda name, values: checks.update({name: bool(values) and all(values)}),
    )
    return checks


def test_tainted_cain_requires_two_actual_native_salvages():
    evidence = [
        {"event": "birthright_state", "phase": "before", "owned": False},
        {"event": "birthright_state", "phase": "held", "owned": True},
        {"event": "birthright_salvage", "owned": False, "consumed": True, "drops": 6},
        {"event": "birthright_salvage", "owned": True, "consumed": True, "drops": 9},
    ]
    assert all(check_trial("salvage", evidence).values())
    for invalid in ({"consumed": False}, {"drops": 6}, {"owned": False}):
        changed = deepcopy(evidence)
        changed[-1].update(invalid)
        assert not all(check_trial("salvage", changed).values())


def test_judas_requires_passive_belial_alongside_the_replacement_active():
    evidence = [
        {"event": "birthright_state", "phase": "before", "owned": False},
        {
            "event": "birthright_state",
            "phase": "held",
            "owned": True,
            "belial": False,
            "passive_belial": True,
            "active": 105,
        },
    ]
    assert all(check_trial("belial", evidence).values())
    evidence[-1]["passive_belial"] = False
    evidence[-1]["belial"] = True
    assert not all(check_trial("belial", evidence).values())


def test_tainted_eden_requires_protection_and_an_actual_reroll():
    evidence = [
        {"event": "birthright_state", "phase": "before", "owned": False},
        {"event": "birthright_state", "phase": "held", "owned": True},
        {"event": "birthright_protected_inventory", "preserved": True, "rerolled": True},
    ]
    assert all(check_trial("protected_items", evidence).values())
    evidence[-1]["rerolled"] = False
    assert not all(check_trial("protected_items", evidence).values())


def test_tainted_isaac_requires_twelve_slots_and_an_actual_thirteenth_item_swap():
    evidence = [
        {"event": "birthright_state", "phase": "before", "owned": False},
        {"event": "birthright_state", "phase": "held", "owned": True},
        *[
            {
                "event": "birthright_inventory_capacity",
                "index": index,
                "owned": min(index, 12),
                "consumed": index <= 12,
                "new_item": True,
                "replaced": index == 13,
            }
            for index in range(9, 14)
        ],
    ]
    assert all(check_trial("inventory_slots", evidence).values())
    for invalid in ({"owned": 13}, {"new_item": False}, {"replaced": False}):
        changed = deepcopy(evidence)
        changed[-1].update(invalid)
        assert not all(check_trial("inventory_slots", changed).values())


def test_lazarus_ghost_effect_does_not_require_duplicate_birthright_inventory():
    evidence = [
        {"event": "birthright_state", "phase": "before", "owned": False},
        {"event": "birthright_state", "phase": "held", "owned": True},
        *[
            {
                "event": "birthright_lazarus_pair",
                "found": True,
                "other_owned": False,
                "other_visible": True,
                "before": 6,
                "after": 6,
                "player_type": 29 if index == 0 else 38,
                "room": 84 if index < 2 else 85,
                "stage": 1 if index < 3 else 2,
            }
            for index in range(4)
        ],
        {"event": "birthright_lazarus_damage", "ghost": False, "amount": 3.5},
        {"event": "birthright_lazarus_damage", "ghost": True, "amount": 0.875},
    ]
    assert all(check_trial("lazarus_ghost", evidence).values())
    for invalid in ({"found": False}, {"other_visible": False}, {"after": 5}):
        changed = deepcopy(evidence)
        changed[2].update(invalid)
        assert not all(check_trial("lazarus_ghost", changed).values())


@pytest.mark.parametrize("scenario", BIRTHRIGHT_SCENARIOS)
def test_birthright_never_accepts_possession_as_effect_evidence(scenario):
    rules = BIRTHRIGHT_SCENARIOS[scenario]
    if "birthright_trial" not in rules:
        return  # Isaac and Tainted Lost use the pedestal/revival validators.
    checks = {}
    birthright_checks(
        rules,
        {
            "host": [
                {
                    "event": "birthright_state",
                    "phase": "before",
                    "owned": False,
                    "limit": 24,
                    "damage": 3.5,
                    "max_hearts": 6,
                },
            ]
        },
        [],
        lambda name, values: checks.update({name: bool(values) and all(values)}),
    )
    effect_checks = [
        value for name, value in checks.items() if name != "birthright_native_holder_observed"
    ]
    assert effect_checks and not all(effect_checks)


def test_birthright_unknown_effect_cannot_fall_through_to_possession_only():
    with pytest.raises(ValueError, match="no effect validator"):
        check_trial("unimplemented", [])


def test_keeper_requires_enemy_death_and_actual_remote_coin_collection():
    evidence = [
        {"event": "birthright_state", "phase": "before", "owned": False},
        {"event": "birthright_state", "phase": "held", "owned": True},
        {
            "event": "birthright_keeper_coins",
            "owned": False,
            "killed": True,
            "emitted": 8,
            "staged": 4,
            "gained": 0,
        },
        {
            "event": "birthright_keeper_coins",
            "owned": True,
            "killed": True,
            "emitted": 8,
            "staged": 4,
            "gained": 2,
        },
    ]
    assert all(check_trial("enemy_coins", evidence).values())
    for invalid in (
        {"killed": False},
        {"emitted": 0},
        {"staged": 0},
        {"gained": 0},
        {"owned": False},
    ):
        changed = deepcopy(evidence)
        changed[-1].update(invalid)
        assert not all(check_trial("enemy_coins", changed).values())


def test_gello_bonus_uses_native_contact_damage_and_excludes_familiar_tears():
    evidence = [
        {"event": "birthright_state", "phase": "before", "owned": False},
        {"event": "birthright_state", "phase": "held", "owned": True},
        {
            "event": "birthright_gello_follower",
            "owned": True,
            "found": True,
            "gello_distance": 15,
            "player_distance": 75,
        },
        *[
            {
                "event": "birthright_gello_damage",
                "owned": owned,
                "source_type": 1,
                "amount": amount,
                "player_damage": 3.5,
            }
            for owned, amount in ((False, 10.5), (True, 13.5))
        ],
    ]
    assert all(check_trial("gello", evidence).values())
    for invalid in ({"source_type": 2}, {"amount": 10.5}, {"owned": False}):
        changed = deepcopy(evidence)
        changed[-1].update(invalid)
        assert not all(check_trial("gello", changed).values())


def test_azazel_range_requires_new_sneeze_mark_even_if_enemy_collision_did_damage():
    evidence = [
        {"event": "birthright_state", "phase": "before", "owned": False},
        {"event": "birthright_state", "phase": "held", "owned": True},
        *[
            {
                "event": "birthright_native_ability_range",
                "owned": owned,
                "targets": [
                    {"distance": 75, "damage": 7.875, "marked": True},
                    {"distance": 110, "damage": damage, "marked": owned},
                ],
            }
            for owned, damage in ((False, 20), (True, 27.875))
        ],
    ]
    assert all(check_trial("sneeze_range", evidence).values())
    for invalid in ({"marked": False}, {"damage": 20}):
        changed = deepcopy(evidence)
        changed[-1]["targets"][-1].update(invalid)
        assert not all(check_trial("sneeze_range", changed).values())
