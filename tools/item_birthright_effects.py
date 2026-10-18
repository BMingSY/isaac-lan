"""Character-specific Birthright acceptance, using native character starts."""

from item_interaction_effects import RECALL_SEPARATION_MIN_DISTANCE

BIRTHRIGHT_SCENARIOS = {
    "isaac": {"character_before": "PLAYER_ISAAC", "generated_pedestals": True, "pedestal_cycle": 2},
    "magdalene": {
        "character_before": "PLAYER_MAGDALENE",
        "birthright_trial": {"mode": "heart_limit", "limit": 36},
    },
    "cain": {
        "character_before": "PLAYER_CAIN",
        "stats": {"luck": 1},
        "floor_visit": {"room": "ROOM_ARCADE"},
        "birthright_trial": {"mode": "arcade"},
        "end_tick": 660,
    },
    "judas": {
        "character_before": "PLAYER_JUDAS",
        "active_before": "COLLECTIBLE_D6",
        "input_schedule": [[90, 96, "active"]],
        "stats": {"damage": 1},
        "birthright_trial": {"mode": "belial"},
    },
    "blue_baby": {
        "character_before": "PLAYER_BLUEBABY",
        "birthright_trial": {"mode": "soul_upgrade"},
    },
    "eve": {"character_before": "PLAYER_EVE", "birthright_trial": {"mode": "eve"}},
    "samson": {
        "character_before": "PLAYER_SAMSON",
        "birthright_trial": {"mode": "bloodlust"},
        "end_tick": 420,
    },
    "azazel": {
        "character_before": "PLAYER_AZAZEL",
        "birthright_trial": {"mode": "beam"},
        "button_intervals": [[90, 135, "ACTION_SHOOTUP"], [270, 315, "ACTION_SHOOTUP"]],
        "end_tick": 390,
    },
    "lazarus": {
        "character_before": "PLAYER_LAZARUS",
        "revive": True,
        "revive_natural_damage": True,
        "revive_type": "PLAYER_LAZARUS2",
        "revive_hearts": 2,
        "remaining_lives": 0,
        "birthright_trial": {"mode": "revive_damage"},
        "end_tick": 900,
    },
    "eden": {"character_before": "PLAYER_EDEN", "birthright_trial": {"mode": "eden_choice"}},
    "lost": {"character_before": "PLAYER_THELOST", "birthright_trial": {"mode": "lost_pool"}},
    "lilith": {
        "character_before": "PLAYER_LILITH",
        "prerequisite_items": ["COLLECTIBLE_BROTHER_BOBBY"],
        "button_intervals": [[90, 150, "ACTION_SHOOTUP"], [180, 240, "ACTION_SHOOTRIGHT"]],
        "birthright_trial": {"mode": "front_familiars"},
    },
    "keeper": {
        "character_before": "PLAYER_KEEPER",
        "birthright_trial": {"mode": "heart_limit", "limit": 8},
    },
    "bethany": {
        "character_before": "PLAYER_BETHANY",
        "active_before": "COLLECTIBLE_BOOK_OF_SHADOWS",
        "input_schedule": [[90 + i * 45, 96 + i * 45, "active"] for i in range(32)],
        "birthright_trial": {"mode": "soul_charges", "count": 32},
        "end_tick": 1560,
    },
    "jacob": {"character_before": "PLAYER_JACOB", "birthright_trial": {"mode": "twin_items"}},
    "esau": {
        "character_before": "PLAYER_JACOB",
        "birthright_twin": True,
        "birthright_trial": {"mode": "twin_items"},
    },
    "tainted_magdalene": {
        "character_before": "PLAYER_MAGDALENE_B",
        "birthright_trial": {"mode": "permanent_heart"},
        "end_tick": 900,
    },
    "tainted_cain": {
        "character_before": "PLAYER_CAIN_B",
        "birthright_trial": {"mode": "salvage"},
        "end_tick": 390,
    },
    "tainted_blue_baby": {
        "character_before": "PLAYER_BLUEBABY_B",
        "birthright_trial": {"mode": "poop_capacity"},
    },
    "tainted_eden": {
        "character_before": "PLAYER_EDEN_B",
        "birthright_trial": {"mode": "protected_items"},
        "end_tick": 600,
    },
    "tainted_lost": {
        "character_before": "PLAYER_THELOST_B",
        "revive": True,
        "revive_natural_damage": True,
        "revive_type": "PLAYER_THELOST_B",
        "revive_hearts": 0,
        "enemies": 1,
        "enemy_damage": 200,
        "end_tick": 450,
    },
    "tainted_bethany": {
        "character_before": "PLAYER_BETHANY_B",
        "birthright_trial": {"mode": "quality_wisps"},
    },
    "tainted_jacob": {
        "character_before": "PLAYER_JACOB_B",
        "birthright_trial": {"mode": "double_esau"},
        "input_schedule": [[90, 96, "card"], [360, 366, "card"]],
        "end_tick": 600,
    },
}
BIRTHRIGHT_SCENARIOS.update(
    {
        "apollyon": {
            "character_before": "PLAYER_APOLLYON",
            "active_before": "COLLECTIBLE_VOID",
            "birthright_trial": {"mode": "void", "attempts": 64},
            "rng_seed": 1,
            "input_schedule": [[90, 96, "active"]]
            + [[210 + i * 60, 216 + i * 60, "active"] for i in range(64)],
            "end_tick": 4110,
        },
        "forgotten": {
            "character_before": "PLAYER_THEFORGOTTEN",
            "birthright_trial": {"mode": "chain"},
            "input_schedule": [[90, 93, "drop"]],
            "button_intervals": [[120, 200, "ACTION_RIGHT"], [270, 350, "ACTION_RIGHT"]],
            "end_tick": 390,
        },
        "tainted_isaac": {
            "character_before": "PLAYER_ISAAC_B",
            "birthright_trial": {"mode": "inventory_slots"},
            "end_tick": 1020,
        },
        "tainted_judas": {
            "character_before": "PLAYER_JUDAS_B",
            "birthright_trial": {"mode": "dark_arts_range"},
            "input_schedule": [[120, 126, "card"], [360, 366, "card"]],
            "end_tick": 480,
        },
        "tainted_eve": {
            "character_before": "PLAYER_EVE_B",
            "birthright_trial": {"mode": "clot_hearts"},
            "button_intervals": [[90, 270, "ACTION_SHOOTUP"]],
            "end_tick": 450,
        },
        "tainted_samson": {
            "character_before": "PLAYER_SAMSON_B",
            "birthright_trial": {"mode": "berserk_duration"},
            "button_intervals": [
                [150, 180, "ACTION_SHOOTUP"],
                [240, 270, "ACTION_SHOOTUP"],
                [720, 750, "ACTION_SHOOTUP"],
                [810, 840, "ACTION_SHOOTUP"],
            ],
            "end_tick": 1050,
        },
        "tainted_azazel": {
            "character_before": "PLAYER_AZAZEL_B",
            "birthright_trial": {"mode": "sneeze_range"},
            "button_intervals": [
                [120, 122, "ACTION_SHOOTUP"],
                [123, 129, "ACTION_SHOOTUP"],
                [360, 362, "ACTION_SHOOTUP"],
                [363, 369, "ACTION_SHOOTUP"],
            ],
            "end_tick": 480,
        },
        "tainted_lazarus": {
            "character_before": "PLAYER_LAZARUS_B",
            "birthright_trial": {"mode": "lazarus_ghost"},
            "enemies": 1,
            "hit_target": True,
            "target_hp": 10000,
            "button_intervals": [[90, 150, "ACTION_SHOOTUP"], [210, 270, "ACTION_SHOOTUP"]],
            "input_schedule": [[180, 186, "card"]],
            "end_tick": 900,
        },
        "tainted_lilith": {
            "character_before": "PLAYER_LILITH_B",
            "prerequisite_items": ["COLLECTIBLE_BROTHER_BOBBY"],
            "birthright_trial": {"mode": "gello"},
            "enemies": 1,
            "hit_target": True,
            "target_distance": 75,
            "target_hp": 10000,
            "button_intervals": [[90, 150, "ACTION_SHOOTUP"], [240, 300, "ACTION_SHOOTUP"]],
            "end_tick": 360,
        },
        "tainted_keeper": {
            "character_before": "PLAYER_KEEPER_B",
            "birthright_trial": {"mode": "enemy_coins"},
            "end_tick": 450,
        },
        "tainted_apollyon": {
            "character_before": "PLAYER_APOLLYON_B",
            "active_before": "COLLECTIBLE_ABYSS",
            "birthright_trial": {"mode": "abyss_attack"},
            "input_schedule": [[90, 96, "active"]],
            "button_intervals": [[180, 330, "ACTION_SHOOTUP"], [420, 570, "ACTION_SHOOTUP"]],
            "end_tick": 630,
        },
        "tainted_forgotten": {
            "character_before": "PLAYER_THEFORGOTTEN_B",
            "birthright_trial": {"mode": "recall"},
            "input_schedule": [[240, 246, "card"]],
            "end_tick": 420,
        },
    }
)

for scenario in BIRTHRIGHT_SCENARIOS.values():
    scenario.setdefault("end_tick", 330)
    scenario["observe_until"] = scenario["end_tick"] - 3


def birthright_checks(rules, observations, probes, check):
    trial = rules.get("birthright_trial")
    if not trial:
        return
    events = observations.get("host", [])
    values = [e for e in events if e["event"] == "birthright_state"]
    before = next((e for e in values if e["phase"] == "before"), None)
    after = [e for e in values if e["phase"] == "held"]
    check(
        "birthright_native_holder_observed",
        [before is not None, bool(after), all(e["owned"] for e in after)],
    )
    mode = trial["mode"]
    if mode == "heart_limit":
        check(
            "birthright_expands_character_heart_limit",
            [
                before is not None and before["limit"] < trial["limit"],
                any(e["limit"] == trial["limit"] for e in after),
            ],
        )
    elif mode == "belial":
        check(
            "birthright_belial_becomes_passive",
            [any(e.get("passive_belial") and e["active"] == 105 for e in after)],
        )
    elif mode == "arcade":
        check(
            "birthright_native_upgraded_arcade",
            [any(e["room_type"] == 9 and e["slots"] >= 3 for e in after)],
        )
    elif mode == "soul_upgrade":
        upgrades = [e for e in events if e["event"] == "birthright_health_upgrade"]
        check(
            "blue_baby_health_upgrade_doubles_soul_hearts",
            [len(upgrades) == 1 and upgrades[0]["after"] - upgrades[0]["before"] == 4],
        )
    elif mode == "eve":
        check(
            "eve_babylon_and_dead_bird_at_full_health",
            [any(e["hearts"] > 2 and e["babylon"] > 0 and e["birds"] > 0 for e in after)],
        )
    elif mode == "bloodlust":
        hits = [e for e in events if e["event"] == "birthright_bloodlust_hit"]
        check(
            "samson_ten_native_hits", [len(hits) == 10, all(e["after"] < e["before"] for e in hits)]
        )
        check(
            "samson_extended_bloody_lust",
            [before is not None and any(e["damage"] >= before["damage"] + 13.9 for e in after)],
        )
    elif mode == "beam":
        beams = [e for e in events if e["event"] == "birthright_beam"]
        control = [e["size"] for e in beams if not e["owned"]]
        held = [e["size"] for e in beams if e["owned"]]
        check(
            "azazel_native_beam_becomes_wider",
            [bool(control), bool(held), bool(control and held) and max(held) > max(control) * 1.5],
        )
    elif mode == "revive_damage":
        alive = [e for e in after if not e["dead"] and e["tick"] >= 300]
        check(
            "lazarus_native_revival_damage_decays",
            [
                before is not None
                and bool(alive)
                and max(e["damage"] for e in alive) > before["damage"] + 6
                and alive[-1]["damage"] < max(e["damage"] for e in alive)
            ],
        )
    elif mode == "eden_choice":
        choices = [e for e in events if e["event"] == "birthright_eden_choice"]
        check(
            "eden_three_items_one_choice",
            [
                len(choices) == 1
                and choices[0]["options"] == 3
                and choices[0]["acquired"]
                and choices[0]["remaining"] == 0
            ],
        )
    elif mode == "lost_pool":
        pools = [e for e in events if e["event"] == "birthright_lost_pool"]
        control = next((e for e in pools if not e["owned"]), None)
        held = next((e for e in pools if e["owned"]), None)
        check(
            "lost_rejects_health_only_items",
            [bool(control and held) and control["useless"] > 0 and held["useless"] == 0],
        )
    elif mode == "front_familiars":
        facing = [e for e in events if e["event"] == "birthright_front_familiars"]
        for direction in ("up", "right"):
            check(
                "lilith_familiars_in_front:" + direction,
                [
                    any(
                        e["direction"] == direction and e["count"] >= 2 and e["front"] == e["count"]
                        for e in facing
                    )
                ],
            )
    elif mode == "soul_charges":
        uses = [e for e in events if e["event"] == "birthright_soul_charge_use"]
        check(
            "bethany_native_soul_charge_uses",
            [len(uses) == trial["count"], all(e["used"] for e in uses)],
        )
        check(
            "bethany_sometimes_uses_soul_charges_free",
            [any(e["spent"] == 0 for e in uses), any(e["spent"] > 0 for e in uses)],
        )
    elif mode == "twin_items":
        copied = [e for e in events if e["event"] == "birthright_copied_items"]
        check(
            "jacob_esau_copies_three_other_twin_items",
            [len(copied) == 1 and copied[0]["before"] == 0 and copied[0]["after"] == 3],
        )
    elif mode == "permanent_heart":
        check(
            "tainted_magdalene_extra_permanent_heart",
            [
                before is not None
                and any(e["max_hearts"] >= before["max_hearts"] + 2 for e in after),
                any(e["tick"] >= 870 and e["hearts"] >= 6 for e in after),
            ],
        )
    elif mode == "poop_capacity":
        check("tainted_blue_baby_holds_29_poop", [any(e["poop"] == 29 for e in after)])
    elif mode == "salvage":
        salvages = [e for e in events if e["event"] == "birthright_salvage"]
        control = next((e for e in salvages if not e["owned"]), None)
        held = next((e for e in salvages if e["owned"]), None)
        check(
            "tainted_cain_increases_native_pickup_salvage",
            [
                bool(control and held)
                and control["consumed"]
                and held["consumed"]
                and control["drops"] > 0
                and held["drops"] > control["drops"]
            ],
        )
    elif mode == "protected_items":
        rerolls = [e for e in events if e["event"] == "birthright_protected_inventory"]
        check(
            "tainted_eden_rerolls_new_items_preserving_old",
            [
                bool(rerolls),
                all(e["preserved"] for e in rerolls),
                any(e["rerolled"] for e in rerolls),
            ],
        )
    elif mode == "quality_wisps":
        wisps = [w for e in after for w in e["wisps"]]
        check(
            "tainted_bethany_four_quality_wisps",
            [
                any(len(e["wisps"]) == 4 for e in after),
                bool(wisps) and all(w["quality"] >= 3 and w["health"] > 8 for w in wisps),
            ],
        )
    elif mode == "double_esau":
        check("tainted_jacob_two_dark_esaus", [any(e["esaus"] == 2 for e in after)])
        check(
            "tainted_jacob_anima_chains_both",
            [any(e["tick"] > 180 and e["chained_esaus"] == 2 for e in after)],
        )
    elif mode == "void":
        absorbed = [e for e in events if e["event"] == "birthright_void_absorbed"]
        returned = [e for e in events if e["event"] == "birthright_void_returned"]
        uses = [e for e in events if e["event"] == "birthright_void_use" and e["tick"] >= 210]
        check(
            "apollyon_void_actually_used",
            [len(uses) >= trial["attempts"], all(e["correct_actor"] for e in uses)],
        )
        check(
            "apollyon_void_absorbs_native_pedestals",
            [len(absorbed) == 1 and absorbed[0]["pickups"] == 0],
        )
        check(
            "apollyon_void_returns_absorbed_items",
            [
                len(returned) == trial["attempts"],
                any(e["items"] for e in returned),
                all(set(e["items"]) <= {25, 50, 1, 32, 7, 14} for e in returned),
                bool(absorbed)
                and all(
                    e["damage"] >= absorbed[0]["damage"]
                    and e["speed"] >= absorbed[0]["speed"]
                    and e["delay"] <= absorbed[0]["delay"]
                    for e in returned
                ),
            ],
        )
    elif mode == "chain":
        values = [e for e in events if e["event"] == "birthright_soul_chain"]
        control = next((e for e in values if not e["owned"]), None)
        held = next((e for e in values if e["owned"]), None)
        check(
            "forgotten_soul_moves_beyond_native_tether",
            [
                bool(control and held)
                and control["found"]
                and held["found"]
                and control["distance"] > 50
                and held["distance"] > control["distance"] + 60
            ],
        )
    elif mode == "inventory_slots":
        pickups = [e for e in events if e["event"] == "birthright_inventory_capacity"]
        check(
            "tainted_isaac_twelve_native_inventory_slots",
            [
                len(pickups) == 5,
                all(
                    (e["consumed"] if e["index"] <= 12 else e.get("replaced", False))
                    and e["new_item"]
                    and e["owned"] == min(e["index"], 12)
                    for e in pickups
                ),
            ],
        )
    elif mode in ("dark_arts_range", "sneeze_range"):
        values = [e for e in events if e["event"] == "birthright_native_ability_range"]
        control = next((e for e in values if not e["owned"]), None)
        held = next((e for e in values if e["owned"]), None)
        if mode == "sneeze_range":
            control_targets = {e["distance"]: e for e in (control or {}).get("targets", [])}
            held_targets = {e["distance"]: e for e in (held or {}).get("targets", [])}
            check(
                "birthright_extends_native_ability_range",
                [
                    bool(control_targets) and control_targets.keys() == held_targets.keys(),
                    any(e["damage"] > 0 and e["marked"] for e in control_targets.values()),
                    any(
                        not e["marked"]
                        and held_targets.get(distance, {}).get("damage", 0) > e["damage"]
                        and held_targets[distance]["marked"]
                        for distance, e in control_targets.items()
                    ),
                ],
            )
            check(
                "tainted_azazel_sneeze_marks_enemy",
                [any(e["marked"] for e in held_targets.values())],
            )
            return
        check(
            "birthright_extends_native_ability_range",
            [
                bool(control and held)
                and control["damage"] == 0
                and not control["marked"]
                and held["damage"] > 0
            ],
        )
    elif mode == "clot_hearts":
        drops = [e for e in events if e["event"] == "birthright_clot_hearts"]
        initial = next((e for e in drops if e["tick"] == 330), None)
        expired = next((e for e in drops if e["tick"] == 405), None)
        check(
            "tainted_eve_dead_clots_drop_temporary_half_hearts",
            [
                bool(initial and expired)
                and initial["clots"] > 0
                and len(initial["hearts"]) > 0
                and len(expired["hearts"]) == 0,
                bool(initial)
                and all(h["subtype"] == 2 and 0 < h["timeout"] <= 90 for h in initial["hearts"]),
            ],
        )
    elif mode == "berserk_duration":
        timers = [e for e in events if e["event"] == "birthright_berserk_timer"]
        durations = []
        for owned in (False, True):
            phase = [
                e for e in timers if e["owned"] == owned and e["tick"] >= (630 if owned else 60)
            ]
            active = [e["tick"] for e in phase if e["active"]]
            ended = bool(active) and any(not e["active"] and e["tick"] > max(active) for e in phase)
            check("tainted_samson_native_berserk_ends:" + str(owned), [bool(active), ended])
            durations.append(max(active) - min(active) if active else 0)
        kills = [e for e in events if e["event"] == "birthright_berserk_kill"]
        ready = [e for e in events if e["event"] == "birthright_berserk_kill_prerequisite"]
        check(
            "tainted_samson_extra_berserk_time_per_kill",
            [
                len(kills) == 2 and all(e["killed"] for e in kills),
                len(ready) == 2 and all(e["active"] for e in ready),
                durations[1] >= durations[0] + 57,
            ],
        )
    elif mode == "lazarus_ghost":
        pairs = [e for e in events if e["event"] == "birthright_lazarus_pair"]
        check(
            "tainted_lazarus_visible_invulnerable_other_form",
            [
                len(pairs) == 4,
                all(e["found"] and e["other_visible"] and e["before"] == e["after"] for e in pairs),
            ],
        )
        check(
            "tainted_lazarus_flip_room_and_floor",
            [
                len(pairs) == 4
                and pairs[0]["player_type"] != pairs[1]["player_type"]
                and pairs[1]["room"] != pairs[2]["room"]
                and pairs[2]["stage"] != pairs[3]["stage"]
            ],
        )
        hits = [e for e in events if e["event"] == "birthright_lazarus_damage"]
        real = [e["amount"] for e in hits if not e["ghost"]]
        ghosts = [e["amount"] for e in hits if e["ghost"]]
        check(
            "tainted_lazarus_ghost_deals_quarter_damage",
            [
                bool(real),
                bool(ghosts),
                bool(real and ghosts) and any(abs(g * 4 - r) < 0.01 for g in ghosts for r in real),
            ],
        )
    elif mode == "gello":
        followers = [e for e in events if e["event"] == "birthright_gello_follower"]
        held = next((e for e in followers if e["owned"]), None)
        check(
            "tainted_lilith_familiar_follows_gello",
            [bool(held) and held["found"] and held["gello_distance"] < held["player_distance"]],
        )
        hits = [
            e
            for e in events
            if e["event"] == "birthright_gello_damage"
            # Native Gello contact reports the player as its source. Tears from
            # Gello/Brother Bobby are separate hits and cannot prove this bonus.
            and e.get("source_type") == 1
            and e["amount"] > e.get("player_damage", 3.5)
        ]
        control_damage = [e["amount"] for e in hits if not e["owned"]]
        held_damage = [e["amount"] for e in hits if e["owned"]]
        check(
            "tainted_lilith_gello_gains_familiar_damage",
            [
                bool(control_damage and held_damage)
                and max(held_damage) >= max(control_damage) + 2.9
            ],
        )
    elif mode == "enemy_coins":
        coins = [e for e in events if e["event"] == "birthright_keeper_coins"]
        control = next((e for e in coins if not e["owned"]), None)
        held = next((e for e in coins if e["owned"]), None)
        check(
            "tainted_keeper_attracts_native_enemy_coins",
            [
                bool(control and held)
                and control["killed"]
                and held["killed"]
                and control.get("emitted", 0) > 0
                and held.get("emitted", 0) > 0
                and control.get("staged", 0) > 0
                and held.get("staged", 0) > 0
                and control["gained"] == 0
                and held["gained"] > 0
            ],
        )
    elif mode == "abyss_attack":
        positions = [e for e in events if e["event"] == "birthright_locust_target"]
        runs = []
        for owned, first, last in ((False, 180, 330), (True, 420, 570)):
            phase = [e for e in positions if e["owned"] == owned and first <= e["tick"] <= last]
            streak = longest = 0
            for e in phase:
                streak = streak + 1 if e["distance"] < 35 else 0
                longest = max(longest, streak)
            runs.append(longest)
            check(
                "tainted_apollyon_native_locust_damage:" + str(owned),
                [bool(phase) and phase[-1]["damage"] > phase[0]["damage"]],
            )
        check("tainted_apollyon_locust_stays_on_target", [runs[0] > 0, runs[1] > runs[0] * 1.5])
    elif mode == "recall":
        recalls = [e for e in events if e["event"] == "birthright_native_recall"]
        check(
            "tainted_forgotten_native_pocket_recall",
            [
                len(recalls) == 2
                and all(
                    e["found"] and 714 in (e["primary_pocket"], e["other_pocket"]) for e in recalls
                )
                and recalls[0]["distance"] > RECALL_SEPARATION_MIN_DISTANCE
                and recalls[1]["distance"] < 50
            ],
        )
    else:
        raise ValueError("Birthright trial has no effect validator: " + mode)
