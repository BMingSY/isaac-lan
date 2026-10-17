from copy import deepcopy
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from item_familiar_effects import FAMILIAR_EFFECTS, familiar_checks


def evidence(enum="COLLECTIBLE_BROTHER_BOBBY"):
    rules = FAMILIAR_EFFECTS[enum]
    host = []

    def probe(tick, *, shots=None):
        removed = tick >= 780
        moved = tick > 110
        return {
            "event": "familiar_probe",
            "tick": tick,
            "room": 85 if 300 < tick < 390 else 84,
            "stage": 2 if tick > 390 else 1,
            "x": 150 if moved else 100,
            "y": 100,
            "owned": 0 if removed else 1,
            "teammate_owned": 0,
            "room_visible": True,
            "familiars": []
            if removed
            else [{"x": 130 if moved else 80, "y": 100, "controller": 1}],
            "shots": shots or [],
        }

    host.extend(probe(t) for t in (90, 140, 360, 610, 820))
    damage = rules.get("damage", 3.5 * rules.get("damage_factor", 1))
    directions = {
        None: [(0, -8)],
        "split": [(-3, -8), (3, -8)],
        "cross": [(-8, 0), (8, 0), (0, -8), (0, 8)],
    }[rules.get("pattern")]
    for start in (175, 655):
        for i in range(3):
            tick = start + i * rules["interval"]
            shots = [
                {
                    "id": tick * 10 + j,
                    "age": 1,
                    "damage": damage,
                    "controller": 1,
                    "spectral": bool(rules.get("spectral")),
                    "vx": x,
                    "vy": y,
                }
                for j, (x, y) in enumerate(directions)
            ]
            host.append(probe(tick, shots=shots))
            host.append(
                {
                    "event": "familiar_hit",
                    "tick": tick + 5,
                    "amount": damage,
                    "before": 100,
                    "after": 100 - damage,
                    "controller": 1,
                    "rock_intact": bool(rules.get("spectral")),
                }
            )
    host.sort(key=lambda e: e["tick"])
    client = deepcopy([e for e in host if e["event"] == "familiar_probe"])
    return {"enum": enum, "slot": 0}, {"host": host, "client": client}


@pytest.mark.parametrize("enum", FAMILIAR_EFFECTS)
def test_familiar_requires_attack_and_lifecycle_evidence(enum):
    case, peers = evidence(enum)
    assert all(c["status"] == "passed" for c in familiar_checks(case, peers))
    peers["host"] = [e for e in peers["host"] if e["event"] != "familiar_hit"]
    assert any(c["status"] == "missing" for c in familiar_checks(case, peers))


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
        helper.sample(case, 164, true)
        assert(#events == 1, 'Pending native references must be dropped on exit')
        local tear = { SpawnerEntity = { ToPlayer = function() return true end } }
        function tear:Remove() error('Player tear suppression survived case cleanup') end
        helper.suppressPlayerTear(tear)
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
