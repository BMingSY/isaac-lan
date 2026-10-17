import json
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from item_audit import catalog_from_log, events, select_cases, summarize_case
from lab_profile import validate_labs, validate_startup


def test_effect_recipes_use_real_unique_catalog_enums():
    from item_effect_checks import SUPPORTED_EFFECTS

    catalog = json.loads((ROOT / "tests/fixtures/item_catalog.json").read_text())
    names = [item.get("enum") for item in catalog["items"]]
    assert all(names.count(name) == 1 for name in SUPPORTED_EFFECTS)


def test_damage_effects_require_real_loss_expiry_and_replica_health():
    from copy import deepcopy
    from item_damage_effects import damage_checks

    case = {"enum": "PILLEFFECT_PERCS", "slot": 0}
    host = [
        {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [{"hearts": 12, "max_hearts": 24, "soul": 0, "broken": 0} for _ in (0, 1)],
        }
        for label, tick in (("before", 30), ("post_use", 61))
    ]
    left = [12, 12]
    for name, tick, losses, room in (
        ("first", 90, [1, 2], 84),
        ("repeat", 180, [1, 2], 84),
        ("next_room", 330, [2, 2], 85),
    ):
        for slot, loss in enumerate(losses):
            host.append(
                {
                    "event": "damage_trial",
                    "probe": name,
                    "tick": tick,
                    "slot": slot,
                    "amount": 2,
                    "room": room,
                    "stage": 1,
                    "before": {"hearts": left[slot], "soul": 0, "broken": 0},
                    "after": {"hearts": left[slot] - loss, "soul": 0, "broken": 0},
                }
            )
            left[slot] -= loss
        host.append(
            {
                "event": "sample",
                "label": "captured",
                "tick": tick + 30,
                "players": [{"hearts": n, "max_hearts": 24, "soul": 0, "broken": 0} for n in left],
            }
        )
    host.append({"event": "damage_transition", "tick": 240, "room": 84, "stage": 1})
    peers = {"host": host, "client": deepcopy([e for e in host if e.get("label") == "captured"])}
    assert all(c["status"] == "passed" for c in damage_checks(case, peers))
    # A shield on the teammate, or reduction that survives changing rooms,
    # must fail even when the game used the item and stayed connected.
    wrong = deepcopy(peers)
    next(e for e in wrong["host"] if e.get("probe") == "first" and e["slot"] == 1)["after"][
        "hearts"
    ] += 1
    assert any(c["status"] == "failed" for c in damage_checks(case, wrong))
    wrong = deepcopy(peers)
    trial = next(e for e in wrong["host"] if e.get("probe") == "next_room" and e["slot"] == 0)
    trial["after"]["hearts"] += 1
    assert any(c["status"] == "failed" for c in damage_checks(case, wrong))
    wrong = deepcopy(peers)
    wrong["client"][-1]["players"][0]["hearts"] += 1
    assert any(c["status"] == "failed" for c in damage_checks(case, wrong))
    delayed = deepcopy(peers)
    for trial in delayed["host"]:
        if trial.get("probe") == "first":
            trial["tick"] = 101
    before_hit = {**deepcopy(host[0]), "label": "captured", "tick": 100}
    delayed["host"].append(before_hit)
    delayed["client"].append(deepcopy(before_hit))
    assert all(c["status"] == "passed" for c in damage_checks(case, delayed))
    wrong = deepcopy(peers)
    wrong["host"][1]["players"][1]["hearts"] = 24
    assert any(
        c["name"] == "damage_use_hearts" and c["status"] == "failed"
        for c in damage_checks(case, wrong)
    )
    peers["client"].pop()
    assert any(c["status"] == "missing" for c in damage_checks(case, peers))


def test_damage_shield_requires_peer_state_and_expiry():
    from copy import deepcopy
    from item_damage_effects import damage_checks

    host = [
        {
            "event": "sample",
            "label": "captured",
            "tick": tick,
            "players": [
                {"shield": {"shadows": count, "invincible": bool(count)}},
                {"shield": {"shadows": 0, "invincible": False}},
            ],
        }
        for tick, count in ((120, 1), (450, 0))
    ]
    peers = {"host": host, "client": deepcopy(host)}

    def status():
        return next(
            c["status"]
            for c in damage_checks({"enum": "COLLECTIBLE_BOOK_OF_SHADOWS", "slot": 0}, peers)
            if c["name"] == "damage_shield_peer"
        )

    assert status() == "passed"
    peers["client"][0]["players"][0]["shield"]["shadows"] = 0
    assert status() == "failed", "A missing replica shield passed damage-only verification"
    peers["client"] = deepcopy(host)
    peers["client"][1]["players"][0]["shield"]["invincible"] = True
    assert status() == "failed", "An expired shield remained on the replica"
    del peers["client"][1]["players"][0]["shield"]
    assert status() == "missing"


def test_damage_effect_cases_include_expiry_floor_and_horse_prerequisites():
    catalog = json.loads((ROOT / "tests/fixtures/item_catalog.json").read_text())
    cases = select_cases(catalog, ["pill:28", "pill:29", "trinket:121", "card:39"])
    percs = next(c for c in cases if c["item"] == "pill:28" and c["horse"])
    assert percs["damage_effects"]["hearts"] == 12
    assert percs["damage_effects"]["full_heal"] is True
    addicted = next(c for c in cases if c["item"] == "pill:29" and c["horse"])
    assert addicted["damage_effects"]["broken"] == 1
    cross = next(c for c in cases if c["item"] == "trinket:121")
    assert len([s for s in cross["damage_effects"]["steps"] if s["action"] == "floor"]) == 2
    algiz = next(c for c in cases if c["item"] == "card:39")
    assert algiz["end_tick"] > 60 + 20 * 30


def test_damage_fixture_observes_after_simulation_and_clears_pending_on_next_case():
    import shutil
    import subprocess

    executable = shutil.which("lua5.3") or shutil.which("lua")
    if not executable:
        pytest.skip("Lua is unavailable")
    script = r"""
        local factory = dofile("tests/fixtures/item_audit_damage.lua")
        local records, players = {}, {}
        for i = 0, 1 do
            players[i] = {
                hearts = 12,
                GetHearts = function(p) return p.hearts end,
                GetMaxHearts = function() return 24 end,
                GetSoulHearts = function() return 0 end,
                GetBrokenHearts = function() return 0 end,
                GetDamageCooldown = function() return 0 end,
                GetTrinketMultiplier = function() return 0 end,
                GetEffects = function() return {GetCollectibleEffectNum=function() return 0 end} end,
                AddMaxHearts = function() end,
                AddSoulHearts = function() end,
                AddHearts = function(p, n) p.hearts = p.hearts + n end,
                ResetDamageCooldown = function() end,
                TakeDamage = function(p, n) p.pending = n end,
            }
        end
        function EntityRef(p) return p end
        CollectibleType = {COLLECTIBLE_HOLY_MANTLE=313}
        TrinketType = {TRINKET_WOODEN_CROSS=121}
        function Game() return { GetRoom=function() return {GetFrameCount=function() return 10 end} end,
            GetLevel = function()
            return { GetStage = function() return 1 end }
        end } end
        _IsaacLan = { rooms_positions = function()
            return { ["0"] = {index=84}, ["1"] = {index=97} }
        end }
        local probe = factory(function(event, v)
            assert(event == "damage_trial")
            records[#records+1] = v
        end, function(slot, callback) callback(players[slot]) end)
        local case = {slot=0, damage_effects={steps={
            {action="hit", name="first", tick=90, amount=2},
            {action="hit", name="repeat", tick=180, amount=2},
        }}}
        probe.prepare(case)
        probe.advance(case, 90)
        assert(#records == 0)
        for _, p in pairs(players) do p.hearts = p.hearts - p.pending end
        probe.advance(case, 91)
        assert(#records == 2)
        assert(records[1].before.hearts == 24 and records[1].after.hearts == 22)
        assert(records[1].tick == 90 and records[1].after_tick == 91)
        probe.advance(case, 180)
        probe.prepare(case)
        probe.advance(case, 31)
        assert(#records == 2, "Old case leaked a pending hit into its successor")
    """
    subprocess.run([executable, "-"], input=script, text=True, cwd=ROOT, check=True)


def test_mapping_checks_actual_reveal_peer_and_next_floor():
    from copy import deepcopy
    from item_room_effects import room_effect_checks

    def sample(label, tick, stage, flags):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "floor_effects": {
                "stage": stage,
                "map": [
                    {"index": 10, "type": 1, "flags": flags},
                    {"index": 11, "type": 7, "flags": 0},
                ],
            },
        }

    host = [sample("before", 30, 1, 0)]
    host += [sample("captured", t, 1 if t < 360 else 2, 1) for t in (90, 120, 360, 390)]
    peers = {"host": host, "client": deepcopy(host[1:])}
    case = {"enum": "COLLECTIBLE_TREASURE_MAP"}
    assert all(c["status"] == "passed" for c in room_effect_checks(case, peers))
    peers["client"][-1]["floor_effects"]["map"][0]["flags"] = 0
    assert (
        next(c for c in room_effect_checks(case, peers) if c["name"] == "map_next_floor")["status"]
        == "failed"
    )
    peers["client"] = peers["client"][:2]
    assert (
        next(c for c in room_effect_checks(case, peers) if c["name"] == "map_next_floor")["status"]
        == "missing"
    )
    case["enum"] = "CARD_WORLD"
    # A one-use reveal must not remain on the following floor.
    peers["client"] = deepcopy(host[1:])
    assert (
        next(c for c in room_effect_checks(case, peers) if c["name"] == "map_next_floor")["status"]
        == "failed"
    )


def test_curse_removal_preserves_labyrinth_and_requires_replica_evidence():
    from copy import deepcopy
    from item_room_effects import room_effect_checks

    def sample(label, tick, curses):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "floor_effects": {"stage": 1, "curses": curses},
        }

    host = [
        {"event": "floor_effect_precondition", "initial_curses": 7, "remaining_curses": 2},
        sample("before", 30, 7),
        sample("captured", 90, 2),
        sample("captured", 120, 2),
    ]
    peers = {"host": host, "client": deepcopy(host[2:])}
    case = {"enum": "RUNE_DAGAZ"}
    assert all(c["status"] == "passed" for c in room_effect_checks(case, peers))
    peers["client"][-1]["floor_effects"]["curses"] = 0
    assert room_effect_checks(case, peers)[-1]["status"] == "failed"


def test_treasure_map_can_reveal_special_room_outlines_when_ordinary_rooms_are_explored():
    from copy import deepcopy
    from item_room_effects import room_effect_checks

    def sample(label, tick, stage, flag):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "floor_effects": {
                "stage": stage,
                "map": [
                    {"index": 10, "type": 1, "flags": 5},
                    {"index": 11, "type": 5, "flags": flag},
                ],
            },
        }

    host = [sample("before", 30, 1, 0)]
    host += [sample("captured", t, 1 if t < 360 else 2, 1) for t in (90, 120, 360, 390)]
    peers = {"host": host, "client": deepcopy(host[1:])}
    case = {"enum": "COLLECTIBLE_TREASURE_MAP"}
    assert all(c["status"] == "passed" for c in room_effect_checks(case, peers))
    peers["client"][0]["floor_effects"]["map"][1]["flags"] = 5
    assert (
        next(c for c in room_effect_checks(case, peers) if c["name"] == "map_scope")["status"]
        == "failed"
    )


def test_horse_amnesia_forgets_other_pills_and_does_not_carry_its_curse():
    from copy import deepcopy
    from item_room_effects import room_effect_checks

    def sample(label, tick, stage, curses, known):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "floor_effects": {
                "stage": stage,
                "curses": curses,
                "identified_pills": [{"color": c, "known": known} for c in (1, 2, 3)],
            },
        }

    host = [
        {"event": "floor_effect_precondition", "initial_curses": 0, "remaining_curses": 4},
        {"event": "pill_assigned", "color": 2049},
        sample("before", 30, 1, 0, True),
    ]
    host += [sample("captured", t, 1, 4, False) for t in (90, 120)]
    host += [{"event": "floor_curse_roll", "stage": 2, "curses": 0}]
    host += [sample("captured", t, 2, 0, False) for t in (360, 390)]
    peers = {"host": host, "client": deepcopy([e for e in host if e.get("label") == "captured"])}
    case = {"enum": "PILLEFFECT_AMNESIA", "horse": True}
    assert all(c["status"] == "passed" for c in room_effect_checks(case, peers))
    peers["client"][0]["floor_effects"]["identified_pills"][1]["known"] = True
    assert room_effect_checks(case, peers)[-1]["status"] == "failed"
    peers["client"][-1]["floor_effects"]["curses"] = 4
    assert (
        next(c for c in room_effect_checks(case, peers) if c["name"] == "curse_next_floor")[
            "status"
        ]
        == "failed"
    )


def test_familiar_counts_follow_the_replica_room_and_reappear_on_reunion():
    from copy import deepcopy
    from item_effect_checks import consumable_checks, stat_checks

    case = {"enum": "PILLEFFECT_FRIENDS_TILL_THE_END", "slot": 0, "split": True}

    def sample(label, tick, flies, joined=False):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [
                {"slot": 0, "room": 84, "owned_blue_flies": flies, "room_visible": True},
                {
                    "slot": 1,
                    "room": 84 if joined else 97,
                    "owned_blue_flies": 0,
                    "room_visible": True,
                },
            ],
        }

    host = [sample("before", 30, 0), sample("post_use", 61, 3)]
    host += [sample("captured", t, 3, t >= 180) for t in (90, 120, 180, 210)]
    client = deepcopy(host[2:])
    for e in client[:2]:
        e["players"][0].update(owned_blue_flies=0, room_visible=False)
    peers = {"host": host, "client": client}
    checks = lambda: stat_checks(case, peers) + consumable_checks(case, peers)
    assert all(c["status"] == "passed" for c in checks())
    client[0]["players"][0]["owned_blue_flies"] = 3
    assert any(c["status"] == "failed" for c in checks())
    client[0]["players"][0]["owned_blue_flies"] = 0
    client[-1]["players"][0]["owned_blue_flies"] = 0
    assert next(c for c in checks() if c["name"] == "familiar_reunion")["status"] == "failed"
    peers["client"] = client[:2]
    assert next(c for c in checks() if c["name"] == "familiar_reunion")["status"] == "missing"


def test_all_effect_scenarios_build_a_parseable_native_fixture(tmp_path):
    import shutil
    import subprocess
    from item_audit import build_fixture
    from item_effect_checks import SUPPORTED_EFFECTS

    catalog = json.loads((ROOT / "tests/fixtures/item_catalog.json").read_text())
    keys = [item["key"] for item in catalog["items"] if item.get("enum") in SUPPORTED_EFFECTS]
    path = tmp_path / "effects.lua"
    build_fixture(
        path,
        {
            "cases": select_cases(catalog, keys),
            "journal": {"host": "host.log", "client": "client.log"},
        },
    )
    subprocess.run([shutil.which("luac5.3") or "luac", "-p", str(path)], check=True)


def test_teleport_requires_correct_destination_and_independent_teammate():
    from copy import deepcopy
    from item_effect_checks import consumable_checks

    case = {"enum": "CARD_EMPEROR", "slot": 1}

    def sample(label, tick, destination, room_type):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [{"room": 84}, {"room": destination, "room_type": room_type}],
        }

    host = [{"event": "teleport_target", "types": [5]}, sample("before", 30, 97, 1)]
    host += [sample("captured", t, 65, 5) for t in (150, 180)]
    peers = {"host": host, "client": deepcopy(host[2:])}
    assert all(c["status"] == "passed" for c in consumable_checks(case, peers))
    host[-1]["players"][1]["room_type"] = 2
    assert consumable_checks(case, peers)[0]["status"] == "failed"
    peers["client"][-1]["players"][0]["room"] = 65
    assert consumable_checks(case, peers)[2]["status"] == "failed"
    peers["client"] = []
    assert all(c["status"] == "missing" for c in consumable_checks(case, peers))


def test_spawned_spiders_require_native_count_and_survive_reunion():
    from copy import deepcopy
    from item_effect_checks import consumable_checks

    case = {"enum": "COLLECTIBLE_BOX_OF_SPIDERS", "slot": 1}

    def sample(label, tick, count):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [
                {"room": 84, "owned_blue_spiders": 0},
                {"room": 84, "owned_blue_spiders": count, "room_visible": True},
            ],
        }

    host = [sample("before", 30, 0), sample("post_use", 61, 6)]
    host += [sample("captured", t, 6) for t in (180, 210)]
    peers = {"host": host, "client": deepcopy(host[2:])}
    assert all(c["status"] == "passed" for c in consumable_checks(case, peers))
    host[1]["players"][1]["owned_blue_spiders"] = 3
    assert consumable_checks(case, peers)[0]["status"] == "failed"
    host[1]["players"][1]["owned_blue_spiders"] = 6
    for e in host[2:] + peers["client"]:
        e["players"][1]["owned_blue_spiders"] = 0
    assert (
        next(c for c in consumable_checks(case, peers) if c["name"] == "familiar_reunion")["status"]
        == "failed"
    )


def test_room_damage_checks_remote_authority_and_visible_replica():
    from copy import deepcopy
    from item_effect_checks import consumable_checks

    case = {"enum": "CARD_DEATH", "slot": 0}

    def sample(label, tick, hp):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [
                {
                    "room": 84,
                    "stage": 1,
                    "room_visible": True,
                    "targets": [{"seed": seed, "hp": hp} for seed in (1, 2)],
                },
                {},
            ],
        }

    host = [sample("before", 30, 200), sample("post_use", 61, 160)]
    host += [sample("captured", t, 160) for t in (90, 120)]
    peers = {"host": host, "client": deepcopy(host[2:])}
    assert all(c["status"] == "passed" for c in consumable_checks(case, peers))
    for event in peers["client"]:
        event["players"][0].update(room_visible=False, targets=[])
    assert all(c["status"] == "passed" for c in consumable_checks(case, peers))
    peers["client"][0]["players"][0]["room_visible"] = True
    assert consumable_checks(case, peers)[-1]["status"] == "failed"
    peers["client"] = deepcopy(host[2:])
    host[1]["players"][0]["targets"][0]["hp"] = 200
    assert consumable_checks(case, peers)[0]["status"] == "failed"


def test_prayer_card_requires_heart_conversion_on_next_floor():
    from copy import deepcopy
    from item_effect_checks import consumable_checks

    case = {"enum": "COLLECTIBLE_PRAYER_CARD", "slot": 1}

    def sample(label, tick, room, stage, eternal, maximum):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [
                {"eternal": 0},
                {"eternal": eternal, "room": room, "stage": stage, "max_hearts": maximum},
            ],
        }

    host = [sample("before", 30, 97, 1, 0, 6), sample("post_use", 61, 97, 1, 1, 6)]
    host += [sample("captured", t, 84, 1, 1, 6) for t in (180, 210)]
    host += [sample("captured", t, 84, 2, 0, 8) for t in (360, 390)]
    peers = {"host": host, "client": deepcopy(host[2:])}
    assert all(c["status"] == "passed" for c in consumable_checks(case, peers))
    peers["client"][-1]["players"][1]["max_hearts"] = 6
    assert consumable_checks(case, peers)[-1]["status"] == "failed"


def test_pickup_effect_requires_new_objects_and_replica_evidence():
    from item_effect_checks import spawn_checks

    case = {"enum": "COLLECTIBLE_SQUEEZY", "slot": 1}

    def sample(label, tick, count):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [{"entity_types": {}}, {"entity_types": {"5.10.3": count}}],
        }

    host = [
        sample("before", 30, 1),
        sample("acquired", 30, 3),
        sample("captured", 90, 3),
        sample("captured", 120, 3),
    ]
    peers = {"host": host, "client": host[-2:]}
    assert all(c["status"] == "passed" for c in spawn_checks(case, peers))
    host[1] = sample("acquired", 30, 2)
    assert spawn_checks(case, peers)[0]["status"] == "failed"
    peers["client"] = []
    assert spawn_checks(case, peers)[1]["status"] == "missing"


def test_generated_objects_are_absent_outside_the_client_room():
    from item_effect_checks import spawn_checks

    case = {"enum": "COLLECTIBLE_ANARCHIST_COOKBOOK", "slot": 0}

    def sample(label, tick, count, visible):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [{"entity_types": {"4.3.0": count}, "room_visible": visible}, {}],
        }

    host = [sample("before", 30, 0, True), sample("post_use", 62, 6, True)]
    host += [sample("captured", t, 6, True) for t in (90, 100)]
    client = [sample("replica", t, 0, False) for t in (90, 100)]
    peers = {"host": host, "client": client}
    assert all(c["status"] == "passed" for c in spawn_checks(case, peers))
    client[0]["players"][0]["entity_types"]["4.3.0"] = 6
    assert spawn_checks(case, peers)[1]["status"] == "failed"


def test_multishot_requires_actual_volleys_and_synced_damage():
    from copy import deepcopy
    from item_effect_checks import shot_checks

    case = {"enum": "COLLECTIBLE_INNER_EYE", "slot": 1}
    host = [
        {
            "event": "shot_probe",
            "tick": tick,
            "tears": [
                {"id": offset + i, "age": 1, "damage": 3.5, "vx": i - 2, "vy": -10}
                for i in range(1, 4)
            ],
        }
        for tick, offset in ((90, 0), (120, 3))
    ]
    peers = {"host": host, "client": deepcopy(host)}
    assert all(c["status"] == "passed" for c in shot_checks(case, peers))
    peers["client"][0]["tears"][0]["damage"] = 7
    assert shot_checks(case, peers)[1]["status"] == "failed"
    host[1]["tears"].pop()
    assert shot_checks(case, peers)[0]["status"] == "failed"
    assert all(c["status"] == "missing" for c in shot_checks(case, {}))


def test_consumable_requires_native_use_spawns_and_not_just_acquisition():
    from item_effect_checks import spawn_checks

    case = {"enum": "CARD_HIEROPHANT", "slot": 1}

    def sample(label, tick, count):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [{"entity_types": {}}, {"entity_types": {"5.10.3": count}}],
        }

    host = [
        sample("before", 30, 0),
        sample("acquired", 30, 0),
        sample("post_use", 61, 2),
        sample("captured", 90, 2),
        sample("captured", 120, 2),
    ]
    peers = {"host": host, "client": host[-2:]}
    assert all(c["status"] == "passed" for c in spawn_checks(case, peers))
    host[2] = sample("post_use", 61, 0)
    assert spawn_checks(case, peers)[0]["status"] == "failed"


def test_tower_waits_for_all_six_native_bombs_and_rejects_extra_bombs():
    from item_effect_checks import spawn_checks

    def sample(label, tick, bombs):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [{"entity_types": {"4.3.0": bombs}}, {}],
        }

    host = [
        sample("before", 30, 0),
        sample("post_use", 62, 0),
        sample("captured", 90, 5),
        sample("captured", 91, 6),
        sample("captured", 120, 6),
    ]
    peers = {"host": host, "client": [host[2], host[4]]}
    case = {"enum": "CARD_TOWER", "slot": 0}
    assert all(c["status"] == "passed" for c in spawn_checks(case, peers))
    host[3]["players"][0]["entity_types"]["4.3.0"] = 7
    assert spawn_checks(case, peers)[0]["status"] == "failed"


def test_consumable_doubling_and_room_expiration_require_both_peers():
    from copy import deepcopy
    from item_effect_checks import consumable_checks

    def sample(label, tick, **fields):
        return {"event": "sample", "label": label, "tick": tick, "players": [{}, fields]}

    host = [
        sample("before", 30, coins=7),
        sample("post_use", 61, coins=14),
        sample("captured", 90, coins=14),
        sample("captured", 120, coins=14),
    ]
    peers = {"host": host, "client": deepcopy(host[-2:])}
    case = {"enum": "CARD_DIAMONDS_2", "slot": 1}
    assert all(c["status"] == "passed" for c in consumable_checks(case, peers))
    host[1]["players"][1]["coins"] = 8
    assert consumable_checks(case, peers)[0]["status"] == "failed"
    peers["client"][0]["players"][1]["coins"] = 7
    assert consumable_checks(case, peers)[1]["status"] == "failed"
    host = [
        sample("before", 30, flying=False, room=84),
        sample("captured", 180, flying=False, room=85),
        sample("captured", 210, flying=False, room=85),
    ]
    peers = {"host": host, "client": deepcopy(host[-2:])}
    case = {"enum": "CARD_HANGED_MAN", "slot": 1}
    assert consumable_checks(case, peers)[0]["status"] == "passed"
    peers["client"][0]["players"][1]["flying"] = True
    assert consumable_checks(case, peers)[0]["status"] == "failed"
    peers["client"] = []
    assert consumable_checks(case, peers)[0]["status"] == "missing"


def test_room_damage_requires_each_target_and_replica_health():
    from copy import deepcopy
    from item_effect_checks import consumable_checks

    def sample(label, tick, hp):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [{}, {"targets": [{"seed": i, "hp": hp} for i in (1, 2)]}],
        }

    host = [
        sample("before", 30, 200),
        sample("post_use", 61, 160),
        sample("captured", 90, 160),
        sample("captured", 120, 160),
    ]
    peers = {"host": host, "client": deepcopy(host[-2:])}
    case = {"enum": "CARD_DEATH", "slot": 1}
    assert all(c["status"] == "passed" for c in consumable_checks(case, peers))
    host[1]["players"][1]["targets"][1]["hp"] = 200
    assert consumable_checks(case, peers)[0]["status"] == "failed"
    peers["client"][0]["players"][1]["targets"].pop()
    assert consumable_checks(case, peers)[1]["status"] == "failed"


def test_generated_consumable_counts_held_and_dropped_pockets():
    from copy import deepcopy
    from item_effect_checks import consumable_checks
    from import_item_audit import item_status

    def sample(label, tick, card, floor):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [{"card": 0, "pill": 0}, {"card": card, "pill": 0, "entity_types": floor}],
        }

    case = {"enum": "COLLECTIBLE_DECK_OF_CARDS", "slot": 1}
    for initial, floor in ((0, {}), (1, {"5.300.1": 1})):
        host = [
            sample("before", 30, initial, {}),
            sample("post_use", 62, 6, floor),
            sample("captured", 90, 6, floor),
            sample("captured", 120, 6, floor),
        ]
        peers = {"host": host, "client": deepcopy(host[-2:])}
        assert all(c["status"] == "passed" for c in consumable_checks(case, peers))
        host[1]["players"][1] = deepcopy(host[0]["players"][1])
        assert consumable_checks(case, peers)[0]["status"] == "failed"
    checks = [
        {
            "case": "collectible:85/" + context,
            "status": "verified",
            "conditions": {"pocket_effect": True},
        }
        for context in ("host-same", "client-split")
    ]
    assert item_status("collectible:85", checks) == "basic_pass"
    checks += [{**c, "case": c["case"] + "/occupied"} for c in checks]
    assert item_status("collectible:85", checks) == "verified"


def test_horse_pill_swaps_increase_resources_and_swap_golden_flags():
    from copy import deepcopy
    from item_effect_checks import consumable_checks

    def sample(label, tick, bombs, keys, golden_bomb, golden_key):
        return {
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [
                {},
                dict(
                    bombs=bombs,
                    keys=keys,
                    golden_bomb=golden_bomb,
                    golden_key=golden_key,
                    room=84 if tick < 150 else 85,
                    stage=1 if tick < 240 else 2,
                ),
            ],
        }

    case = {"enum": "PILLEFFECT_BOMBS_ARE_KEYS", "slot": 1, "horse": True}
    host = [
        sample("before", 30, 4, 8, True, False),
        sample("post_use", 62, 12, 6, False, True),
        sample("captured", 90, 12, 6, False, True),
        sample("captured", 120, 12, 6, False, True),
        sample("captured", 180, 12, 6, False, True),
        sample("captured", 210, 12, 6, False, True),
        sample("captured", 360, 12, 6, False, False),
        sample("captured", 390, 12, 6, False, False),
    ]
    peers = {"host": host, "client": deepcopy(host[2:])}
    assert all(c["status"] == "passed" for c in consumable_checks(case, peers))
    host[1]["players"][1]["bombs"] = 8
    assert any(c["status"] == "failed" for c in consumable_checks(case, peers))
    host[1]["players"][1]["bombs"] = 12
    peers["client"][0]["players"][1]["golden_bomb"] = True
    assert any(c["status"] == "failed" for c in consumable_checks(case, peers))
    peers["client"] = deepcopy(host[2:])
    peers["client"][-1]["players"][1]["golden_key"] = True
    assert any(
        c["name"] == "golden_flags_clear_on_floor" and c["status"] == "failed"
        for c in consumable_checks(case, peers)
    )


def test_chaos_needs_shared_pool_removal_and_holder_only_ownership():
    from item_effect_checks import effect_checks

    case = {"enum": "COLLECTIBLE_CHAOS", "slot": 1}
    probes = [
        {
            "event": "pool_probe",
            "label": label,
            "slot": slot,
            "owned": int(label == "acquired" and slot == 1),
            "results": list(range(32)) if label != "acquired" else list(range(32, 64)),
        }
        for label in ("before", "acquired", "removed")
        for slot in (0, 1)
    ]
    samples = [
        {
            "event": "sample",
            "tick": tick,
            "players": [{"slot": 0, "target_count": 0}, {"slot": 1, "target_count": 1}],
        }
        for tick in (90, 120)
    ]
    peers = {"host": [*probes, *samples], "client": samples}
    assert all(c["status"] == "passed" for c in effect_checks(case, peers))
    probes[2]["results"] = probes[0]["results"]
    assert any(
        c["name"] == "shared_pool" and c["status"] == "failed" for c in effect_checks(case, peers)
    )
    peers["client"] = []
    assert any(c["status"] == "missing" for c in effect_checks(case, peers))


def test_effect_verification_needs_every_attribute_and_both_peer_snapshots():
    case = {"key": "collectible:14/client-split", "enum": "COLLECTIBLE_ROID_RAGE", "slot": 1}

    def event(name, **values):
        return {"event": name, "key": case["key"], **values}

    def sample(label, tick, speed, reach):
        return event(
            "sample",
            label=label,
            tick=tick,
            players=[
                {"slot": 0, "speed": 1, "range": 260},
                {"slot": 1, "speed": speed, "range": reach},
            ],
        )

    host = [event(n) for n in ("case_begin", "give_end", "use_return", "case_end")]
    before = sample("before", 30, 1, 260)
    later = [sample("captured", t, 1.3, 360) for t in (90, 120)]
    peers = {"host": [*host, before, *later], "client": [event("case_end"), *later]}
    assert summarize_case(case, peers)["compatibility_verified"]
    later[0]["players"][0]["speed"] = 1.3
    result = summarize_case(case, peers)
    assert any(p["detail"] == "holder_only" for p in result["problems"])
    later[0]["players"][0]["speed"] = 1
    peers["client"] = [event("case_end"), later[0]]
    result = summarize_case(case, peers)
    assert (
        not result["compatibility_verified"] and "peer_effect_state" in result["unconfirmed_checks"]
    )
    peers["client"] = [event("case_end"), *later]
    for value in later:
        value["players"][1]["range"] = 260
    result = summarize_case(case, peers)
    assert not result["compatibility_verified"] and result["status"] == "problem"
    assert any(p["detail"] == "effect:range" for p in result["problems"])
    peers["host"].remove(before)
    result = summarize_case(case, peers)
    assert not result["compatibility_verified"] and "effect:speed" in result["unconfirmed_checks"]


def test_cleanup_crash_revokes_an_effect_pass():
    case = {"key": "collectible:1/host-same", "enum": "COLLECTIBLE_SAD_ONION", "slot": 0}

    def event(name, **values):
        return {"event": name, "key": case["key"], **values}

    later = [
        event(
            "sample",
            label="captured",
            tick=t,
            players=[{"slot": 0, "delay": 7}, {"slot": 1, "delay": 10}],
        )
        for t in (90, 120)
    ]
    host = [event(n) for n in ("case_begin", "give_begin", "give_end", "use_return", "case_end")]
    peers = {
        "host": [
            *host,
            event(
                "sample",
                label="before",
                tick=30,
                players=[{"slot": 0, "delay": 10}, {"slot": 1, "delay": 10}],
            ),
            *later,
        ],
        "client": [event("case_end"), *later],
    }
    assert summarize_case(case, peers)["compatibility_verified"]
    result = summarize_case(case, peers, {"process_exit": {"host": {"exit_code": 0xC0000005}}})
    assert result["status"] == "crash" and not result["compatibility_verified"]


@pytest.mark.parametrize("players", [[], [{"slot": 0, "delay": 7}], [{"slot": 1}, {"slot": 0}]])
def test_incomplete_actor_roster_cannot_verify_an_effect(players):
    from item_effect_checks import effect_checks

    case = {"enum": "COLLECTIBLE_SAD_ONION", "slot": 1}
    before = {"event": "sample", "label": "before", "players": players}
    captured = [
        {"event": "sample", "label": "captured", "tick": t, "players": players} for t in (90, 120)
    ]
    result = effect_checks(case, {"host": [before, *captured], "client": captured})
    assert all(c["status"] == "missing" for c in result)


def test_mega_rendering_state_mismatch_is_detected_even_if_damage_matches():
    case = {"key": "collectible:625/host-same", "mega": True}
    host = [{"event": name, "key": case["key"]} for name in ("case_begin", "give_end")]
    client = []
    for tick in (210, 300):
        sample = {"event": "sample", "key": case["key"], "label": "captured", "tick": tick}
        host.append(
            {**sample, "players": [{"slot": 0, "damage": 14, "size": 20, "temporary_count": 1}]}
        )
        client.append(
            {**sample, "players": [{"slot": 0, "damage": 14, "size": 20, "temporary_count": 0}]}
        )
    result = summarize_case(case, {"host": host, "client": client})
    assert result["status"] == "problem"
    assert any("temporary_count" in p["detail"] for p in result["problems"])


def test_item_verification_needs_both_holders_and_pill_sizes():
    from import_item_audit import item_status

    checks = [{"case": "pill:7/host-same", "status": "verified"}]
    assert item_status("pill:7", checks) == "basic_pass"
    checks += [{"case": "pill:7/client-split", "status": "verified"}]
    assert item_status("pill:7", checks) == "basic_pass"
    checks += [{**c, "case": c["case"] + "/horse"} for c in checks]
    assert item_status("pill:7", checks) == "verified"
    checks.append({"case": "pill:7/host-same", "status": "crash"})
    assert item_status("pill:7", checks) == "crash"


def test_new_candidate_preserves_old_failure_and_build_identity():
    from import_item_audit import start_candidate

    old = {"case": "card:97/host-same", "status": "crash", "evidence": "old/batch-001"}
    findings = {
        "candidate": "old-commit",
        "dll_sha256": "old-dll",
        "audit": {"card:97": {"status": "crash", "checks": [old]}},
        "stress": [],
    }
    start_candidate(findings, {"commit": "new-commit", "dll_sha256": "new-dll"})
    assert old["dll_sha256"] == "old-dll" and old["status"] == "crash"
    assert findings["audit"]["card:97"]["status"] == "crash"
    assert findings["dll_sha256"] == "new-dll"
    assert findings["candidates"]["old-dll"]["commit"] == "old-commit"


def test_peer_failure_stops_batch_before_client_and_host_cases_drift():
    from item_audit import unexpected_peer_failure

    host = [
        {"key": "a", "event": "case_begin", "now_ms": 100},
        {"key": "a", "event": "exit_requested", "now_ms": 200},
    ]
    failure = {"key": "a", "event": "problem", "category": "reconnect", "now_ms": 150}
    assert unexpected_peer_failure(host, [failure]) == failure
    assert unexpected_peer_failure(host, [{**failure, "now_ms": 99}]) is None
    assert unexpected_peer_failure(host, [{**failure, "now_ms": 201}]) is None
    assert unexpected_peer_failure(host, [{**failure, "key": "unstarted"}]) is None


def test_pill_zero_and_horse_variants_are_not_lost_or_used_as_entity_subtypes():
    catalog = {"items": [{"kind": "pill", "id": 0, "key": "pill:0", "entity_subtype": "color"}]}
    cases = select_cases(catalog)
    assert len(cases) == 4
    assert {case["horse"] for case in cases} == {False, True}
    assert {case["slot"] for case in cases} == {0, 1}
    assert all(case["id"] == 0 for case in cases)
    assert all(case["physical"] for case in cases)


def test_partial_or_one_sided_run_never_becomes_verified_compatibility():
    case = {"key": "collectible:625/host-same"}
    begin = {"event": "case_begin", "key": case["key"]}
    end = {"event": "case_end", "key": case["key"]}
    assert summarize_case(case, {"host": [begin, end], "client": []})["status"] == "incomplete"
    result = summarize_case(case, {"host": [begin, end], "client": [begin, end]})
    assert result["status"] == "incomplete"
    assert not result["compatibility_verified"]


def test_mismatched_peer_case_windows_cannot_be_counted_as_a_pass():
    case = {"key": "card:12/client-split"}
    host = [
        {"event": name, "key": case["key"], "now_ms": 100}
        for name in ("case_begin", "give_end", "use_return", "case_end")
    ]
    samples = [{"event": "sample", "key": case["key"], "tick": t, "players": []} for t in (90, 120)]
    client = [{"event": "case_end", "key": case["key"], "now_ms": 90}, *samples]
    result = summarize_case(case, {"host": host + samples, "client": client})
    assert result["status"] == "incomplete"
    assert "peer_case_window" in result["unconfirmed_checks"]


def test_complete_native_smoke_still_does_not_prove_conditional_effects():
    case = {"key": "card:1/host-same", "physical": True}

    def event(name, **values):
        return {"event": name, "key": case["key"], **values}

    samples = [event("sample", tick=tick, players=[]) for tick in (90, 120)]
    values = [
        event(name) for name in ("case_begin", "give_end", "use_return", "use_callback", "case_end")
    ] + samples
    result = summarize_case(case, {"host": values, "client": [event("case_end"), *samples]})
    assert result["status"] == "basic_pass"
    assert not result["compatibility_verified"]
    values = [value for value in values if value["event"] != "use_callback"]
    assert (
        summarize_case(case, {"host": values, "client": [event("case_end"), *samples]})["status"]
        == "incomplete"
    )


def test_repeated_attribute_divergence_is_reported_even_after_clean_exit():
    case = {"key": "collectible:7/host-same"}
    host = [
        {
            "event": "sample",
            "key": case["key"],
            "label": "observe",
            "tick": tick,
            "players": [{"slot": 0, "damage": 4.5}],
        }
        for tick in (90, 120)
    ]
    client = [{**event, "players": [{"slot": 0, "damage": 3.5}]} for event in host]
    host.insert(0, {"event": "case_begin", "key": case["key"]})
    host.insert(1, {"event": "give_begin", "key": case["key"]})
    # Pre-update probes (including stress measurements) are not snapshots.
    assert not summarize_case(case, {"host": host, "client": client})["problems"]
    host += [{**event, "label": "captured"} for event in host[2:]]
    result = summarize_case(case, {"host": host, "client": client})
    assert result["status"] == "problem"
    assert result["problems"][0]["category"] == "non_native"
    # A temporary stat may change between pre-update observation and capture.
    # The actual snapshot boundary is the relevant peer comparison.
    host += [{**event, "label": "captured"} for event in client]
    assert not summarize_case(case, {"host": host, "client": client})["problems"]


def test_held_item_requires_measured_effect_and_charge_without_use_callback():
    case = {
        "key": "collectible:655/host-same",
        "enum": "COLLECTIBLE_SPIN_TO_WIN",
        "id": 655,
        "slot": 0,
        "physical": True,
    }

    def sample(label, tick, speed, charge):
        return {
            "key": case["key"],
            "event": "sample",
            "label": label,
            "tick": tick,
            "players": [{"slot": 0, "active": 655, "speed": speed, "charge": charge}],
        }

    markers = [
        {"key": case["key"], "event": name}
        for name in ("case_begin", "give_end", "use_return", "case_end")
    ]
    host = markers + [
        sample("before", 30, 1, 0),
        sample("acquired", 30, 1, 90),
        sample("captured", 90, 1.5, 60),
        sample("captured", 120, 1.5, 30),
    ]
    client = [markers[-1], *host[-2:]]
    result = summarize_case(case, {"host": host, "client": client})
    assert not result["compatibility_verified"]
    assert result["use_evidence"] == "held_charge_and_speed"
    for event in host[-2:]:
        event["players"][0]["charge"] = 90
    result = summarize_case(case, {"host": host, "client": client})
    assert result["use_evidence"] is None
    assert "native_use_callback" in result["unconfirmed_checks"]


def test_crash_is_distinct_from_forced_cleanup_and_unstarted_cases():
    case = {"key": "card:1/client-split"}
    peers = {"host": [{"event": name, "key": case["key"]} for name in ("case_begin", "give_begin")]}
    result = {"process_exit": {"host": {"exit_code": 0xC0000005}}}
    assert summarize_case(case, peers, result)["status"] == "crash"
    assert summarize_case({"key": "card:2/client-split"}, peers, result)["status"] == "untested"
    result["process_exit"]["host"]["exit_code"] = 0xFFFFFFFF
    assert summarize_case(case, peers, result)["status"] == "incomplete"
    result["process_exit"]["host"]["exit_code"] = -1
    assert summarize_case(case, peers, result)["status"] == "incomplete"
    result["process_exit"]["host"]["exit_code"] = 0xC0000005
    peers["host"].append({"event": "case_begin", "key": "card:2/client-split"})
    assert summarize_case(case, peers, result)["status"] == "incomplete"


def test_setup_crash_is_incomplete_and_cleanup_crash_is_not_a_pass():
    case = {"key": "card:1/host-same"}
    begin = {"event": "case_begin", "key": case["key"]}
    end = {"event": "case_end", "key": case["key"]}
    engine = {"process_exit": {"client": {"exit_code": 0xC0000005}}}
    result = summarize_case(case, {"host": [begin], "client": []}, engine)
    assert result["status"] == "incomplete"
    assert result["crash_phase"] == "setup"
    peers = {
        "host": [begin, {"event": "give_begin", "key": case["key"]}, end],
        "client": [begin, end],
    }
    result = summarize_case(case, peers, engine)
    assert result["status"] == "crash"
    assert result["crash_phase"] == "cleanup"


def test_failed_fixture_prerequisite_is_not_an_item_reconnect_bug():
    case = {"key": "collectible:580/client-split"}
    host = [
        {"key": case["key"], "event": "case_begin"},
        {
            "key": case["key"],
            "event": "problem",
            "category": "reconnect",
            "detail": "fixture error",
        },
    ]
    result = summarize_case(case, {"host": host, "client": []})
    assert result["status"] == "incomplete"
    assert result["interruption_phase"] == "setup"
    assert "fixture_setup" in result["unconfirmed_checks"]


def test_full_registry_and_shards_cover_each_entry_and_pill_variant_once():
    from collections import Counter
    from item_consumable_recipes import CONSUMABLE_RECIPES

    catalog = json.loads((ROOT / "tests/fixtures/item_catalog.json").read_text())
    cases = select_cases(catalog)
    assert len({item["key"] for item in catalog["items"]}) == len(catalog["items"])
    assert len({case["key"] for case in cases}) == len(cases)
    count = Counter(case["item"] for case in cases)
    assert all(
        count[item["key"]]
        == (
            4
            if item["kind"] == "pill" or CONSUMABLE_RECIPES.get(item.get("enum"), {}).get("pocket")
            else 2
        )
        for item in catalog["items"]
    )
    shards = [cases[index::3] for index in range(3)]
    assert Counter(case["key"] for shard in shards for case in shard) == Counter(
        case["key"] for case in cases
    )
    assert all(
        item["entity_subtype"] == "color" for item in catalog["items"] if item["kind"] == "pill"
    )


def test_basic_pass_does_not_erase_a_known_unresolved_crash():
    from render_item_compatibility import conclusion

    value = conclusion(
        {"status": "reported", "impact": "random crash unresolved"},
        {"status": "basic_pass", "impact": "smoke completed"},
    )
    assert value["status"] == "reported"
    assert value["impact"] == "random crash unresolved"
    value = conclusion(
        {"status": "reported", "impact": "user report"},
        {"status": "crash", "impact": "native crash reproduced"},
    )
    assert value["status"] == "crash"
    assert value["impact"] == "native crash reproduced"


def test_truncated_catalog_and_torn_event_are_not_accepted():
    assert events('LAN_ITEM_AUDIT {"event":') == []
    text = "LAN_ITEM_AUDIT " + json.dumps({"event": "catalog", "item": {"key": "pill:0"}})
    with pytest.raises(ValueError, match="truncated"):
        catalog_from_log(text)


def test_known_problem_is_not_overridden_by_later_completion():
    case = {"key": "pill:0/host-same"}
    values = [
        {"key": case["key"], "event": "case_begin"},
        {"key": case["key"], "event": "give_begin"},
        {"key": case["key"], "event": "case_end"},
        {"key": case["key"], "event": "problem", "category": "reconnect"},
    ]
    assert summarize_case(case, {"host": values, "client": values})["status"] == "problem"


def test_client_errors_after_host_crash_do_not_consume_the_next_item():
    case = {"key": "pill:1/host-same"}
    peers = {
        "host": [{"event": "case_begin", "key": "card:97/host-same"}],
        "client": [{"event": "problem", "key": case["key"], "category": "reconnect"}],
    }
    assert summarize_case(case, peers)["status"] == "untested"


def test_fixture_exit_socket_close_is_not_misattributed_to_item_reconnect():
    case = {"key": "collectible:171/host-same"}

    def event(name, **values):
        return {"event": name, "key": case["key"], **values}

    host = [
        event("case_begin"),
        event("give_begin"),
        event("exit_requested", now_ms=100),
        event("case_end"),
    ]
    client = [
        event("case_begin"),
        event("problem", category="reconnect", now_ms=101),
        event("case_aborted"),
    ]
    result = summarize_case(case, {"host": host, "client": client})
    assert result["status"] == "incomplete"
    assert not result["problems"]
    assert result["teardown_events"]
    assert "client_case_end" in result["unconfirmed_checks"]
    client[1]["now_ms"] = 99
    assert summarize_case(case, {"host": host, "client": client})["status"] == "problem"


def test_manual_lab_alias_is_refused(tmp_path):
    manual = tmp_path / "host-001"
    manual.mkdir()
    alias = tmp_path / "alias"
    alias.symlink_to(manual, target_is_directory=True)
    with pytest.raises(ValueError, match="manual"):
        validate_labs([alias, tmp_path / "client"], tmp_path / "evidence")


def test_first_start_notice_must_be_cleared_before_native_audit(tmp_path):
    options = tmp_path / "profile/Documents/My Games/Binding of Isaac Repentance+/options.ini"
    options.parent.mkdir(parents=True)
    options.write_text("[Options]\nEnableMods=1\n")
    with pytest.raises(ValueError, match="first-start Beta notice"):
        validate_startup([tmp_path])
    options.write_text("[Options]\nAcceptedPublicBeta_v1.9.7.17=1\n")
    validate_startup([tmp_path])


def test_import_preserves_failures_and_requires_explicit_review_to_exclude(tmp_path):
    from import_item_audit import import_run

    case = {
        "key": "collectible:1/host-same",
        "item": "collectible:1",
        "kind": "collectible",
        "id": 1,
    }

    def make_report(name, problem=False):
        directory = tmp_path / name
        batch = directory / "batch-001"
        batch.mkdir(parents=True)
        (directory / "manifest.json").write_text(json.dumps({"dll_sha256": "candidate"}))
        (batch / "report.json").write_text(json.dumps({"cases": [case], "engine": {}}))
        values = [
            {"event": event, "key": case["key"]}
            for event in ("case_begin", "give_end", "use_return", "case_end")
        ]
        values += [
            {"event": "sample", "key": case["key"], "tick": tick, "players": []}
            for tick in (90, 120)
        ]
        if problem:
            values.append({"event": "problem", "key": case["key"], "category": "non_native"})
        for role in ("host", "client"):
            (batch / (role + "-events.log")).write_text(
                "\n".join("LAN_ITEM_AUDIT " + json.dumps(v) for v in values)
            )
        return directory

    failed, passed = make_report("failed", True), make_report("passed")
    findings = {"dll_sha256": "candidate", "audit": {}, "stress": []}
    import_run(findings, failed)
    import_run(findings, failed)
    item = findings["audit"][case["item"]]
    assert len(item["checks"]) == 1
    import_run(findings, passed)
    assert item["status"] == "problem"
    findings["excluded_checks"] = [
        {
            "case": case["key"],
            "evidence": "failed/batch-001",
            "reason": "Confirmed fixture failure; original evidence retained",
        }
    ]
    import_run(findings, failed)
    assert item["status"] == "basic_pass"
    assert len(item["checks"]) == 2
    assert any(
        entry["status"] == "problem" and entry.get("excluded_reason") for entry in item["checks"]
    )


def test_excluded_run_cannot_be_reimported_as_valid_coverage(tmp_path):
    from import_item_audit import import_run

    findings = {
        "excluded_runs": [{"evidence": "obscured", "reason": "Startup notice hid gameplay"}]
    }
    with pytest.raises(ValueError, match="Startup notice hid gameplay"):
        import_run(findings, tmp_path / "obscured")


def test_frozen_failure_is_not_reinterpreted_by_a_new_validator(tmp_path, monkeypatch):
    import import_item_audit

    batch = tmp_path / "frozen/batch-001"
    batch.mkdir(parents=True)
    (batch.parent / "manifest.json").write_text(
        json.dumps({"dll_sha256": "candidate", "validator_sha256": "original-validator"})
    )
    case = {
        "key": "collectible:29/host-same",
        "item": "collectible:29",
        "kind": "collectible",
        "id": 29,
    }
    result = {
        **case,
        "status": "problem",
        "unconfirmed_checks": [],
        "problems": [{"category": "non_native"}],
        "effect_checks": [{"name": "peer_effect_state", "status": "failed"}],
    }
    (batch / "report.json").write_text(json.dumps({"cases": [case], "results": [result]}))

    def unexpected(*args):
        raise AssertionError("Old evidence must retain its original conclusion")

    monkeypatch.setattr(import_item_audit, "summarize_case", unexpected)
    findings = {"dll_sha256": "candidate", "audit": {}, "stress": []}
    import_item_audit.import_run(findings, batch.parent)
    assert findings["audit"]["collectible:29"]["status"] == "problem"
    (batch / "report.json").write_text(json.dumps({"cases": [case], "results": []}))
    with pytest.raises(ValueError, match="missing a case result"):
        import_item_audit.import_run(findings, batch.parent)


def test_later_stress_completion_cannot_erase_a_same_build_crash(tmp_path):
    from import_item_audit import import_run

    case = {"key": "stress:copies-1000", "kind": "stress", "id": 0, "slot": 0, "copies": 1000}
    batch = tmp_path / "repeat/batch-001"
    batch.mkdir(parents=True)
    (batch.parent / "manifest.json").write_text(json.dumps({"dll_sha256": "candidate"}))
    (batch / "report.json").write_text(json.dumps({"cases": [case], "engine": {}}))
    values = [
        {"key": case["key"], "event": name}
        for name in ("case_begin", "give_end", "use_return", "case_end")
    ]
    values += [
        {
            "key": case["key"],
            "event": "sample",
            "tick": t,
            "players": [{"item_count": 1000, "tears": 0, "projectiles": 0}],
        }
        for t in (150, 180)
    ]
    for role in ("host", "client"):
        (batch / (role + "-events.log")).write_text(
            "\n".join("LAN_ITEM_AUDIT " + json.dumps(e) for e in values)
        )
    old = {
        "case": case["key"],
        "status": "crash",
        "evidence": "failed/batch-001",
        "dll_sha256": "candidate",
    }
    findings = {"dll_sha256": "candidate", "audit": {}, "stress": [old]}
    import_run(findings, batch.parent)
    import_run(findings, batch.parent)
    current = findings["stress"][0]
    assert current["status"] == "crash" and current["latest_status"] == "basic_pass"
    assert current["load_reached"]
    assert findings["previous_stress"] == [old]


def test_direct_effect_requires_observed_change_and_tolerates_missing_actor():
    case = {"key": "pill:6/host-same", "kind": "pill", "slot": 0, "enum": "PILLEFFECT_HEALTH_UP"}

    def sample(label, tick, player):
        return {
            "event": "sample",
            "key": case["key"],
            "label": label,
            "tick": tick,
            "players": [player],
        }

    before = sample("before", 30, {"slot": 0, "max_hearts": 8})
    use = {"event": "use_callback", "key": case["key"]}
    unchanged = sample("observe", 90, {"slot": 0, "max_hearts": 8})
    result = summarize_case(case, {"host": [before, use, unchanged]})
    assert any(p["category"] == "no_effect" for p in result["problems"])
    changed = sample("observe", 90, {"slot": 0, "max_hearts": 10})
    assert not summarize_case(case, {"host": [before, use, changed]})["problems"]
    missing = sample("observe", 90, {"slot": 0, "missing": True})
    assert not summarize_case(case, {"host": [before, use, missing]})["problems"]


def test_requested_projectile_count_does_not_substitute_for_actual_stress_load():
    from import_item_audit import measured_stress

    result = {
        "slot": 0,
        "key": "stress:tears-2000",
        "status": "incomplete",
        "tears": 2000,
        "observations": {
            "host": [
                {
                    "event": "sample",
                    "tick": 150,
                    "players": [{"item_count": 0, "tears": 512, "projectiles": 0}],
                }
            ]
        },
    }
    measured = measured_stress(result, "capacity-test")
    assert not measured["load_reached"]
    assert measured["observed"]["host"]["tears"]["max"] == 512
