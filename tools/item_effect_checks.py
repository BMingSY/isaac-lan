"""Assertions for individual effects; an unknown recipe never becomes a pass."""

from item_consumable_recipes import CONSUMABLE_RECIPES, consumable_recipe
from item_room_effects import ROOM_EFFECTS, room_effect_checks

# These items have direct, unconditional effects in the clean Isaac fixture.
# Values are directions, not a substitute for checking every listed attribute.
# Conditional effects belong in their own recipe instead of this table.
STAT_EFFECTS = {
    "COLLECTIBLE_SAD_ONION": {"delay": -1},
    "COLLECTIBLE_MAXS_HEAD": {"damage": 1},
    "COLLECTIBLE_NUMBER_ONE": {"delay": -1, "range": -1},
    "COLLECTIBLE_BLOOD_MARTYR": {"damage": 1},
    "COLLECTIBLE_MAGIC_MUSHROOM": {
        "max_hearts": 1,
        "hearts": 1,
        "damage": 1,
        "speed": 1,
        "range": 1,
        "scale_x": 1,
    },
    "COLLECTIBLE_TRANSCENDENCE": {"flying": 1},
    "COLLECTIBLE_STEVEN": {"damage": 1},
    "COLLECTIBLE_MINI_MUSH": {"speed": 1, "range": 1, "scale_x": -1},
    "COLLECTIBLE_QUARTER": {"coins": 1},
    "COLLECTIBLE_SMALL_ROCK": {"damage": 1, "delay": -1, "speed": -1},
    "COLLECTIBLE_BLOOD_BAG": {"max_hearts": 1, "hearts": 1, "speed": 1},
    "COLLECTIBLE_CAT_O_NINE_TAILS": {"damage": 1, "shot_speed": 1},
    "COLLECTIBLE_HOLY_GRAIL": {"max_hearts": 1, "hearts": 1, "flying": 1},
    "COLLECTIBLE_MAGIC_SCAB": {"max_hearts": 1, "hearts": 1, "luck": 1},
    "COLLECTIBLE_SYNTHOIL": {"damage": 1, "range": 1},
    "COLLECTIBLE_BINKY": {"soul": 1, "delay": -1, "scale_x": -1},
    "COLLECTIBLE_BAR_OF_SOAP": {"delay": -1, "shot_speed": 1},
    "COLLECTIBLE_SUPPER": {"max_hearts": 1, "hearts": 1},
    "COLLECTIBLE_MOMS_UNDERWEAR": {"range": 1, "owned_blue_flies": 1},
    "COLLECTIBLE_MOMS_LIPSTICK": {"range": 1},
    "COLLECTIBLE_MOMS_PURSE": {"trinket_slots": 1},
    "COLLECTIBLE_SQUEEZY": {"delay": -1},
    "COLLECTIBLE_CRACK_JACKS": {"max_hearts": 1, "hearts": 1},
    "COLLECTIBLE_MR_DOLLY": {"delay": -1, "range": 1},
    "COLLECTIBLE_POLYDACTYLY": {"pocket_slots": 1},
    "COLLECTIBLE_INNER_EYE": {"delay": 1},
    "COLLECTIBLE_MUTANT_SPIDER": {"delay": 1},
    "COLLECTIBLE_20_20": {"damage": -1},
    "COLLECTIBLE_ROID_RAGE": {"speed": 1, "range": 1},
    "COLLECTIBLE_HEART": {"max_hearts": 1, "hearts": 1},
    "COLLECTIBLE_RAW_LIVER": {"max_hearts": 1, "hearts": 1},
    "COLLECTIBLE_SKELETON_KEY": {"keys": 1},
    "COLLECTIBLE_DOLLAR": {"coins": 1},
    "COLLECTIBLE_BOOM": {"bombs": 1},
    "COLLECTIBLE_LUNCH": {"max_hearts": 1, "hearts": 1},
    "COLLECTIBLE_DINNER": {"max_hearts": 1, "hearts": 1},
    "COLLECTIBLE_DESSERT": {"max_hearts": 1, "hearts": 1},
    "COLLECTIBLE_BREAKFAST": {"max_hearts": 1, "hearts": 1},
    "COLLECTIBLE_ROTTEN_MEAT": {"max_hearts": 1, "hearts": 1},
    "COLLECTIBLE_WOODEN_SPOON": {"speed": 1},
    "COLLECTIBLE_BELT": {"speed": 1},
    "COLLECTIBLE_WIRE_COAT_HANGER": {"delay": -1},
    "COLLECTIBLE_GROWTH_HORMONES": {"damage": 1, "speed": 1},
    "COLLECTIBLE_MARK": {"damage": 1, "speed": 1, "soul": 1, "black": 1},
    "COLLECTIBLE_PACT": {"damage": 1, "delay": -1, "soul": 1, "black": 1},
    "COLLECTIBLE_SUPER_BANDAGE": {"max_hearts": 1, "hearts": 1, "soul": 1},
    "COLLECTIBLE_HALO": {
        "max_hearts": 1,
        "hearts": 1,
        "speed": 1,
        "damage": 1,
        "range": 1,
        "delay": -1,
    },
    "COLLECTIBLE_ODD_MUSHROOM_THIN": {"speed": 1, "delay": -1, "damage": -1},
    "COLLECTIBLE_ODD_MUSHROOM_LARGE": {
        "max_hearts": 1,
        "damage": 1,
        "range": 1,
        "speed": -1,
    },
    "COLLECTIBLE_BUCKET_OF_LARD": {"max_hearts": 1, "speed": -1},
    "COLLECTIBLE_STIGMATA": {"max_hearts": 1, "hearts": 1, "damage": 1},
    "COLLECTIBLE_STEM_CELLS": {"max_hearts": 1, "hearts": 1, "shot_speed": 1},
    "COLLECTIBLE_SMB_SUPER_FAN": {
        "max_hearts": 1,
        "hearts": 1,
        "damage": 1,
        "delay": -1,
        "speed": 1,
        "range": 1,
    },
    "COLLECTIBLE_MEAT": {"max_hearts": 1, "hearts": 1, "damage": 1},
    "COLLECTIBLE_JESUS_JUICE": {"damage": 1, "range": 1},
    "COLLECTIBLE_BLACK_LOTUS": {"max_hearts": 1, "hearts": 1, "soul": 1, "black": 1},
    "COLLECTIBLE_EVES_MASCARA": {"damage": 1, "delay": 1, "shot_speed": -1},
    "COLLECTIBLE_BLUE_CAP": {"max_hearts": 1, "hearts": 1, "delay": -1, "shot_speed": -1},
    "COLLECTIBLE_MOMS_PEARLS": {"range": 1, "luck": 1, "soul": 1},
    "TRINKET_CURVED_HORN": {"damage": 1},
    "TRINKET_GOAT_HOOF": {"speed": 1},
    "TRINKET_CANCER": {"delay": -1},
    "PILLEFFECT_BALLS_OF_STEEL": {"soul": 1},
    "PILLEFFECT_HEALTH_UP": {"max_hearts": 1},
    "PILLEFFECT_HEALTH_DOWN": {"max_hearts": -1},
    "PILLEFFECT_SPEED_UP": {"speed": 1},
    "PILLEFFECT_SPEED_DOWN": {"speed": -1},
    "PILLEFFECT_TEARS_UP": {"delay": -1},
    "PILLEFFECT_TEARS_DOWN": {"delay": 1},
    "PILLEFFECT_RANGE_UP": {"range": 1},
    "PILLEFFECT_RANGE_DOWN": {"range": -1},
    "PILLEFFECT_LUCK_UP": {"luck": 1},
    "PILLEFFECT_LUCK_DOWN": {"luck": -1},
    "PILLEFFECT_SHOT_SPEED_UP": {"shot_speed": 1},
    "PILLEFFECT_SHOT_SPEED_DOWN": {"shot_speed": -1},
}


# Each rule also checks the objects on the replica. Counts are pickup-time
# deltas, so a pre-existing fixture pedestal cannot satisfy a spawn effect.
SPAWN_EFFECTS = {
    "COLLECTIBLE_MOMS_LIPSTICK": {"5.10.": (1, 1)},
    "COLLECTIBLE_MOMS_PURSE": {"5.350.": (1, 1)},
    "COLLECTIBLE_MOMS_COIN_PURSE": {"5.70.": (4, 4)},
    "COLLECTIBLE_SQUEEZY": {"5.10.3": (2, 2)},
    "COLLECTIBLE_CRACK_JACKS": {"5.350.": (1, 1)},
    "COLLECTIBLE_MR_DOLLY": {"5.10.": (3, 3)},
    "COLLECTIBLE_POLYDACTYLY": {"5.70.|5.300.": (1, 1)},
}
SHOT_EFFECTS = {
    "COLLECTIBLE_INNER_EYE": {"volley": 3},
    "COLLECTIBLE_MUTANT_SPIDER": {"volley": 4},
    "COLLECTIBLE_20_20": {"volley": 2},
}
SUPPORTED_EFFECTS = {
    *STAT_EFFECTS,
    *SPAWN_EFFECTS,
    *SHOT_EFFECTS,
    *CONSUMABLE_RECIPES,
    *ROOM_EFFECTS,
    "COLLECTIBLE_CHAOS",
}


def peer_field_matches(authority, replica, field):
    left, right = authority.get(field), replica.get(field)
    if field in {"owned_blue_flies", "owned_blue_spiders"}:
        # Remote room shells have player state, but no room entities. Once
        # players reunite, the visible familiar count must match again.
        visible = replica.get("room_visible")
        if visible is None:
            return None
        if not visible:
            left = 0
    return None if left is None or right is None else abs(left - right) <= 0.001


def chaos_checks(case, observations):
    probes = {
        (e["label"], e["slot"]): e
        for e in observations.get("host", [])
        if e["event"] == "pool_probe"
    }
    required = [(label, slot) for label in ("before", "acquired", "removed") for slot in (0, 1)]
    if any(key not in probes or len(probes[key].get("results", [])) != 32 for key in required):
        return [{"name": "shared_pool", "status": "missing"}]
    before = probes["before", 0]["results"]
    acquired = probes["acquired", 0]["results"]
    shared = acquired != before and all(
        probes[label, 0]["results"] == probes[label, 1]["results"]
        for label in ("before", "acquired", "removed")
    )
    restored = probes["removed", 0]["results"] == before
    ownership = all(
        probes[label, slot]["owned"] == int(label == "acquired" and slot == case["slot"])
        for label, slot in required
    )
    checks = [
        {"name": name, "status": "passed" if passed else "failed"}
        for name, passed in (
            ("shared_pool", shared),
            ("pool_removal", restored),
            ("ownership", ownership),
        )
    ]
    for role in ("host", "client"):
        samples = [
            e
            for e in observations.get(role, [])
            if e["event"] == "sample" and 90 <= e.get("tick", 0) < case.get("end_tick", 150)
        ]
        complete = len(samples) >= 2 and all(
            len(e.get("players", [])) == 2
            and [p.get("slot") for p in e["players"]] == [0, 1]
            and all("target_count" in p for p in e["players"])
            for e in samples
        )
        matches = complete and all(
            p["target_count"] == int(p["slot"] == case["slot"])
            for e in samples
            for p in e["players"]
        )
        checks.append(
            {
                "name": role + "_ownership",
                "status": "missing" if not complete else "passed" if matches else "failed",
            }
        )
    return checks


def stat_checks(case, observations):
    """Return named checks with passed/failed/missing evidence, never a guess."""
    if case.get("enum") == "COLLECTIBLE_CHAOS":
        return chaos_checks(case, observations)
    expected = STAT_EFFECTS.get(case.get("enum")) or consumable_recipe(case).get("stats")
    if not expected:
        return []
    host = observations.get("host", [])
    client = observations.get("client", [])
    slot, use_tick = case["slot"], case.get("use_tick", 60)

    def samples(values):
        return [e for e in values if e["event"] == "sample"]

    def players(event):
        values = event.get("players", []) if event else []
        if len(values) != 2 or [p.get("slot") for p in values] != [0, 1]:
            return None
        return values

    before = next((e for e in samples(host) if e.get("label") == "before"), None)
    captured = {e["tick"]: e for e in samples(host) if e.get("label") == "captured"}
    after = [e for tick, e in captured.items() if use_tick < tick <= use_tick + 30]
    checks = []
    for field, direction in expected.items():
        initial = players(before)[slot].get(field) if players(before) else None
        measured = [players(e)[slot].get(field) for e in after if players(e)]
        measured = [v for v in measured if v is not None]
        passed = initial is not None and bool(measured)
        state = "missing"
        if passed:
            state = (
                "passed" if any((v - initial) * direction > 0.001 for v in measured) else "failed"
            )
        checks.append({"name": "effect:" + field, "status": state})
    pairs = [
        (captured[e["tick"]], e)
        for e in samples(client)
        if e.get("tick", 0) >= use_tick + 30 and e["tick"] in captured
    ]
    complete = len(pairs) >= 2 and all(
        players(e) is not None and all(field in p for p in players(e) for field in expected)
        for pair in pairs
        for e in pair
    )
    comparisons = (
        [
            peer_field_matches(a, b, field)
            for authority, replica in pairs
            for a, b in zip(authority["players"], replica["players"])
            for field in expected
        ]
        if complete
        else []
    )
    complete = complete and None not in comparisons
    matches = complete and all(comparisons)
    checks.append(
        {
            "name": "peer_effect_state",
            "status": "missing" if not complete else "passed" if matches else "failed",
        }
    )
    # Resource counters are shared by the native co-op rules. Personal stats
    # and health must not be granted to the teammate along with the holder.
    personal = set(expected) - {"coins", "bombs", "keys"}
    if personal:
        other = 1 - slot
        complete = (
            players(before) is not None
            and bool(after)
            and all(
                players(e) is not None and all(field in players(e)[other] for field in personal)
                for e in [before, *after]
            )
        )
        unchanged = complete and all(
            abs(players(e)[other][field] - players(before)[other][field]) <= 0.001
            for e in after
            for field in personal
        )
        checks.append(
            {
                "name": "holder_only",
                "status": "missing" if not complete else "passed" if unchanged else "failed",
            }
        )
    return checks


def spawn_checks(case, observations):
    recipe = consumable_recipe(case)
    rules = SPAWN_EFFECTS.get(case.get("enum")) or recipe.get("spawns", {})
    if not rules:
        return []
    slot = case["slot"]
    host = [e for e in observations.get("host", []) if e["event"] == "sample"]
    before = next((e for e in host if e.get("label") == "before"), None)
    label = "post_use" if recipe else "acquired"
    acquired = next((e for e in host if e.get("label") == label), None)
    captured = {e["tick"]: e for e in host if e.get("label") == "captured"}
    pairs = [
        (captured[e["tick"]], e)
        for e in observations.get("client", [])
        if e["event"] == "sample"
        and e.get("tick", 0) >= case.get("use_tick", 60) + 1
        and e["tick"] in captured
    ]

    def count(event, pattern):
        players = event.get("players", []) if event else []
        if len(players) != 2 or "entity_types" not in players[slot]:
            return None
        values = players[slot]["entity_types"] or {}
        return sum(
            n
            for key, n in values.items()
            if any(
                key.startswith(part) if part.endswith(".") else key == part
                for part in pattern.split("|")
            )
        )

    checks = []
    for pattern, (low, high) in rules.items():
        left, right = count(before, pattern), count(acquired, pattern)
        if recipe.get("delayed_spawn"):
            window = [
                count(e, pattern)
                for tick, e in captured.items()
                if case.get("use_tick", 60) < tick <= case.get("use_tick", 60) + 60
            ]
            right = max((n for n in window if n is not None), default=None)
        state = (
            "missing"
            if left is None or right is None
            else ("passed" if low <= right - left <= high else "failed")
        )
        checks.append({"name": "spawn:" + pattern, "status": state})
        present = [
            (count(a, pattern), count(b, pattern), b["players"][slot].get("room_visible", True))
            for a, b in pairs
            if len(b.get("players", [])) == 2
        ]
        complete = len(present) >= 2 and all(a is not None and b is not None for a, b, _ in present)
        checks.append(
            {
                "name": "peer_spawn:" + pattern,
                "status": "missing"
                if not complete
                else "passed"
                if all((a if visible else 0) == b for a, b, visible in present)
                and any(a > 0 for a, _, _ in present)
                else "failed",
            }
        )
    return checks


def shot_checks(case, observations):
    expected = SHOT_EFFECTS.get(case.get("enum"))
    if not expected:
        return []
    frames = {e["tick"]: e for e in observations.get("host", []) if e["event"] == "shot_probe"}
    volleys = {}
    seen = set()
    for tick, frame in frames.items():
        for tear in frame["tears"]:
            if tear["id"] and tear["id"] not in seen:
                seen.add(tear["id"])
                volleys.setdefault(tick - tear["age"], []).append(tear)
    fired = list(volleys.values())
    matches = [len(v) == expected["volley"] for v in fired]
    checks = [
        {
            "name": "actual_volley",
            "status": "missing" if len(matches) < 2 else "passed" if all(matches) else "failed",
            "observed": [len(v) for v in fired],
        }
    ]
    paired = []
    for e in observations.get("client", []):
        if e["event"] != "shot_probe" or e["tick"] not in frames:
            continue
        source = {t["id"]: t for t in frames[e["tick"]]["tears"] if t["id"]}
        target = {t["id"]: t for t in e["tears"] if t["id"]}
        if source:
            paired.append(
                source.keys() == target.keys()
                and all(
                    abs(source[k][f] - target[k][f]) <= 0.001
                    for k in source
                    for f in ("damage", "vx", "vy")
                )
            )
    checks.append(
        {
            "name": "peer_actual_tears",
            "status": "missing" if len(paired) < 2 else "passed" if all(paired) else "failed",
        }
    )
    return checks


def effect_checks(case, observations):
    return (
        stat_checks(case, observations)
        + spawn_checks(case, observations)
        + shot_checks(case, observations)
        + consumable_checks(case, observations)
        + room_effect_checks(case, observations)
    )


def consumable_checks(case, observations):
    recipe = consumable_recipe(case)
    if not recipe:
        return []
    slot = case["slot"]
    host = [e for e in observations.get("host", []) if e["event"] == "sample"]
    before = next((e for e in host if e.get("label") == "before"), None)
    used = next((e for e in host if e.get("label") == "post_use"), None)
    captured = {e["tick"]: e for e in host if e.get("label") == "captured"}
    pairs = [
        (captured[e["tick"]], e)
        for e in observations.get("client", [])
        if e["event"] == "sample"
        and e["tick"] in captured
        and e["tick"] >= case.get("use_tick", 60) + 1
    ]
    checks = []

    def value(event, field, player=slot):
        players = event.get("players", []) if event else []
        return players[player].get(field) if len(players) == 2 else None

    def check(name, values):
        checks.append(
            {
                "name": name,
                "status": "missing"
                if not values or None in values
                else "passed"
                if all(values)
                else "failed",
            }
        )

    if recipe.get("teleport"):
        target = next(
            (e for e in observations.get("host", []) if e["event"] == "teleport_target"), None
        )
        later = [(a, b) for a, b in pairs if a["tick"] >= 150]
        origin, teammate_origin = value(before, "room"), value(before, "room", 1 - slot)
        check(
            "teleport_destination",
            [
                None
                if target is None or origin is None or value(a, "room") is None
                else value(a, "room") != origin
                and (
                    value(a, "room") == target["index"]
                    if "index" in target
                    else value(a, "room_type") in target.get("types", [])
                )
                for a, _ in later
            ]
            if len(later) >= 2
            else [],
        )
        check(
            "peer_teleport",
            [
                None
                if value(a, "room") is None or value(b, "room") is None
                else value(a, "room") == value(b, "room")
                for a, b in later
            ]
            if len(later) >= 2
            else [],
        )
        check(
            "teleport_holder_only",
            [
                None
                if teammate_origin is None or value(e, "room", 1 - slot) is None
                else value(e, "room", 1 - slot) == teammate_origin
                for pair in later
                for e in pair
            ]
            if len(later) >= 2
            else [],
        )

    expected_values = dict(recipe.get("exact", {}))
    expected_values.update({f: f for f in recipe.get("unchanged", [])})
    for field, (low, high) in recipe.get("range_delta", {}).items():
        left, right = value(before, field), value(used, field)
        check(
            "effect_count:" + field,
            [None if left is None or right is None else low <= right - left <= high],
        )
        # Keep the observed number for exact replica and reunion checks.
        expected_values[field] = right
    for field in set(recipe.get("double", [])) | set(recipe.get("delta", {})):
        left = value(before, field)
        desired = (
            (left * 2 if field in recipe.get("double", []) else left + recipe["delta"][field])
            if left is not None
            else None
        )
        expected_values[field] = desired
    for a, b in recipe.get("swap", []):
        for target, source in ((a, b), (b, a)):
            original = value(before, source)
            expected_values[target] = (
                original
                if isinstance(original, bool) or original is None
                else original * recipe.get("swap_multiplier", 1)
            )
    for field, expected in expected_values.items():
        desired = value(before, expected) if isinstance(expected, str) else expected
        right = value(used, field)
        check(
            "exact_effect:" + field,
            [None if right is None or desired is None else abs(right - desired) <= 0.001],
        )
        check(
            "peer_exact_effect:" + field,
            [
                peer_field_matches(a["players"][slot], b["players"][slot], field)
                if len(a.get("players", [])) == 2 and len(b.get("players", [])) == 2
                else None
                for a, b in pairs
            ]
            if len(pairs) >= 2
            else [],
        )
        if field not in {
            "coins",
            "bombs",
            "keys",
            "golden_bomb",
            "golden_key",
        } and field not in recipe.get("team_delta", {}):
            left, right = value(before, field, 1 - slot), value(used, field, 1 - slot)
            check(
                "holder_only:" + field,
                [None if left is None or right is None else abs(left - right) <= 0.001],
            )
    for field, delta in recipe.get("team_delta", {}).items():
        left, right = value(before, field, 1 - slot), value(used, field, 1 - slot)
        check(
            "teammate_effect:" + field,
            [None if left is None or right is None else abs(right - left - delta) <= 0.001],
        )
        check(
            "peer_teammate_effect:" + field,
            [
                None
                if value(a, field, 1 - slot) is None or value(b, field, 1 - slot) is None
                else abs(value(a, field, 1 - slot) - value(b, field, 1 - slot)) <= 0.001
                for a, b in pairs
            ]
            if len(pairs) >= 2
            else [],
        )
    if recipe.get("reunite"):
        later = [(a, b) for a, b in pairs if a["tick"] >= 180]
        check(
            "familiar_reunion",
            [
                None
                if any(value(e, "room", s) is None for e in pair for s in (0, 1))
                else all(value(e, "room", 0) == value(e, "room", 1) for e in pair)
                and all(
                    value(e, field) == desired
                    for e in pair
                    for field, desired in expected_values.items()
                )
                for pair in later
            ]
            if len(later) >= 2
            else [],
        )
    if recipe.get("pocket"):

        def pocket_state(event):
            card, pill, types = (value(event, f) for f in ("card", "pill", "entity_types"))
            if card is None or pill is None or types is None:
                return None
            floor = {
                key: n for key, n in (types or {}).items() if key.startswith(("5.300.", "5.70."))
            }
            return card, pill, floor

        a, b = pocket_state(before), pocket_state(used)

        def total(state):
            return int(state[0] != 0) + int(state[1] != 0) + sum(state[2].values())

        check("produced_pocket", [None if a is None or b is None else total(b) - total(a) == 1])
        check(
            "peer_pocket",
            [
                None
                if pocket_state(a) is None or pocket_state(b) is None
                else pocket_state(a) == pocket_state(b)
                for a, b in pairs
            ]
            if len(pairs) >= 2
            else [],
        )
        check(
            "holder_only:pocket",
            [
                None
                if value(before, f, 1 - slot) is None or value(used, f, 1 - slot) is None
                else value(before, f, 1 - slot) == value(used, f, 1 - slot)
                for f in ("card", "pill")
            ],
        )
    for field in recipe.get("expire_room", []):
        left = value(before, field)
        room = value(before, "room")
        later = [(a, b) for a, b in pairs if a["tick"] >= 180]
        check(
            "room_expiry:" + field,
            [
                None
                if any(v is None for v in (left, room, value(e, field), value(e, "room")))
                else value(e, "room") != room and abs(value(e, field) - left) <= 0.001
                for pair in later
                for e in pair
            ]
            if len(later) >= 2
            else [],
        )
    if recipe.get("eternal_lifecycle"):
        room_pairs = [(a, b) for a, b in pairs if 180 <= a["tick"] < 240]
        floor_pairs = [(a, b) for a, b in pairs if a["tick"] >= 360]
        for name, window, next_floor in (
            ("eternal_heart_across_room", room_pairs, False),
            ("eternal_heart_converts_on_floor", floor_pairs, True),
        ):
            check(
                name,
                [
                    None
                    if any(
                        value(before, f) is None or value(e, f) is None
                        for f in ("eternal", "max_hearts", "stage", "room")
                    )
                    else value(e, "stage") == value(before, "stage") + int(next_floor)
                    and value(e, "eternal") == (0 if next_floor else 1)
                    and value(e, "max_hearts")
                    == value(before, "max_hearts") + (2 if next_floor else 0)
                    and (next_floor or value(e, "room") != value(before, "room"))
                    for pair in window
                    for e in pair
                ]
                if len(window) >= 2
                else [],
            )
    if recipe.get("golden_lifecycle"):
        room_pairs = [(a, b) for a, b in pairs if 180 <= a["tick"] < 240]
        floor_pairs = [(a, b) for a, b in pairs if a["tick"] >= 360]
        check(
            "golden_flags_across_room",
            [
                None
                if value(before, "room") is None
                or any(value(e, f) is None for f in ("room", "golden_key", "golden_bomb"))
                else value(e, "room") != value(before, "room")
                and value(e, "golden_key") is True
                and value(e, "golden_bomb") is False
                for pair in room_pairs
                for e in pair
            ]
            if len(room_pairs) >= 2
            else [],
        )
        check(
            "golden_flags_clear_on_floor",
            [
                None
                if value(before, "stage") is None
                or any(value(e, f) is None for f in ("stage", "golden_key", "golden_bomb"))
                else value(e, "stage") == value(before, "stage") + 1
                and value(e, "golden_key") is False
                and value(e, "golden_bomb") is False
                for pair in floor_pairs
                for e in pair
            ]
            if len(floor_pairs) >= 2
            else [],
        )
    if "enemy_damage" in recipe:
        left, right = value(before, "targets"), value(used, "targets")
        complete = bool(left) and bool(right) and len(left) == len(right) == 2
        check(
            "room_damage",
            [
                a["seed"] == b["seed"] and abs(a["hp"] - b["hp"] - recipe["enemy_damage"]) <= 0.001
                for a, b in zip(left, right)
            ]
            if complete
            else [],
        )
        check(
            "peer_room_damage",
            [
                None
                if value(a, "targets") is None or value(b, "targets") is None
                else len(value(a, "targets")) == 2
                and (value(a, "targets") if value(b, "room_visible") is not False else [])
                == value(b, "targets")
                for a, b in pairs
                if value(a, "room") == value(before, "room")
                and value(a, "stage") == value(before, "stage")
            ]
            if len(pairs) >= 2
            else [],
        )
    return checks
