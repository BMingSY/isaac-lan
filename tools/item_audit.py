"""Catalog and evidence contracts shared by the isolated item audit tools."""

import json
from pathlib import Path
import re

from item_effect_checks import SHOT_EFFECTS, SUPPORTED_EFFECTS, effect_checks
from item_consumable_recipes import CONSUMABLE_RECIPES, consumable_recipe
from item_room_effects import ROOM_EFFECTS, room_effect_recipe
from item_damage_effects import DAMAGE_EFFECTS, damage_recipe
from item_familiar_effects import FAMILIAR_EFFECTS
from item_trigger_effects import TRIGGER_EFFECTS, trigger_recipe

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "LAN_ITEM_AUDIT "
KINDS = ("collectible", "trinket", "card", "pill")
COMPLETION = "LAN_NETWORK PASS item audit batch"
DIRECT_EFFECTS = {
    "COLLECTIBLE_SAD_ONION": ("delay", -1),
    "COLLECTIBLE_BLOOD_MARTYR": ("damage", 1),
    "COLLECTIBLE_MAGIC_MUSHROOM": ("damage", 1),
    "COLLECTIBLE_ROID_RAGE": ("speed", 1),
    "PILLEFFECT_BALLS_OF_STEEL": ("soul", 1),
    "PILLEFFECT_HEALTH_UP": ("max_hearts", 1),
    "PILLEFFECT_HEALTH_DOWN": ("max_hearts", -1),
    "PILLEFFECT_SPEED_UP": ("speed", 1),
    "PILLEFFECT_SPEED_DOWN": ("speed", -1),
    "PILLEFFECT_TEARS_UP": ("delay", -1),
    "PILLEFFECT_TEARS_DOWN": ("delay", 1),
    "PILLEFFECT_RANGE_UP": ("range", 1),
    "PILLEFFECT_RANGE_DOWN": ("range", -1),
    "PILLEFFECT_LUCK_UP": ("luck", 1),
    "PILLEFFECT_LUCK_DOWN": ("luck", -1),
    "PILLEFFECT_SHOT_SPEED_UP": ("shot_speed", 1),
    "PILLEFFECT_SHOT_SPEED_DOWN": ("shot_speed", -1),
}


def events(text):
    result = []
    for line in text.splitlines():
        if PREFIX not in line:
            continue
        try:
            value = json.loads(line.split(PREFIX, 1)[1])
        except json.JSONDecodeError:
            continue  # A process may die halfway through its final log write.
        if isinstance(value, dict) and isinstance(value.get("event"), str):
            result.append(value)
    return result


def unexpected_peer_failure(host_markers, client_events):
    bounds = {}
    for event in host_markers:
        bounds.setdefault(event["key"], {})[event["event"]] = event.get("now_ms")
    for event in client_events:
        window = bounds.get(event.get("key"), {})
        begin, end = window.get("case_begin"), window.get("exit_requested")
        now = event.get("now_ms")
        if (
            event["event"] == "problem"
            and event.get("category") == "reconnect"
            and begin is not None
            and now is not None
            and now >= begin
            and (end is None or now < end)
        ):
            return event
    return None


def catalog_from_log(text):
    records = [event["item"] for event in events(text) if event["event"] == "catalog"]
    keys = [record["key"] for record in records]
    if not records or len(set(keys)) != len(keys):
        raise ValueError("A complete, unique runtime catalog is required")
    end = [event for event in events(text) if event["event"] == "catalog_end"]
    if len(end) != 1 or end[0]["count"] != len(records):
        raise ValueError("Runtime catalog is truncated")
    if {record["kind"] for record in records} != set(KINDS):
        raise ValueError("Runtime catalog is missing an item category")
    return {"game": "1.9.7.17.J460", "source": "Isaac.GetItemConfig", "items": records}


def localize_catalog(catalog, names_file):
    """Import only ID/name metadata from an unmodified EID names table."""
    kinds = {"C_ID": "collectible", "T_ID": "trinket", "Card_ID": "card", "Pill_ID": "pill"}
    names = {}
    for prefix, number, name in re.findall(
        r'\[(C_ID|T_ID|Card_ID|Pill_ID)\s*\.\.\s*(\d+)\]\s*=\s*"([^"]+)"', names_file.read_text()
    ):
        names[f"{kinds[prefix]}:{number}"] = name
    for item in catalog["items"]:
        if item["key"] in names:
            item["name_zh"] = names[item["key"]]
    catalog["name_source"] = (
        "https://github.com/wofsauge/External-Item-Descriptions/blob/master/descriptions/names/zh_cn.lua"
    )
    return catalog


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (str, int, float)):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{" + ",".join(lua(v) for v in value) + "}"
    return "{" + ",".join("[" + lua(k) + "]=" + lua(v) for k, v in value.items()) + "}"


def select_cases(catalog, keys=None, contexts=("host-same", "client-split"), horse=True):
    items = catalog["items"]
    known = {item["key"] for item in items}
    if keys is not None and (not keys or not set(keys) <= known or len(set(keys)) != len(keys)):
        raise ValueError("Choose distinct runtime catalog keys")
    cases = []
    for item in items:
        if keys is not None and item["key"] not in keys:
            continue
        for context in contexts:
            if context not in {"host-same", "host-split", "client-same", "client-split"}:
                raise ValueError("Unknown holder/room context")
            variants = (False, True) if item["kind"] == "pill" and horse else (False,)
            for large in variants:
                cases.append(
                    {
                        "key": item["key"] + "/" + context + ("/horse" if large else ""),
                        "item": item["key"],
                        "kind": item["kind"],
                        "id": item["id"],
                        "enum": item.get("enum"),
                        "slot": int(context.startswith("client")),
                        "split": context.endswith("split"),
                        "horse": large,
                        "mega": item["kind"] == "collectible" and item["id"] == 625,
                        "companion": (item["kind"] == "card" and item["id"] in (95, 97))
                        or (item["kind"] == "trinket" and item["id"] == 180),
                        "physical": item["kind"] in {"card", "pill"} or item.get("item_type") == 3,
                        "effect_check": item.get("enum") in SUPPORTED_EFFECTS,
                        "quiet_room": item.get("enum") in SUPPORTED_EFFECTS,
                        "shot_effect": item.get("enum") in SHOT_EFFECTS,
                        "protect_use": item.get("enum") in SUPPORTED_EFFECTS
                        or item.get("enum") in ("COLLECTIBLE_STITCHES", "COLLECTIBLE_SUPLEX"),
                        "moving_use": item.get("enum") == "COLLECTIBLE_SUPLEX",
                    }
                )
                if item.get("enum") in SHOT_EFFECTS:
                    cases[-1]["end_tick"] = 300
                if item.get("enum") in TRIGGER_EFFECTS:
                    rules = trigger_recipe(cases[-1])
                    cases[-1]["trigger_effects"] = rules
                    if rules.get("wall_use"):
                        cases[-1]["wall_use"] = True
                    if rules.get("moving_use"):
                        cases[-1]["moving_use"] = True
                    if "use_tick" in rules:
                        cases[-1]["use_tick"] = rules["use_tick"]
                    if "hold_ticks" in rules:
                        cases[-1]["hold_ticks"] = rules["hold_ticks"]
                    cases[-1]["recipe"] = {}
                    cases[-1]["open_room"] = True
                    cases[-1]["end_tick"] = rules.get(
                        "end_tick", 300 if rules.get("expire_room") else 180
                    )
                if item.get("enum") in DAMAGE_EFFECTS:
                    rules = damage_recipe(cases[-1])
                    cases[-1]["damage_effects"] = rules
                    cases[-1]["recipe"] = {}
                    cases[-1]["open_room"] = True
                    cases[-1]["end_tick"] = rules["steps"][-1]["tick"] + 60
                if item.get("enum") in FAMILIAR_EFFECTS:
                    cases[-1]["familiar_effects"] = FAMILIAR_EFFECTS[item["enum"]]
                    cases[-1]["recipe"] = {}
                    cases[-1]["open_room"] = True
                    cases[-1]["end_tick"] = 840 * FAMILIAR_EFFECTS[item["enum"]].get(
                        "timeline_scale", 1
                    )
                if item.get("enum") in ROOM_EFFECTS:
                    rules = room_effect_recipe(cases[-1])
                    cases[-1]["room_effects"] = rules
                    cases[-1]["recipe"] = {}
                    cases[-1]["open_room"] = True
                    if rules.get("floor_lifecycle"):
                        cases[-1]["end_tick"] = 480
                if item.get("enum") in CONSUMABLE_RECIPES:
                    recipe = consumable_recipe(cases[-1])
                    cases[-1]["recipe"] = {
                        key: recipe[key]
                        for key in (
                            "resources",
                            "expire_room",
                            "enemy_damage",
                            "golden_bomb",
                            "team_hearts",
                            "golden_lifecycle",
                            "eternal_lifecycle",
                            "reunite",
                            "teleport",
                        )
                        if key in recipe
                    }
                    cases[-1]["open_room"] = True
                    if recipe.get("expire_room") or recipe.get("reunite") or recipe.get("teleport"):
                        cases[-1]["end_tick"] = 270
                    if recipe.get("golden_lifecycle") or recipe.get("eternal_lifecycle"):
                        cases[-1]["end_tick"] = 480
                    if recipe.get("pocket"):
                        cases[-1]["pocket_effect"] = True
                        cases.append(
                            {
                                **cases[-1],
                                "key": cases[-1]["key"] + "/occupied",
                                "occupied_pocket": True,
                            }
                        )
    return cases


def summarize_case(case, peers, engine=None):
    """A smoke result never proves the complete conditional native effect."""
    observations = {
        role: [
            event
            for event in values
            if event.get("key") == case["key"] and event["event"] not in {"catalog", "catalog_end"}
        ]
        for role, values in peers.items()
    }
    host, client = observations.get("host", []), observations.get("client", [])
    problems = [
        event for values in observations.values() for event in values if event["event"] == "problem"
    ]
    begin_time = next((e.get("now_ms") for e in host if e["event"] == "case_begin"), None)
    preparation = [
        e for e in problems if begin_time is not None and e.get("now_ms", begin_time) < begin_time
    ]
    problems = [e for e in problems if e not in preparation]
    exit_time = next(
        (event.get("now_ms") for event in host if event["event"] == "exit_requested"), None
    )
    # Both peers run on the same machine/monotonic clock. A socket closing after
    # the fixture deliberately exits is not evidence that this item reconnects.
    teardown = [
        event
        for event in problems
        if event.get("category") == "reconnect"
        and exit_time is not None
        and event.get("now_ms", -1) >= exit_time
    ]
    problems = [event for event in problems if event not in teardown]
    host_samples = {
        event["tick"]: event
        for event in host
        if event["event"] == "sample" and event.get("label") in {"observe", "captured"}
    }
    mismatches = {}
    for event in client:
        if event["event"] != "sample" or event.get("tick", 0) < 90:
            continue
        authority = host_samples.get(event["tick"])
        if not authority or authority.get("label") != "captured":
            continue
        for expected, actual in zip(authority["players"], event["players"]):
            compared = (
                "damage",
                "delay",
                "speed",
                "range",
                "shot_speed",
                "luck",
                "target_count",
            )
            if case.get("mega"):
                compared += ("temporary_count", "size", "scale_x", "scale_y", "visible")
            for field in compared:
                left, right = expected.get(field), actual.get(field)
                if left is not None and right is not None and abs(left - right) > 0.001:
                    mismatches.setdefault((actual["slot"], field), []).append(event["tick"])
    for (slot, field), ticks in mismatches.items():
        if len(ticks) >= 2:
            problems.append(
                {
                    "event": "problem",
                    "category": "non_native",
                    "detail": f"slot {slot} {field} differs on two or more matching snapshots",
                    "ticks": ticks,
                }
            )
    expectation = DIRECT_EFFECTS.get(case.get("enum"))
    before = next(
        (event for event in host if event["event"] == "sample" and event.get("label") == "before"),
        None,
    )
    use_tick = case.get("use_tick", 60)
    after = [event for tick, event in host_samples.items() if use_tick <= tick <= use_tick + 30]
    if (
        expectation
        and before
        and after
        and (case.get("kind") != "pill" or any(event["event"] == "use_callback" for event in host))
    ):
        field, direction = expectation
        baseline = before["players"][case["slot"]].get(field)
        values = [event["players"][case["slot"]].get(field) for event in after]
        observed = [value for value in values if value is not None]
        if (
            baseline is not None
            and observed
            and not any((value - baseline) * direction > 0.001 for value in observed)
        ):
            problems.append(
                {
                    "event": "problem",
                    "category": "no_effect",
                    "detail": f"expected direct {field} change was not observed",
                }
            )
    ended = all(any(event["event"] == "case_end" for event in values) for values in (host, client))
    samples = {
        role: sum(event["event"] == "sample" for event in values)
        for role, values in observations.items()
    }
    began = any(event["event"] == "case_begin" for event in host)
    missing = []
    client_ends = [e.get("now_ms") for e in client if e["event"] == "case_end"]
    if (
        begin_time is not None
        and client_ends
        and all(t is not None and t < begin_time for t in client_ends)
    ):
        missing.append("peer_case_window")
    if began:
        for role, values in observations.items():
            if not any(value["event"] == "case_end" for value in values):
                missing.append(role + "_case_end")
    for event in ("give_end", "use_return"):
        if not any(value["event"] == event for value in host):
            missing.append(event)
    if min(samples.get("host", 0), samples.get("client", 0)) < 2:
        missing.append("two_samples_on_each_peer")
    use_evidence = (
        "native_callback"
        if any(v["event"] == "use_callback" and v.get("tick", use_tick) >= use_tick for v in host)
        else None
    )
    acquired = next(
        (
            event
            for event in host
            if event["event"] == "sample" and event.get("label") == "acquired"
        ),
        None,
    )
    # Spin to Win is a held action and does not emit the ordinary item-use
    # callback. Require its actual speed increase and charge consumption.
    if case.get("enum") == "COLLECTIBLE_SPIN_TO_WIN" and acquired and before:
        slot = case["slot"]
        initial = acquired["players"][slot]
        speed = before["players"][slot].get("speed")
        for event in host_samples.values():
            player = event["players"][slot]
            if (
                speed is not None
                and player.get("active") == case["id"]
                and player.get("speed", speed) > speed
                and 0 <= player.get("charge", -1) < initial.get("charge", 0)
            ):
                use_evidence = "held_charge_and_speed"
                break
    if (case.get("physical") or case.get("kind") == "pill") and not use_evidence:
        missing.append("native_use_callback")
    checks = effect_checks(case, observations)
    if case.get("frame_budget_ms"):
        for role, values in observations.items():
            metrics = [event.get("render") for event in values if event["event"] == "metrics"]
            render = metrics[-1] if metrics else None
            checks.append(
                {
                    "name": f"performance:{role}:render_p95",
                    "status": "missing"
                    if not render or render.get("count", 0) < 100
                    else "passed"
                    if render.get("p95", float("inf")) <= case["frame_budget_ms"]
                    else "failed",
                    "budget_ms": case["frame_budget_ms"],
                    "actual": render,
                }
            )
    for check in checks:
        if check["status"] == "missing":
            missing.append(check["name"])
        elif check["status"] == "failed":
            problems.append(
                {
                    "event": "problem",
                    "category": "no_effect"
                    if check["name"].startswith("effect:")
                    else "non_native",
                    "detail": check["name"],
                }
            )
    done = ended and not missing
    verified = done and bool(checks) and not problems
    result = {
        **case,
        "status": "problem"
        if any(problem["category"] != "incomplete" for problem in problems)
        else "incomplete"
        if problems
        else "verified"
        if verified
        else "basic_pass"
        if done
        else "incomplete"
        if began
        else "untested",
        "compatibility_verified": verified,
        "effect_checks": checks,
        "problems": problems,
        "samples": samples,
        "observations": observations,
        "unconfirmed_checks": missing,
        "teardown_events": teardown,
        "use_evidence": use_evidence,
        "preparation_events": preparation,
    }
    # The client advances its fixture index after an unexpected host exit.
    # Subsequent connection errors must not consume the next unstarted item.
    if not began:
        result["status"] = "untested"
        result["compatibility_verified"] = False
    if "peer_case_window" in missing:
        result["status"] = "incomplete"
        result["compatibility_verified"] = False
        result["interruption_phase"] = "fixture_alignment"
    if (
        began
        and problems
        and not any(event["event"] in {"give_begin", "give_end"} for event in host)
    ):
        result["status"] = "incomplete"
        result["compatibility_verified"] = False
        result["interruption_phase"] = "setup"
        missing.append("fixture_setup")
    if began and engine:
        exits = engine.get("process_exit", {})
        latest = next(
            (
                event.get("key")
                for event in reversed(peers.get("host", []))
                if event["event"] == "case_begin"
            ),
            None,
        )
        crashed = {
            role: value
            for role, value in exits.items()
            if value.get("exit_code") is not None
            and (value["exit_code"] & 0xFFFFFFFF) not in (0, 0xFFFFFFFF)
            and latest == case["key"]
        }
        if crashed:
            given = any(event["event"] == "give_begin" for event in host)
            result["status"] = "crash" if given else "incomplete"
            result["compatibility_verified"] = False
            result["process_exit"] = crashed
            result["crash_phase"] = (
                "setup"
                if not given
                else (
                    "cleanup"
                    if all(
                        any(e["event"] == "case_end" for e in observations.get(role, []))
                        for role in crashed
                    )
                    else "effect"
                )
            )
        elif not ended and engine.get("error"):
            result["interruption"] = engine["error"]
    return result


def cases_passed(results):
    return bool(results) and all(
        result["status"] in {"verified", "basic_pass"} for result in results
    )


def build_fixture(path, config):
    path.write_text(
        "local audit = "
        + lua(config)
        + "\n"
        + "local exportCatalog = (function()\n"
        + (ROOT / "tests/fixtures/item_audit_catalog.lua").read_text()
        + "\nend)()\n"
        + "local createStress = (function()\n"
        + (ROOT / "tests/fixtures/item_audit_stress.lua").read_text()
        + "\nend)()\n"
        + "local createEntityFieldsProbe = (function()\n"
        + (ROOT / "tests/fixtures/entity_fields_probe.lua").read_text()
        + "\nend)()\n"
        + "local createRoomEffects = (function()\n"
        + (ROOT / "tests/fixtures/item_audit_rooms.lua").read_text()
        + "\nend)()\n"
        + "local createDamageEffects = (function()\n"
        + (ROOT / "tests/fixtures/item_audit_damage.lua").read_text()
        + "\nend)()\n"
        + "local createDamageTrace = (function()\n"
        + (ROOT / "tests/fixtures/item_damage_trace.lua").read_text()
        + "\nend)()\n"
        + "local createFamiliarEffects = (function()\n"
        + (ROOT / "tests/fixtures/item_audit_familiars.lua").read_text()
        + "\nend)()\n"
        + "local createTriggerEffects = (function()\n"
        + "local createProjectileTrials = (function()\n"
        + (ROOT / "tests/fixtures/item_audit_projectiles.lua").read_text()
        + "\nend)()\n"
        + "local createInteractionEffects = (function()\n"
        + (ROOT / "tests/fixtures/item_audit_interactions.lua").read_text()
        + "\nend)()\n"
        + (ROOT / "tests/fixtures/item_audit_triggers.lua").read_text()
        + "\nend)()\n"
        + (ROOT / "tests/state_item_audit.lua").read_text()
    )


def stress_cases(catalog, keys=None):
    # Missing No./TMTRAINER belong in the individual randomized-effect audit.
    excluded = {258, 721}
    loadout = [
        item["id"]
        for item in catalog["items"]
        if item["kind"] == "collectible"
        and item["item_type"] in (1, 4)
        and not item.get("hidden")
        and item["id"] not in excluded
    ]
    profiles = [{"key": "stress:baseline"}]
    for count in (100, 300, 500):
        if len(loadout) < count:
            raise ValueError("Runtime registry cannot supply the requested distinct inventory")
        profiles.append({"key": f"stress:inventory-{count}", "loadout": loadout[:count]})
    profiles.append({"key": "stress:copies-1000", "copies": 1000})
    # Preserve the attacking workloads and measure idle holding separately.
    profiles.extend(
        {
            **profile,
            "key": profile["key"].replace("stress:", "stress:idle-"),
            "idle": True,
            "frame_budget_ms": 1000 / 30,
        }
        for profile in list(profiles)
    )
    for kind in ("tears", "projectiles"):
        for count in (100, 500, 1000, 2000):
            profiles.append({"key": f"stress:{kind}-{count}", kind: count})
    profiles.append(
        {"key": "stress:combined", "loadout": loadout[:300], "tears": 500, "projectiles": 500}
    )
    if keys is not None and not set(keys) <= {profile["key"] for profile in profiles}:
        raise ValueError("Unknown stress case")
    return [
        {**profile, "item": profile["key"], "kind": "stress", "id": 0, "slot": 1, "split": False}
        for profile in profiles
        if keys is None or profile["key"] in keys
    ]
