"""Shooting familiar trials: native attacks, damage, ownership and lifetime."""

from collections import defaultdict
from math import hypot


FAMILIAR_EFFECTS = {
    "COLLECTIBLE_BROTHER_BOBBY": {"variant": "BROTHER_BOBBY", "damage": 3.5, "interval": 16},
    "COLLECTIBLE_SISTER_MAGGY": {"variant": "SISTER_MAGGY", "damage": 6, "interval": 22},
    "COLLECTIBLE_GHOST_BABY": {
        "variant": "GHOST_BABY",
        "damage": 3.5,
        "interval": 22,
        "spectral": True,
    },
    "COLLECTIBLE_HARLEQUIN_BABY": {
        "variant": "HARLEQUIN_BABY",
        "damage": 4,
        "interval": 22,
        "pattern": "split",
        "volley": 2,
    },
    "COLLECTIBLE_INCUBUS": {"variant": "INCUBUS", "damage_factor": 0.75, "interval": 11},
    "COLLECTIBLE_LIL_LOKI": {
        "variant": "LIL_LOKI",
        "damage": 3.5,
        "interval": 22,
        "pattern": "cross",
        "volley": 4,
    },
}


def familiar_checks(case, observations):
    rules = FAMILIAR_EFFECTS.get(case.get("enum"))
    if not rules:
        return []
    host = observations.get("host", [])
    probes = [e for e in host if e["event"] == "familiar_probe"]
    checks = []

    def check(name, values):
        checks.append(
            {
                "name": "familiar_" + name,
                "status": "missing"
                if not values or None in values
                else "passed"
                if all(values)
                else "failed",
            }
        )

    def window(low, high):
        return [e for e in probes if low <= e["tick"] <= high]

    for name, low, high, count in (
        ("acquired", 80, 140, 1),
        ("room", 350, 380, 1),
        ("floor", 600, 620, 1),
        ("removed", 810, 840, 0),
    ):
        values = window(low, high)
        check(
            name,
            [
                e.get("owned") == count
                and e.get("teammate_owned") == 0
                and len(e.get("familiars", [])) == count
                and all(f.get("controller") == case["slot"] + 1 for f in e["familiars"])
                for e in values
            ],
        )
    initial, moved = window(80, 90), window(130, 140)
    check(
        "follows_owner",
        [
            moved[-1]["x"] - initial[0]["x"] > 20
            and len(initial[0]["familiars"]) == len(moved[-1]["familiars"]) == 1
            and moved[-1]["familiars"][0]["x"] - initial[0]["familiars"][0]["x"] > 15
            and hypot(
                moved[-1]["familiars"][0]["x"] - moved[-1]["x"],
                moved[-1]["familiars"][0]["y"] - moved[-1]["y"],
            )
            < 90
        ]
        if initial and moved
        else [],
    )
    a, b, c = window(140, 145), window(350, 380), window(600, 620)
    check(
        "transitions",
        [a[0]["room"] != b[0]["room"] and c[0]["stage"] == a[0]["stage"] + 1]
        if a and b and c
        else [],
    )
    for phase, low, high in (("initial", 165, 260), ("floor", 645, 740)):
        frames = window(low, high)
        shots = {}
        for e in frames:
            for shot in e.get("shots", []):
                shots.setdefault(shot["id"], (e, shot))
        expected = rules.get("damage", 3.5 * rules.get("damage_factor", 1))
        check(
            phase + "_shot_damage",
            [
                abs(s["damage"] - expected) < 0.001
                and s["controller"] == case["slot"] + 1
                and (not rules.get("spectral") or s.get("spectral") is True)
                for _, s in shots.values()
            ],
        )
        volleys = defaultdict(list)
        for e, s in shots.values():
            volleys[e["tick"] - s["age"]].append(s)
        full = [v for v in volleys.values() if len(v) == rules.get("volley", 1)]
        check(phase + "_volley", [len(full) >= 3])
        times = sorted(volleys)
        intervals = [b - a for a, b in zip(times, times[1:])]
        check(phase + "_cadence", [n == rules["interval"] for n in intervals])
        if rules.get("pattern") == "split":
            check(
                phase + "_pattern",
                [
                    min(s["vx"] for s in v) < -1
                    and max(s["vx"] for s in v) > 1
                    and all(s["vy"] < -1 for s in v)
                    for v in full
                ],
            )
        elif rules.get("pattern") == "cross":
            check(
                phase + "_pattern",
                [
                    any(s["vx"] > 1 and abs(s["vy"]) < 0.1 for s in v)
                    and any(s["vx"] < -1 and abs(s["vy"]) < 0.1 for s in v)
                    and any(s["vy"] > 1 and abs(s["vx"]) < 0.1 for s in v)
                    and any(s["vy"] < -1 and abs(s["vx"]) < 0.1 for s in v)
                    for v in full
                ],
            )
        hits = [
            e for e in host if e["event"] == "familiar_hit" and low - 15 <= e["tick"] <= high + 10
        ]
        check(
            phase + "_actual_damage",
            [
                abs(e["amount"] - expected) < 0.001
                and abs(e["before"] - e["after"] - expected) < 0.001
                and e["controller"] == case["slot"] + 1
                for e in hits
            ],
        )
        if rules.get("spectral"):
            check(phase + "_through_rock", [e.get("rock_intact") is True for e in hits])

    captured = {e["tick"]: e for e in probes}
    pairs = [
        (captured[e["tick"]], e)
        for e in observations.get("client", [])
        if e["event"] == "familiar_probe" and e["tick"] in captured and e["tick"] >= 80
    ]
    check(
        "peer_ownership",
        [
            b.get("owned") == a["owned"]
            and a.get("teammate_owned") == b.get("teammate_owned") == 0
            and b.get("room_visible") is not None
            and len(b.get("familiars", [])) == (len(a["familiars"]) if b["room_visible"] else 0)
            and all(f.get("controller") == case["slot"] + 1 for f in b.get("familiars", []))
            for a, b in pairs
        ],
    )
    check("peer_visible", [any(b.get("room_visible") for _, b in pairs)] if pairs else [])
    check(
        "peer_attack_visible",
        [any(b.get("room_visible") and a["shots"] and b["shots"] for a, b in pairs)]
        if pairs
        else [],
    )
    compare = []
    for a, b in pairs:
        if not b.get("room_visible"):
            continue
        left, right = {s["id"]: s for s in a["shots"]}, {s["id"]: s for s in b["shots"]}
        compare.append(
            left.keys() == right.keys()
            and all(
                abs(s["damage"] - right[k]["damage"]) < 0.001
                and s["controller"] == right[k]["controller"]
                for k, s in left.items()
            )
        )
    check("peer_shots", compare)
    return checks
