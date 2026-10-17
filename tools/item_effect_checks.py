"""Assertions for individual effects; an unknown recipe never becomes a pass."""

# These items have direct, unconditional effects in the clean Isaac fixture.
# Values are directions, not a substitute for checking every listed attribute.
# Conditional effects belong in their own recipe instead of this table.
STAT_EFFECTS = {
    "COLLECTIBLE_SAD_ONION": {"delay": -1},
    "COLLECTIBLE_MAXS_HEAD": {"damage": 1},
    "COLLECTIBLE_NUMBER_ONE": {"delay": -1, "range": -1},
    "COLLECTIBLE_BLOOD_MARTYR": {"damage": 1},
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


SUPPORTED_EFFECTS = {*STAT_EFFECTS, "COLLECTIBLE_CHAOS"}


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


def effect_checks(case, observations):
    """Return named checks with passed/failed/missing evidence, never a guess."""
    if case.get("enum") == "COLLECTIBLE_CHAOS":
        return chaos_checks(case, observations)
    expected = STAT_EFFECTS.get(case.get("enum"))
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
    matches = complete and all(
        abs(a[field] - b[field]) <= 0.001
        for authority, replica in pairs
        for a, b in zip(authority["players"], replica["players"])
        for field in expected
    )
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
