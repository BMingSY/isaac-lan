"""Native pickup consumption, pocket repetition and active-slot trials."""

INTERACTION_EFFECTS = {}
for name, mode, extra in (
    ("SKATOLE", "fly_contact", {}),
    ("BURSTING_SACK", "spider_contact", {}),
    ("SOCKS", "spike_contact", {}),
    ("HOST_HAT", "explosion", {}),
    ("LADDER", "pit_crossing", {}),
    ("HOW_TO_JUMP", "pit_crossing", {"use_tick": 300}),
):
    INTERACTION_EFFECTS["COLLECTIBLE_" + name] = {
        "world_collision_trial": mode,
        "button_intervals": [[90, 135, "ACTION_RIGHT"], [270, 360, "ACTION_RIGHT"]]
        if mode == "pit_crossing"
        else [],
        "observe_until": 417,
        "end_tick": 420,
        **extra,
    }
for name, variant, pickup, count in (
    ("BUM_FRIEND", "BUM_FRIEND", "PICKUP_COIN", 12),
    ("DARK_BUM", "DARK_BUM", "PICKUP_HEART", 8),
    ("KEY_BUM", "KEY_BUM", "PICKUP_KEY", 8),
    ("BUMBO", "BUMBO", "PICKUP_COIN", 45),
):
    INTERACTION_EFFECTS["COLLECTIBLE_" + name] = {
        "feed_familiar": {"variant": variant, "pickup": pickup, "count": count},
        "end_tick": 150 + count * 60,
        "observe_until": 150 + count * 60,
    }

INTERACTION_EFFECTS.update(
    {
        "COLLECTIBLE_THE_JAR": {
            "jar_hearts": True,
            "full_health_before": True,
            "use_tick": 270,
            "end_tick": 360,
            "observe_until": 360,
        },
        "COLLECTIBLE_ECHO_CHAMBER": {
            "echo_cards": True,
            "input_schedule": [[120, 126, "card"], [180, 186, "card"], [240, 246, "card"]],
            "end_tick": 300,
            "observe_until": 300,
        },
        "COLLECTIBLE_SCHOOLBAG": {
            "switch_actives": True,
            "input_schedule": [[120, 124, "drop"], [180, 186, "active"], [240, 244, "drop"]],
            "end_tick": 300,
            "observe_until": 300,
        },
        "COLLECTIBLE_SHARP_PLUG": {
            "empty_active": True,
            "full_health_before": True,
            "sharp_plug": True,
            "use_existing_active": True,
            "use_tick": 90,
            "end_tick": 210,
            "observe_until": 210,
        },
        "COLLECTIBLE_EVERYTHING_JAR": {
            "jar_charges": True,
            "use_tick": 90,
            "input_schedule": [[90 + n * 90, 96 + n * 90, "active"] for n in range(11)],
            "end_tick": 1110,
            "observe_until": 1110,
        },
        "COLLECTIBLE_MOVING_BOX": {
            "moving_box": True,
            "use_tick": 90,
            "input_schedule": [[90, 96, "active"], [330, 336, "active"]],
            "end_tick": 420,
            "observe_until": 420,
        },
    }
)

for name, mode, variant in (
    ("MITRE", "pickup", "PICKUP_HEART"),
    ("HUMBLEING_BUNDLE", "pickup", "PICKUP_COIN"),
    ("BOGO_BOMBS", "pickup", "PICKUP_BOMB"),
    ("SACK_HEAD", "chest", "PICKUP_CHEST"),
    ("MOMS_KEY", "chest", "PICKUP_CHEST"),
    ("GUPPYS_TAIL", "award", None),
    ("CONTRACT_FROM_BELOW", "award", None),
    ("GLYPH_OF_BALANCE", "award", None),
    ("OPTIONS", "award", None),
    ("ROSARY", "pool", None),
    ("MAGIC_8_BALL", "planetarium", None),
    ("CHAMPION_BELT", "champions", None),
):
    INTERACTION_EFFECTS["COLLECTIBLE_" + name] = {
        "generation_trial": {"mode": mode, "variant": variant},
        "observe_until": 297,
        "end_tick": 300,
    }
INTERACTION_EFFECTS["COLLECTIBLE_ROSARY"]["stats"] = {"soul": 1, "delay": -1}
INTERACTION_EFFECTS["COLLECTIBLE_MAGIC_8_BALL"].update(
    {"stats": {"shot_speed": 1}, "spawns": {"5.300.": [1, 1]}}
)


def interaction_checks(rules, observations, probes, check):
    events = observations.get("host", [])

    def named(name):
        return [e for e in events if e["event"] == name]

    if rules.get("deal_item_trial"):
        doors = named("native_deal_doors")
        check("native_devil_door_generated", [len(doors) == 1 and doors[0]["devil"]])
        entered = [e for e in probes if 630 <= e["tick"] <= 660]
        check(
            "native_devil_room_entered",
            [bool(entered), all(e["room_type"] == "ROOM_DEVIL" for e in entered)],
        )
        if rules["deal_item_trial"] == "duality":
            choices = named("duality_choice_result")
            check("duality_generates_both_deal_doors", [len(doors) == 1 and doors[0]["angel"]])
            check(
                "taking_devil_choice_removes_angel_door",
                [len(choices) == 1 and not choices[0]["angel"]],
            )
        elif rules["deal_item_trial"] == "redemption":
            initial = next((e for e in probes if e["tick"] == 570), None)
            late = [e for e in probes if e["tick"] >= 960]
            check(
                "unclaimed_devil_visit_rewards_next_floor",
                [
                    initial is not None
                    and any(
                        e["damage"] >= initial["damage"] + 0.99 and e["soul"] >= initial["soul"] + 2
                        for e in late
                    )
                ],
            )
        elif rules["deal_item_trial"] == "sanguine":
            hits = named("sanguine_native_spike_hit")
            check(
                "native_devil_spikes_damage_holder",
                [len(hits) == 12 and any(e["after"] < e["before"] for e in hits)],
            )
            initial = next((e for e in probes if e["tick"] == 627), None)
            late = [e for e in probes if e["tick"] >= 1320]
            check(
                "sanguine_sacrifices_produce_native_reward",
                [
                    initial is not None
                    and any(
                        e["damage"] > initial["damage"]
                        or e["coins"] > initial["coins"]
                        or e["soul"] > initial["soul"]
                        or e["pickup_count"] > initial["pickup_count"]
                        or len(e["pedestals"]) > len(initial["pedestals"])
                        for e in late
                    )
                ],
            )

    if rules.get("modem_projectiles_trial"):
        trials = named("modem_projectile_result")
        check(
            "stationary_projectile_control_survives",
            [len(trials) == 2 and trials[0]["removed"] == 0],
        )
        check(
            "broken_modem_removes_native_projectiles",
            [len(trials) == 2 and trials[1]["removed"] > 0],
        )

    if rules.get("betrayal_trial"):
        hits = named("betrayal_projectile_result")
        check(
            "enemy_projectile_control_does_not_hurt_other_enemy",
            [len(hits) == 2 and hits[0]["after"] == hits[0]["before"]],
        )
        check(
            "betrayal_enables_native_enemy_friendly_fire",
            [len(hits) == 2 and hits[1]["after"] < hits[1]["before"]],
        )
    if rules.get("puppy_feed_trial"):
        values = named("puppy_native_feeding")
        check(
            "blood_puppy_native_contact_kills",
            [bool(values) and max(e["killed"] for e in values) >= 40],
        )
        check("feeding_blood_puppy_produces_health", [any(e["hearts"] > 0 for e in values)])

    if rules.get("guppy_preview_trial"):
        opened = named("guppy_preview_opened")
        check("previewed_native_chest_opens", [len(opened) == 1 and opened[0]["opened"]])
    if rules.get("flip_pedestal_trial"):
        phases = named("flip_native_pedestal")
        check(
            "native_flip_restores_uncollected_side",
            [
                len(phases) == 3
                and bool(phases[0]["real"])
                and not phases[1]["real"]
                and bool(phases[2]["real"])
                and phases[2]["real"] != phases[0]["real"]
            ],
        )
        acquired = named("flip_pedestal_acquired")
        check(
            "both_flip_sides_can_be_collected",
            [
                len(acquired) == 1
                and len(acquired[0]["items"]) == 2
                and len({e["id"] for e in acquired[0]["items"]}) == 2
                and all(e["held"] for e in acquired[0]["items"])
            ],
        )

    if rules.get("d7_trial"):
        states = named("d7_combat_state")
        check(
            "native_d7_restarts_cleared_combat_room",
            [
                len(states) == 3
                and states[0]["alive"] > 0
                and states[1]["alive"] == 0
                and states[2]["alive"] > 0
                and len({e["room"] for e in states}) == 1
            ],
        )

    if rules.get("strawman_trial"):
        created, died = named("strawman_body_created"), named("strawman_body_death")
        check("strawman_creates_owned_keeper_body", [len(created) == 1 and created[0]["found"]])
        check(
            "keeper_death_removes_strawman_but_preserves_owner",
            [
                len(died) == 1
                and died[0]["alive"]
                and not died[0]["owned"]
                and died[0]["spiders"] > 0
            ],
        )
    if rules.get("recall_trial"):
        values = named("recall_body_distance")
        check(
            "native_recall_returns_distant_body",
            [
                len(values) == 2
                and all(e["found"] for e in values)
                and values[0]["distance"] > 100
                and values[1]["distance"] < 40
            ],
        )

    if rules.get("blanket_trial"):
        hits = named("blanket_damage_trial")
        check(
            "boss_entry_grants_one_damage_shield",
            [
                len(hits) == 2
                and hits[0]["room_type"] == 5
                and hits[0]["after"] == hits[0]["before"]
                and hits[1]["after"] == hits[1]["before"] - 1
            ],
        )
    if rules.get("mercurius_trial"):
        checks = named("mercurius_doors")
        check(
            "normal_doors_remain_open_during_native_combat",
            [
                len(checks) == 1
                and checks[0]["enemies"] > 0
                and checks[0]["open"] == checks[0]["total"]
                and checks[0]["total"] > 0
            ],
        )

    if rules.get("secret_map_trial"):
        targets = named("secret_neighbor_trial")
        secret = targets[0]["secret"] if targets else None
        initial = next((e for e in probes if e.get("label") == "before"), None)
        later = [e for e in probes if e["tick"] >= 240]
        check(
            "secret_room_unknown_before_hat",
            [
                initial is not None
                and any(r["index"] == secret and r["flags"] == 0 for r in initial["map"])
            ],
        )
        check(
            "hat_reveals_adjacent_secret_room",
            [any(any(r["index"] == secret and r["flags"] != 0 for r in e["map"]) for e in later)],
        )
    if rules.get("secret_sound_trial"):
        check(
            "native_howl_on_secret_neighbor_entry",
            [any(e["howl"] for e in named("secret_sound_probe") if e["tick"] >= 210)],
        )
    if rules.get("fairy_trial"):
        check(
            "fairy_indicates_native_tinted_rock",
            [
                any(
                    e["distance"] < 20 and e["owner_distance"] > 50
                    for e in named("fairy_target_probe")
                )
            ],
        )

    if rules.get("portal_pair_trial") or rules.get("portal_feed_trial"):
        travels = named("native_portal_entry")
        returned = named("native_portal_destination")
        check("native_portal_created_and_entered", [bool(travels)])
        if rules.get("portal_pair_trial"):
            origin = named("native_portal_origin")
            check(
                "ventricle_returns_to_original_room",
                [
                    bool(origin)
                    and bool(returned)
                    and returned[-1]["room"] == origin[0]["room"]
                    and returned[-1]["room"] != travels[-1]["room"]
                ],
            )
        else:
            check("lil_portal_enters_generated_room", [bool(returned) and returned[0]["room"] < 0])
    if rules.get("coin_chest_trial"):
        opened = named("coin_chest_result")
        check(
            "locked_chest_uses_coin_without_key",
            [
                len(opened) == 1
                and opened[0]["opened"]
                and opened[0]["keys"] == 0
                and opened[0]["coins"] == opened[0]["before_coins"] - 1
            ],
        )
    if rules.get("paid_stats_trial"):
        paid = named("shop_stat_purchase")
        later = [e for e in probes if e["tick"] >= 240]
        check(
            "native_shop_purchase_spends_coins",
            [bool(paid) and any(e["coins"] == paid[0]["coins"] - 15 for e in later)],
        )
        check(
            "paid_purchase_grants_keeper_stat_bonus",
            [
                bool(paid)
                and any(
                    any(e[k] > paid[0][k] + 0.001 for k in ("speed", "range", "damage"))
                    for e in later
                )
            ],
        )
    if rules.get("flesh_prices_trial"):
        later = [e for e in probes if e["tick"] >= 450]
        check(
            "native_shop_collectibles_cost_health",
            [any(p["price"] < 0 and p["price"] != -1000 for e in later for p in e["pedestals"])],
        )
        check(
            "native_shop_consumables_have_spike_price",
            [any(p["price"] == -5 for e in later for p in e["pickups"])],
        )

    if rules.get("world_collision_trial"):
        trials = named("world_collision_result")
        control = next((e for e in trials if e["control"]), None)
        effect = next((e for e in trials if not e["control"]), None)
        check("native_collision_control_and_item_trial", [control is not None, effect is not None])
        if control and effect:
            if rules["world_collision_trial"] == "pit_crossing":
                check("ordinary_movement_stops_at_pit", [control["x"] < control["obstacle_x"]])
                check("native_item_crosses_pit", [effect["x"] > effect["obstacle_x"] + 30])
            else:
                check(
                    "native_collision_control_damages_player",
                    [control["health"] < control["before_health"]],
                )
                check(
                    "item_prevents_native_collision_damage",
                    [effect["health"] == effect["before_health"]],
                )
                if rules["world_collision_trial"] == "explosion":
                    check(
                        "native_bomb_also_tests_explosion_immunity",
                        [len(named("native_immunity_bomb")) == 2],
                    )

    if rules.get("crafting_trial"):
        values = named("crafting_trial_probe")
        full = [e for e in values if 570 <= e["tick"] <= 597]
        crafted = [e for e in values if e["tick"] >= 750]
        check("eight_materials_collected_by_native_swings", [e["count"] == 8 for e in full])
        check(
            "holding_pocket_crafts_and_consumes_materials",
            [bool(full)]
            + [
                e["count"] == 0 and e["collectibles"] > full[-1]["collectibles"]
                for e in crafted
                if full
            ],
        )
        peer = {
            e["tick"]: e
            for e in observations.get("client", [])
            if e["event"] == "crafting_trial_probe"
        }
        check(
            "replica:crafting_contents_and_result",
            [
                e["tick"] in peer
                and e["materials"] == peer[e["tick"]]["materials"]
                and e["collectibles"] == peer[e["tick"]]["collectibles"]
                for e in values
            ],
        )
    if rules.get("hold_poop_trial"):
        values = named("hold_poop_probe")
        stored = [e for e in values if 120 <= e["tick"] <= 210]
        used = [e for e in values if e["tick"] >= 300]
        initial = next((e for e in values if e["tick"] == 57), None)
        check(
            "hold_stores_one_spell_from_queue",
            [initial is not None]
            + [
                e["mana"] == initial["mana"] - 1 and e["queue"] != initial["queue"]
                for e in stored
                if initial
            ],
        )
        check(
            "using_stored_spell_does_not_consume_next_spell",
            [bool(stored)]
            + [
                e["mana"] == stored[-1]["mana"] and e["queue"] == stored[-1]["queue"]
                for e in used
                if stored
            ],
        )
        before = next((e for e in probes if e["tick"] == 210), None)
        late = [e for e in probes if e["tick"] >= 243]
        check(
            "stored_spell_has_native_world_effect",
            [
                bool(before)
                and any(
                    e["poop_count"] > before["poop_count"]
                    or e["familiar_count"] > before["familiar_count"]
                    or any(
                        n > before["spawned"].get(k, 0)
                        for k, n in e["spawned"].items()
                        if k.startswith(("245.", "4."))
                    )
                    or e["effects"].get("FART", 0) > 0
                    for e in late
                )
            ],
        )

    if rules.get("generation_trial"):
        trials = named("native_generation_sample")
        before = next((e for e in trials if e["phase"] == "before"), None)
        after = next((e for e in trials if e["phase"] == "after"), None)
        check("native_generation_control_and_item_samples", [before is not None, after is not None])
        if before and after:
            for event in (before, after):
                if event["drops"] == []:
                    event["drops"] = {}
            key = after["item"]

            def count(event, variant, subtype=None):
                return sum(
                    n
                    for identity, n in event["drops"].items()
                    if identity.startswith(str(variant) + ".")
                    and (subtype is None or identity == f"{variant}.{subtype}")
                )

            if key == 72:
                check(
                    "rosary_adds_bible_to_boss_pool", [before["bibles"] == 0, after["bibles"] > 0]
                )
            elif key == 194:
                check("native_planetarium_chance_increases", [after["chance"] > before["chance"]])
            elif key == 208:
                check(
                    "champion_belt_increases_native_champions",
                    [after["champions"] > before["champions"]],
                )
            elif key == 173:
                check(
                    "mitre_converts_native_heart_drops",
                    [count(after, 10, 3) > count(before, 10, 3)],
                )
            elif key == 203:
                check(
                    "bundle_increases_double_pickups", [count(after, 20, 4) > count(before, 20, 4)]
                )
            elif key == 250:
                check(
                    "bogo_native_bomb_pairs",
                    [count(after, 40, 2) > 0, count(after, 40, 1) == 0, count(before, 40, 1) > 0],
                )
            elif key == 424:
                check("sack_head_replaces_native_drops", [count(after, 69) > count(before, 69)])
            elif key == 199:
                check(
                    "moms_key_increases_native_chest_contents",
                    [sum(after["drops"].values()) > sum(before["drops"].values())],
                )
            elif key == 134:
                check(
                    "tail_increases_native_chest_rewards",
                    [
                        sum(count(after, v) for v in (50, 60))
                        > sum(count(before, v) for v in (50, 60))
                    ],
                )
            elif key == 241:
                check(
                    "contract_doubles_native_clear_awards",
                    [
                        any(n >= 2 for n in after["award_counts"]),
                        max(before["award_counts"], default=0)
                        < max(after["award_counts"], default=0),
                    ],
                )
            elif key == 464:
                check(
                    "glyph_grants_needed_health",
                    [count(after, 10) > 0, count(after, 10) > count(before, 10)],
                )
            elif key == 670:
                check(
                    "native_awards_are_mutually_exclusive_options",
                    [after["options"] >= 2, before["options"] == 0],
                )
                picked = named("native_award_choice_result")
                check(
                    "choosing_award_removes_alternative",
                    [len(picked) == 1 and picked[0]["remaining"] == 0],
                )

    if rules.get("feed_familiar"):
        feeds = named("familiar_feed_result")
        expected = rules["feed_familiar"]["count"]
        check(
            "familiar_consumes_pickups",
            [
                len(feeds) == expected,
                all(
                    e["consumed"] and e.get("resource_before") == e.get("resource_after")
                    for e in feeds
                ),
            ],
        )
        rewards = named("fed_familiar_reward")
        check("fed_familiar_produces_reward", [bool(rewards)])
        peer = {
            e["seed"]: e
            for e in observations.get("client", [])
            if e["event"] == "fed_familiar_reward"
        }
        check(
            "replica:fed_familiar_rewards",
            [
                e["seed"] in peer
                and all(e[k] == peer[e["seed"]][k] for k in ("variant", "subtype"))
                for e in rewards
            ],
        )
        if rules["feed_familiar"]["variant"] == "BUMBO":
            check(
                "bumbo_reaches_final_stage",
                [
                    any(
                        e.get("bumbo_level", 0) >= 3 or e.get("bumbo_coins", 0) >= 24
                        for e in named("interaction_probe")
                    )
                ],
            )
    if rules.get("jar_hearts"):
        stored = [e for e in named("interaction_probe") if 249 <= e["tick"] <= 267]
        emptied = [e for e in named("interaction_probe") if e["tick"] >= 300]
        check("jar_stores_four_red_hearts", [e["jar_hearts"] >= 8 for e in stored])
        check(
            "jar_releases_stored_hearts",
            [e["jar_hearts"] == 0 and e["heart_pickups"] >= 4 for e in emptied],
        )
    if rules.get("echo_cards"):
        values = named("echo_result")
        check(
            "echo_repeats_previous_cards",
            [
                len(values) == 3,
                [e["bombs"] for e in values] == [2, 4, 8],
                [e["coins"] for e in values] == [1, 2, 8],
            ],
        )
    if rules.get("switch_actives"):
        values = named("interaction_probe")
        check(
            "schoolbag_holds_two_actives",
            [e["active"] != 0 and e["secondary"] != 0 for e in values if 99 <= e["tick"] <= 117],
        )
        check(
            "drop_swaps_active_slots",
            [
                e["active"] == 292 and e["secondary"] == 105
                for e in values
                if 150 <= e["tick"] <= 177
            ],
        )
        check(
            "switched_active_is_usable",
            [e["soul"] >= 2 and e["charge"] == 0 for e in values if 210 <= e["tick"] <= 237],
        )
        check(
            "second_swap_restores_original",
            [e["active"] == 105 and e["secondary"] == 292 for e in values if e["tick"] >= 270],
        )
    if rules.get("sharp_plug"):
        before = next((e for e in probes if e.get("label") == "before"), None)
        after = [e for e in probes if 120 <= e["tick"] <= 177]
        check(
            "sharp_plug_spends_health_for_charge",
            [
                e["charge"] > 0
                and before["hearts"] - e["hearts"] == e["charge"]
                and e["hearts"] > 0
                for e in after
            ]
            if before
            else [],
        )
    if rules.get("jar_charges"):
        values = named("jar_charge_result")
        expected = [
            (10, 1),
            (20, 1),
            (40, 1),
            (30, 1),
            (10, 1),
            (70, None),
            (300, None),
            (10, 3),
            (10, 7),
            (30, 2),
            (40, 4),
        ]
        check(
            "everything_jar_distinct_charge_rewards",
            [
                len(values) == 11,
                all(
                    any(
                        p["variant"] == variant and (subtype is None or p["subtype"] == subtype)
                        for p in e["pickups"]
                    )
                    if e["charge"] != 1
                    else e["poops"] > 0
                    for e, (variant, subtype) in zip(values, expected)
                ),
            ],
        )
    if rules.get("moving_box"):
        values = named("box_checkpoint")
        before = next((e for e in values if e["phase"] == "before"), None)
        stored = next((e for e in values if e["phase"] == "stored"), None)
        released = next((e for e in values if e["phase"] == "released"), None)
        check(
            "moving_box_stores_and_transports_pickups",
            [
                before is not None
                and stored is not None
                and released is not None
                and 4 <= len(before["pickups"]) <= 10
                and {"10.1", "20.1", "30.1", "40.1"} <= set(before["pickups"])
                and not stored["pickups"]
                and before["room"] != released["room"]
                and sorted(before["pickups"]) == sorted(released["pickups"])
            ],
        )
