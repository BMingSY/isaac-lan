"""Shooting familiar trials: native attacks, damage, ownership and lifetime."""

from collections import defaultdict
from math import hypot


FAMILIAR_EFFECTS = {
    "TRINKET_DUCT_TAPE": {
        "variant": "BROTHER_BOBBY",
        "prerequisite": "COLLECTIBLE_BROTHER_BOBBY",
        "damage": 3.5,
        "modifier": True,
        "fixed_offset": True,
    },
    "TRINKET_FRIENDSHIP_NECKLACE": {
        "variant": "BROTHER_BOBBY",
        "prerequisite": "COLLECTIBLE_BROTHER_BOBBY",
        "damage": 3.5,
        "modifier": True,
        "orbital": True,
        "native_orbit": True,
        "distance": 120,
    },
    "TRINKET_RC_REMOTE": {
        "variant": "BROTHER_BOBBY",
        "prerequisite": "COLLECTIBLE_BROTHER_BOBBY",
        "damage": 3.5,
        "modifier": True,
        "drop_window": [120, 139],
        "distance": 150,
    },
    "TRINKET_ISAACS_HEAD": {"variant": "ISAACS_HEAD", "damage": 3.5, "flags": ["TEAR_PIERCING"]},
    "TRINKET_SOUL": {"variant": "BLUE_BABY_SOUL", "damage": 3.5, "independent_motion": True},
    "TRINKET_BABY_BENDER": {
        "variant": "BROTHER_BOBBY",
        "prerequisite": "COLLECTIBLE_BROTHER_BOBBY",
        "damage": 3.5,
        "flags": ["TEAR_HOMING"],
        "modifier": True,
    },
    "TRINKET_FORGOTTEN_LULLABY": {
        "variant": "BROTHER_BOBBY",
        "prerequisite": "COLLECTIBLE_BROTHER_BOBBY",
        "damage": 3.5,
        "interval": 8,
        "modifier": True,
    },
    "TRINKET_CHILD_LEASH": {
        "variant": "BROTHER_BOBBY",
        "prerequisite": "COLLECTIBLE_BROTHER_BOBBY",
        "damage": 4.375,
        "distance": 50,
        "modifier": True,
    },
    "TRINKET_LIL_CLOT": {
        "variant": "BLOOD_BABY",
        "damage_factor": 0.35,
        "physical_remove": True,
        "persists_after_drop": True,
        "drop_damage_ticks": [900, 945, 990],
        "remove_room_tick": 1140,
        "end_tick": 1260,
    },
    "TRINKET_APOLLYONS_BEST_FRIEND": {
        "variant": "ABYSS_LOCUST",
        "contact": True,
        "contact_shoot": True,
        "independent_motion": True,
        "idle_without_targets": True,
        "physical_remove": True,
        "remove_room_tick": 900,
        "end_tick": 1020,
    },
    "COLLECTIBLE_BFFS": {
        "variant": "BROTHER_BOBBY",
        "prerequisite": "COLLECTIBLE_BROTHER_BOBBY",
        "damage": 7,
        "interval": 16,
        "modifier": True,
    },
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
    "COLLECTIBLE_LITTLE_STEVEN": {
        "variant": "LITTLE_STEVEN",
        "damage": 3.5,
        "flags": ["TEAR_HOMING"],
    },
    "COLLECTIBLE_LITTLE_GISH": {"variant": "LITTLE_GISH", "damage": 3.5, "flags": ["TEAR_SLOW"]},
    "COLLECTIBLE_DEMON_BABY": {"variant": "DEMON_BABY", "damage": 3, "automatic": True},
    "COLLECTIBLE_RAINBOW_BABY": {
        "variant": "RAINBOW_BABY",
        "variable_damage": True,
        "observe_flags": [
            "TEAR_HOMING",
            "TEAR_SLOW",
            "TEAR_POISON",
            "TEAR_FREEZE",
            "TEAR_SPECTRAL",
            "TEAR_PIERCING",
        ],
    },
    "COLLECTIBLE_MONGO_BABY": {
        "variant": "MONGO_BABY",
        "damage": 3.5,
        "spectral": True,
        "prerequisite": "COLLECTIBLE_GHOST_BABY",
    },
    "COLLECTIBLE_FATES_REWARD": {
        "variant": "FATES_REWARD",
        "damage_factor": 1,
        "prerequisite": "COLLECTIBLE_SCORPIO",
        "flags": ["TEAR_POISON"],
        "interval": 44,
        "minimum_volleys": 2,
    },
    "COLLECTIBLE_SERAPHIM": {"variant": "SERAPHIM", "damage": 10, "flags": ["TEAR_HOMING"]},
    "COLLECTIBLE_ABEL": {"variant": "ABEL", "damage": 3.5, "independent_motion": True},
    "COLLECTIBLE_CAINS_OTHER_EYE": {
        "variant": "CAINS_OTHER_EYE",
        "damage_factor": 0.75,
        "independent_motion": True,
    },
    "COLLECTIBLE_PAPA_FLY": {"variant": "PAPA_FLY", "damage_factor": 1, "automatic": True},
    "COLLECTIBLE_FREEZER_BABY": {"variant": "FREEZER_BABY", "damage": 3.5},
    "COLLECTIBLE_TWISTED_PAIR": {
        "variant": "TWISTED_BABY",
        "damage_factor": 0.375,
        "count": 2,
        "volley": 2,
    },
}

for name, variant, blocks, distance in (
    ("DISTANT_ADMIRATION", "DISTANT_ADMIRATION", False, 100),
    ("FOREVER_ALONE", "FOREVER_ALONE", False, 160),
    ("FRIEND_ZONE", "FRIEND_ZONE", False, 100),
    ("BIG_FAN", "BIG_FAN", True, 100),
    ("SACRIFICIAL_DAGGER", "SACRIFICIAL_DAGGER", True, 100),
    ("GUARDIAN_ANGEL", "GUARDIAN_ANGEL", True, 100),
    ("CUBE_OF_MEAT", "CUBE_OF_MEAT_1", True, 100),
    ("BALL_OF_BANDAGES", "BALL_OF_BANDAGES_1", True, 100),
    ("GUILLOTINE", "GUILLOTINE", True, 100),
    ("MOMS_RAZOR", "MOMS_RAZOR", False, 100),
):
    FAMILIAR_EFFECTS["COLLECTIBLE_" + name] = {
        "variant": variant,
        "contact": True,
        "orbital": True,
        "blocks": blocks,
        "distance": distance,
    }

for name, variant in (
    ("PEEPER", "PEEPER"),
    ("LEECH", "LEECH"),
    ("LIL_HAUNT", "LIL_HAUNT"),
    ("GEMINI", "GEMINI"),
    ("BLUE_BABYS_ONLY_FRIEND", "BLUEBABYS_ONLY_FRIEND"),
    ("SAMSONS_CHAINS", "SAMSONS_CHAINS"),
    ("LOST_FLY", "LOST_FLY"),
    ("OBSESSED_FAN", "OBSESSED_FAN"),
    ("SHADE", "SHADE"),
    ("POINTY_RIB", "POINTY_RIB"),
    ("GUPPYS_HAIRBALL", "GUPPYS_HAIRBALL"),
    ("HUSHY", "HUSHY"),
):
    FAMILIAR_EFFECTS["COLLECTIBLE_" + name] = {
        "variant": variant,
        "contact": True,
        "independent_motion": True,
    }

for name, variant, pickup, subtype in (
    ("SACK_OF_PENNIES", "SACK_OF_PENNIES", 20, None),
    ("LITTLE_CHAD", "LITTLE_CHAD", 10, 2),
    ("RELIC", "RELIC", 10, 3),
    ("BOMB_BAG", "BOMB_BAG", 40, None),
    ("MYSTERY_SACK", "MYSTERY_SACK", None, None),
    ("RUNE_BAG", "RUNE_BAG", 300, None),
    ("SACK_OF_SACKS", "SACK_OF_SACKS", 69, None),
    ("LIL_CHEST", "LIL_CHEST", None, None),
):
    FAMILIAR_EFFECTS["COLLECTIBLE_" + name] = {
        "variant": variant,
        "provider": {"pickup": pickup, "subtype": subtype},
        "timeline_scale": 3,
    }

FAMILIAR_EFFECTS["COLLECTIBLE_BLUE_BABYS_ONLY_FRIEND"]["controlled"] = True
FAMILIAR_EFFECTS["COLLECTIBLE_MOMS_RAZOR"]["damage_over_time"] = True
FAMILIAR_EFFECTS["COLLECTIBLE_LIL_HAUNT"].update({"idle_without_targets": True, "fear": True})
FAMILIAR_EFFECTS["COLLECTIBLE_ABEL"]["aims_at_player"] = True

for name, variant in (
    ("LITTLE_CHUBBY", "LITTLE_CHUBBY"),
    ("BIG_CHUBBY", "BIG_CHUBBY"),
    ("ANGRY_FLY", "ANGRY_FLY"),
):
    FAMILIAR_EFFECTS["COLLECTIBLE_" + name] = {
        "variant": variant,
        "contact": True,
        "independent_motion": True,
        "contact_shoot": name != "ANGRY_FLY",
        "blocks": name == "BIG_CHUBBY",
    }
FAMILIAR_EFFECTS["COLLECTIBLE_SWORN_PROTECTOR"] = {
    "variant": "SWORN_PROTECTOR",
    "contact": True,
    "orbital": True,
    "blocks": True,
    "distance": 100,
}
FAMILIAR_EFFECTS["COLLECTIBLE_HALO_OF_FLIES"] = {
    "variant": "FLY_ORBITAL",
    "contact": True,
    "orbital": True,
    "blocks": True,
    "block_only": True,
    "count": 2,
    "distance": 100,
}
FAMILIAR_EFFECTS["COLLECTIBLE_BLOODSHOT_EYE"] = {
    "variant": "BLOODSHOT_EYE",
    "damage": 3.5,
    "automatic": True,
    "orbital": True,
    "distance": 100,
}


def familiar_checks(case, observations):
    rules = FAMILIAR_EFFECTS.get(case.get("enum"))
    if not rules:
        return []
    host = observations.get("host", [])
    probes = [e for e in host if e["event"] == "familiar_probe"]
    checks = []
    timeline_scale = rules.get("timeline_scale", 1)

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
        return [e for e in probes if low * timeline_scale <= e["tick"] <= high * timeline_scale]

    for name, low, high, count in (
        ("acquired", 80, 140, 1),
        ("room", 350, 380, 1),
        ("floor", 600, 620, 1),
        (
            "trinket_dropped_clot_remains" if rules.get("persists_after_drop") else "removed",
            870 if rules.get("physical_remove") else 810,
            890 if rules.get("physical_remove") else 840,
            0,
        ),
    ):
        values = window(low, high)
        check(
            name,
            [
                e.get("owned") == count
                and e.get("teammate_owned") == 0
                and len(e.get("familiars", []))
                == (1 if rules.get("modifier") or rules.get("persists_after_drop") else count)
                * rules.get("count", 1)
                and all(f.get("controller") == case["slot"] + 1 for f in e["familiars"])
                for e in values
            ],
        )
    initial, moved = window(80, 90), window(130, 140)
    if rules.get("drop_window"):
        # Normal following precedes the intentional hold-position interval.
        moved = window(110, 119)
    if rules.get("persists_after_drop"):
        collisions = [e for e in host if e["event"] == "familiar_drop_collision"]
        check("dropped_clot_takes_three_projectile_hits", [len(collisions) == 3])
        check("dropped_clot_dies", [not e["familiars"] for e in window(1080, 1110)])
    if rules.get("remove_room_tick"):
        boundary = rules["remove_room_tick"]
        check(
            "removed_after_room_transition",
            [e["owned"] == 0 and not e["familiars"] for e in window(boundary + 60, boundary + 90)],
        )
    if rules.get("fixed_offset"):
        positions = [
            (e["familiars"][0]["x"] - e["x"], e["familiars"][0]["y"] - e["y"])
            for e in window(95, 138)
            if e["familiars"]
        ]
        check(
            "fixed_offset_while_owner_moves",
            [
                len(positions) >= 3
                and max(hypot(x - positions[0][0], y - positions[0][1]) for x, y in positions) < 3
            ],
        )
    if rules.get("native_orbit"):
        positions = [
            (e["familiars"][0]["x"] - e["x"], e["familiars"][0]["y"] - e["y"])
            for e in window(80, 140)
            if e["familiars"]
        ]
        check(
            "familiar_actually_orbits_owner",
            [
                len(positions) >= 3
                and max(x for x, y in positions) - min(x for x, y in positions) > 20
                and max(y for x, y in positions) - min(y for x, y in positions) > 20
            ],
        )
    if rules.get("drop_window"):
        held = window(124, 137)
        check(
            "drop_holds_familiar_while_owner_moves",
            [
                len(held) >= 3
                and all(len(e["familiars"]) == 1 for e in held)
                and held[-1]["x"] - held[0]["x"] > 10
                and max(
                    hypot(
                        e["familiars"][0]["x"] - held[0]["familiars"][0]["x"],
                        e["familiars"][0]["y"] - held[0]["familiars"][0]["y"],
                    )
                    for e in held
                )
                < 3
            ],
        )
    expected_familiars = rules.get("count", 1)
    check(
        "independent_motion" if rules.get("independent_motion") else "follows_owner",
        [
            moved[-1]["x"] - initial[0]["x"] > 20
            and len(initial[0]["familiars"]) == len(moved[-1]["familiars"]) == expected_familiars
            and (
                hypot(
                    moved[-1]["familiars"][0]["x"] - initial[0]["familiars"][0]["x"],
                    moved[-1]["familiars"][0]["y"] - initial[0]["familiars"][0]["y"],
                )
                > 5
                or rules.get("idle_without_targets", False)
                if rules.get("independent_motion")
                else rules.get("orbital")
                or moved[-1]["familiars"][0]["x"] - initial[0]["familiars"][0]["x"] > 15
            )
            and (
                rules.get("independent_motion")
                or hypot(
                    moved[-1]["familiars"][0]["x"] - moved[-1]["x"],
                    moved[-1]["familiars"][0]["y"] - moved[-1]["y"],
                )
                < rules.get("distance", 90)
            )
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
    if rules.get("fear"):
        hits = [e for e in host if e["event"] == "familiar_hit"]
        check("contact_fear", [any(e.get("fear") for e in hits)] if hits else [])
    for phase, low, high in (("initial", 165, 260), ("floor", 645, 740)):
        frames = window(low, high)
        if rules.get("provider"):
            clear_events = [
                e
                for e in host
                if e["event"] == "familiar_clear"
                and (low - 15) * timeline_scale <= e["tick"] <= (high + 10) * timeline_scale
            ]
            drops = [
                e
                for e in host
                if e["event"] == "familiar_drop"
                and (low - 15) * timeline_scale <= e["tick"] <= (high + 10) * timeline_scale
            ]
            check(phase + "_native_clears", [len(clear_events) >= 8])
            reward = rules["provider"]
            check(
                phase + "_clear_rewards",
                [
                    e["controller"] == case["slot"] + 1
                    and (reward["pickup"] is None or e["variant"] == reward["pickup"])
                    and (reward["subtype"] is None or e["subtype"] == reward["subtype"])
                    for e in drops
                ],
            )
            replica_drops = {
                e["seed"]: e
                for e in observations.get("client", [])
                if e["event"] == "familiar_drop"
            }
            check(
                phase + "_peer_rewards",
                [
                    e["seed"] in replica_drops
                    and all(
                        e[f] == replica_drops[e["seed"]][f]
                        for f in ("variant", "subtype", "controller")
                    )
                    for e in drops
                ],
            )
            continue
        if rules.get("contact"):
            all_hits = [e for e in host if e["event"] == "familiar_hit"]
            hits = [
                e
                for e in host
                if e["event"] == "familiar_hit" and low - 15 <= e["tick"] <= high + 10
            ]

            def damage_matches(hit):
                direct = sum(
                    other["amount"]
                    for other in all_hits
                    if other.get("seed") == hit.get("seed")
                    and hit["tick"] <= other["tick"] < hit.get("after_tick", hit["tick"] + 1)
                )
                loss = hit["before"] - hit["after"]
                if rules.get("damage_over_time"):
                    return hit.get("bleeding") is True and loss >= direct - 0.001
                return abs(loss - direct) < 0.001

            if not rules.get("block_only"):
                check(
                    phase + "_contact_damage",
                    [
                        e["amount"] > 0
                        and damage_matches(e)
                        and e["controller"] == case["slot"] + 1
                        for e in hits
                    ],
                )
            if rules.get("blocks"):
                blocks = [
                    e
                    for e in host
                    if e["event"] == "familiar_block" and low - 15 <= e["tick"] <= high + 10
                ]
                check(
                    phase + "_blocks_projectiles",
                    [any(e["removed"] and e["familiar_collision"] for e in blocks)]
                    if blocks
                    else [],
                )
            continue
        shots = {}
        for e in frames:
            for shot in e.get("shots", []):
                # The host's separate room is not serialized for the client,
                # so its native tears do not need network entity identities.
                shots.setdefault(shot.get("seed", shot["id"]), (e, shot))
        expected = rules.get("damage", 3.5 * rules.get("damage_factor", 1))
        low_damage, high_damage = rules.get("damage_range", (expected, expected))
        check(
            phase + "_shot_damage",
            [
                (
                    s["damage"] > 0
                    if rules.get("variable_damage")
                    else low_damage - 0.001 <= s["damage"] <= high_damage + 0.001
                )
                and s["controller"] == case["slot"] + 1
                and (not rules.get("spectral") or s.get("spectral") is True)
                and all(s.get("flags", {}).get(flag) is True for flag in rules.get("flags", []))
                for _, s in shots.values()
            ],
        )
        volleys = defaultdict(list)
        for e, s in shots.values():
            volleys[s["source_age"] - s["age"]].append(s)
        full = [v for v in volleys.values() if len(v) == rules.get("volley", 1)]
        check(phase + "_volley", [len(full) >= rules.get("minimum_volleys", 3)])
        if rules.get("observe_flags"):
            fingerprints = {
                (s.get("variant"), tuple(sorted(k for k, v in s.get("flags", {}).items() if v)))
                for _, s in shots.values()
            }
            check(phase + "_random_effects", [len(fingerprints) >= 2])
        times = sorted(volleys)
        intervals = [b - a for a, b in zip(times, times[1:])]
        if "interval" in rules:
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
                (
                    e["amount"] > 0
                    if rules.get("variable_damage")
                    else low_damage * e.get("hits", 1) - 0.001
                    <= e["amount"]
                    <= high_damage * e.get("hits", 1) + 0.001
                )
                and abs(e["before"] - e["after"] - e["amount"]) < 0.001
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
    if not rules.get("contact") and not rules.get("provider"):
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
            and all(k > 0 for k in left)
            and all(
                abs(s["damage"] - right[k]["damage"]) < 0.001
                and s["controller"] == right[k]["controller"]
                for k, s in left.items()
            )
        )
    check("peer_shots", compare)
    return checks
