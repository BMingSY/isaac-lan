"""Native trinket effects exercised through the shared item audit probes."""

from item_interaction_effects import DEAL_REWARD_SETTLE_TICKS

DEVIL_NUMBER_MAGNET_SUBTYPE = 1
TRINKET_EFFECTS = {}

for name, flags, stats in (
    ("PULSE_WORM", ["TEAR_PULSE"], {}),
    ("WIGGLE_WORM", ["TEAR_WIGGLE", "TEAR_SPECTRAL"], {"delay": -1}),
    ("RING_WORM", ["TEAR_SPIRAL", "TEAR_SPECTRAL"], {"delay": -1}),
    ("FLAT_WORM", ["TEAR_FLAT"], {}),
    ("HOOK_WORM", ["TEAR_SQUARE", "TEAR_SPECTRAL"], {"delay": -1, "range": 1}),
    ("PINKY_EYE", ["TEAR_POISON"], {}),
    ("PUSH_PIN", ["TEAR_PIERCING", "TEAR_SPECTRAL"], {}),
    ("BLISTER", ["TEAR_KNOCKBACK"], {}),
    ("BLACK_TOOTH", ["TEAR_POISON"], {}),
    (
        "OUROBOROS_WORM",
        ["TEAR_BIG_SPIRAL", "TEAR_SPECTRAL", "TEAR_HOMING"],
        {"delay": -1, "range": 1},
    ),
    ("NOSE_GOBLIN", ["TEAR_BOOGER"], {}),
    ("SUPER_BALL", ["TEAR_BOUNCE"], {}),
    ("CHEWED_PEN", ["TEAR_SLOW"], {}),
):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "shoot": True,
        "shoot_until": 510,
        "tear_flags": flags,
        "stats": stats,
        "luck": 100,
        "observe_until": 537,
        "end_tick": 540,
    }

TRINKET_EFFECTS.update(
    {
        "TRINKET_WHIP_WORM": {"stats": {"shot_speed": 1}},
        "TRINKET_TAPE_WORM": {"stats": {"range": 1}},
        "TRINKET_LAZY_WORM": {"stats": {"damage": 1, "shot_speed": -1}},
        "TRINKET_MOTHERS_KISS": {"delta": {"max_hearts": 2}},
        "TRINKET_BLACK_FEATHER": {
            "prerequisite_items": ["COLLECTIBLE_CEREMONIAL_ROBES"],
            "stats": {"damage": 1},
        },
        "TRINKET_CRACKED_CROWN": {
            "prerequisite_items": ["COLLECTIBLE_MAGIC_MUSHROOM", "COLLECTIBLE_SAD_ONION"],
            "stats": {"damage": 1, "speed": 1, "range": 1},
        },
        "TRINKET_VIBRANT_BULB": {
            "active_before": "COLLECTIBLE_D6",
            "stats": {"damage": 1, "speed": 1, "delay": -1, "range": 1, "shot_speed": 1, "luck": 1},
        },
        "TRINKET_DIM_BULB": {
            "empty_active": True,
            "stats": {"damage": 1, "speed": 1, "delay": -1, "range": 1, "shot_speed": 1, "luck": 1},
        },
        "TRINKET_SWALLOWED_PENNY": {"damage_trigger": True, "spawns": {"5.20.": [1, 1]}},
        "TRINKET_FISH_HEAD": {"damage_trigger": True, "familiar_range": {"BLUE_FLY": [1, 2]}},
        "TRINKET_RED_PATCH": {"damage_trigger": True, "luck": 100, "hit_stats": {"damage": 1}},
        "TRINKET_JAW_BREAKER": {
            "shoot": True,
            "shoot_until": 510,
            "charged_damage": 3.2,
            "luck": 100,
            "observe_until": 537,
            "end_tick": 540,
        },
    }
)
TRINKET_EFFECTS["TRINKET_BLIND_RAGE"] = {
    "trinket_trial": {"mode": "cooldown"},
    "observe_until": 327,
    "end_tick": 330,
}
TRINKET_EFFECTS["TRINKET_SECOND_HAND"] = {
    "prerequisite_items": ["COLLECTIBLE_SCORPIO"],
    "trinket_trial": {"mode": "poison_duration"},
    "observe_until": 1197,
    "end_tick": 1200,
}
for name, extra in (("PAPER_CLIP", {}), ("BROKEN_PADLOCK", {"explosion": True})):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "trinket_trial": {"mode": "locked_chest", **extra},
        "trinket_loot": True,
        "observe_until": 327,
        "end_tick": 330,
    }
TRINKET_EFFECTS["TRINKET_STORE_CREDIT"] = {
    "floor_visit": {"room": "ROOM_SHOP"},
    "trinket_trial": {"mode": "shop", "reward": "credit"},
    "observe_until": 717,
    "end_tick": 720,
}
TRINKET_EFFECTS["TRINKET_ADOPTION_PAPERS"] = {
    "floor_visit": {"room": "ROOM_SHOP"},
    "trinket_trial": {"mode": "shop", "reward": "familiars"},
    "observe_until": 657,
    "end_tick": 660,
}

for name, reward, clear, extra in (
    ("LIBERTY_CAP", "temporary", False, {}),
    ("ERROR", "temporary", False, {}),
    ("BROKEN_SYRINGE", "temporary", False, {}),
    ("MOMS_LOCK", "temporary", False, {}),
    ("MODELING_CLAY", "temporary", False, {}),
    ("DICE_BAG", "pocket", False, {}),
    ("ISAACS_FORK", "hearts", True, {"health_before": 1, "luck": 100}),
    ("LOUSE", "spiders", True, {}),
    ("DINGLE_BERRY", "dips", True, {}),
    ("POLISHED_BONE", "bonies", True, {}),
    ("CRYSTAL_KEY", "red_rooms", True, {"red_rooms": True}),
    ("AZAZELS_STUMP", "azazel", True, {}),
    ("AAA_BATTERY", "aaa", True, {"empty_active": True}),
    ("OLD_CAPACITOR", "capacitor", True, {"empty_active": True, "luck": 100}),
    ("THE_TWINS", "twins", False, {}),
    ("USED_DIAPER", "flies", False, {}),
    ("LIGHTER", "burn", False, {"enemies": 1, "enemy_flags": ["FLAG_BURN"]}),
    ("ICE_CUBE", "petrify", False, {"enemies": 1, "enemy_flags": ["FLAG_FREEZE"]}),
):
    count = 5 if name == "AAA_BATTERY" else 8
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "entry_floor": True,
        "entry_trial": count,
        "clear_entries": clear,
        "clear_count": count,
        "confirm_entry_clear": clear,
        "trinket_trial": {"mode": "rooms", "reward": reward, "count": count},
        "observe_until": 450 + count * 120 - 3,
        "end_tick": 450 + count * 120,
        **extra,
    }

for name, stage, stage_type, rooms in (
    ("FRAGMENTED_CARD", "STAGE1_2", "STAGETYPE_ORIGINAL", {"ROOM_SECRET": 2}),
    ("SILVER_DOLLAR", "STAGE4_1", "STAGETYPE_ORIGINAL", {"ROOM_SHOP": 1}),
    ("BLOODY_CROWN", "STAGE4_1", "STAGETYPE_ORIGINAL", {"ROOM_TREASURE": 1}),
    ("HOLY_CROWN", "STAGE5", "STAGETYPE_WOTL", {"ROOM_SHOP": 1, "ROOM_TREASURE": 1}),
    ("WICKED_CROWN", "STAGE5", "STAGETYPE_ORIGINAL", {"ROOM_SHOP": 1, "ROOM_TREASURE": 1}),
):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "trinket_trial": {
            "mode": "floor",
            "stage": stage,
            "stage_type": stage_type,
            "rooms": rooms,
        },
        "observe_map": True,
        "observe_until": 897,
        "end_tick": 900,
    }
TRINKET_EFFECTS["TRINKET_HAIRPIN"] = {
    "empty_active": True,
    "trinket_trial": {"mode": "door", "reward": "charge", "room": "ROOM_BOSS"},
    "charged": True,
    "observe_until": 777,
    "end_tick": 780,
}
TRINKET_EFFECTS["TRINKET_DICE_BAG"]["input_schedule"] = [
    [495 + i * 120, 501 + i * 120, "card"] for i in range(8)
]
TRINKET_EFFECTS["TRINKET_AZAZELS_STUMP"].update(
    {
        "rng_seed": 1,
        "entry_trial": 24,
        "clear_count": 24,
        "minimum_combat_clears": 12,
        "reset_entry_combat": True,
        "trinket_trial": {"mode": "rooms", "reward": "azazel", "count": 24},
        "button_intervals": [[480 + i * 120, 525 + i * 120, "ACTION_SHOOTUP"] for i in range(24)],
        "observe_until": 3327,
        "end_tick": 3330,
        "lasers": True,
    }
)
TRINKET_EFFECTS["TRINKET_CAINS_EYE"] = {
    "prerequisite_items": ["COLLECTIBLE_LUCKY_FOOT"] * 3,
    "trinket_trial": {
        "mode": "floor",
        "stage": "STAGE1_2",
        "stage_type": "STAGETYPE_ORIGINAL",
        "icons": True,
    },
    "observe_map": True,
    "observe_until": 897,
    "end_tick": 900,
}
TRINKET_EFFECTS["TRINKET_PURPLE_HEART"] = {
    "trinket_trial": {"mode": "champion_floors", "count": 16},
    "observe_until": 7317,
    "end_tick": 7320,
}

for name, effect in (("PULSE_WORM", "pulse"), ("FLAT_WORM", "flat"), ("BLISTER", "knockback")):
    TRINKET_EFFECTS["TRINKET_" + name]["trinket_trial"] = {"mode": "tear_control", "effect": effect}
TRINKET_EFFECTS["TRINKET_BLACK_TOOTH"]["charged_damage"] = 2
TRINKET_EFFECTS.update(
    {
        "TRINKET_BROKEN_MAGNET": {"attract_pickup": True},
        "TRINKET_EQUALITY": {"coins_before": 2, "keys_before": 2, "stats": {"delay": -1}},
        "TRINKET_TORN_CARD": {
            "shoot": True,
            "shoot_until": 900,
            "tear_flags": ["TEAR_EXPLOSIVE", "TEAR_BOOMERANG"],
            "observe_until": 927,
            "end_tick": 930,
        },
        "TRINKET_BROKEN_REMOTE": {
            "active_before": "COLLECTIBLE_D6",
            "input_schedule": [[90, 96, "active"]],
            "trinket_trial": {"mode": "active", "effect": "teleport"},
        },
        "TRINKET_BUTTER": {
            "active_before": "COLLECTIBLE_D6",
            "consumed_active": True,
            "input_schedule": [[90, 96, "active"]],
            "trinket_trial": {"mode": "active", "effect": "drop"},
        },
        "TRINKET_M": {
            "active_before": "COLLECTIBLE_D6",
            "input_schedule": [[90, 96, "active"]],
            "trinket_trial": {"mode": "active", "effect": "reroll"},
        },
        "TRINKET_PANIC_BUTTON": {
            "active_before": "COLLECTIBLE_BOOK_OF_SHADOWS",
            "projectile_trial": {"kind": "player"},
            "trinket_trial": {"mode": "active", "effect": "panic"},
            "observe_until": 1620,
            "end_tick": 1650,
        },
        "TRINKET_KIDS_DRAWING": {
            "prerequisite_items": ["COLLECTIBLE_GUPPYS_COLLAR", "COLLECTIBLE_GUPPYS_TAIL"],
            "prerequisite_first_time": True,
            "flying": True,
            "trinket_trial": {"mode": "guppy"},
        },
        "TRINKET_TELESCOPE_LENS": {"trinket_trial": {"mode": "planetarium"}},
        "TRINKET_RAINBOW_WORM": {
            "shoot": True,
            "random_tears": True,
            "shoot_until": 1260,
            "trinket_trial": {"mode": "rainbow"},
            "observe_until": 1287,
            "end_tick": 1290,
        },
        "TRINKET_FADED_POLAROID": {
            "enemies": 2,
            "enemy_flags": ["FLAG_CONFUSION"],
            "observe_until": 2697,
            "end_tick": 2700,
        },
    }
)

# These trials cause native damage repeatedly; they never grant the expected
# reward themselves. Consumed trinkets remain consumed for the rest of the case.
for name, reward, count, extra in (
    ("CARTRIDGE", "invincible", 128, {}),
    ("MONKEY_PAW", "monkey_paw", 4, {"low_health": True}),
    ("CURSED_SKULL", "room", 2, {"low_health": True}),
    ("MISSING_PAGE", "enemy_damage", 128, {"enemy": True}),
    ("TONSIL", "tonsil", 28, {}),
    ("WISH_BONE", "pedestal", 128, {}),
    ("BAG_LUNCH", "lunch", 128, {}),
    ("CROW_HEART", "red_first", 4, {"max_hearts": 12, "health": 12, "soul": 8}),
    ("WALNUT", "walnut", 32, {"explosion": True}),
    ("FINGER_BONE", "bone", 128, {"max_hearts": 12}),
    ("PERFECTION", "destroyed", 2, {}),
    ("TORN_POCKET", "resources", 8, {"resources": True}),
    ("SWALLOWED_M80", "explosion", 32, {"enemy": True}),
):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "trinket_trial": {"mode": "damage", "reward": reward, "count": count, **extra},
        "observe_until": 120 + count * 15 - 3,
        "end_tick": 120 + count * 15,
    }

TRINKET_EFFECTS.update(
    {
        "TRINKET_MISSING_POSTER": {
            "revive": True,
            "revive_natural_damage": True,
            "revive_hearts": 0,
            "revive_type": "PLAYER_THELOST",
            "observe_until": 447,
            "end_tick": 450,
        },
        "TRINKET_BROKEN_ANKH": {
            "revive": True,
            "revive_natural_damage": True,
            "revive_chance": 0.22,
            "revive_hearts": 0,
            "revive_type": "PLAYER_BLUEBABY",
            "observe_until": 447,
            "end_tick": 450,
        },
        "TRINKET_BOBS_BLADDER": {
            "bomb_trial": True,
            "enemies": 1,
            "effects": ["PLAYER_CREEP_RED"],
            "target_effect": "PLAYER_CREEP_RED",
            "enemy_hurt": True,
            "damage_source": {"type": "ENTITY_EFFECT", "variant": "PLAYER_CREEP_RED"},
            "observe_until": 297,
            "end_tick": 300,
        },
        "TRINKET_RING_CAP": {
            "bomb_trial": True,
            "spawns": {"4.": [2, 2]},
            "observe_until": 297,
            "end_tick": 300,
        },
        "TRINKET_FIRECRACKER": {
            "bomb_trial": True,
            "enemies": 1,
            "enemy_hurt": True,
            "bomb_damage": 115,
            "observe_until": 297,
            "end_tick": 300,
        },
        "TRINKET_SAMSONS_LOCK": {
            "enemies": 3,
            "kill_after": True,
            "luck": 100,
            "stats": {"damage": 1},
        },
        "TRINKET_EVES_BIRD_FOOT": {
            "enemies": 3,
            "kill_after": True,
            "luck": 100,
            "minimum_spawned_familiars": {"EVES_BIRD_FOOT": 1},
        },
        "TRINKET_SIGIL_OF_BAPHOMET": {
            "enemies": 3,
            "kill_after": True,
            "timed_invincible": {"during": [105, 150], "after": 210},
            "observe_until": 267,
            "end_tick": 270,
        },
        "TRINKET_LIL_LARVA": {
            "poops": 2,
            "destroy_fixture_poops": True,
            "trinket_trial": {"mode": "grid_actor"},
            "minimum_spawned_familiars": {"BLUE_FLY": 2},
        },
        "TRINKET_MAGGYS_FAITH": {"floor_bonus": {"eternal": 1}, "end_tick": 660},
        "TRINKET_STEM_CELL": {"health_before": 2, "floor_bonus": {"hearts": 2}, "end_tick": 660},
        "TRINKET_HOLLOW_HEART": {"floor_bonus": {"bone": 1}, "end_tick": 660},
        "TRINKET_LUCKY_SACK": {"floor_pickup": "PICKUP_GRAB_BAG", "end_tick": 660},
        "TRINKET_BETHS_FAITH": {
            "floor_bonus": {"hearts": 0},
            "observe_until": 657,
            "minimum_spawned_familiars": {"WISP": 4},
            "end_tick": 660,
        },
    }
)

for name, variant, target, all_match in (
    ("BLACK_LIPSTICK", "PICKUP_HEART", "10.6", False),
    ("BIBLE_TRACT", "PICKUP_HEART", "10.4", False),
    ("DAEMONS_TAIL", "PICKUP_HEART", "10.6", True),
    ("MOMS_PEARL", "PICKUP_HEART", ["10.3", "10.6", "10.11"], False),
    ("LEFT_HAND", "PICKUP_CHEST", "360.1", True),
    ("MOMS_LOCKET", "PICKUP_HEART", "10.2", "absent"),
    ("GILDED_KEY", "PICKUP_CHEST", "60.1", True),
):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "trinket_trial": {
            "mode": "generation",
            "variant": variant,
            "count": 512,
            "target": target,
            "all_match": all_match,
        },
        "observe_until": 297,
        "end_tick": 300,
    }
TRINKET_EFFECTS["TRINKET_NO"] = {
    "trinket_trial": {
        "mode": "generation",
        "pool": "POOL_TREASURE",
        "count": 512,
        "reject_actives": True,
    },
    "observe_until": 297,
    "end_tick": 300,
}
TRINKET_EFFECTS["TRINKET_LEFT_HAND"]["trinket_trial"]["exempt"] = ["69.1"]
TRINKET_EFFECTS["TRINKET_GILDED_KEY"]["trinket_trial"]["exempt_variants"] = [55, 57, 69]
TRINKET_EFFECTS["TRINKET_ROSARY_BEAD"] = {
    "trinket_trial": {
        "mode": "generation",
        "pool": "POOL_SHOP",
        "count": 1024,
        "target": "33",
        "all_match": False,
    },
    "observe_until": 297,
    "end_tick": 300,
}
_rosary_pool = TRINKET_EFFECTS["TRINKET_ROSARY_BEAD"]
TRINKET_EFFECTS["TRINKET_ROSARY_BEAD"] = {
    "scenarios": {
        "shop": _rosary_pool,
        "library": {
            **_rosary_pool,
            "trinket_trial": {**_rosary_pool["trinket_trial"], "pool": "POOL_LIBRARY"},
        },
        "angel": {
            "prerequisite_items": ["COLLECTIBLE_GOAT_HEAD"],
            "floor_visit": {"room": "ROOM_BOSS", "kill_boss": True},
            "trinket_trial": {"mode": "angel_door"},
            "observe_until": 717,
            "end_tick": 720,
        },
    }
}
TRINKET_EFFECTS["TRINKET_MOMS_TOENAIL"] = {
    "enemies": 1,
    "enemy_hurt": True,
    "contact_target": True,
    "input_schedule": [[90, 180, "drop"]],
    "toenail_trial": True,
    "target_effect": "MOM_FOOT_STOMP",
    "trinket_trial": {"mode": "toenail"},
    "observe_until": 477,
    "end_tick": 480,
}
TRINKET_EFFECTS["TRINKET_MYSTERIOUS_CANDY"] = {
    "trinket_trial": {"mode": "candy"},
    "rng_seed": 1,
    "observe_until": 2097,
    "end_tick": 2100,
}
TRINKET_EFFECTS["TRINKET_SAFETY_SCISSORS"] = {
    "trinket_trial": {"mode": "troll_bombs"},
    "trinket_loot": True,
    "observe_until": 417,
    "end_tick": 420,
}
TRINKET_EFFECTS["TRINKET_EXTENSION_CORD"] = {
    "prerequisite_items": ["COLLECTIBLE_BROTHER_BOBBY", "COLLECTIBLE_SISTER_MAGGY"],
    "lasers": True,
    "enemies": 1,
    "enemy_hurt": True,
    "target_laser": True,
    "observe_until": 897,
    "end_tick": 900,
}
TRINKET_EFFECTS["TRINKET_EXPANSION_PACK"] = {
    "active_before": "COLLECTIBLE_D6",
    "input_schedule": [[90 + i * 90, 96 + i * 90, "active"] for i in range(16)],
    "trinket_trial": {"mode": "expansion", "count": 16, "minimum_uses": 8},
    "observe_until": 1557,
    "end_tick": 1560,
}
TRINKET_EFFECTS["TRINKET_ENDLESS_NAMELESS"] = {
    "input_schedule": [[90 + i * 45, 96 + i * 45, "card"] for i in range(72)],
    "trinket_trial": {"mode": "endless", "count": 72},
    "trinket_loot": True,
    "observe_until": 3357,
    "end_tick": 3360,
}
_butter_active = TRINKET_EFFECTS["TRINKET_BUTTER"]
TRINKET_EFFECTS["TRINKET_BUTTER"] = {
    "scenarios": {
        "active": _butter_active,
        "damage": {
            "trinket_trial": {
                "mode": "damage",
                "reward": "passive_drop",
                "count": 256,
                "passive_items": [
                    "COLLECTIBLE_STEVEN",
                    "COLLECTIBLE_MINI_MUSH",
                    "COLLECTIBLE_SAD_ONION",
                ],
            },
            "observe_until": 3957,
            "end_tick": 3960,
        },
    }
}
TRINKET_EFFECTS["TRINKET_CALLUS"] = {
    "world_collision_trial": "spike_and_creep",
    "observe_until": 867,
    "end_tick": 870,
}
TRINKET_EFFECTS["TRINKET_FLAT_FILE"] = {
    "world_collision_trial": "spike_contact",
    "observe_until": 417,
    "end_tick": 420,
}
_flat_spikes = TRINKET_EFFECTS["TRINKET_FLAT_FILE"]
TRINKET_EFFECTS["TRINKET_FLAT_FILE"] = {
    "scenarios": {
        "spikes": _flat_spikes,
        "chests": {
            "trinket_trial": {"mode": "spiked_chests"},
            "observe_until": 597,
            "end_tick": 600,
        },
        **{
            name: {
                "floor_visit": {"room": "ROOM_CURSE", "optional": True},
                "trinket_trial": {"mode": "curse_door", "control": control},
                "observe_until": 687,
                "end_tick": 690,
            }
            for name, control in (("curse_control", True), ("curse", False))
        },
    }
}

TRINKET_EFFECTS["TRINKET_FISH_TAIL"] = {
    "trinket_trial": {"mode": "flies"},
    "observe_until": 297,
    "end_tick": 300,
}
TRINKET_EFFECTS["TRINKET_APPLE_OF_SODOM"] = {
    "trinket_trial": {"mode": "hearts", "count": 24, "period": 45, "observation_delay": 39},
    "observe_until": 1197,
    "end_tick": 1200,
}
TRINKET_EFFECTS["TRINKET_CRACKED_DICE"] = {
    "trinket_trial": {"mode": "damage", "reward": "dice", "count": 128},
    "reroll_pedestals": True,
    "reroll_pickups": True,
    "loose_pickups": True,
    "random_stats": True,
    "observe_until": 2037,
    "end_tick": 2040,
}
TRINKET_EFFECTS["TRINKET_MYSTERIOUS_PAPER"] = {
    "trinket_trial": {
        "mode": "damage",
        "reward": "paper",
        "count": 128,
        "health": 1,
        "max_hearts": 2,
        "soul": 8,
        "enemy": True,
    },
    "observe_until": 2037,
    "end_tick": 2040,
}
TRINKET_EFFECTS["TRINKET_SHINY_ROCK"] = {
    "trinket_trial": {"mode": "shiny_rock"},
    "visual_review": "tinted_rock_flashes_and_ordinary_rock_does_not",
    "observe_until": 687,
    "end_tick": 690,
}
TRINKET_EFFECTS["TRINKET_PAY_TO_WIN"] = {
    "floor_visit": {"room": "ROOM_TREASURE"},
    "trinket_trial": {"mode": "floor_room", "reward": "restock"},
    "observe_until": 657,
    "end_tick": 660,
}
TRINKET_EFFECTS["TRINKET_DEVILS_CROWN"] = {
    "floor_visit": {"room": "ROOM_TREASURE"},
    "trinket_trial": {"mode": "floor_room", "reward": "devil_prices"},
    "observe_until": 657,
    "end_tick": 660,
}
for name, reward in (("GOLDEN_HORSE_SHOE", "choice"), ("BROKEN_GLASSES", "blind_choice")):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "trinket_trial": {
            "mode": "floor_series",
            "reward": reward,
            "count": 16,
            "stage": "STAGE1_2",
            "room": "ROOM_TREASURE",
        },
        "observe_until": 7317,
        "end_tick": 7320,
    }
_glasses = TRINKET_EFFECTS["TRINKET_BROKEN_GLASSES"]
TRINKET_EFFECTS["TRINKET_BROKEN_GLASSES"] = {
    "scenarios": {
        "treasure": {**_glasses, "visual_review": "broken_glasses_extra_choice_is_blind"},
        "alt_path": {
            **_glasses,
            "visual_review": "broken_glasses_alt_path_blind_item_revealed",
            "observe_until": 3717,
            "end_tick": 3720,
            "trinket_trial": {
                **_glasses["trinket_trial"],
                "count": 8,
                "stage_type": "STAGETYPE_REPENTANCE",
                "reward": "reveal_choice",
            },
        },
    }
}
TRINKET_EFFECTS["TRINKET_NUH_UH"] = {
    "trinket_trial": {
        "mode": "floor_series",
        "reward": "replace_resources",
        "count": 1,
        "stage": "STAGE4_1",
        "room": "ROOM_DEFAULT",
    },
    "observe_until": 537,
    "end_tick": 540,
}
TRINKET_EFFECTS["TRINKET_MYOSOTIS"] = {
    "trinket_trial": {"mode": "myosotis"},
    "observe_until": 1077,
    "end_tick": 1080,
}
TRINKET_EFFECTS["TRINKET_STRANGE_KEY"] = {
    "active_before": "COLLECTIBLE_BLUE_BOX",
    "input_schedule": [[90, 96, "active"]],
    "trinket_trial": {"mode": "pandora"},
    "observe_until": 297,
    "end_tick": 300,
}
_pandora = TRINKET_EFFECTS["TRINKET_STRANGE_KEY"]
TRINKET_EFFECTS["TRINKET_STRANGE_KEY"] = {
    "scenarios": {
        "pandora": _pandora,
        **{
            name: {
                "floor_visit": {
                    "room": "ROOM_BOSS",
                    "stage": "STAGE4_2",
                    "kill_boss": True,
                    "kill_repeated": True,
                },
                "trinket_trial": {"mode": "hush_door", "control": control},
                "observe_until": 927,
                "end_tick": 930,
            }
            for name, control in (("hush_control", True), ("hush", False))
        },
    }
}
for name, reward in (
    ("JUDAS_TONGUE", "tongue"),
    ("KEEPERS_BARGAIN", "coins"),
    ("YOUR_SOUL", "free"),
    ("NUMBER_MAGNET", "magnet"),
):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "prerequisite_items": ["COLLECTIBLE_GOAT_HEAD"],
        "floor_visit": {"room": "ROOM_BOSS", "kill_boss": True},
        "deal_item_trial": "trinket",
        "deal_delay": DEAL_REWARD_SETTLE_TICKS,
        "stay_in_deal": True,
        "trinket_trial": {"mode": "devil_deal", "reward": reward},
        "observe_until": 1017 + DEAL_REWARD_SETTLE_TICKS,
        "end_tick": 1020 + DEAL_REWARD_SETTLE_TICKS,
    }
for name in ("JUDAS_TONGUE", "KEEPERS_BARGAIN"):
    TRINKET_EFFECTS["TRINKET_" + name].update(
        observe_until=1317 + DEAL_REWARD_SETTLE_TICKS,
        end_tick=1320 + DEAL_REWARD_SETTLE_TICKS,
    )

TRINKET_EFFECTS["TRINKET_BETHS_ESSENCE"] = {
    "scenarios": {
        "angel": {
            "prerequisite_items": ["COLLECTIBLE_EUCHARIST"],
            "floor_visit": {"room": "ROOM_BOSS", "kill_boss": True},
            "deal_item_trial": "trinket",
            "deal_delay": DEAL_REWARD_SETTLE_TICKS,
            "deal_room": "ROOM_ANGEL",
            "stay_in_deal": True,
            "minimum_spawned_familiars": {"WISP": 5},
            "observe_until": 837 + DEAL_REWARD_SETTLE_TICKS,
            "end_tick": 840 + DEAL_REWARD_SETTLE_TICKS,
        },
        "beggar": {
            "trinket_trial": {"mode": "donations", "reward": "wisps", "count": 32},
            "observe_until": 3057,
            "end_tick": 3060,
        },
    },
}
TRINKET_EFFECTS["TRINKET_KARMA"] = {
    "trinket_trial": {"mode": "donations", "reward": "luck", "count": 64},
    "observe_until": 5937,
    "end_tick": 5940,
}
TRINKET_EFFECTS["TRINKET_FILIGREE_FEATHERS"] = {
    "prerequisite_items": ["COLLECTIBLE_EUCHARIST"],
    "floor_visit": {"room": "ROOM_BOSS", "kill_boss": True},
    "deal_item_trial": "trinket",
    "deal_delay": DEAL_REWARD_SETTLE_TICKS,
    "deal_room": "ROOM_ANGEL",
    "stay_in_deal": True,
    "trinket_trial": {"mode": "angel_boss"},
    "observe_until": 1197 + DEAL_REWARD_SETTLE_TICKS,
    "end_tick": 1200 + DEAL_REWARD_SETTLE_TICKS,
}
TRINKET_EFFECTS["TRINKET_TICK"] = {
    "health_before": 2,
    "floor_visit": {"room": "ROOM_BOSS", "native_transition": True},
    "input_schedule": [[510, 585, "drop"]],
    "observe_until": 837,
    "end_tick": 840,
    "scenarios": {
        "match_stick": {"trinket_trial": {"mode": "tick", "replacement": "TRINKET_MATCH_STICK"}},
        "lighter": {"trinket_trial": {"mode": "tick", "replacement": "TRINKET_LIGHTER"}},
    },
}
for name, reward, room in (
    ("STORE_KEY", "store", "ROOM_SHOP"),
    ("BLUE_KEY", "blue", "ROOM_TREASURE"),
    ("DOOR_STOP", "open", "ROOM_DEFAULT"),
):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "trinket_trial": {"mode": "door", "reward": reward, "room": room},
        "observe_until": 1077,
        "end_tick": 1080,
    }
TRINKET_EFFECTS["TRINKET_RIB_OF_GREED"] = {
    "scenarios": {
        room.lower(): {
            "trinket_trial": {
                "mode": "floor_series",
                "reward": "greed",
                "count": 32,
                "held_count": 16,
                "stage": "STAGE3_2",
                "room": room,
            },
            "observe_until": 14517,
            "end_tick": 14520,
        }
        for room in ("ROOM_SHOP", "ROOM_SECRET")
    }
}
TRINKET_EFFECTS["TRINKET_RIB_OF_GREED"]["scenarios"]["awards"] = {
    "trinket_trial": {"mode": "awards", "reward": "coins", "count": 1024},
    "observe_until": 297,
    "end_tick": 300,
}
TRINKET_EFFECTS["TRINKET_TEARDROP_CHARM"] = {
    "prerequisite_items": ["COLLECTIBLE_TOUGH_LOVE"] + ["COLLECTIBLE_LUCKY_FOOT"] * 6,
    "button_intervals": [[90, 690, "ACTION_SHOOTUP"], [870, 1470, "ACTION_SHOOTUP"]],
    "trinket_trial": {"mode": "tear_probability", "minimum_shots": 200},
    "observe_until": 1527,
    "end_tick": 1530,
}
TRINKET_EFFECTS["TRINKET_BRAIN_WORM"] = {
    "shoot": True,
    "enemies": 1,
    "target_offset": [70, -100],
    "enemy_hurt": True,
    "trinket_trial": {"mode": "turning_tears"},
    "shoot_until": 510,
    "observe_until": 537,
    "end_tick": 540,
}
TRINKET_EFFECTS["TRINKET_SUPER_MAGNET"] = {
    "attract_pickup": True,
    "trinket_trial": {"mode": "enemy_attraction"},
    "observe_until": 477,
    "end_tick": 480,
}
TRINKET_EFFECTS["TRINKET_BLASTING_CAP"] = {
    "trinket_trial": {"mode": "bomb_drops", "count": 32, "period": 40},
    "input_schedule": [[90 + n * 40, 93 + n * 40, "bomb"] for n in range(32)],
    "observe_until": 1407,
    "end_tick": 1410,
}
TRINKET_EFFECTS["TRINKET_BUTT_PENNY"] = {
    "scenarios": {
        "coin": {
            "trinket_trial": {
                "mode": "coins",
                "count": 4,
                "period": 45,
                "observation_delay": 39,
                "reward": "poison",
            },
            "enemies": 1,
            "enemy_flags": ["FLAG_POISON"],
            "enemy_hurt": True,
            "observe_until": 297,
            "end_tick": 300,
        },
        "poop": {
            "trinket_trial": {
                "mode": "grid",
                "grid": "GRID_POOP",
                "count": 256,
                "held_tick": 297,
                "reward": "coins",
            },
            "observe_until": 516,
            "end_tick": 519,
        },
    },
}
TRINKET_EFFECTS["TRINKET_UMBILICAL_CORD"] = {
    "trinket_trial": {
        "mode": "damage",
        "count": 32,
        "reward": "umbilical",
        "health": 1,
        "max_hearts": 2,
        "soul": 8,
    },
    "minimum_spawned_familiars": {"LITTLE_STEVEN": 1, "GEMINI": 1},
    "observe_until": 597,
    "end_tick": 600,
}
TRINKET_EFFECTS["TRINKET_WATCH_BATTERY"] = {
    "empty_active": True,
    "trinket_trial": {
        "mode": "generation",
        "variant": "PICKUP_NULL",
        "count": 1024,
        "target": ["90.1", "90.2", "90.3", "90.4"],
        "retain_targets": True,
        "all_match": False,
    },
    "observe_until": 297,
    "end_tick": 300,
}
_watch_pickups = TRINKET_EFFECTS["TRINKET_WATCH_BATTERY"]
TRINKET_EFFECTS["TRINKET_WATCH_BATTERY"] = {
    "scenarios": {
        "pickups": _watch_pickups,
        "awards": {
            "trinket_trial": {"mode": "awards", "reward": "batteries", "count": 1024},
            "observe_until": 297,
            "end_tick": 300,
        },
        "charge": {
            "rng_seed": 1,
            "entry_floor": True,
            "entry_trial": 64,
            "clear_entries": True,
            "clear_count": 64,
            "minimum_combat_clears": 32,
            "confirm_entry_clear": True,
            "reset_entry_combat": True,
            "empty_active": True,
            "trinket_trial": {
                "mode": "rooms",
                "reward": "watch_charge",
                "count": 64,
                "minimum_clears": 32,
            },
            "observe_until": 8127,
            "end_tick": 8130,
        },
    }
}

TRINKET_EFFECTS["TRINKET_BAT_WING"] = {
    "enemies": 128,
    "rng_seed": 1,
    "kill_after": True,
    "flying": True,
    "expire_room": True,
    "flying_expire_room": True,
    "observe_until": 357,
    "end_tick": 360,
}
TRINKET_EFFECTS["TRINKET_CRICKET_LEG"] = {
    "enemies": 64,
    "kill_after": True,
    "minimum_spawned_familiars": {"BLUE_FLY": 1},
    "trinket_trial": {"mode": "locust", "kills": True},
    "observe_until": 357,
    "end_tick": 360,
}
for name, subtype, multiplier, flags in (
    ("WRATH", 1, 2, []),
    ("PESTILENCE", 2, 2, ["FLAG_POISON"]),
    ("FAMINE", 3, 2, ["FLAG_SLOW"]),
    ("DEATH", 4, 4, []),
    ("CONQUEST", 5, 2, []),
):
    TRINKET_EFFECTS["TRINKET_LOCUST_OF_" + name] = {
        "entry_floor": True,
        "entry_trial": 4,
        "trinket_trial": {
            "mode": "locust",
            "subtype": subtype,
            "multiplier": multiplier,
            "contact_hits": 2 if name == "DEATH" else 1,
            "flags": flags,
        },
        "observe_until": 927,
        "end_tick": 930,
    }

TRINKET_EFFECTS["TRINKET_TEMPORARY_TATTOO"] = {
    "scenarios": {
        "normal": {
            "floor_visit": {"room": "ROOM_CHALLENGE", "stage": "STAGE2_1", "optional": True},
            "trinket_trial": {"mode": "challenge", "boss": False},
            "run_seed": 12345,
        },
        "boss": {
            "floor_visit": {"room": "ROOM_CHALLENGE", "stage": "STAGE2_2", "optional": True},
            "health_before": 1,
            "trinket_trial": {"mode": "challenge", "boss": True},
        },
    },
    "observe_until": 1437,
    "end_tick": 1440,
}

for name, active, variant in (
    ("LOST_CORK", "COLLECTIBLE_LEMON_MISHAP", "PLAYER_CREEP_LEMON_MISHAP"),
    ("GIGANTE_BEAN", "COLLECTIBLE_BUTTER_BEAN", "FART"),
):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "active_before": active,
        "input_schedule": [[90, 96, "active"], [210, 216, "active"]],
        "trinket_trial": {"mode": "effect_size", "variant": variant},
        "observe_until": 327,
        "end_tick": 330,
    }

for name, prefix, stats in (
    ("CHILDS_HEART", "10.", {}),
    ("RUSTED_KEY", "30.", {}),
    ("MATCH_STICK", "40.", {}),
    ("LUCKY_TOE", "", {"luck": 1}),
    ("SAFETY_CAP", "70.", {}),
    ("ACE_SPADES", "300.", {}),
):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "trinket_trial": {"mode": "loot", "source": "chest", "count": 256, "prefix": prefix},
        "trinket_loot": True,
        "stats": stats,
        "observe_until": 297,
        "end_tick": 300,
    }

TRINKET_EFFECTS["TRINKET_POKER_CHIP"] = {
    "trinket_trial": {"mode": "loot", "source": "chest", "count": 256, "poker": True},
    "trinket_loot": True,
    "observe_until": 297,
    "end_tick": 300,
}

for name, source, count, reward in (
    ("PETRIFIED_POOP", "GRID_POOP", 256, "pickups"),
    ("LUCKY_ROCK", "GRID_ROCK", 256, "coins"),
    ("STUD_FINDER", "GRID_ROCK", 1024, "crawl_spaces"),
    ("BROWN_CAP", "GRID_POOP", 16, "explosion"),
    ("MECONIUM", "GRID_POOP", 512, "black_poop"),
):
    phase_ticks = count // 8 * 6
    held_tick = 105 + phase_ticks
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "trinket_trial": {
            "mode": "grid",
            "grid": source,
            "count": count,
            "held_tick": held_tick,
            "reward": reward,
            "native_poop": name == "MECONIUM",
        },
        "trinket_loot": True,
        "observe_until": held_tick + phase_ticks + 27,
        "end_tick": held_tick + phase_ticks + 30,
    }

for name, reward, extra in (
    ("BLOODY_PENNY", "10.2", {}),
    ("BURNT_PENNY", "40.", {}),
    ("FLAT_PENNY", "30.", {}),
    ("COUNTERFEIT_PENNY", "coins", {}),
    ("ROTTEN_PENNY", "flies", {}),
    ("BLESSED_PENNY", "10.8", {}),
    ("CHARGED_PENNY", "charge", {"empty_active": True}),
    ("CURSED_PENNY", "room", {}),
):
    TRINKET_EFFECTS["TRINKET_" + name] = {
        "trinket_trial": {
            "mode": "coins",
            "count": 32,
            "period": 45,
            "observation_delay": 39,
            "reward": reward,
            "charge": reward == "charge",
        },
        "observe_until": 1587,
        "end_tick": 1590,
        **extra,
    }


TRINKET_EFFECTS["TRINKET_CURSED_PENNY"]["trinket_trial"].update(
    {"count": 8, "period": 120, "observation_delay": 105}
)
TRINKET_EFFECTS["TRINKET_CURSED_PENNY"].update({"observe_until": 1107, "end_tick": 1110})
TRINKET_EFFECTS["TRINKET_POLISHED_BONE"].update(
    {
        "entry_trial": 32,
        "clear_count": 32,
        "reset_entry_combat": True,
        "trinket_trial": {"mode": "rooms", "reward": "bonies", "count": 32},
        "observe_until": 4287,
        "end_tick": 4290,
    }
)
TRINKET_EFFECTS["TRINKET_LIBERTY_CAP"].update(
    {"entry_trial": 32, "observe_until": 4287, "end_tick": 4290}
)
TRINKET_EFFECTS["TRINKET_LIBERTY_CAP"]["trinket_trial"]["count"] = 32


def trinket_checks(rules, observations, probes, check):
    trial = rules.get("trinket_trial")
    if not trial:
        return
    events = observations.get("host", [])
    if trial["mode"] == "spiked_chests":
        chests = [e for e in events if e["event"] == "flat_file_native_chest"]
        check(
            "flat_file_native_spiked_and_mimic_chest_trials",
            [len(chests) == 4, len({(e["kind"], e["owned"]) for e in chests}) == 4],
        )
        check(
            "flat_file_opens_spiked_chests_without_damage",
            [
                all(
                    e["opened"]
                    and (e["after"] == e["before"] if e["owned"] else e["after"] < e["before"])
                    for e in chests
                )
            ],
        )
    elif trial["mode"] == "curse_door":
        crossings = [e for e in events if e["event"] == "flat_file_native_curse_door"]
        check(
            "flat_file_crosses_actual_curse_room_door",
            [
                len(crossings) == 1
                and crossings[0]["room"] == crossings[0]["destination"]
                and crossings[0]["room"] != crossings[0]["source"]
            ],
        )
        check(
            "flat_file_curse_door_damage_control",
            [
                len(crossings) == 1
                and crossings[0]["owned"] != trial["control"]
                and (
                    crossings[0]["after"] < crossings[0]["before"]
                    if trial["control"]
                    else crossings[0]["after"] == crossings[0]["before"]
                )
            ],
        )
    elif trial["mode"] in ("angel_door", "hush_door"):
        doors = [e for e in events if e["event"] == "trinket_native_special_door"]
        kills = [e for e in events if e["event"] == "native_bosses_defeated"]
        check(
            "native_boss_defeated_before_special_door",
            [
                bool(kills) and any(e["count"] > 0 for e in kills),
                len(doors) == 1 and doors[0]["clear"],
            ],
        )
        if trial["mode"] == "angel_door":
            check(
                "rosary_bead_turns_guaranteed_devil_room_into_angel_room",
                [
                    len(doors) == 1
                    and doors[0]["owned"]
                    and doors[0]["angel"]
                    and not doors[0]["devil"]
                ],
            )
        else:
            check(
                "strange_key_overrides_hush_time_limit",
                [
                    len(doors) == 1
                    and doors[0]["stage"] == 8
                    and doors[0]["time"] > 30 * 60 * 30
                    and doors[0]["owned"] != trial["control"]
                    and doors[0]["hush"] != trial["control"]
                ],
            )
            if not trial["control"]:
                entered = [e for e in events if e["event"] == "strange_key_hush_entry"]
                check(
                    "strange_key_native_hush_entrance_usable",
                    [len(entered) == 1 and entered[0]["room"] == -8],
                )
    elif trial["mode"] == "awards":
        awards = [e for e in events if e["event"] == "trinket_native_clear_awards"]
        control = next((e for e in awards if not e["owned"]), None)
        held = next((e for e in awards if e["owned"]), None)
        prefix = "90." if trial["reward"] == "batteries" else "20."

        def count(sample, prefix):
            return sum(n for key, n in (sample["drops"] or {}).items() if key.startswith(prefix))

        check(
            "native_clear_award_control_and_held",
            [bool(control and held) and control["count"] == held["count"] == trial["count"]],
        )
        check(
            "trinket_changes_clear_award:" + trial["reward"],
            [bool(control and held) and count(held, prefix) > count(control, prefix)],
        )
        if trial["reward"] == "coins":
            check(
                "rib_of_greed_reduces_heart_awards",
                [bool(control and held) and count(held, "10.") < count(control, "10.")],
            )
    elif trial["mode"] == "challenge":
        samples = [e for e in events if e["event"] == "tattoo_native_challenge"]
        check(
            "tattoo_native_challenge_started_and_completed",
            [
                len(samples) == 1
                and samples[0]["started"]
                and samples[0]["done"]
                and samples[0]["enemies"] > 0
            ],
        )
        if trial["boss"]:
            check(
                "tattoo_boss_challenge_rewards_collectible",
                [
                    any(
                        e["bosses"] >= 2 and any(p["variant"] == 100 for p in e["rewards"])
                        for e in samples
                    )
                ],
            )
        else:
            chest_variants = {50, 51, 52, 53, 54, 55, 56, 57, 58, 60, 360, 390}
            check(
                "tattoo_normal_challenge_rewards_chest",
                [
                    any(
                        e["bosses"] == 0
                        and any(p["variant"] in chest_variants for p in e["rewards"])
                        for e in samples
                    )
                ],
            )
    elif trial["mode"] == "door":
        if trial["reward"] not in {"open", "charge"}:
            controls = [e for e in events if e["event"] == "trinket_locked_door_control"]
            check(
                "native_door_requires_key_without_trinket",
                [
                    len(controls) == 1
                    and controls[0]["keys"] == 0
                    and controls[0]["locked"]
                    and controls[0]["room"] == controls[0]["source"]
                ],
            )
        entries = [e for e in events if e["event"] == "trinket_native_door_entry"]
        check("native_trinket_door_entered", [len(entries) == 1 and entries[0]["keys"] == 0])
        if trial["reward"] == "blue":
            destinations = [e for e in events if e["event"] == "blue_key_native_destination"]
            check(
                "blue_key_enters_hostile_blue_room",
                [len(entries) == 1 and entries[0]["room_type"] == 28 and entries[0]["enemies"] > 0],
            )
            check(
                "blue_key_clear_reaches_original_destination",
                [
                    len(destinations) == 1
                    and destinations[0]["room"] == destinations[0]["target"]
                    and destinations[0]["keys"] == 0
                ],
            )
        elif trial["reward"] == "charge":
            check(
                "hairpin_charges_on_physical_boss_entry",
                [
                    len(entries) == 1
                    and entries[0]["room"] == entries[0]["target"]
                    and entries[0]["room_type"] == 5
                    and entries[0]["enemies"] > 0
                    and entries[0].get("room_updates", 1) > 0
                    and entries[0]["charge_before"] == 0
                    and entries[0]["charge_after"] == entries[0]["max_charge"] > 0
                    and entries[0]["owned"]
                ],
            )
        elif trial["reward"] == "open":
            check(
                "door_stop_keeps_combat_entry_open",
                [
                    len(entries) == 1
                    and entries[0]["room"] == entries[0]["target"]
                    and entries[0]["enemies"] > 0
                    and entries[0]["entry_open"]
                ],
            )
        else:
            check(
                "store_key_enters_native_shop_without_spending_key",
                [
                    len(entries) == 1
                    and entries[0]["room"] == entries[0]["target"]
                    and entries[0]["room_type"] == 2
                ],
            )
    elif trial["mode"] == "donations":
        samples = [e for e in events if e["event"] == "trinket_native_donation"]
        check(
            "native_beggar_donations_spend_coins",
            [
                len(samples) == trial["count"],
                all(e["after"]["coins"] < e["before"]["coins"] for e in samples),
            ],
        )
        if trial["reward"] == "luck":
            check(
                "karma_native_donations_grant_luck",
                [any(e["after"]["luck"] > e["before"]["luck"] for e in samples)],
            )
        else:
            wisp_variant = "206"
            check(
                "beth_essence_native_donations_spawn_wisps",
                [
                    any(
                        (e["after"]["familiars"] or {}).get(wisp_variant, 0)
                        > (e["before"]["familiars"] or {}).get(wisp_variant, 0)
                        for e in samples
                    )
                ],
            )
    elif trial["mode"] == "tick":
        entries = [e for e in events if e["event"] == "tick_boss_entry"]
        check("tick_heals_on_native_boss_entry", [len(entries) == 1 and entries[0]["hearts"] == 4])
        check(
            "tick_reduces_native_boss_health",
            [
                any(
                    e["bosses"] and all(0.83 < b["hp"] / b["max_hp"] < 0.87 for b in e["bosses"])
                    for e in entries
                )
            ],
        )
        dropped = [e for e in events if e["event"] == "tick_drop_attempt"]
        replaced = [e for e in events if e["event"] == "tick_native_replacement"]
        check("tick_cannot_be_dropped_normally", [len(dropped) == 1 and dropped[0]["retained"]])
        check(
            "tick_removed_by_native_replacement",
            [
                len(replaced) == 1
                and all(replaced[0][k] for k in ("removed", "replaced", "consumed"))
            ],
        )
    elif trial["mode"] == "angel_boss":
        statues = [e for e in events if e["event"] == "filigree_native_statues"]
        drops = [e for e in events if e["event"] == "filigree_native_boss_drop"]
        check(
            "native_angel_statue_fight_triggered",
            [
                len(statues) == 1 and statues[0]["count"] > 0,
                len(drops) == 1 and drops[0]["angels"] > 0,
            ],
        )
        rewards = {}
        if drops:
            rewards = {
                k: n - (drops[0]["before"] or {}).get(k, 0)
                for k, n in (drops[0]["after"] or {}).items()
                if k.startswith("100.")
            }
        check(
            "filigree_replaces_key_piece_with_item",
            [
                bool(rewards),
                sum(rewards.values()) >= 1,
                not any(rewards.get(k, 0) > 0 for k in ("100.238", "100.239")),
            ],
        )
    elif trial["mode"] == "devil_deal":
        if trial["reward"] == "magnet":
            rooms = [e for e in events if e["event"] == "trinket_generated_devil_deals"]
            check(
                "number_magnet_generates_enhanced_native_devil_room",
                [len(rooms) == 1 and rooms[0].get("subtype") == DEVIL_NUMBER_MAGNET_SUBTYPE],
            )
            chances = [e for e in events if e["event"] == "trinket_magnet_deal_chance"]
            control = next((e for e in chances if not e["owned"]), None)
            held = next((e for e in chances if e["owned"]), None)
            check(
                "number_magnet_adds_ten_percent_deal_chance",
                [bool(control and held) and abs(held["chance"] - control["chance"] - 0.1) < 0.0001],
            )
        else:
            if trial["reward"] in ("tongue", "coins"):
                prices = [e for e in events if e["event"] == "trinket_native_deal_prices"]
                control = next((e for e in prices if not e["owned"]), None)
                held = next((e for e in prices if e["owned"]), None)
                check(
                    "native_devil_prices_have_control_and_holder",
                    [bool(control and held) and bool(control["prices"]) and bool(held["prices"])],
                )
                if control and held:
                    if trial["reward"] == "tongue":
                        check(
                            "judas_tongue_reduces_two_heart_deal",
                            [
                                all(p == -2 for p in control["prices"]),
                                all(p == -1 for p in held["prices"]),
                            ],
                        )
                    else:
                        check(
                            "keeper_bargain_converts_native_heart_price_to_coins",
                            [
                                all(p < 0 for p in control["prices"]),
                                any(p > 0 for p in held["prices"]),
                            ],
                        )
            purchases = [e for e in events if e["event"] == "trinket_native_deal_purchase"]
            valid = len(purchases) == 1 and purchases[0]["found"]
            check(
                "native_devil_item_purchased",
                [
                    valid
                    and (
                        purchases[0].get("acquired", False)
                        or purchases[0]["after"]["owned"] > purchases[0]["before"]["owned"]
                    )
                ],
            )
            if valid:
                before, after = purchases[0]["before"], purchases[0]["after"]
                if trial["reward"] == "free":
                    check(
                        "your_soul_consumed_without_health_or_coin_cost",
                        [
                            not purchases[0]["trinket"],
                            before["hearts"] == after["hearts"],
                            before["coins"] == after["coins"],
                        ],
                    )
                elif trial["reward"] == "coins":
                    check(
                        "keeper_bargain_purchase_uses_coins",
                        [
                            before["hearts"] == after["hearts"],
                            before["coins"] - after["coins"] == before["price"] > 0,
                        ],
                    )
                else:
                    check(
                        "judas_tongue_purchase_costs_one_heart",
                        [before["hearts"] - after["hearts"] == 2],
                    )
    elif trial["mode"] == "floor_room":
        samples = [e for e in events if e["event"] == "trinket_native_treasure_room"]
        check("native_treasure_room_observed", [len(samples) == 1])
        if trial["reward"] == "restock":
            check(
                "pay_to_win_spawns_native_restock_machine",
                [any(e["machines"] > 0 for e in samples)],
            )
        else:
            check(
                "devils_crown_changes_treasure_to_deals",
                [any(e["prices"] and all(p < 0 for p in e["prices"]) for e in samples)],
            )
    elif trial["mode"] == "floor_series":
        samples = [e for e in events if e["event"] == "trinket_native_floor_room"]
        check("trinket_native_floor_sample_count", [len(samples) == trial["count"]])
        check(
            "trinket_native_floor_sample_ownership",
            [
                e["owned"] == (i < trial.get("held_count", trial["count"]))
                for i, e in enumerate(samples)
            ],
        )
        check(
            "trinket_distinct_native_floor_seeds",
            [len({e["seed"] for e in samples}) == trial["count"]],
        )
        if trial["reward"] == "greed":
            check(
                "rib_of_greed_native_control_spawns_greed",
                [any(not e["owned"] and e["greeds"] > 0 for e in samples)],
            )
            check(
                "rib_of_greed_prevents_native_greed",
                [all(e["greeds"] == 0 for e in samples if e["owned"])],
            )
        elif trial["reward"] == "replace_resources":
            replacements = [
                e["replacements"] for e in samples if e["stage"] >= 7 and e["replacements"]
            ]
            check(
                "nuh_uh_replaces_womb_coins_and_keys",
                [
                    any(
                        e.get("control", {}).get("coins", 0) > 0
                        and e.get("control", {}).get("keys", 0) > 0
                        and e.get("held", {}).get("coins", -1) == 0
                        and e.get("held", {}).get("keys", -1) == 0
                        and e.get("held", {}).get("other", 0) > 0
                        and e.get("held", {}).get("other", 0) + e.get("held", {}).get("removed", 0)
                        == 256
                        for e in replacements
                    )
                ],
            )
        else:
            check(
                "native_extra_treasure_choice",
                [
                    any(
                        len(e["items"]) >= 2
                        and len({p["options"] for p in e["items"]}) == 1
                        and e["items"][0]["options"] > 0
                        for e in samples
                    )
                ],
            )
            choices = [e for e in events if e["event"] == "trinket_native_floor_choice"]
            option_seeds = {e["seed"] for e in samples if len(e["items"]) >= 2}
            check(
                "native_treasure_choice_acquires_one_and_removes_alternative",
                [
                    any(
                        e["seed"] in option_seeds
                        and e["acquired"]
                        and e["consumed"]
                        and e["remaining"] == 0
                        for e in choices
                    )
                ],
            )
    elif trial["mode"] == "pandora":
        values = [e for e in events if e["event"] == "strange_key_pandora"]

        def pedestals(counts):
            return sum(n for key, n in (counts or {}).items() if key.startswith("100."))

        check(
            "strange_key_consumed_for_six_pandora_items",
            [
                len(values) == 1
                and values[0]["consumed"]
                and pedestals(values[0]["after"]) - pedestals(values[0]["before"]) == 6
            ],
        )
    elif trial["mode"] == "myosotis":
        initial = [e for e in events if e["event"] == "myosotis_left_behind"]
        carried = [e for e in events if e["event"] == "myosotis_floor_carry"]
        collected = [e for e in events if e["event"] == "myosotis_collected"]
        check(
            "myosotis_native_uncollected_pickups",
            [len(initial) == 1 and initial[0]["drops"].get("20.3") == 4],
        )
        check(
            "myosotis_carries_only_remaining_pickups_across_floors",
            [
                len(carried) == 2
                and carried[0]["drops"].get("20.3") == 4
                and carried[1]["drops"].get("20.3") == 3
                and carried[1]["stage"] == carried[0]["stage"] + 1
            ],
        )
        check(
            "myosotis_actual_pickup_consumption",
            [len(collected) == 1 and collected[0]["consumed"] and collected[0]["gain"] == 10],
        )
    elif trial["mode"] == "locust":
        samples = [e for e in events if e["event"] == "trinket_locust_state"]
        check(
            "native_locust_familiar_spawned",
            [
                any(
                    any(
                        f["subtype"] == trial["subtype"] if "subtype" in trial else f["subtype"] > 0
                        for f in e["flies"]
                    )
                    for e in samples
                )
            ],
        )
        if not trial.get("kills"):
            hits = [
                e
                for e in events
                if e["event"] == "native_locust_damage" and e["subtype"] == trial["subtype"]
            ]
            contacts = {}
            for hit in hits:
                key = (hit["tick"], hit["source_seed"], hit["target_seed"])
                contacts.setdefault(key, []).append(hit)
            check(
                "native_locust_contact_damage",
                [
                    any(
                        len(contact) == trial.get("contact_hits", 1)
                        and abs(
                            sum(e["amount"] for e in contact)
                            - contact[0]["holder_damage"] * trial["multiplier"]
                        )
                        < 0.01
                        for contact in contacts.values()
                    )
                ],
            )
            for flag in trial["flags"]:
                check(
                    "native_locust_status:" + flag,
                    [any((e["flags"] or {}).get(flag) for e in samples)],
                )
    elif trial["mode"] in {"flies", "tear_probability", "effect_size", "enemy_attraction"}:
        event = {
            "flies": "trinket_controlled_spawn",
            "tear_probability": "trinket_controlled_spawn",
            "effect_size": "trinket_effect_size",
            "enemy_attraction": "trinket_enemy_attraction",
        }[trial["mode"]]
        samples = [e for e in events if e["event"] == event]
        before = next((e for e in samples if e["phase"] == "control"), None)
        after = next((e for e in samples if e["phase"] == "held"), None)
        check("trinket_native_control_and_holder", [before is not None and after is not None])
        if not before or not after:
            return
        check("trinket_native_trial_ownership", [not before["owned"], after["owned"]])
        if trial["mode"] == "flies":
            check(
                "fish_tail_doubles_native_fly_spawn",
                [
                    before["after"] - before["before"] == 1,
                    after["after"] - after["before"] == 2,
                ],
            )
        elif trial["mode"] == "tear_probability":
            check(
                "teardrop_increases_teeth_without_luck_change",
                [
                    before["luck"] == after["luck"],
                    min(before["count"], after["count"]) >= trial.get("minimum_shots", 200),
                    0 < before["teeth"] < before["count"] * 0.5,
                    after["teeth"] >= after["count"] * 0.9,
                ],
            )
        elif trial["mode"] == "effect_size":
            check(
                "trinket_increases_native_effect_size",
                [
                    before["count"] > 0,
                    after["count"] > 0,
                    any(after[k] > before[k] * 1.1 for k in ("scale", "sprite", "size")),
                ],
            )
        else:
            check(
                "super_magnet_attracts_stationary_enemy",
                [
                    abs(before["distance"] - before["initial"]) < 5,
                    after["distance"] < after["initial"] - 20,
                ],
            )
    elif trial["mode"] == "shiny_rock":
        samples = [e for e in events if e["event"] == "shiny_rock_color"]
        for kind in ("tinted", "normal"):
            colors = {tuple(e["color"]) for e in samples if e["kind"] == kind}
            check(
                "shiny_rock_flashes:" + kind,
                [len(colors) >= 2 if kind == "tinted" else len(colors) == 1],
            )
    elif trial["mode"] == "hearts":
        samples = [e for e in events if e["event"] == "trinket_native_result"]
        check(
            "apple_full_health_trials",
            [
                len(samples) == trial["count"],
                all(e["before"]["hearts"] == e["after"]["hearts"] for e in samples),
            ],
        )
        check(
            "apple_converts_native_red_hearts_to_spiders",
            [
                any(
                    e["consumed"] and e["after"]["spiders"] > e["before"]["spiders"]
                    for e in samples
                )
            ],
        )
    elif trial["mode"] == "bomb_drops":
        samples = [e for e in events if e["event"] == "trinket_bomb_drops"]
        check(
            "bombs_actually_explode",
            [len(samples) == trial["count"], all(e["exploded"] for e in samples)],
        )
        check(
            "native_bomb_button_consumes_ammunition",
            [all(e.get("placed") and e.get("owned") and e.get("ammo_spent") == 1 for e in samples)],
        )
        check(
            "blasting_cap_native_bomb_pickup",
            [
                any(
                    any(k.startswith("40.") and n > 0 for k, n in (e["drops"] or {}).items())
                    for e in samples
                )
            ],
        )
    elif trial["mode"] == "turning_tears":
        tracks = {}
        for e in probes:
            for tear in e.get("tears", []):
                tracks.setdefault(tear["seed"], []).append(tear)
        check(
            "brain_worm_turns_fired_tear_ninety_degrees",
            [
                any(
                    any(abs(t["vx"]) < 1 and abs(t["vy"]) > 3 for t in track)
                    and any(abs(t["vy"]) < 1 and abs(t["vx"]) > 3 for t in track)
                    for track in tracks.values()
                )
            ],
        )
    elif trial["mode"] in {"expansion", "endless"}:
        uses = [e for e in events if e["event"] == "trinket_triggered_use"]
        check("trinket_native_actions_owned_by_holder", [e["correct_actor"] for e in uses])
        check(
            "replica_does_not_trigger_trinket_actions",
            [
                not any(
                    e["event"] == "trinket_triggered_use" for e in observations.get("client", [])
                )
            ],
        )
        if trial["mode"] == "expansion":
            normal = [e for e in uses if e["kind"] == "collectible" and e["id"] == 105]
            extra = [e for e in uses if e["kind"] == "collectible" and e["id"] != 105]
            check(
                "expansion_native_normal_uses",
                [trial["minimum_uses"] <= len(normal) <= trial["count"]],
            )
            check(
                "expansion_triggers_additional_active",
                [
                    bool(normal)
                    and all(any(e["tick"] == use["tick"] for e in extra) for use in normal),
                    bool(extra) and all(e.get("max_charges") in (1, 2) for e in extra),
                    all(any(use["tick"] == e["tick"] for use in normal) for e in extra),
                ],
            )
        else:
            copies = [e for e in events if e["event"] == "trinket_consumable_copy"]
            check(
                "endless_native_consumable_uses",
                [len(uses) >= trial["count"], len(copies) == trial["count"]],
            )
            for kind in ("card", "pill", "rune"):
                check(
                    "endless_spawns_used_consumable:" + kind,
                    [any(e["kind"] == kind and e["copies"] > 0 for e in copies)],
                )
    elif trial["mode"] == "toenail":
        prerequisites = [e for e in events if e["event"] == "toenail_hostile_prerequisite"]
        check(
            "toenail_dropped_during_combat",
            [
                len(prerequisites) == 1
                and not prerequisites[0]["clear"]
                and prerequisites[0]["enemies"] > 0
            ],
        )
        check(
            "toenail_native_drop_observed",
            [
                any(
                    e["trinket"] == 0
                    and any(p["variant"] == 350 and p["subtype"] == 16 for p in e["pickups"])
                    for e in probes
                    if e["tick"] >= 90
                )
            ],
        )
        check(
            "toenail_native_foot_stomp",
            [
                any(
                    e["effects"].get("MOM_FOOT_STOMP", 0) > 0
                    or any(k.startswith("45.") for k in e["spawned"])
                    for e in probes
                    if e["tick"] >= 90
                )
            ],
        )
    elif trial["mode"] == "candy":
        baseline = next((e for e in probes if e["label"] == "before"), None)
        check(
            "candy_natively_farts_or_spawns_poop",
            [
                baseline is not None
                and any(
                    e["effects"].get("FART", 0) > 0 or e["poop_count"] > baseline["poop_count"]
                    for e in probes
                    if e["tick"] >= 900
                )
            ],
        )
    elif trial["mode"] == "troll_bombs":
        samples = [e for e in events if e["event"] == "trinket_troll_bombs"]
        before = next((e for e in samples if e["phase"] == "control"), None)
        after = next((e for e in samples if e["phase"] == "held"), None)
        check("troll_bomb_control_and_holder", [before is not None and after is not None])
        if before and after:
            check(
                "scissors_convert_native_troll_bombs",
                [
                    not before["owned"],
                    after["owned"],
                    before["bombs"] == 2,
                    after["bombs"] == 0,
                    sum(n for k, n in (after["pickups"] or {}).items() if k.startswith("40.")) >= 2,
                ],
            )
    elif trial["mode"] == "shop":
        shops = [e for e in events if e["event"] == "trinket_native_shop"]
        check(
            "native_shop_with_trinket",
            [len(shops) == 1 and shops[0]["owned"] and bool(shops[0]["shelf"])],
        )
        if trial["reward"] == "credit":
            sales = [e for e in events if e["event"] == "trinket_shop_purchase"]
            check(
                "store_credit_buys_native_shop_item_free",
                [
                    len(sales) == 1
                    and sales[0]["found"]
                    and sales[0]["acquired"]
                    and not sales[0]["owned"]
                    and sales[0]["coins_before"] == sales[0]["coins_after"] == 0
                ],
            )
        else:
            check(
                "adoption_shop_familiars_at_discount",
                [
                    bool(shops)
                    and all(
                        p["familiar"] and 0 < p["price"] <= 10 for e in shops for p in e["shelf"]
                    )
                ],
            )
    elif trial["mode"] == "locked_chest":
        samples = [e for e in events if e["event"] == "trinket_locked_chest"]
        before = next((e for e in samples if e["phase"] == "control"), None)
        after = next((e for e in samples if e["phase"] == "held"), None)
        check("locked_chest_control_and_holder", [before is not None and after is not None])
        if before and after:
            check(
                "native_chest_unlocks_without_key",
                [
                    not before["owned"],
                    after["owned"],
                    not before["opened"],
                    after["opened"],
                    before["keys"] == after["keys"] == 0,
                ],
            )
    elif trial["mode"] in {"champions", "champion_floors"}:
        samples = [e for e in events if e["event"] == "native_champion_rooms"]
        before = next((e for e in samples if e["phase"] == "control"), None)
        after = next((e for e in samples if e["phase"] == "held"), None)
        check("native_champion_control_and_holder", [before is not None and after is not None])
        if before and after:
            check("native_champion_trial_ownership", [not before["owned"], after["owned"]])
            check(
                "native_room_enemy_population",
                [
                    e["total"] >= 64 and e["respawns"] >= 24
                    if trial["mode"] == "champion_floors"
                    else e["total"] >= trial["count"] and e["respawns"] == trial["count"]
                    for e in (before, after)
                ],
            )
            check(
                "holder_increases_native_champion_fraction",
                [after["champions"] * before["total"] > before["champions"] * after["total"]],
            )
    elif trial["mode"] in {"cooldown", "poison_duration"}:
        event = "trinket_" + trial["mode"]
        samples = [e for e in events if e["event"] == event]
        before = next((e for e in samples if e["phase"] == "control"), None)
        after = next((e for e in samples if e["phase"] == "held"), None)
        check("trinket_duration_control_and_held", [before is not None and after is not None])
        if not before or not after:
            return
        if trial["mode"] == "cooldown":
            check(
                "actual_damage_starts_cooldown",
                [e["accepted"] and e["after"] < e["before"] for e in (before, after)],
            )
            check(
                "blind_rage_doubles_native_cooldown",
                [before["cooldown"] > 0, abs(after["cooldown"] - before["cooldown"] * 2) <= 2],
            )
        else:
            valid = all(
                e.get("first") is not None
                and e.get("last") is not None
                and e["damage"] > 0
                and e["expired"]
                for e in (before, after)
            )
            check("poison_hit_and_natural_expiry", [valid])
            if valid:
                baseline = before["last"] - before["first"]
                changed = after["last"] - after["first"]
                check(
                    "second_hand_doubles_poison_duration", [baseline > 0, changed >= baseline * 1.8]
                )
    elif trial["mode"] == "floor":
        samples = [e for e in events if e["event"] == "trinket_floor"]
        before = next((e for e in samples if e["phase"] == "control"), None)
        after = next((e for e in samples if e["phase"] == "held"), None)
        check("floor_trinket_control_and_held", [before is not None and after is not None])
        if not before or not after:
            return
        check(
            "floor_trinket_same_native_stage",
            [before["stage"] == after["stage"], before["stage_type"] == after["stage_type"]],
        )
        check("floor_trinket_ownership", [not before["owned"], after["owned"]])
        for room, minimum in trial.get("rooms", {}).items():
            initial, changed = (
                (before["counts"] or {}).get(room, 0),
                (after["counts"] or {}).get(room, 0),
            )
            check("native_floor_extra_room:" + room, [changed >= minimum, changed > initial])
        if trial.get("icons"):
            check("cains_eye_reveals_floor_icons", [after["icons"] > before["icons"]])
    elif trial["mode"] == "rooms":
        samples = [e for e in events if e["event"] == "trinket_room_state"]
        entered = [e for e in samples if e["phase"] == "entered"]
        cleared = [e for e in samples if e["phase"] == "cleared"]
        check(
            "room_trinket_observation_count",
            [len(entered) == trial["count"], len(cleared) == trial["count"]],
        )
        reward = trial["reward"]
        if reward == "watch_charge":
            kills = [e for e in events if e["event"] == "native_entry_clear"]
            combat = [
                after
                for before, kill, after in zip(entered, kills, cleared)
                if before["alive"] > 0
                and before["charge"] == 0
                and kill["killed"] > 0
                and after["clear"]
                and after["alive"] == 0
            ]
            check(
                "watch_battery_real_repeated_combat_clears",
                [
                    len(kills) == trial["count"],
                    len(combat) >= trial.get("minimum_clears", trial["count"]),
                ],
            )
            check(
                "watch_battery_adds_extra_charge_to_normal_clear",
                [any(e["charge"] == 1 for e in combat), any(e["charge"] == 2 for e in combat)],
            )
        elif reward == "temporary":
            check(
                "native_room_grants_temporary_effect",
                [any(e["collectible_effects"] or e["trinket_effects"] for e in entered)],
            )
        elif reward == "pocket":
            check("dice_bag_grants_pocket_die", [any(e["pocket"] > 0 for e in entered)])
            granted = {e["pocket"] for e in entered if e["pocket"] > 0}
            uses = [e for e in events if e["event"] == "trinket_triggered_use"]
            check(
                "dice_bag_single_use_die_activated",
                [
                    any(
                        e["kind"] == "collectible" and e["id"] in granted and e["correct_actor"]
                        for e in uses
                    )
                ],
            )
            check(
                "dice_bag_die_disappears_after_use",
                [any(a["pocket"] > 0 and b["pocket"] == 0 for a, b in zip(entered, cleared))],
            )
        elif reward == "hearts":
            check(
                "room_clear_heals_holder",
                [any(b["hearts"] > a["hearts"] for a, b in zip(entered, cleared))],
            )
        elif reward == "aaa":
            check(
                "five_room_clears_charge_six_charge_item",
                [bool(cleared) and cleared[-1]["charge"] == 6],
            )
        elif reward == "capacitor":
            check("capacitor_prevents_clear_charge", [e["charge"] == 0 for e in cleared])
            check(
                "capacitor_drops_battery",
                [any(any(k.startswith("90.") for k in (e["pickups"] or {})) for e in cleared)],
            )
        elif reward in {"burn", "petrify"}:
            # Native enemy flag checks and replicated health are performed by the shared checks.
            pass
        else:
            check("native_room_reward:" + reward, [any(e[reward] > 0 for e in samples)])
    elif trial["mode"] in {"guppy", "planetarium"}:
        conditions = [e for e in events if e["event"] == "trinket_condition"]
        before = next((e for e in conditions if e["phase"] == "control"), None)
        after = next((e for e in conditions if e["phase"] == "held"), None)
        valid = before is not None and after is not None
        check("trinket_condition_observed", [valid])
        if valid:
            if trial["mode"] == "guppy":
                check(
                    "trinket_completes_guppy_transformation", [not before["guppy"], after["guppy"]]
                )
            else:
                check(
                    "lens_increases_native_planetarium_chance", [after["chance"] > before["chance"]]
                )
    elif trial["mode"] == "rainbow":
        flags = {flag for e in probes if e["tick"] >= 90 for t in e["tears"] for flag in t["flags"]}
        worms = {
            "TEAR_WIGGLE",
            "TEAR_SPIRAL",
            "TEAR_BIG_SPIRAL",
            "TEAR_FLAT",
            "TEAR_SQUARE",
            "TEAR_PULSE",
        }
        check("rainbow_cycles_native_tear_effects", [len(flags & worms) >= 2])
    elif trial["mode"] == "active":
        baseline = next((e for e in probes if e["label"] == "before"), None)
        after = [e for e in probes if e["tick"] >= 120]
        check("trinket_active_prerequisite", [baseline is not None and bool(after)])
        if not baseline or not after:
            return
        effect = trial["effect"]
        if effect == "teleport":
            check(
                "active_use_triggers_remote_teleport",
                [any(e["room"] != baseline["room"] for e in after)],
            )
        elif effect == "drop":
            # The consumed-active fixture installs an empty D6 at tick 120;
            # observe the real drop before that independent discharge check.
            dropped = [e for e in probes if 90 <= e["tick"] < 120]
            check(
                "butter_drops_held_active",
                [
                    any(
                        e["active_item"] == "COLLECTIBLE_NULL"
                        and any(p["enum"] == baseline["active_item"] for p in e["pedestals"])
                        for e in dropped
                    )
                ],
            )
        elif effect == "reroll":
            check(
                "m_rerolls_held_active",
                [
                    any(
                        e["active_item"] not in {"COLLECTIBLE_NULL", baseline["active_item"]}
                        for e in after
                    )
                ],
            )
        elif effect == "panic":
            check(
                "panic_uses_and_discharges_active",
                [any(e["charge"] == 0 and e["invincible"] for e in after)],
            )
    elif trial["mode"] == "tear_control":
        control = [t for e in probes if 90 <= e["tick"] <= 150 for t in e["tears"]]
        held = [t for e in probes if 300 <= e["tick"] <= 480 for t in e["tears"]]
        check("trinket_native_tear_control", [bool(control), bool(held)])
        if not control or not held:
            return
        if trial["effect"] in {"flat", "knockback"}:
            impacts = [e for e in events if e["event"] == "trinket_knockback_result"]
            baseline = next((e for e in impacts if e["phase"] == "control"), None)
            changed = next((e for e in impacts if e["phase"] == "held"), None)
            check(
                "flat_worm_preserves_native_collision"
                if trial["effect"] == "flat"
                else "trinket_increases_native_knockback",
                [
                    baseline is not None
                    and changed is not None
                    and baseline["damage"] > 0
                    and changed["damage"] > 0
                    and changed["velocity"]
                    > baseline["velocity"] * (0.99 if trial["effect"] == "flat" else 1.05)
                ],
            )
        if trial["effect"] == "pulse":
            span = lambda values: max(t["scale"] for t in values) - min(t["scale"] for t in values)
            check("trinket_native_tears_pulsate", [span(held) > span(control) + 0.01])
    elif trial["mode"] == "grid":
        samples = [e for e in events if e["event"] == "trinket_grid_loot"]
        before = next((e for e in samples if e["phase"] == "control"), None)
        after = next((e for e in samples if e["phase"] == "held"), None)
        check("native_grid_control_and_held", [before is not None and after is not None])
        if not before or not after:
            return
        check("native_grids_destroyed", [e["destroyed"] == trial["count"] for e in (before, after)])
        check("native_grid_trial_ownership", [not before["owned"], after["owned"]])
        reward = trial["reward"]
        if reward in {"pickups", "coins"}:

            def count(e):
                return sum(
                    n
                    for k, n in (e["drops"] or {}).items()
                    if reward == "pickups" or k.startswith("20.")
                )

            check("trinket_changes_native_grid_loot", [count(after) > count(before)])
        elif reward == "explosion":
            check(
                "destroyed_poop_explodes_and_hurts_enemy",
                [before["enemy_damage"] == 0, after["enemy_damage"] >= 100],
            )
        else:
            check("trinket_grid_effect:" + reward, [after[reward] > before[reward]])
            if reward == "black_poop":
                check(
                    "meconium_destroyed_black_poop_drops_black_hearts",
                    [
                        (after["drops"] or {}).get("10.6", 0)
                        > (before["drops"] or {}).get("10.6", 0)
                    ],
                )
    elif trial["mode"] == "loot":
        samples = [e for e in events if e["event"] == "trinket_loot"]
        before = next((e for e in samples if e["phase"] == "control"), None)
        after = next((e for e in samples if e["phase"] == "held"), None)
        check("native_chest_control_and_held", [before is not None and after is not None])
        if not before or not after:
            return
        check(
            "native_chests_opened", [e["opened"] >= trial["count"] * 0.9 for e in (before, after)]
        )
        check("trinket_loot_ownership", [not before["owned"], after["owned"]])
        if trial.get("poker"):
            check(
                "poker_chip_empty_or_fly_outcomes",
                [after["empty"] > before["empty"] or after["flies"] > before["flies"]],
            )
        else:

            def drops(e):
                return sum(
                    n for k, n in (e["drops"] or {}).items() if k.startswith(trial["prefix"])
                )

            check("native_chest_bonus:" + trial["prefix"], [drops(after) > drops(before)])
    elif trial["mode"] == "generation":
        values = [e for e in events if e["event"] == "trinket_generation"]
        before = next((e for e in values if e["phase"] == "control"), None)
        after = next((e for e in values if e["phase"] == "held"), None)
        check("trinket_generation_control", [before is not None and not before["owned"]])
        check("trinket_generation_holder", [after is not None and after["owned"]])
        if not before or not after:
            return
        check(
            "trinket_generation_sample_size",
            [sum((e["counts"] or {}).values()) == trial["count"] for e in (before, after)],
        )
        if trial.get("reject_actives"):
            check("trinket_excludes_active_items", [before["active"] > 0, after["active"] == 0])
        else:
            targets = trial["target"]
            if isinstance(targets, str):
                targets = [targets]
            initial = sum((before["counts"] or {}).get(t, 0) for t in targets)
            changed = sum((after["counts"] or {}).get(t, 0) for t in targets)
            if trial["all_match"] == "absent":
                check("trinket_replaces_target_pickups", [initial > 0, changed == 0])
            elif trial["all_match"]:
                # Old/Mega chests and non-chest grab bags are not replaced.
                exempt = sum((after["counts"] or {}).get(t, 0) for t in trial.get("exempt", []))
                exempt += sum(
                    n
                    for k, n in (after["counts"] or {}).items()
                    if int(k.split(".")[0]) in trial.get("exempt_variants", [])
                )
                check(
                    "trinket_converts_pickup_generation",
                    [initial < trial["count"], changed + exempt == trial["count"]],
                )
            else:
                check("trinket_changes_native_distribution", [changed > initial])
        if not trial.get("pool"):
            # Spawn() returns before native pickup initialization settles. Compare
            # the retained examples that still exist on the authority afterwards.
            client = [
                e
                for e in observations.get("client", [])
                if e["event"] == "trigger_probe" and 210 <= e["tick"] <= 270
            ]
            expected = {e["seed"]: e for e in after["examples"]}
            settled = [
                [p for p in e["pickups"] if p["seed"] in expected]
                for e in events
                if e["event"] == "trigger_probe" and 210 <= e["tick"] <= 270
            ]
            check(
                "replica:trinket_generated_pickups",
                [
                    bool(expected),
                    any(
                        samples
                        and all(
                            any(
                                p["seed"] == sample["seed"]
                                and p["variant"] == sample["variant"]
                                and p["subtype"] == sample["subtype"]
                                for p in e["pickups"]
                            )
                            for sample in samples
                        )
                        for samples in settled
                        for e in client
                    ),
                ],
            )
    elif trial["mode"] == "damage":
        values = [e for e in events if e["event"] == "trinket_native_result"]
        check(
            "trinket_native_hit_trials",
            [len(values) == trial["count"], any(e.get("accepted") for e in values)],
        )
        reward = trial["reward"]

        def count(state, prefix):
            return sum(n for k, n in (state["pickups"] or {}).items() if k.startswith(prefix))

        def removed(e):
            return e["before"]["trinket"] != 0 and e["after"]["trinket"] == 0

        if reward == "paper":
            check("mysterious_paper_native_shield", [any(e["after"]["invincible"] for e in values)])
            check(
                "mysterious_paper_native_damage",
                [any(e["before"]["enemy_health"] > e["after"]["enemy_health"] for e in values)],
            )
        elif reward == "dice":
            uses = [e for e in events if e["event"] == "trinket_triggered_use"]
            check(
                "cracked_dice_native_reroll_actions",
                [
                    bool(uses),
                    all(e["id"] in (105, 406, 285, 386, 166) and e["correct_actor"] for e in uses),
                ],
            )
        elif reward in {"pedestal", "lunch", "monkey_paw", "walnut"}:
            prefix = {
                "pedestal": "100.",
                "lunch": "100.22",
                "monkey_paw": "10.6",
                "walnut": "350.",
            }[reward]
            check(
                "trinket_damage_reward:" + reward,
                [any(count(e["after"], prefix) > count(e["before"], prefix) for e in values)],
            )
            check("trinket_reward_consumes_item", [any(removed(e) for e in values)])
            if reward == "monkey_paw":
                check(
                    "monkey_paw_three_charges",
                    [
                        sum(count(e["after"], prefix) - count(e["before"], prefix) for e in values)
                        == 3
                    ],
                )
            if reward == "walnut":
                for prefix in ("10.", "20.", "30."):
                    check(
                        "walnut_reward:" + prefix,
                        [
                            any(
                                count(e["after"], prefix) > count(e["before"], prefix)
                                for e in values
                            )
                        ],
                    )
        elif reward == "red_first":
            check(
                "red_hearts_protect_soul_hearts",
                [
                    e["before"]["soul"] > 0
                    and e["after"]["hearts"] == e["before"]["hearts"] - 1
                    and e["after"]["soul"] == e["before"]["soul"]
                    for e in values
                ],
            )
        elif reward in {"invincible", "room", "bone"}:
            check(
                "trinket_damage_reward:" + reward,
                [
                    any(
                        e["after"][reward] > e["before"][reward]
                        if reward != "room"
                        else e["after"][reward] != e["before"][reward]
                        for e in values
                    )
                ],
            )
        elif reward == "destroyed":
            check(
                "perfection_luck_before_hit", [bool(values) and values[0]["before"]["luck"] >= 10]
            )
            check("perfection_destroyed_by_hit", [bool(values) and removed(values[0])])
        elif reward == "tonsil":
            # FamiliarVariant.TONSIL is exported by the fixture with the count.
            check("tonsil_spawns_two_blockers", [any(e.get("tonsils", 0) == 2 for e in values)])
            check("tonsil_consumed", [any(removed(e) for e in values)])
        elif reward == "resources":
            check(
                "torn_pocket_resource_loss",
                [
                    sum(e["before"][k] - e["immediate"][k] for k in ("coins", "keys", "bombs")) == 2
                    for e in values
                ],
            )
            check(
                "torn_pocket_drops_resources",
                [
                    any(
                        sum(count(e["after"], k) for k in ("20.", "30.", "40."))
                        > sum(count(e["before"], k) for k in ("20.", "30.", "40."))
                        for e in values
                    )
                ],
            )
        elif reward == "passive_drop":
            check(
                "butter_damage_drops_an_owned_passive",
                [
                    any(
                        e.get("lost_passives")
                        and any(
                            (e["after"]["pickups"] or {}).get("100." + str(item), 0) > 0
                            for item in e["lost_passives"]
                        )
                        for e in values
                    )
                ],
            )
        elif reward in {"enemy_damage", "explosion"}:
            check(
                "trinket_hit_hurts_enemy",
                [any(e["before"]["enemy_health"] > e["after"]["enemy_health"] for e in values)],
            )
            if reward == "explosion":
                check("native_damage_explosion", [any(e.get("explosions", 0) for e in values)])
    elif trial["mode"] == "coins":
        values = [e for e in events if e["event"] == "trinket_native_result"]
        check(
            "trinket_physical_coin_pickups",
            [len(values) == trial["count"], all(e["consumed"] for e in values)],
        )
        reward = trial["reward"]
        if reward in {"coins", "flies", "charge"}:
            check(
                "trinket_coin_reward:" + reward,
                [
                    any(
                        e["after"][reward] > e["before"][reward] + (1 if reward == "coins" else 0)
                        for e in values
                    )
                ],
            )
        elif reward == "room":
            check(
                "trinket_coin_teleport",
                [any(e["after"]["room"] != e["before"]["room"] for e in values)],
            )
        elif reward != "poison":

            def count(value):
                return sum(
                    n for key, n in (value["pickups"] or {}).items() if key.startswith(reward)
                )

            check(
                "trinket_coin_reward:" + reward,
                [any(count(e["after"]) > count(e["before"]) for e in values)],
            )
