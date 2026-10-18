from copy import deepcopy
import json
from pathlib import Path

import pytest

from item_trinket_effects import TRINKET_EFFECTS, trinket_checks


def test_native_collectible_prerequisites_exist_in_game_catalog():
    from item_birthright_effects import BIRTHRIGHT_SCENARIOS

    catalog = json.loads((Path(__file__).parent / "fixtures/item_catalog.json").read_text())
    native_names = {item["enum"] for item in catalog["items"] if item["kind"] == "collectible"}

    def validate(value):
        if isinstance(value, dict):
            for nested in value.values():
                validate(nested)
        elif isinstance(value, (list, tuple)):
            for nested in value:
                validate(nested)
        elif isinstance(value, str) and value.startswith("COLLECTIBLE_"):
            assert value in native_names

    validate(TRINKET_EFFECTS)
    validate(BIRTHRIGHT_SCENARIOS)


def test_visual_review_requirements_have_named_evidence():
    for recipe in TRINKET_EFFECTS.values():
        for rules in [recipe, *recipe.get("scenarios", {}).values()]:
            if "visual_review" in rules:
                assert isinstance(rules["visual_review"], str) and rules["visual_review"]


def test_repeated_damage_fixture_leaves_room_for_its_soul_heart_buffer():
    for recipe in TRINKET_EFFECTS.values():
        trial = recipe.get("trinket_trial", {})
        if trial.get("mode") == "damage" and trial.get("soul"):
            assert trial.get("max_hearts", 24) + trial["soul"] <= 24


def test_crow_heart_requires_existing_soul_hearts_to_protect():
    trial = {"mode": "damage", "reward": "red_first", "count": 1}
    event = {
        "event": "trinket_native_result",
        "accepted": True,
        "before": {"hearts": 12, "soul": 8},
        "after": {"hearts": 11, "soul": 8},
    }
    assert all(results(trial, [event]).values())
    event["before"]["soul"] = event["after"]["soul"] = 0
    assert not all(results(trial, [event]).values())


def test_watch_battery_does_not_count_revisiting_cleared_rooms():
    trial = {"mode": "rooms", "reward": "watch_charge", "count": 2}
    events = [
        {"event": "trinket_room_state", "phase": "entered", "alive": 2, "charge": 0},
        {"event": "trinket_room_state", "phase": "cleared", "alive": 0, "clear": True, "charge": 1},
        {"event": "trinket_room_state", "phase": "entered", "alive": 1, "charge": 0},
        {"event": "trinket_room_state", "phase": "cleared", "alive": 0, "clear": True, "charge": 2},
        {"event": "native_entry_clear", "killed": 2},
        {"event": "native_entry_clear", "killed": 1},
    ]
    assert all(results(trial, events).values())
    events[-1]["killed"] = 0
    assert not all(results(trial, events).values())


def test_number_magnet_uses_native_room_subtype_and_unmasked_deal_chance():
    trial = {"mode": "devil_deal", "reward": "magnet"}
    events = [
        {"event": "trinket_generated_devil_deals", "variant": 30, "subtype": 1},
        {"event": "trinket_magnet_deal_chance", "owned": False, "chance": 1.35},
        {"event": "trinket_magnet_deal_chance", "owned": True, "chance": 1.45},
    ]
    assert all(results(trial, events).values())
    ordinary = deepcopy(events)
    ordinary[0].update(variant=1000, subtype=0)
    assert not all(results(trial, ordinary).values())
    events[-1]["chance"] = 1.35
    assert not all(results(trial, events).values())


def test_expansion_pairs_every_native_use_with_its_additional_effect():
    trial = {"mode": "expansion", "count": 16, "minimum_uses": 8}
    events = [
        {
            "event": "trinket_triggered_use",
            "kind": "collectible",
            "id": item,
            "tick": tick,
            "max_charges": charge,
            "correct_actor": True,
        }
        for tick in range(90, 810, 90)
        for item, charge in ((105, 6), (44, 2))
    ]
    assert all(results(trial, events).values())
    assert not all(results(trial, events[:-1]).values())
    changed = deepcopy(events)
    changed[-1]["tick"] += 1
    assert not all(results(trial, changed).values())
    changed = deepcopy(events)
    changed[-1]["max_charges"] = 6
    assert not all(results(trial, changed).values())
    assert not all(results(trial, events[:2]).values())


def test_choice_requires_physical_acquisition_and_alternative_disappearance():
    trial = {"mode": "floor_series", "count": 1, "reward": "choice"}
    events = [
        {
            "event": "trinket_native_floor_room",
            "owned": True,
            "seed": 12,
            "items": [{"id": 1, "options": 1}, {"id": 2, "options": 1}],
        },
        {
            "event": "trinket_native_floor_choice",
            "seed": 12,
            "acquired": True,
            "consumed": True,
            "remaining": 0,
        },
    ]
    assert all(results(trial, events).values())
    for invalid in ({"acquired": False}, {"remaining": 1}, {"seed": 13}):
        changed = deepcopy(events)
        changed[-1].update(invalid)
        assert not all(results(trial, changed).values())


def test_watch_battery_ignores_empty_rooms_even_when_they_show_bonus_charge():
    trial = {"mode": "rooms", "reward": "watch_charge", "count": 3, "minimum_clears": 2}
    events = []
    for alive, charge in ((2, 1), (0, 2), (3, 1)):
        events.extend(
            [
                {"event": "trinket_room_state", "phase": "entered", "alive": alive, "charge": 0},
                {"event": "native_entry_clear", "killed": alive},
                {
                    "event": "trinket_room_state",
                    "phase": "cleared",
                    "alive": 0,
                    "clear": True,
                    "charge": charge,
                },
            ]
        )
    checks = results(trial, events)
    assert checks["watch_battery_real_repeated_combat_clears"]
    assert not checks["watch_battery_adds_extra_charge_to_normal_clear"]
    events[-1]["charge"] = 2
    assert all(results(trial, events).values())


def test_multi_effect_cases_keep_their_own_timeline_and_validator():
    from item_audit import select_cases
    from item_trigger_effects import trigger_recipe

    catalog = {
        "items": [{"key": "trinket:24", "kind": "trinket", "id": 24, "enum": "TRINKET_BUTT_PENNY"}]
    }
    cases = select_cases(catalog, contexts=("client-split",))
    assert [c["key"] for c in cases] == [
        "trinket:24/client-split/coin",
        "trinket:24/client-split/poop",
    ]
    assert [c["end_tick"] for c in cases] == [300, 519]
    assert [trigger_recipe(c)["trinket_trial"]["mode"] for c in cases] == ["coins", "grid"]
    assert all(c["trigger_effects"] == trigger_recipe(c) for c in cases)
    assert all("scenarios" not in c["trigger_effects"] for c in cases)
    with pytest.raises(KeyError):
        trigger_recipe({**cases[0], "scenario": "unknown"})


def test_size_change_needs_native_effects_and_an_actual_control():
    trial = {"mode": "effect_size"}
    samples = [
        {
            "event": "trinket_effect_size",
            "phase": phase,
            "owned": held,
            "scale": scale,
            "sprite": 1,
            "size": 20,
            "count": 5,
        }
        for phase, held, scale in (("control", False, 1), ("held", True, 2))
    ]
    assert all(results(trial, samples).values())
    samples[1]["scale"] = 1
    assert not all(results(trial, samples).values())
    samples[1]["scale"], samples[0]["count"] = 2, 0
    assert not all(results(trial, samples).values())


def results(trial, host, client=(), probes=()):
    checks = {}

    def check(name, values):
        checks[name] = bool(values) and all(values)

    trinket_checks({"trinket_trial": trial}, {"host": host, "client": client}, probes, check)
    return checks


def test_nuh_uh_requires_real_replacements_but_not_live_original_allocations():
    trial = {"mode": "floor_series", "reward": "replace_resources", "count": 1}
    sample = {
        "event": "trinket_native_floor_room",
        "owned": True,
        "seed": 187,
        "stage": 7,
        "replacements": {
            "control": {"coins": 128, "keys": 128},
            "held": {"coins": 0, "keys": 0, "other": 219, "removed": 37},
        },
    }
    assert all(results(trial, [sample]).values())
    for invalid in ({"coins": 1}, {"keys": 1}, {"other": 0, "removed": 256}, {"removed": 38}):
        changed = deepcopy(sample)
        changed["replacements"]["held"].update(invalid)
        assert not all(results(trial, [changed]).values())


def test_butter_observes_drop_before_replacement_active_is_installed():
    trial = {"mode": "active", "effect": "drop"}
    probes = [
        {"label": "before", "tick": 30, "active_item": "COLLECTIBLE_D6"},
        {
            "label": "captured",
            "tick": 93,
            "active_item": "COLLECTIBLE_NULL",
            "pedestals": [{"enum": "COLLECTIBLE_D6"}],
        },
        {"label": "captured", "tick": 120, "active_item": "COLLECTIBLE_D6", "pedestals": []},
    ]
    assert all(results(trial, [], probes=probes).values())
    probes[1]["pedestals"] = []
    assert not all(results(trial, [], probes=probes).values())


def test_hairpin_requires_empty_active_and_physical_hostile_boss_entry():
    trial = {"mode": "door", "reward": "charge"}
    entry = {
        "event": "trinket_native_door_entry",
        "room": 85,
        "target": 85,
        "room_type": 5,
        "keys": 0,
        "enemies": 1,
        "owned": True,
        "charge_before": 0,
        "charge_after": 6,
        "max_charge": 6,
    }
    assert all(results(trial, [entry]).values())
    for invalid in ({"charge_before": 6}, {"charge_after": 0}, {"room": 84}, {"enemies": 0}):
        assert not all(results(trial, [{**entry, **invalid}]).values())


def test_generation_requires_control_ownership_and_visible_native_examples():
    trial = {"mode": "generation", "count": 2, "target": "360.1", "all_match": True}
    samples = [
        {"event": "trinket_generation", "phase": "control", "owned": False, "counts": {"50.1": 2}},
        {
            "event": "trinket_generation",
            "phase": "held",
            "owned": True,
            "counts": {"360.1": 2},
            "examples": [{"seed": 1, "variant": 360, "subtype": 1}],
        },
    ]
    client = [
        {
            "event": "trigger_probe",
            "tick": 240,
            "pickups": [{"seed": 1, "variant": 360, "subtype": 1}],
        }
    ]
    samples.extend(deepcopy(client))
    assert all(results(trial, samples, client).values())
    assert not all(results(trial, samples[:1], client).values())
    invalid = deepcopy(samples)
    invalid[0]["owned"] = True
    assert not all(results(trial, invalid, client).values())
    assert not results(trial, samples)["replica:trinket_generated_pickups"]
    client[0]["pickups"][0]["subtype"] = 2
    assert not results(trial, samples, client)["replica:trinket_generated_pickups"]


def test_generation_compares_native_examples_after_initialization_settles():
    trial = {"mode": "generation", "count": 2, "target": "90.1", "all_match": False}
    pickup = {"seed": 1, "variant": 90, "subtype": 1}
    host = [
        {"event": "trinket_generation", "phase": "control", "owned": False, "counts": {"20.1": 2}},
        {
            "event": "trinket_generation",
            "phase": "held",
            "owned": True,
            "counts": {"90.1": 2},
            "examples": [pickup, {**pickup, "seed": 2}],
        },
        {"event": "trigger_probe", "tick": 240, "pickups": [pickup]},
    ]
    client = [deepcopy(host[-1])]
    assert all(results(trial, host, client).values())
    client[-1]["pickups"] = []
    assert not results(trial, host, client)["replica:trinket_generated_pickups"]
    host[-1]["pickups"] = []
    assert not results(trial, host, client)["replica:trinket_generated_pickups"]


def test_keeper_bargain_requires_actual_acquisition_and_coin_payment():
    trial = {"mode": "devil_deal", "reward": "coins"}
    events = [
        {"event": "trinket_native_deal_prices", "owned": False, "prices": [-2]},
        {"event": "trinket_native_deal_prices", "owned": True, "prices": [15]},
        {
            "event": "trinket_native_deal_purchase",
            "found": True,
            "acquired": True,
            "before": {"owned": 0, "hearts": 6, "coins": 99, "price": 15},
            "after": {"owned": 0, "hearts": 6, "coins": 84},
        },
    ]
    assert all(results(trial, events).values())
    events[-1]["acquired"] = False
    assert not results(trial, events)["native_devil_item_purchased"]
    events[-1]["acquired"] = True
    events[-1]["after"]["coins"] = 99
    assert not results(trial, events)["keeper_bargain_purchase_uses_coins"]


@pytest.mark.parametrize(
    "consumed,coins,passed", [(True, 2, True), (True, 1, False), (False, 2, False)]
)
def test_counterfeit_requires_actual_pickup_and_bonus_coin(consumed, coins, passed):
    trial = {"mode": "coins", "count": 1, "reward": "coins"}
    samples = [
        {
            "event": "trinket_native_result",
            "consumed": consumed,
            "before": {"coins": 0},
            "after": {"coins": coins},
        }
    ]
    assert all(results(trial, samples).values()) is passed
    assert not all(results(trial, []).values())


def test_damage_reward_requires_hit_consumption_and_native_drop():
    trial = {"mode": "damage", "count": 1, "reward": "lunch"}
    event = {
        "event": "trinket_native_result",
        "accepted": True,
        "before": {"trinket": 105, "pickups": {}},
        "after": {"trinket": 0, "pickups": {"100.22": 1}},
    }
    assert all(results(trial, [event]).values())
    for invalid in (
        {**event, "accepted": False},
        {**event, "after": {"trinket": 105, "pickups": {"100.22": 1}}},
        {**event, "after": {"trinket": 0, "pickups": {}}},
    ):
        assert not all(results(trial, [invalid]).values())
    assert not all(results(trial, []).values())


def test_knockback_needs_two_actual_collisions():
    trial = {"mode": "tear_control", "effect": "flat"}
    probes = [{"tick": t, "tears": [{"scale": 1}]} for t in (120, 330)]
    events = [
        {"event": "trinket_knockback_result", "phase": phase, "damage": 3.5, "velocity": speed}
        for phase, speed in (("control", 2), ("held", 4))
    ]
    assert all(results(trial, events, probes=probes).values())
    events[1]["velocity"] = events[0]["velocity"]
    assert all(results(trial, events, probes=probes).values())
    assert not all(results({**trial, "effect": "knockback"}, events, probes=probes).values())
    events[0]["damage"] = 0
    assert not all(results(trial, events, probes=probes).values())


def test_death_locust_counts_two_hits_from_the_same_native_contact():
    trial = {"mode": "locust", "subtype": 4, "multiplier": 4, "contact_hits": 2, "flags": []}
    hit = {
        "event": "native_locust_damage",
        "subtype": 4,
        "tick": 478,
        "source_seed": 7,
        "target_seed": 11,
        "holder_damage": 3.5,
        "amount": 7,
    }
    spawned = {"event": "trinket_locust_state", "flies": [{"subtype": 4}]}
    assert all(results(trial, [spawned, hit, dict(hit)]).values())
    for changed in ({"tick": 479}, {"source_seed": 8}, {"target_seed": 12}, {"amount": 0}):
        assert not all(results(trial, [spawned, hit, {**hit, **changed}]).values())
    assert not all(results(trial, [spawned, hit]).values())
