"""Evidence boundaries for the extended native effect trials."""

from copy import deepcopy

from item_trigger_effects import trigger_checks
from item_projectile_effects import projectile_checks


def test_unstarted_native_cases_keep_missing_evidence_instead_of_aborting_the_report():
    for enum in ("COLLECTIBLE_LIBRA", "COLLECTIBLE_VOID", "COLLECTIBLE_CANDY_HEART"):
        checks = trigger_checks({"enum": enum}, {"host": [], "client": []})
        assert checks and all(c["status"] != "passed" for c in checks)


def test_projectile_despawn_without_a_damaging_control_is_not_defense_evidence():
    checks = {}
    defense = {
        "event": "defense_projectile_result",
        "control": False,
        "before": 24,
        "after": 24,
        "removed": True,
        "reflected": False,
    }
    projectile_checks(
        {"projectile_trial": {"kind": "player"}},
        {"host": [defense] * 25},
        [],
        lambda name, values: checks.update({name: bool(values) and all(values)}),
    )
    assert checks["item_prevents_projectile_damage"]
    assert not checks["ordinary_projectile_control_causes_damage"]


def test_player_collision_does_not_certify_a_familiar_block():
    checks = {}
    hit = {
        "event": "defense_projectile_result",
        "control": False,
        "collision": True,
        "collider": 1,
        "removed": True,
        "reflected": False,
    }
    projectile_checks(
        {"projectile_trial": {"kind": "familiar"}},
        {"host": [hit] * 25},
        [],
        lambda name, values: checks.update({name: bool(values) and all(values)}),
    )
    assert not checks["familiar_intercepts_projectiles"]


def probe(tick, hearts=6, label="captured"):
    return {
        "event": "trigger_probe",
        "label": label,
        "tick": tick,
        "hearts": hearts,
        "max_hearts": 6,
        "charge": 0,
        "damage": 3.5,
        "delay": 10,
        "speed": 1,
        "range": 260,
        "shot_speed": 1,
        "luck": 0,
        "tear_flags": [],
        "enemy_flags": [],
        "effects": [],
        "familiars": [],
        "spawned": [],
        "tears": [],
        "enemy_hp": 500,
    }


def bad_trip_evidence():
    after = [probe(t, hearts=4) for t in (66, 90, 120)]
    return {"host": [probe(30, label="before"), *after], "client": deepcopy(after)}


def test_native_bomb_flags_are_evidence_and_replica_geometry_still_must_match():
    before = {**probe(30, label="before"), "explosives": []}
    after = []
    for tick, flags in (
        (90, "BitSet128: 0000"),
        (120, "BitSet128: 0010"),
        (150, "BitSet128: 0000"),
    ):
        after.append(
            {
                **probe(tick),
                "explosives": [
                    {
                        "seed": tick,
                        "variant": 0,
                        "x": 100,
                        "y": 150,
                        "damage": 100,
                        "radius": 1,
                        "flags": flags,
                    }
                ],
            }
        )
    evidence = {"host": [before, *after], "client": deepcopy(after)}
    case = {"enum": "COLLECTIBLE_NANCY_BOMBS"}
    assert all(c["status"] == "passed" for c in trigger_checks(case, evidence))
    evidence["client"][0]["explosives"][0]["x"] += 30
    assert {"name": "trigger:replica:explosives_geometry", "status": "failed"} in trigger_checks(
        case, evidence
    )
    for e in after:
        e["explosives"][0]["flags"] = "BitSet128: 0000"
    assert {"name": "trigger:native_random_bomb_effects", "status": "failed"} in trigger_checks(
        case, evidence
    )


def test_empty_lua_tables_and_measured_pill_damage():
    checks = trigger_checks({"enum": "PILLEFFECT_BAD_TRIP"}, bad_trip_evidence())
    assert checks and all(c["status"] == "passed" for c in checks)


def test_horse_pill_requires_its_own_damage_amount():
    checks = trigger_checks({"enum": "PILLEFFECT_BAD_TRIP", "horse": True}, bad_trip_evidence())
    assert {"name": "trigger:delta:hearts", "status": "failed"} in checks


def test_missing_peer_cannot_certify_an_effect():
    evidence = bad_trip_evidence()
    evidence["client"] = []
    checks = trigger_checks({"enum": "PILLEFFECT_BAD_TRIP"}, evidence)
    assert any(c["status"] != "passed" for c in checks)
    assert {"name": "trigger:replica:hearts", "status": "missing"} in checks


def homing_evidence():
    before = probe(30, label="before")
    samples = []
    for tick in (75, 90, 120):
        sample = probe(tick)
        sample["enemy_hp"] = 496.5
        sample["tear_flags"] = {"TEAR_HOMING": 1}
        sample["tears"] = [
            {
                "seed": 17,
                "x": 100 + tick,
                "y": 300 - tick,
                "vx": 2,
                "vy": -8,
                "color": [1, 0, 1, 1, 0, 0, 0],
            }
        ]
        samples.append(sample)
    replicas = deepcopy(samples)
    for sample in replicas:
        sample["tear_flags"] = []
    return {"host": [before, *samples], "client": replicas}


def test_replica_homing_is_observed_through_motion_and_appearance():
    checks = trigger_checks({"enum": "COLLECTIBLE_SPOON_BENDER"}, homing_evidence())
    assert checks and all(c["status"] == "passed" for c in checks)


def test_wrong_replica_trajectory_is_not_hidden_by_native_homing_flags():
    evidence = homing_evidence()
    evidence["client"][1]["tears"][0]["x"] += 20
    checks = trigger_checks({"enum": "COLLECTIBLE_SPOON_BENDER"}, evidence)
    assert {"name": "trigger:replica:tear_motion", "status": "failed"} in checks


def test_split_tears_sharing_a_seed_require_every_distinct_sibling():
    evidence = homing_evidence()
    for role in ("host", "client"):
        for sample in evidence[role]:
            if sample["tears"]:
                sibling = deepcopy(sample["tears"][0])
                sibling["x"] += 20
                sibling["vx"] = -2
                sample["tears"].append(sibling)
                if role == "client":
                    sample["tears"].reverse()
    case = {"enum": "COLLECTIBLE_SPOON_BENDER"}
    assert all(c["status"] == "passed" for c in trigger_checks(case, evidence))
    evidence["client"][0]["tears"].pop()
    assert {"name": "trigger:replica:tear_motion", "status": "failed"} in trigger_checks(
        case, evidence
    )


def test_host_in_a_separate_room_requires_player_state_but_no_invisible_entities():
    evidence = homing_evidence()
    for event in evidence["client"]:
        event.update(room_visible=False, tears=[])
    case = {"enum": "COLLECTIBLE_SPOON_BENDER", "slot": 0, "split": True}
    checks = trigger_checks(case, evidence)
    assert checks and all(c["status"] == "passed" for c in checks)
    evidence["client"][0]["hearts"] -= 1
    assert {"name": "trigger:replica:hearts", "status": "failed"} in trigger_checks(case, evidence)


def test_remote_room_shell_does_not_claim_visible_world_evidence():
    evidence = homing_evidence()
    authority = deepcopy(evidence["host"][-1])
    authority.update(tick=190, enemy_hp=0, tears=[])
    replica = deepcopy(authority)
    replica.update(room_visible=False, enemy_hp=500)
    evidence["host"].append(authority)
    evidence["client"].append(replica)
    assert all(
        c["status"] == "passed"
        for c in trigger_checks({"enum": "COLLECTIBLE_SPOON_BENDER"}, evidence)
    )
    for event in evidence["client"]:
        event["room_visible"] = False
    assert any(
        c["status"] != "passed"
        for c in trigger_checks({"enum": "COLLECTIBLE_SPOON_BENDER"}, evidence)
    )


def test_reroll_requires_targets_and_two_changed_snapshots_after_native_input():
    before = probe(30, label="before")
    before.update(
        pickups=[{"seed": i, "subtype": 1} for i in range(4)],
        pedestals=[],
        poop_count=0,
        rock_count=0,
    )
    unchanged = {**deepcopy(before), "label": "captured", "tick": 60}
    changed = {
        **deepcopy(unchanged),
        "tick": 90,
        "pickups": [{"seed": i + 10, "subtype": 2} for i in range(4)],
    }
    later = {**deepcopy(changed), "tick": 120}
    evidence = {
        "host": [before, unchanged, changed, later],
        "client": deepcopy([unchanged, changed, later]),
    }
    assert all(
        c["status"] == "passed" for c in trigger_checks({"enum": "COLLECTIBLE_D20"}, evidence)
    )
    for event in (changed, later):
        event["pickups"] = deepcopy(before["pickups"])
    assert {"name": "trigger:pickups_rerolled", "status": "failed"} in trigger_checks(
        {"enum": "COLLECTIBLE_D20"}, evidence
    )


def test_duplication_requires_an_added_pickup_and_is_separate_from_enemy_splitting():
    before = probe(30, label="before")
    before.update(
        pickup_count=4,
        pickups=[],
        pedestals=[],
        poop_count=0,
        rock_count=0,
        enemy_count=2,
        targets=[{"hp": 500}, {"hp": 500}],
    )
    samples = [
        {
            **deepcopy(before),
            "label": "captured",
            "tick": t,
            "enemy_count": 4,
            "targets": [{"hp": 200}] * 4,
        }
        for t in (66, 90, 120)
    ]
    evidence = {"host": [before, *samples], "client": deepcopy(samples)}
    checks = trigger_checks({"enum": "COLLECTIBLE_D1"}, evidence)
    assert {"name": "trigger:pickups_duplicated", "status": "failed"} in checks
    for role in evidence.values():
        for event in role:
            if event["label"] != "before":
                event["pickup_count"] = 5
    assert all(
        c["status"] == "passed" for c in trigger_checks({"enum": "COLLECTIBLE_D1"}, evidence)
    )
    assert all(
        c["status"] == "passed"
        for c in trigger_checks({"enum": "COLLECTIBLE_MEAT_CLEAVER"}, evidence)
    )


def test_eden_needs_a_reward_on_the_holder_in_the_next_native_run():
    before = probe(30, label="before")
    samples = [{**probe(t), "delay": 9} for t in (66, 90, 120)]
    evidence = {"host": [before, *samples], "client": deepcopy(samples)}
    case = {"enum": "COLLECTIBLE_EDENS_BLESSING", "slot": 1}
    name = "trigger:blessing_grants_item_in_next_native_run"
    evidence["host"].append({"event": "eden_run_initial", "count": 1})
    assert {"name": name, "status": "missing"} in trigger_checks(case, evidence)
    evidence["host"].extend(
        [
            {"event": "eden_next_run", "count": 1},
            {"event": "eden_next_peer", "count": 2},
        ]
    )
    assert {"name": name, "status": "failed"} in trigger_checks(case, evidence)
    evidence["host"][-2]["count"] = 2
    assert all(c["status"] == "passed" for c in trigger_checks(case, evidence))


def test_deaths_list_accepts_native_shot_speed_reward_but_not_just_marked_kills():
    before = {**probe(30, label="before"), "pickup_count": 0}
    samples = [{**probe(t), "pickup_count": 0, "shot_speed": 1.2} for t in (600, 630, 660)]
    evidence = {
        "host": [
            before,
            *samples,
            {"event": "native_combat_room_visit", "tick": 90, "index": 97},
            {"event": "deaths_list_native_targets", "count": 1},
            {"event": "marked_enemy_killed", "tick": 150, "seed": 42},
        ],
        "client": deepcopy(samples),
    }
    case = {"enum": "COLLECTIBLE_DEATHS_LIST"}
    assert all(c["status"] == "passed" for c in trigger_checks(case, evidence))
    for sample in samples:
        sample["shot_speed"] = 1
    assert {
        "name": "trigger:completing_deaths_list_grants_reward",
        "status": "failed",
    } in trigger_checks(case, evidence)
