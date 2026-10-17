"""Single-item map and floor-state assertions against native room descriptors."""

ROOM_EFFECTS = {
    "PILLEFFECT_AMNESIA": {
        "preset_curses": [],
        "remaining_curses": ["CURSE_OF_THE_LOST"],
        "floor_lifecycle": True,
        "identify_pills": True,
        "horse": {"forget_pills": True},
    },
    "PILLEFFECT_QUESTIONMARK": {
        "preset_curses": [],
        "remaining_curses": ["CURSE_OF_MAZE"],
        "floor_lifecycle": True,
        "horse": {"extra_curse": True},
    },
    "COLLECTIBLE_COMPASS": {"map": "compass", "persistent": True, "floor_lifecycle": True},
    "COLLECTIBLE_TREASURE_MAP": {"map": "layout", "persistent": True, "floor_lifecycle": True},
    "COLLECTIBLE_BLUE_MAP": {"map": "secrets", "persistent": True, "floor_lifecycle": True},
    "COLLECTIBLE_MIND": {"map": "full", "persistent": True, "floor_lifecycle": True},
    "CARD_WORLD": {"map": "world", "floor_lifecycle": True},
    "RUNE_ANSUZ": {"map": "full", "floor_lifecycle": True},
    "CARD_SUN": {
        "map": "world",
        "floor_lifecycle": True,
        "preset_curses": ["CURSE_OF_DARKNESS"],
        "remaining_curses": [],
    },
    "RUNE_DAGAZ": {
        "preset_curses": [
            "CURSE_OF_DARKNESS",
            "CURSE_OF_THE_LOST",
            "CURSE_OF_MAZE",
            "CURSE_OF_LABYRINTH",
        ],
        "remaining_curses": ["CURSE_OF_LABYRINTH"],
    },
}

# RoomType and native DisplayFlags. Check the visible result rather than an
# inventory bit or a call to ApplyMapEffect, which could hide a missing effect.
ORDINARY, SECRET, SUPER_SECRET, ULTRA_SECRET = 1, 7, 8, 29
VISIBLE, ICON = 1, 4
PILL_COLOR_MASK = 0x7FF


def room_effect_recipe(case):
    rules = ROOM_EFFECTS.get(case.get("enum"), {})
    return {**rules, **(rules.get("horse", {}) if case.get("horse") else {})}


def required_flags(profile, kind):
    if profile == "layout":
        return VISIBLE if kind not in (SECRET, SUPER_SECRET, ULTRA_SECRET) else 0
    if profile == "compass":
        return ICON if kind not in (ORDINARY, SECRET, SUPER_SECRET, ULTRA_SECRET) else 0
    if profile == "secrets":
        return ICON if kind in (SECRET, SUPER_SECRET) else 0
    if kind == ULTRA_SECRET or profile == "world" and kind == SUPER_SECRET:
        return 0
    return VISIBLE if kind == ORDINARY else ICON


def room_effect_checks(case, observations):
    rules = room_effect_recipe(case)
    if not rules:
        return []
    host = observations.get("host", [])
    before = next((e for e in host if e["event"] == "sample" and e.get("label") == "before"), None)
    captured = {
        e["tick"]: e for e in host if e["event"] == "sample" and e.get("label") == "captured"
    }
    pairs = [
        (captured[e["tick"]], e)
        for e in observations.get("client", [])
        if e["event"] == "sample" and e["tick"] in captured and e["tick"] >= 90
    ]
    checks = []

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

    def state(e):
        return e.get("floor_effects", {}) if e else {}

    initial = state(before)
    early = [(a, b) for a, b in pairs if state(a).get("stage") == initial.get("stage")]
    if rules.get("map"):
        profile = rules["map"]
        base = {r["index"]: r for r in initial.get("map", [])}

        def revealed(e):
            rooms = state(e).get("map", [])
            targets = [r for r in rooms if required_flags(profile, r["type"])]
            return (
                None
                if not targets
                else all(r["flags"] & required_flags(profile, r["type"]) for r in targets)
            )

        check(
            "map_precondition",
            [
                any(
                    required_flags(profile, r["type"])
                    and not r["flags"] & required_flags(profile, r["type"])
                    for r in base.values()
                )
            ]
            if base
            else [],
        )
        check(
            "map_revealed", [revealed(e) for pair in early for e in pair] if len(early) >= 2 else []
        )
        scope_pairs = [(a, b) for a, b in early if a["tick"] <= 120]
        check(
            "map_scope",
            [
                all(
                    (r["flags"] & ICON) == (base[r["index"]]["flags"] & ICON)
                    for r in state(e).get("map", [])
                    if r["index"] in base
                    and (
                        profile == "layout"
                        or r["type"] in (SECRET, SUPER_SECRET, ULTRA_SECRET)
                        and not required_flags(profile, r["type"])
                    )
                )
                for pair in scope_pairs
                for e in pair
            ]
            if len(scope_pairs) >= 2 and base
            else [],
        )
        check(
            "peer_map",
            [
                state(a).get("map") == state(b).get("map")
                if state(a).get("map") and state(b).get("map")
                else None
                for a, b in pairs
            ]
            if len(pairs) >= 2
            else [],
        )
        later = [(a, b) for a, b in pairs if state(a).get("stage") != initial.get("stage")]
        check(
            "map_next_floor",
            [
                revealed(e)
                if rules.get("persistent")
                else any(
                    r["type"] == ORDINARY and not r["flags"] & VISIBLE
                    for r in state(e).get("map", [])
                )
                for pair in later
                for e in pair
            ]
            if len(later) >= 2
            else [],
        )
    if "remaining_curses" in rules:
        wanted = next((e for e in host if e["event"] == "floor_effect_precondition"), {})
        check(
            "curse_precondition",
            [initial.get("curses") == wanted["initial_curses"]]
            if "initial_curses" in wanted and "curses" in initial
            else [],
        )
        desired = wanted.get("remaining_curses")
        check(
            "curse_result",
            [
                None
                if "curses" not in state(e) or desired is None
                else (
                    state(e)["curses"] & desired == desired
                    and state(e)["curses"].bit_count() == desired.bit_count() + 1
                )
                if rules.get("extra_curse")
                else state(e)["curses"] == desired
                for pair in early
                for e in pair
            ]
            if len(early) >= 2
            else [],
        )
        if rules.get("floor_lifecycle"):
            rolled = {e["stage"]: e["curses"] for e in host if e["event"] == "floor_curse_roll"}
            later = [(a, b) for a, b in pairs if state(a).get("stage") != initial.get("stage")]
            check(
                "curse_next_floor",
                [
                    state(e)["curses"] == rolled[state(e)["stage"]]
                    if "curses" in state(e) and state(e).get("stage") in rolled
                    else None
                    for pair in later
                    for e in pair
                ]
                if len(later) >= 2
                else [],
            )
    if rules.get("identify_pills"):
        before_pills = initial.get("identified_pills", [])
        assigned = next((e.get("color") for e in host if e["event"] == "pill_assigned"), None)
        color = assigned & PILL_COLOR_MASK if assigned is not None else None
        known = {p["color"] for p in before_pills if p["known"] and p["color"] != color}
        check("identified_pills_precondition", [len(known) >= 2] if color is not None else [])
        check(
            "identified_pills_after_use",
            [
                len([p for p in state(e).get("identified_pills", []) if p["color"] in known])
                == len(known)
                and all(
                    p["known"] is not rules.get("forget_pills", False)
                    for p in state(e).get("identified_pills", [])
                    if p["color"] in known
                )
                for pair in early
                for e in pair
            ]
            if len(early) >= 2 and len(known) >= 2
            else [],
        )
    return checks
