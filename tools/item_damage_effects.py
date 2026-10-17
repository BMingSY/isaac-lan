"""Damage-effect trials: real health loss, ownership, expiry and native resets."""


def hit(name, tick, loss, amount=1):
    return {"action": "hit", "name": name, "tick": tick, "amount": amount, "loss": loss}


def move(action, tick):
    return {"action": action, "tick": tick}


ROOM_DAMAGE = [move("room", 240), hit("next_room", 330, 2, 2)]
DAMAGE_EFFECTS = {
    "COLLECTIBLE_WAFER": {
        "steps": [
            hit("first", 90, 1, 2),
            hit("repeat", 180, 1, 2),
            move("room", 240),
            hit("next_room", 330, 1, 2),
            move("floor", 390),
            hit("next_floor", 630, 1, 2),
        ]
    },
    "PILLEFFECT_PERCS": {
        "hearts": 12,
        "team_hearts": 12,
        "steps": [hit("first", 90, 1, 2), hit("repeat", 180, 1, 2), *ROOM_DAMAGE],
        "horse": {"full_heal": True},
    },
    "PILLEFFECT_ADDICTED": {
        "team_hearts": 12,
        "steps": [
            hit("first", 90, 2),
            hit("repeat", 180, 2),
            move("room", 240),
            hit("next_room", 330, 1),
        ],
        "horse": {"broken": 1},
    },
    "COLLECTIBLE_HOLY_MANTLE": {
        "mantle_shield": True,
        "steps": [
            hit("first", 90, 0),
            hit("repeat", 180, 1),
            move("room", 240),
            hit("next_room", 330, 0),
            hit("room_repeat", 420, 1),
            move("floor", 480),
            hit("next_floor", 720, 0),
            hit("floor_repeat", 810, 1),
        ],
    },
    "CARD_HOLY": {
        "mantle_shield": True,
        "steps": [
            move("room", 150),
            hit("carried_shield", 240, 0),
            hit("consumed_shield", 330, 1),
            move("floor", 390),
            hit("next_floor", 630, 1),
        ],
    },
    "TRINKET_WOODEN_CROSS": {
        "mantle_shield": True,
        # The shield is granted by a floor entry, not by the fixture itself.
        "steps": [
            move("floor", 90),
            hit("first_floor", 330, 0),
            hit("consumed_shield", 420, 1),
            move("room", 480),
            hit("next_room", 570, 1),
            move("floor", 630),
            hit("next_floor", 870, 0),
            hit("floor_repeat", 960, 1),
        ],
    },
    "COLLECTIBLE_BOOK_OF_SHADOWS": {
        "shadow_shield": True,
        "steps": [
            hit("first", 90, 0),
            hit("repeat", 240, 0),
            hit("before_expiry", 330, 0),
            hit("expired", 390, 1),
            move("room", 450),
            hit("next_room", 540, 1),
        ],
    },
    "RUNE_ALGIZ": {
        "shadow_shield": True,
        "steps": [
            hit("first", 90, 0),
            hit("repeat", 240, 0),
            hit("before_expiry", 630, 0),
            hit("expired", 690, 1),
            move("room", 750),
            hit("next_room", 840, 1),
        ],
    },
}


def damage_recipe(case):
    rules = DAMAGE_EFFECTS.get(case.get("enum"), {})
    return {**rules, **(rules.get("horse", {}) if case.get("horse") else {})}


def damage_checks(case, observations):
    rules = damage_recipe(case)
    if not rules:
        return []
    host = observations.get("host", [])
    slot = case["slot"]
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

    def health(state):
        return state["hearts"] + state["soul"]

    trials = {(e["probe"], e["slot"]): e for e in host if e["event"] == "damage_trial"}
    hits = [step for step in rules["steps"] if step["action"] == "hit"]
    check(
        "damage_trial_count",
        [len([e for e in host if e["event"] == "damage_trial"]) == len(hits) * 2],
    )
    for step in rules["steps"]:
        if step["action"] != "hit":
            continue
        limit = next(
            (s["tick"] for s in rules["steps"] if s["tick"] > step["tick"]),
            case.get("end_tick", rules["steps"][-1]["tick"] + 60),
        )
        for player in (slot, 1 - slot):
            trial = trials.get((step["name"], player))
            expected = step["loss"] if player == slot else step["amount"]
            check(
                "damage:" + step["name"] + (":holder" if player == slot else ":teammate"),
                [
                    trial["amount"] == step["amount"]
                    and step["tick"] <= trial["tick"] < limit
                    and health(trial["before"]) > step["amount"]
                    and health(trial["before"]) - health(trial["after"]) == expected
                ]
                if trial
                else [],
            )
    transitions = [e for e in host if e["event"] == "damage_transition"]
    for step in rules["steps"]:
        if step["action"] == "hit":
            continue
        request = next((e for e in transitions if e["tick"] == step["tick"]), None)
        next_hit = next(
            s for s in rules["steps"] if s["action"] == "hit" and s["tick"] > step["tick"]
        )
        trial = trials.get((next_hit["name"], slot))
        check(
            "damage_transition:" + str(step["tick"]),
            [
                trial["room"] != request["room"] and trial["stage"] == request["stage"]
                if step["action"] == "room"
                else trial["stage"] == request["stage"] + 1
            ]
            if trial and request
            else [],
        )
    captured = {
        e["tick"]: e for e in host if e["event"] == "sample" and e.get("label") == "captured"
    }
    pairs = [
        (captured[e["tick"]], e)
        for e in observations.get("client", [])
        if e["event"] == "sample" and e.get("tick", 0) >= 90 and e["tick"] in captured
    ]
    for step in hits:
        end = next(
            (s["tick"] for s in rules["steps"] if s["tick"] > step["tick"]),
            case.get("end_tick", rules["steps"][-1]["tick"] + 60),
        )
        actual_tick = max(
            (trials[step["name"], p]["tick"] for p in (0, 1) if (step["name"], p) in trials),
            default=step["tick"],
        )
        window = [(a, b) for a, b in pairs if actual_tick < a["tick"] < end]
        check(
            "damage_health_retained:" + step["name"],
            [
                None
                if any((step["name"], p) not in trials for p in (0, 1))
                or len(e.get("players", [])) != 2
                else all(
                    e["players"][p].get(field) == trials[step["name"], p]["after"][field]
                    for p in (0, 1)
                    for field in ("hearts", "soul", "broken")
                )
                for pair in window
                for e in pair
            ],
        )
    for field in ("hearts", "max_hearts", "soul", "broken"):
        check(
            "damage_peer:" + field,
            [
                None
                if len(a.get("players", [])) != 2
                or len(b.get("players", [])) != 2
                or any(field not in e["players"][p] for e in (a, b) for p in (0, 1))
                else all(a["players"][p][field] == b["players"][p][field] for p in (0, 1))
                for a, b in pairs
            ]
            if len(pairs) >= 2
            else [],
        )
    shield_fields = (
        ("shadows", "invincible")
        if rules.get("shadow_shield")
        else ("mantle",)
        if rules.get("mantle_shield")
        else ()
    )
    if shield_fields:
        check(
            "damage_shield_peer",
            [
                None
                if len(a.get("players", [])) != 2
                or len(b.get("players", [])) != 2
                or any(
                    field not in e["players"][p].get("shield", {})
                    for e in (a, b)
                    for p in (0, 1)
                    for field in shield_fields
                )
                else all(
                    a["players"][p]["shield"][field] == b["players"][p]["shield"][field]
                    for p in (0, 1)
                    for field in shield_fields
                )
                for a, b in pairs
            ]
            if len(pairs) >= 2
            else [],
        )
    before = next((e for e in host if e.get("label") == "before"), None)
    used = next((e for e in host if e.get("label") == "post_use"), None)
    if rules.get("team_hearts"):
        check(
            "damage_use_hearts",
            [
                before["players"][p]["hearts"] < before["players"][p]["max_hearts"]
                and used["players"][p]["hearts"]
                == (
                    used["players"][p]["max_hearts"]
                    if rules.get("full_heal") and p == slot
                    else before["players"][p]["hearts"]
                )
                for p in (0, 1)
            ]
            if before and used
            else [],
        )
    if rules.get("full_heal"):
        check(
            "damage_full_heal",
            [
                before["players"][slot]["hearts"] < before["players"][slot]["max_hearts"]
                and used["players"][slot]["hearts"] == used["players"][slot]["max_hearts"]
            ]
            if before and used
            else [],
        )
    if case.get("enum") == "PILLEFFECT_ADDICTED":
        check(
            "damage_broken_hearts",
            [
                used["players"][p]["broken"] - before["players"][p]["broken"]
                == (rules.get("broken", 0) if p == slot else 0)
                for p in (0, 1)
            ]
            if before and used
            else [],
        )
    return checks
