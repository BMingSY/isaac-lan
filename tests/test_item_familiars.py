from copy import deepcopy
from math import cos, sin
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from item_familiar_effects import FAMILIAR_EFFECTS, familiar_checks


@pytest.mark.parametrize(
    "enum,check",
    [
        ("TRINKET_DUCT_TAPE", "familiar_fixed_offset_while_owner_moves"),
        ("TRINKET_FRIENDSHIP_NECKLACE", "familiar_familiar_actually_orbits_owner"),
        ("TRINKET_RC_REMOTE", "familiar_drop_holds_familiar_while_owner_moves"),
    ],
)
def test_familiar_trinkets_require_their_actual_motion(enum, check):
    case, peers = evidence(enum)
    for e in peers["host"]:
        if e["event"] == "familiar_probe" and 80 <= e["tick"] <= 140:
            for f in e["familiars"]:
                if enum == "TRINKET_DUCT_TAPE":
                    f["x"] += e["tick"]
                else:
                    f["x"], f["y"] = e["x"] - 20, e["y"]
    assert next(c for c in familiar_checks(case, peers) if c["name"] == check)["status"] == "failed"


def test_remote_control_fixture_moves_player_during_native_drop_hold():
    executable = shutil.which("lua5.3") or shutil.which("lua")
    assert executable, "Lua 5.3 is required"
    subprocess.run(
        [executable, "-"],
        input="""
ButtonAction = { ACTION_RIGHT = 2, ACTION_SHOOTUP = 4 }
local factory = dofile("tests/fixtures/item_audit_familiars.lua")
local fixture = factory(function() end, function() end, function() end, function() end)
local case = { familiar_effects = { drop_window = {120, 139} } }
assert(fixture.input(case, 125) == 1 << ButtonAction.ACTION_RIGHT)
assert(fixture.input(case, 140) == 0)
""",
        text=True,
        cwd=Path(__file__).resolve().parents[1],
        check=True,
    )


def test_lil_clot_drop_preserves_the_clot_until_native_damage_kills_it():
    case, peers = evidence("TRINKET_LIL_CLOT")
    assert all(c["status"] == "passed" for c in familiar_checks(case, peers))
    dropped = next(e for e in peers["host"] if e["event"] == "familiar_probe" and e["tick"] == 880)
    dropped["familiars"] = []
    assert (
        next(
            c
            for c in familiar_checks(case, peers)
            if c["name"] == "familiar_trinket_dropped_clot_remains"
        )["status"]
        == "failed"
    )
    case, peers = evidence("TRINKET_LIL_CLOT")
    peers["host"] = [e for e in peers["host"] if e["event"] != "familiar_drop_collision"]
    assert (
        next(
            c
            for c in familiar_checks(case, peers)
            if c["name"] == "familiar_dropped_clot_takes_three_projectile_hits"
        )["status"]
        == "failed"
    )


def evidence(enum="COLLECTIBLE_BROTHER_BOBBY"):
    rules = FAMILIAR_EFFECTS[enum]
    host = []

    def probe(tick, *, shots=None):
        removed = tick >= 780
        moved = tick > 110
        player_x, familiar_x, familiar_y = 150 if moved else 100, 130 if moved else 80, 100
        if rules.get("fixed_offset") or rules.get("native_orbit") or rules.get("drop_window"):
            player_x = 100 + max(0, min(tick, 140) - 100) * 2
            familiar_x = player_x - 20
            if rules.get("native_orbit"):
                familiar_x, familiar_y = player_x + 40 * cos(tick / 10), 100 + 40 * sin(tick / 10)
            elif rules.get("drop_window") and 120 <= tick < 139:
                familiar_x = 120
        return {
            "event": "familiar_probe",
            "tick": tick,
            "room": 85 if 300 < tick < 390 else 84,
            "stage": 2 if tick > 390 else 1,
            "x": player_x,
            "y": 100,
            "owned": 0 if removed else 1,
            "teammate_owned": 0,
            "room_visible": True,
            "familiars": []
            if removed
            and not rules.get("modifier")
            and (not rules.get("persists_after_drop") or tick >= 1080)
            else [
                {"x": familiar_x + i * 5, "y": familiar_y, "controller": 1}
                for i in range(rules.get("count", 1))
            ],
            "shots": shots or [],
        }

    host.extend(probe(t) for t in (90, 140, 360, 610, 880 if rules.get("physical_remove") else 820))
    if rules.get("persists_after_drop"):
        host.extend({"event": "familiar_drop_collision", "tick": t} for t in (901, 946, 991))
        host.extend(probe(t) for t in (1080, 1110))
    if rules.get("remove_room_tick"):
        host.extend(probe(rules["remove_room_tick"] + t) for t in (60, 90))
    if rules.get("fixed_offset") or rules.get("native_orbit") or rules.get("drop_window"):
        host.extend(probe(t) for t in (95, 110, 117, 124, 130, 135, 137))
    damage = rules.get("damage", 3.5 * rules.get("damage_factor", 1))
    directions = {
        None: [(0, -8)] * rules.get("count", 1),
        "split": [(-3, -8), (3, -8)],
        "cross": [(-8, 0), (8, 0), (0, -8), (0, 8)],
    }[rules.get("pattern")]
    for start in (175, 655):
        if rules.get("provider"):
            host.extend({"event": "familiar_clear", "tick": start - 25 + i * 12} for i in range(8))
            host.append(
                {
                    "event": "familiar_drop",
                    "tick": start + 60,
                    "seed": start,
                    "variant": rules["provider"]["pickup"] or 20,
                    "subtype": rules["provider"]["subtype"] or 1,
                    "controller": 1,
                }
            )
        for i in range(3):
            tick = start + i * rules.get("interval", 22)
            shots = [
                {
                    "id": tick * 10 + j,
                    "age": 1,
                    "source_age": tick,
                    "damage": damage,
                    "controller": 1,
                    "spectral": bool(rules.get("spectral")),
                    "flags": {flag: True for flag in rules.get("flags", [])},
                    "variant": i % 2 if rules.get("observe_flags") else 0,
                    "vx": x,
                    "vy": y,
                }
                for j, (x, y) in enumerate(directions)
            ]
            host.append(probe(tick, shots=shots))
            if rules.get("blocks"):
                host.append(
                    {
                        "event": "familiar_block",
                        "tick": tick,
                        "removed": True,
                        "familiar_collision": True,
                    }
                )
            host.append(
                {
                    "event": "familiar_hit",
                    "tick": tick + 5,
                    "amount": damage,
                    "before": 100,
                    "after": 100 - damage,
                    "bleeding": bool(rules.get("damage_over_time")),
                    "fear": bool(rules.get("fear")),
                    "controller": 1,
                    "rock_intact": bool(rules.get("spectral")),
                }
            )
    host.sort(key=lambda e: e["tick"])
    client = deepcopy([e for e in host if e["event"] in ("familiar_probe", "familiar_drop")])
    for event in host + client:
        event["tick"] *= rules.get("timeline_scale", 1)
    return {"enum": enum, "slot": 0}, {"host": host, "client": client}


@pytest.mark.parametrize("enum", FAMILIAR_EFFECTS)
def test_familiar_requires_attack_and_lifecycle_evidence(enum):
    case, peers = evidence(enum)
    assert all(c["status"] == "passed" for c in familiar_checks(case, peers))
    peers["host"] = [
        e
        for e in peers["host"]
        if e["event"] not in ("familiar_hit", "familiar_drop", "familiar_block")
    ]
    assert any(c["status"] == "missing" for c in familiar_checks(case, peers))


def test_lil_haunt_contact_damage_alone_does_not_prove_fear():
    case, peers = evidence("COLLECTIBLE_LIL_HAUNT")
    for event in peers["host"]:
        if event["event"] == "familiar_hit":
            event["fear"] = False
    assert any(c["status"] == "failed" for c in familiar_checks(case, peers))


def test_twisted_pair_requires_both_familiars_and_both_shots():
    case, peers = evidence("COLLECTIBLE_TWISTED_PAIR")
    for event in peers["host"]:
        if event["event"] == "familiar_probe":
            event["familiars"] = event["familiars"][:1]
            event["shots"] = event["shots"][:1]
    checks = familiar_checks(case, peers)
    assert {"name": "familiar_acquired", "status": "failed"} in checks
    assert {"name": "familiar_initial_volley", "status": "failed"} in checks


@pytest.mark.parametrize("fault", ("owner", "health", "cadence", "replica", "removal", "teammate"))
def test_familiar_rejects_visible_but_incorrect_effects(fault):
    case, peers = evidence()
    if fault == "owner":
        peers["host"][0]["familiars"][0]["controller"] = 2
    elif fault == "health":
        next(e for e in peers["host"] if e["event"] == "familiar_hit")["after"] = 100
    elif fault == "cadence":
        next(e for e in peers["host"] if e.get("shots"))["shots"][0]["age"] = 5
    elif fault == "replica":
        next(e for e in peers["client"] if e.get("shots"))["shots"] = []
    elif fault == "removal":
        peers["host"][-1]["familiars"] = [{"x": 130, "y": 100, "controller": 1}]
    else:
        peers["host"][0]["teammate_owned"] = 1
    assert any(c["status"] == "failed" for c in familiar_checks(case, peers))


def test_familiar_spectral_requires_real_hit_behind_intact_rock():
    case, peers = evidence("COLLECTIBLE_GHOST_BABY")
    next(e for e in peers["host"] if e["event"] == "familiar_hit")["rock_intact"] = False
    assert any(c["status"] == "failed" for c in familiar_checks(case, peers))


def test_projectile_disappearance_without_familiar_collision_is_not_blocking_evidence():
    case, peers = evidence("COLLECTIBLE_SACRIFICIAL_DAGGER")
    for event in peers["host"]:
        if event["event"] == "familiar_block":
            event["familiar_collision"] = False
    assert any(
        c["name"].endswith("blocks_projectiles") and c["status"] == "failed"
        for c in familiar_checks(case, peers)
    )


def test_contact_damage_accounts_for_overlapping_native_observation_windows():
    case, peers = evidence("COLLECTIBLE_DISTANT_ADMIRATION")
    first = next(e for e in peers["host"] if e["event"] == "familiar_hit")
    second = {
        **first,
        "tick": first["tick"] + 1,
        "before": first["after"],
        "after": first["after"] - first["amount"],
    }
    first["after_tick"] = first["tick"] + 2
    first["after"] = second["after"]
    peers["host"].append(second)
    assert all(c["status"] == "passed" for c in familiar_checks(case, peers))
    second["after"] += second["amount"]
    assert any(
        c["name"].endswith("contact_damage") and c["status"] == "failed"
        for c in familiar_checks(case, peers)
    )


def test_familiar_replica_only_materializes_its_current_room():
    case, peers = evidence()
    for e in peers["client"]:
        if e["tick"] < 390:
            e["room_visible"] = False
            e["familiars"], e["shots"] = [], []
    assert all(c["status"] == "passed" for c in familiar_checks(case, peers))
    peers["client"] = []
    assert any(c["status"] == "missing" for c in familiar_checks(case, peers))


def test_familiar_replica_requires_observed_attacks():
    case, peers = evidence()
    peers["client"] = [e for e in peers["client"] if not e["shots"]]
    assert any(c["status"] == "failed" for c in familiar_checks(case, peers))


def test_familiar_damage_waits_for_native_update_and_clears_between_cases():
    script = """
        FamiliarVariant = { GHOST_BABY = 9 }
        Vector = { Zero = {} }
        local events = {}
        local helper = dofile('tests/fixtures/item_audit_familiars.lua')(
            function(name, value) events[#events + 1] = { name, value } end,
            function() end, function() end, function() end)
        local case = { familiar_effects = { variant = 'GHOST_BABY' }, slot = 0 }
        local target = { HitPoints = 100 }
        function target:GetData() return { auditFamiliarTarget = true } end
        local familiar = { Variant = 9, Player = { ControllerIndex = 1 } }
        function familiar:ToFamiliar() return self end
        helper.prepare(case)
        assert(helper.holdTarget(target) == true)
        assert(helper.holdTarget({GetData = function() return {} end}) == nil)
        helper.advance(case, 160)
        helper.damage(target, 3.5, { Entity = familiar })
        helper.sample(case, 160, true)
        helper.sample(case, 161, true)
        assert(#events == 0, 'Damage must wait for the deferred native update')
        target.HitPoints = 96.5
        helper.sample(case, 162, true)
        assert(#events == 1 and events[1][1] == 'familiar_hit')
        local hit = events[1][2]
        assert(hit.before == 100 and hit.after == 96.5 and hit.amount == 3.5)
        assert(hit.after_tick > hit.tick and hit.entity == nil)
        helper.damage(target, 3.5, { Entity = familiar })
        helper.prepare({})
        assert(helper.holdTarget(target) == nil)
        helper.sample(case, 164, true)
        assert(#events == 1, 'Pending native references must be dropped on exit')
        local tear = {
            FrameCount = 1, SpawnerEntity = { ToPlayer = function() return true end }
        }
        function tear:Remove() error('Player tear suppression survived case cleanup') end
        helper.suppressPlayerTear(tear)
        helper.prepare(case)
        tear.FrameCount = 0
        function tear:Remove() error('Incubus source has not been assigned yet') end
        helper.suppressPlayerTear(tear)
        tear.FrameCount = 1
        tear.SpawnerEntity = { ToPlayer = function() return nil end }
        helper.suppressPlayerTear(tear)
        local removed = false
        tear.SpawnerEntity = { ToPlayer = function() return true end }
        function tear:Remove() removed = true end
        helper.suppressPlayerTear(tear)
        assert(removed, 'Only the holder tear is isolated from target damage')
        helper.advance(case, 180)
        helper.damage(target, 3.5, { Entity = familiar })
        helper.damage(target, 3.5, { Entity = familiar })
        target.HitPoints = 89.5
        helper.sample(case, 182, true)
        hit = events[#events][2]
        assert(hit.hits == 2 and hit.amount == 7 and hit.before - hit.after == 7)
    """
    executable = shutil.which("lua5.3") or shutil.which("lua")
    assert executable, "Lua 5.3 is required"
    subprocess.run(
        [executable, "-"],
        input=script,
        text=True,
        cwd=Path(__file__).resolve().parents[1],
        check=True,
    )


def test_familiar_cadence_uses_native_updates_during_network_barriers():
    case, peers = evidence()
    for peer in peers.values():
        for e in peer:
            if e["event"] == "familiar_probe" and e["shots"]:
                e["tick"] += 1 if e["tick"] % 3 else 2
    assert all(c["status"] == "passed" for c in familiar_checks(case, peers))


def test_familiar_host_room_uses_native_identities_when_not_replicated():
    case, peers = evidence("COLLECTIBLE_LIL_LOKI")
    for e in peers["host"]:
        if e["event"] == "familiar_probe" and e["tick"] < 390:
            for s in e["shots"]:
                s["seed"], s["id"] = s["id"], 0
    for e in peers["client"]:
        if e["tick"] < 390:
            e["room_visible"] = False
            e["familiars"], e["shots"] = [], []
    assert all(c["status"] == "passed" for c in familiar_checks(case, peers))


def test_contact_fear_needs_a_real_proc_without_requiring_every_hit_to_keep_the_flag():
    case = {"enum": "COLLECTIBLE_LIL_HAUNT", "slot": 0}
    _, observations = evidence(case["enum"])
    hits = [e for e in observations["host"] if e["event"] == "familiar_hit"]
    hits[0]["fear"] = False
    checks = familiar_checks(case, observations)
    assert {"name": "familiar_contact_fear", "status": "passed"} in checks
    assert {"name": "familiar_initial_contact_damage", "status": "passed"} in checks
    for hit in hits:
        hit["fear"] = False
    assert {"name": "familiar_contact_fear", "status": "failed"} in familiar_checks(
        case, observations
    )
