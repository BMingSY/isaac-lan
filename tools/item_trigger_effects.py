"""Focused native triggers for effects outside the original stat-only trials."""

from item_room_effects import required_flags
from item_interaction_effects import (
    DEAL_REWARD_SETTLE_TICKS,
    INTERACTION_EFFECTS,
    interaction_checks,
)
from item_projectile_effects import PROJECTILE_EFFECTS, projectile_checks
from item_trinket_effects import TRINKET_EFFECTS, trinket_checks
from item_birthright_effects import BIRTHRIGHT_SCENARIOS, birthright_checks

TRIGGER_EFFECTS = {
    "PILLEFFECT_SEE_FOREVER": {"secret_doors": True, "horse": {"map": "full"}},
    "PILLEFFECT_RETRO_VISION": {
        "visual_review": "pixelation_and_expiry",
        "end_tick": 1080,
        "horse": {"end_tick": 2880},
    },
    "CARD_RULES": {"visual_review": "fortune_text", "end_tick": 240},
    "PILLEFFECT_IM_DROWSY": {
        "enemies": 1,
        "movement_rate": -1,
        "rate_lifecycle": True,
        "end_tick": 690,
        "horse": {"rate_persists_room": True},
    },
    "PILLEFFECT_IM_EXCITED": {
        "enemies": 1,
        "movement_rate": 1,
        "rate_recurrence": True,
        "end_tick": 2100,
        "horse": {
            "rate_recurrence": False,
            "rate_lifecycle": True,
            "rate_persists_room": True,
            "end_tick": 690,
        },
    },
    "PILLEFFECT_BAD_GAS": {"enemies": 2, "enemy_flags": ["FLAG_POISON"]},
    "PILLEFFECT_BAD_TRIP": {"delta": {"hearts": -2}, "horse": {"delta": {"hearts": -4}}},
    "PILLEFFECT_EXPLOSIVE_DIARRHEA": {
        "spawns": {"4.": [5, 5]},
        "horse": {"spawns": {"4.": [8, 8]}},
    },
    "PILLEFFECT_PRETTY_FLY": {
        "familiars": {"FLY_ORBITAL": 1},
        "horse": {"familiars": {"BIG_FAN": 1}},
    },
    "PILLEFFECT_48HOUR_ENERGY": {
        "empty_active": True,
        "charged": True,
        "spawns": {"5.90.": [1, 2]},
        "horse": {"spawns": {"5.90.": [3, 4]}},
    },
    "PILLEFFECT_PHEROMONES": {
        "enemies": 2,
        "enemy_flags": ["FLAG_CHARM"],
        "horse": {"enemy_flags": ["FLAG_FRIENDLY"]},
    },
    "PILLEFFECT_LEMON_PARTY": {
        "enemies": 2,
        "effects": ["PLAYER_CREEP_LEMON_PARTY"],
        "enemy_hurt": True,
    },
    "PILLEFFECT_INFESTED_EXCLAMATION": {
        "poops": 2,
        "familiars": {"BLUE_SPIDER": 2},
        "horse": {"familiars": {"BLUE_SPIDER": 4}},
    },
    "PILLEFFECT_INFESTED_QUESTION": {
        "enemies": 3,
        "familiars": {"BLUE_SPIDER": 3},
        "horse": {"familiars": {"BLUE_SPIDER": 6}},
    },
    "PILLEFFECT_X_LAX": {"effects": ["CREEP_SLIPPERY_BROWN"]},
    "PILLEFFECT_SOMETHINGS_WRONG": {"effects": ["PLAYER_CREEP_BLACK"]},
    "PILLEFFECT_GULP": {"smelt": True},
    "PILLEFFECT_HORF": {
        "tear_flags": ["TEAR_EXPLOSIVE", "TEAR_POISON"],
        "horse": {"minimum_tears": 2},
    },
    "PILLEFFECT_VURP": {"prior_pill": True, "returned_pill": "PILLEFFECT_BALLS_OF_STEEL"},
    "PILLEFFECT_EXPERIMENTAL": {"random_stats": True},
    "PILLEFFECT_PUBERTY": {"puberty": True, "delta": {"max_hearts": 2}},
    "PILLEFFECT_PARALYSIS": {
        "paralysis": True,
        "recover_tick": 135,
        "end_tick": 210,
        "horse": {"recover_tick": 195, "end_tick": 270},
    },
    "PILLEFFECT_RELAX": {"poop_trail": True, "end_tick": 240},
    "PILLEFFECT_POWER": {
        "invulnerable": True,
        "enemies": 1,
        "contact_target": True,
        "enemy_hurt": True,
        "recover_tick": 270,
        "end_tick": 330,
        "horse": {
            "stats": {"damage": 1, "range": 1},
            "expire_room": True,
            "room_tick": 330,
            "end_tick": 450,
        },
    },
    "PILLEFFECT_SUNSHINE": {
        "invulnerable": True,
        "enemies": 1,
        "contact_target": True,
        "no_contact_damage": True,
        "recover_tick": 270,
        "end_tick": 330,
        "horse": {"no_contact_damage": False, "enemy_hurt": True},
    },
    "PILLEFFECT_WIZARD": {"diagonal": True, "shoot": True},
    "PILLEFFECT_TELEPILLS": {"teleport_any": True, "end_tick": 300},
    "CARD_MAGICIAN": {
        "shoot": True,
        "enemies": 1,
        "aim_target": True,
        "homing": True,
        "enemy_hurt": True,
        "tear_flags": ["TEAR_HOMING"],
        "stats": {"range": 1},
        "expire_room": True,
    },
    "CARD_HIGH_PRIESTESS": {"enemies": 2, "enemy_hurt": True, "effects": ["MOM_FOOT_STOMP"]},
    "CARD_QUESTIONMARK": {
        "empty_active": True,
        "active_item": "COLLECTIBLE_NECRONOMICON",
        "enemies": 2,
        "enemy_damage": 40,
        "active_charge_unchanged": True,
    },
    "CARD_HUGE_GROWTH": {
        "stats": {"damage": 1, "range": 1, "scale_x": 1},
        "crush_rock": True,
        "expire_room": True,
    },
    "CARD_ERA_WALK": {
        "enemies": 2,
        "movement_rate": -1,
        "stats": {"speed": 1, "shot_speed": -1},
        "expire_room": True,
    },
    "CARD_SOUL_LILITH": {"new_familiar": True},
    "CARD_SOUL_APOLLYON": {"minimum_familiars": 15},
    "CARD_SOUL_BETHANY": {"familiars": {"WISP": 6}},
    "CARD_CHARIOT": {
        "invulnerable": True,
        "enemies": 1,
        "contact_target": True,
        "enemy_hurt": True,
        "recover_tick": 270,
        "end_tick": 330,
    },
}

# These tears have an explicit unconditional native flag. Attribute modifiers
# are checked as well; conditional follow-up mechanics get separate recipes.
TRIGGER_EFFECTS.update(
    {
        name: {"shoot": True, "tear_flags": [flag]}
        for name, flag in {
            "COLLECTIBLE_SPOON_BENDER": "TEAR_HOMING",
            "COLLECTIBLE_OUIJA_BOARD": "TEAR_SPECTRAL",
            "COLLECTIBLE_CUPIDS_ARROW": "TEAR_PIERCING",
            "COLLECTIBLE_LUMP_OF_COAL": "TEAR_GROW",
            "COLLECTIBLE_STRANGE_ATTRACTOR": "TEAR_ATTRACTOR",
            "COLLECTIBLE_ANTI_GRAVITY": "TEAR_WAIT",
            "COLLECTIBLE_CONTINUUM": "TEAR_CONTINUUM",
            "COLLECTIBLE_TRACTOR_BEAM": "TEAR_TRACTOR_BEAM",
        }.items()
    }
)
TRIGGER_EFFECTS["COLLECTIBLE_SPOON_BENDER"].update(
    {"enemies": 1, "aim_target": True, "homing": True, "enemy_hurt": True}
)
TRIGGER_EFFECTS["COLLECTIBLE_OUIJA_BOARD"].update(
    {"enemies": 1, "spectral_target": True, "enemy_hurt": True, "stats": {"delay": -1}}
)
TRIGGER_EFFECTS["COLLECTIBLE_CUPIDS_ARROW"].update({"enemies": 2, "piercing": True})
TRIGGER_EFFECTS["COLLECTIBLE_LUMP_OF_COAL"]["damage_growth"] = True
TRIGGER_EFFECTS["COLLECTIBLE_STRANGE_ATTRACTOR"]["attract_pickup"] = True
TRIGGER_EFFECTS["COLLECTIBLE_ANTI_GRAVITY"] = {
    "shoot": True,
    "shoot_until": 105,
    "hold_release": True,
    "stats": {"delay": -1},
}
TRIGGER_EFFECTS["COLLECTIBLE_CONTINUUM"]["wrap"] = True
TRIGGER_EFFECTS["COLLECTIBLE_TRACTOR_BEAM"]["beam"] = True
TRIGGER_EFFECTS["COLLECTIBLE_MY_REFLECTION"] = {
    "shoot": True,
    "tear_flags": ["TEAR_BOOMERANG"],
    "reverse": True,
    "wide_lane": True,
    "stats": {"damage": 1, "range": 1, "shot_speed": 1, "luck": -1},
}

TRIGGER_EFFECTS.update(
    {
        "RUNE_JERA": {"loose_pickups": True, "duplicate_pickups": True},
        "RUNE_PERTHRO": {"reroll_pedestals": True},
        "RUNE_BERKANO": {"familiars": {"ABYSS_LOCUST": 3}},
        "CARD_DICE_SHARD": {
            "loose_pickups": True,
            "reroll_pedestals": True,
            "reroll_pickups": True,
        },
        "CARD_SOUL_EDEN": {"loose_pickups": True, "reroll_pedestals": True, "reroll_pickups": True},
        "CARD_SOUL_ISAAC": {"cycling_pedestal": True},
        "CARD_REVERSE_LOVERS": {
            "delta": {"max_hearts": -2, "broken": 1},
            "spawns": {"5.100.": [1, 1]},
        },
        "CARD_REVERSE_STARS": {"remove_oldest": True, "spawns": {"5.100.": [2, 2]}},
        "CARD_REVERSE_HERMIT": {"loose_pickups": True, "sell_room": True},
        "CARD_REVERSE_TOWER": {"rock_spawns": 7},
        "CARD_HUMANITY": {"fill_poop": True},
        "CARD_SUICIDE_KING": {"dies": True, "spawns": {"5.": [10, 10]}},
        "CARD_SOUL_EVE": {"effects": ["DEAD_BIRD"], "enemies": 1, "enemy_hurt": True},
        "CARD_SOUL_LOST": {"null_effects": ["ID_LOST_CURSE"], "flying": True, "expire_room": True},
        "COLLECTIBLE_D6": {"reroll_pedestals": True},
        "COLLECTIBLE_D20": {"loose_pickups": True, "reroll_pickups": True},
        "COLLECTIBLE_D1": {"loose_pickups": True, "duplicate_one": True},
        "COLLECTIBLE_SPINDOWN_DICE": {"spindown": True},
        "COLLECTIBLE_ETERNAL_D6": {"reroll_pedestals": True, "can_remove_pedestal": True},
        "COLLECTIBLE_BOOK_OF_SIN": {"spawns": {"5.": [1, 1]}},
        "COLLECTIBLE_IV_BAG": {"delta": {"hearts": -1}, "spawns": {"5.20.": [1, 2]}},
        "COLLECTIBLE_RAZOR_BLADE": {
            "delta": {"hearts": -2},
            "stats": {"damage": 1},
            "expire_room": True,
        },
        "COLLECTIBLE_MOMS_BRA": {"enemies": 2, "enemy_flags": ["FLAG_FREEZE"]},
        "COLLECTIBLE_MOMS_PAD": {
            "enemies": 2,
            "enemy_flags": ["FLAG_FEAR"],
            "familiars": {"BLUE_FLY": 1},
        },
        "COLLECTIBLE_HOURGLASS": {"enemies": 2, "movement_rate": -1},
        "COLLECTIBLE_BEAN": {"enemies": 2, "enemy_flags": ["FLAG_POISON"], "enemy_hurt": True},
        "COLLECTIBLE_TELEPORT": {"teleport_any": True, "end_tick": 300},
        "COLLECTIBLE_TELEPORT_2": {"teleport_any": True, "end_tick": 300},
        "COLLECTIBLE_MR_BOOM": {"enemies": 1, "enemy_hurt": True, "spawns": {"4.": [1, 1]}},
        "COLLECTIBLE_KAMIKAZE": {"enemies": 1, "enemy_damage": 185},
        "COLLECTIBLE_LEMON_MISHAP": {
            "enemies": 1,
            "effects": ["PLAYER_CREEP_LEMON_MISHAP"],
            "enemy_hurt": True,
        },
        "COLLECTIBLE_FREE_LEMONADE": {
            "enemies": 1,
            "effects": ["PLAYER_CREEP_LEMON_PARTY"],
            "enemy_hurt": True,
        },
    }
)
for name, variant in {
    "CARD_ACE_OF_CLUBS": "PICKUP_BOMB",
    "CARD_ACE_OF_DIAMONDS": "PICKUP_COIN",
    "CARD_ACE_OF_SPADES": "PICKUP_KEY",
    "CARD_ACE_OF_HEARTS": "PICKUP_HEART",
}.items():
    TRIGGER_EFFECTS[name] = {"loose_pickups": True, "enemies": 2, "convert_pickups": variant}

for name in ("TECHNOLOGY", "TECHNOLOGY_2", "BRIMSTONE", "TECH_X", "REVELATION", "MAW_OF_THE_VOID"):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "shoot": True,
        "shoot_until": 160,
        "end_tick": 240,
        "observe_until": 237,
        "enemies": 1,
        "hit_target": True,
        "target_hp": 1000,
        "enemy_hurt": True,
        "lasers": True,
    }
TRIGGER_EFFECTS["COLLECTIBLE_REVELATION"]["flying"] = True
TRIGGER_EFFECTS["COLLECTIBLE_TECHNOLOGY_2"]["stats"] = {"delay": 1}
TRIGGER_EFFECTS["COLLECTIBLE_BRIMSTONE"]["stats"] = {"delay": 1}
TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_DR_FETUS": {
            "shoot": True,
            "bomb_attack": True,
            "stats": {"delay": 1},
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "shoot_until": 180,
            "observe_until": 330,
            "end_tick": 360,
        },
        "COLLECTIBLE_CHOCOLATE_MILK": {"shoot": True, "charged_damage": 4},
        "COLLECTIBLE_MONSTROS_LUNG": {
            "shoot": True,
            "minimum_tears": 8,
            "stats": {"delay": 1},
        },
        "COLLECTIBLE_MOMS_KNIFE": {
            "shoot": True,
            "knives": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
        },
        "COLLECTIBLE_SPIRIT_SWORD": {
            "shoot": True,
            "knives": True,
            "enemies": 1,
            "enemy_hurt": True,
        },
        "COLLECTIBLE_C_SECTION": {
            "shoot": True,
            "tear_flags": ["TEAR_FETUS", "TEAR_SPECTRAL"],
            "enemies": 1,
            "aim_target": True,
            "enemy_hurt": True,
            "shoot_until": 180,
            "observe_until": 330,
            "end_tick": 360,
        },
        "COLLECTIBLE_LUDOVICO_TECHNIQUE": {
            "shoot": True,
            "tear_flags": ["TEAR_LUDOVICO"],
            "controlled_tear": True,
            "stats": {"shot_speed": 1},
        },
        "COLLECTIBLE_IPECAC": {
            "shoot": True,
            "tear_flags": ["TEAR_EXPLOSIVE", "TEAR_POISON"],
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "stats": {"damage": 1, "delay": 1, "range": -1, "shot_speed": -1},
        },
    }
)

for name, tear, status in (
    ("SPIDER_BITE", "SLOW", "SLOW"),
    ("COMMON_COLD", "POISON", "POISON"),
    ("MOMS_CONTACTS", "FREEZE", "FREEZE"),
    ("MOMS_EYESHADOW", "CHARM", "CHARM"),
    ("IRON_BAR", "CONFUSION", "CONFUSION"),
    ("MOMS_PERFUME", "FEAR", "FEAR"),
    ("DARK_MATTER", "FEAR", "FEAR"),
    ("SCORPIO", "POISON", "POISON"),
    ("GLAUCOMA", "PERMANENT_CONFUSION", "CONFUSION"),
    ("LODESTONE", "MAGNETIZE", "MAGNETIZED"),
    ("ROTTEN_TOMATO", "BAIT", "BAITED"),
):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "shoot": True,
        "shoot_until": 420,
        "observe_until": 447,
        "end_tick": 480,
        "luck": 100,
        "enemies": 1,
        "hit_target": True,
        "tear_flags": ["TEAR_" + tear],
        "enemy_flags": ["FLAG_" + status],
        "enemy_hurt": True,
    }
TRIGGER_EFFECTS["COLLECTIBLE_IRON_BAR"]["stats"] = {"damage": 1}
TRIGGER_EFFECTS["COLLECTIBLE_MOMS_CONTACTS"]["stats"] = {"range": 1}
TRIGGER_EFFECTS["COLLECTIBLE_MOMS_PERFUME"]["stats"] = {"delay": -1}
TRIGGER_EFFECTS["COLLECTIBLE_DARK_MATTER"]["stats"] = {"damage": 1}
TRIGGER_EFFECTS["COLLECTIBLE_GLAUCOMA"].update(
    {"shoot_until": 900, "observe_until": 927, "end_tick": 960}
)
for name in ("3_DOLLAR_BILL", "FRUIT_CAKE", "PLAYDOUGH_COOKIE", "ALMOND_MILK"):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "shoot": True,
        "random_tears": True,
        "shoot_until": 420,
        "observe_until": 447,
        "end_tick": 480,
    }
TRIGGER_EFFECTS["COLLECTIBLE_ALMOND_MILK"]["stats"] = {"damage": -1, "delay": -1}
TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_SOY_MILK": {
            "shoot": True,
            "stats": {"damage": -1, "delay": -1},
            "minimum_tears": 12,
        },
        "COLLECTIBLE_FIRE_MIND": {
            "shoot": True,
            "luck": 100,
            "enemies": 1,
            "hit_target": True,
            "tear_flags": ["TEAR_BURN"],
            "enemy_flags": ["FLAG_BURN"],
            "enemy_hurt": True,
        },
        "COLLECTIBLE_ABADDON": {
            "shoot": True,
            "luck": 100,
            "enemies": 1,
            "hit_target": True,
            "tear_flags": ["TEAR_FEAR"],
            "enemy_flags": ["FLAG_FEAR"],
            "enemy_hurt": True,
            "stats": {"damage": 1, "speed": 1},
            "delta": {"max_hearts": -6, "soul": 10},
        },
        "COLLECTIBLE_DEAD_ONION": {
            "shoot": True,
            "enemies": 2,
            "spectral_target": True,
            "piercing": True,
            "tear_flags": ["TEAR_SPECTRAL", "TEAR_PIERCING"],
            "stats": {"range": -1, "shot_speed": -1},
        },
        "COLLECTIBLE_PUPULA_DUPLEX": {
            "shoot": True,
            "enemies": 1,
            "spectral_target": True,
            "tear_flags": ["TEAR_SPECTRAL"],
            "enemy_hurt": True,
        },
    }
)

for name in ("SPIRIT_OF_THE_NIGHT", "DEAD_DOVE"):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "shoot": True,
        "enemies": 1,
        "spectral_target": True,
        "enemy_hurt": True,
        "tear_flags": ["TEAR_SPECTRAL"],
        "flying": True,
    }
for name, stats in {
    "SAGITTARIUS": {"speed": 1},
    "DEATHS_TOUCH": {"damage": 1, "delay": 1},
}.items():
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "shoot": True,
        "enemies": 2,
        "piercing": True,
        "tear_flags": ["TEAR_PIERCING"],
        "stats": stats,
    }
TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_TELEPATHY_BOOK": {
            **TRIGGER_EFFECTS["CARD_MAGICIAN"],
        },
        "COLLECTIBLE_SACRED_HEART": {
            "shoot": True,
            "enemies": 1,
            "aim_target": True,
            "homing": True,
            "enemy_hurt": True,
            "tear_flags": ["TEAR_HOMING"],
            "stats": {"damage": 1, "delay": 1, "shot_speed": -1},
            "delta": {"max_hearts": 2},
        },
        "COLLECTIBLE_THE_WIZ": {
            "shoot": True,
            "diagonal": True,
            "tear_flags": ["TEAR_SPECTRAL"],
        },
        "COLLECTIBLE_PROPTOSIS": {
            "shoot": True,
            "damage_decay": True,
            "stats": {"damage": 1},
        },
        "COLLECTIBLE_TAMMYS_HEAD": {
            "minimum_tears": 10,
            "radial": True,
            "tear_damage_bonus": 25,
        },
        "COLLECTIBLE_ISAACS_TEARS": {
            "minimum_tears": 8,
            "radial": True,
            "tear_damage_bonus": 5,
        },
        "COLLECTIBLE_MOMS_EYE": {"shoot": True, "luck": 100, "back_shot": True},
        "COLLECTIBLE_LOKIS_HORNS": {"shoot": True, "luck": 100, "four_directions": True},
        "COLLECTIBLE_MOMS_WIG": {
            "shoot": True,
            "luck": 100,
            "minimum_spawned_familiars": {"BLUE_SPIDER": 1},
            "shoot_until": 420,
            "observe_until": 447,
            "end_tick": 480,
        },
        "COLLECTIBLE_MULLIGAN": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "minimum_spawned_familiars": {"BLUE_FLY": 1},
            "shoot_until": 600,
            "observe_until": 627,
            "end_tick": 660,
        },
        "RUNE_HAGALAZ": {"rocks": 3, "destroy_rocks": True},
        "RUNE_EHWAZ": {"grid_spawn": "GRID_TRAPDOOR"},
        "RUNE_BLACK": {
            "loose_pickups": True,
            "consume_pedestals": True,
            "positive_random_stat": True,
            "minimum_spawned_familiars": {"BLUE_FLY": 1},
            "enemies": 2,
            "enemy_damage": 80,
        },
        "CARD_CREDIT": {"priced_pickups": True, "free_pickups": True},
        "CARD_GET_OUT_OF_JAIL": {"locked_doors": True, "open_doors": True},
        "CARD_EMERGENCY_CONTACT": {
            "enemies": 2,
            "target_hp": 20,
            "removed_enemies": 2,
            "end_tick": 300,
            "observe_until": 297,
        },
        "CARD_REVERSE_FOOL": {"drop_resources": True, "spawns": {"5.": [4, 100]}},
        "CARD_REVERSE_HIGH_PRIESTESS": {
            "effects": ["MOM_FOOT_STOMP"],
            "repeated_effect": "MOM_FOOT_STOMP",
            "observe_until": 1800,
            "end_tick": 1950,
            "hazard_trial": True,
            "repeated_effect_expiry": 1900,
        },
        "CARD_REVERSE_EMPRESS": {
            "delta": {"max_hearts": 4},
            "stats": {"delay": -1, "speed": -1},
            "expires_at": 1900,
            "end_tick": 1980,
        },
        "CARD_REVERSE_EMPEROR": {"teleport_type": "ROOM_BOSS", "end_tick": 300},
        "CARD_REVERSE_DEVIL": {
            "flying": True,
            "familiars": {"SERAPHIM": 1},
            "expires_at": 1000,
            "flying_expire_room": True,
            "expire_room": True,
            "room_tick": 1100,
            "end_tick": 1220,
        },
        "CARD_REVERSE_MOON": {"teleport_type": "ROOM_ULTRASECRET", "end_tick": 300},
        "CARD_REVERSE_WORLD": {"grid_spawn": "GRID_STAIRS"},
        "CARD_WILD": {
            "prior_active": "COLLECTIBLE_BOOK_OF_REVELATIONS",
            "repeat_active": True,
            "use_tick": 120,
            "observe_until": 237,
            "end_tick": 240,
        },
        "CARD_SOUL_BLUEBABY": {"spawns": {"4.": [7, 7]}, "observe_until": 360, "end_tick": 420},
        "CARD_SOUL_AZAZEL": {
            "shoot": True,
            "lasers": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "observe_until": 270,
            "end_tick": 360,
        },
        "COLLECTIBLE_CAFFEINE_PILL": {
            "stats": {"speed": 1, "scale_x": -1},
            "spawns": {"5.70.": [1, 1]},
        },
        "COLLECTIBLE_PJS": {"health_before": 2, "delta": {"hearts": 4, "soul": 8}},
        "COLLECTIBLE_CAPRICORN": {
            "delta": {"max_hearts": 2, "coins": 1, "bombs": 1, "keys": 1},
            "stats": {"damage": 1, "delay": -1, "speed": 1, "range": 1},
        },
        "COLLECTIBLE_MARROW": {"delta": {"bone": 1}, "spawns": {"5.10.1": [3, 3]}},
        "COLLECTIBLE_DIVORCE_PAPERS": {
            "physical_pickup": True,
            "delta": {"bone": 1},
            "stats": {"delay": -1},
            "spawns": {"5.350.21": [1, 1]},
        },
        "COLLECTIBLE_DADS_LOST_COIN": {"stats": {"range": 1}, "spawns": {"5.20.5": [1, 1]}},
        "COLLECTIBLE_MOMS_RING": {
            "physical_pickup": True,
            "stats": {"damage": 1},
            "rune_drop": True,
        },
        "COLLECTIBLE_2SPOOKY": {
            "stats": {"delay": -1, "shot_speed": 1},
            "enemies": 2,
            "enemy_flags": ["FLAG_FEAR"],
        },
        "COLLECTIBLE_VENUS": {
            "delta": {"max_hearts": 2},
            "enemies": 2,
            "enemy_flags": ["FLAG_CHARM"],
        },
        "COLLECTIBLE_THUNDER_THIGHS": {
            "delta": {"max_hearts": 2},
            "stats": {"speed": -1},
            "crush_rock": True,
        },
        "COLLECTIBLE_SMELTER": {"smelt": True},
        "COLLECTIBLE_KIDNEY_BEAN": {"enemies": 2, "enemy_flags": ["FLAG_CHARM"]},
        "COLLECTIBLE_POOP": {"grid_spawn": "GRID_POOP"},
        "COLLECTIBLE_DIPLOPIA": {
            "loose_pickups": True,
            "duplicate_pickups": True,
            "duplicate_pedestals": True,
        },
        "COLLECTIBLE_EDENS_SOUL": {"spawns": {"5.100.": [2, 2]}, "consumed_active": True},
        "COLLECTIBLE_MYSTERY_GIFT": {"spawns": {"5.100.": [1, 1]}},
        "COLLECTIBLE_SHARP_STRAW": {"enemies": 2, "enemy_damage": 107},
        "COLLECTIBLE_MEAT_CLEAVER": {"enemies": 2, "split_enemies": True},
        "COLLECTIBLE_YUCK_HEART": {"delta": {"rotten": 1}},
        "COLLECTIBLE_MAGIC_SKIN": {
            "delta": {"max_hearts": -2, "broken": 1},
            "spawns": {"5.100.": [1, 1]},
        },
        "COLLECTIBLE_JAR_OF_WISPS": {"familiars": {"WISP": 2}},
        "COLLECTIBLE_DADS_KEY": {"locked_doors": True, "open_doors": True},
        "COLLECTIBLE_WE_NEED_GO_DEEPER": {"grid_spawn": "GRID_TRAPDOOR"},
        "COLLECTIBLE_MOMS_SHOVEL": {"grid_spawn": "GRID_TRAPDOOR"},
        "COLLECTIBLE_HABIT": {"empty_active": True, "damage_trigger": True, "charge_after_hit": 1},
        "COLLECTIBLE_INFESTATION": {"damage_trigger": True, "familiar_range": {"BLUE_FLY": [2, 6]}},
        "COLLECTIBLE_SPIDERBABY": {
            "damage_trigger": True,
            "familiar_range": {"BLUE_SPIDER": [2, 5]},
        },
        "COLLECTIBLE_PIGGY_BANK": {
            "damage_trigger": True,
            "spawn_after_hit": {"5.20.": [1, 2]},
            "delta": {"coins": 3},
        },
        "COLLECTIBLE_CURSE_OF_THE_TOWER": {
            "damage_trigger": True,
            "spawn_after_hit": {"4.": [6, 6]},
        },
        "COLLECTIBLE_VARICOSE_VEINS": {
            "damage_trigger": True,
            "minimum_tears": 10,
            "radial": True,
            "tear_damage_bonus": 25,
        },
        "COLLECTIBLE_ANEMIC": {
            "damage_trigger": True,
            "stats": {"range": 1},
            "effects": ["PLAYER_CREEP_RED"],
        },
        "COLLECTIBLE_BLACK_BEAN": {
            "damage_trigger": True,
            "enemies": 1,
            "enemy_hurt": True,
            "enemy_flags": ["FLAG_POISON"],
        },
        "COLLECTIBLE_HYPERCOAGULATION": {
            "damage_trigger": True,
            "spawn_after_hit": {"5.10.2": [1, 1]},
            "drops_expire": True,
        },
        "COLLECTIBLE_BLOODY_LUST": {
            "damage_trigger": True,
            "hit_stats": {"damage": 1},
            "floor_reset": True,
            "end_tick": 600,
        },
        "COLLECTIBLE_BLOODY_GUST": {
            "damage_trigger": True,
            "hit_stats": {"speed": 1, "delay": -1},
            "floor_reset": True,
            "end_tick": 600,
        },
        "COLLECTIBLE_IT_HURTS": {
            "damage_trigger": True,
            "hit_stats": {"delay": -1},
            "minimum_tears": 10,
            "radial": True,
            "expire_room": True,
        },
    }
)


TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_PYRO": {"stats": {"bombs": 1}},
        "COLLECTIBLE_FATE": {"flying": True, "delta": {"eternal": 1}},
        "COLLECTIBLE_MOMS_HEELS": {
            "stats": {"range": 1},
            "enemies": 1,
            "contact_target": True,
            "enemy_hurt": True,
        },
        "COLLECTIBLE_VIRUS": {
            "stats": {"speed": 1},
            "enemies": 1,
            "contact_target": True,
            "enemy_flags": ["FLAG_POISON"],
            "enemy_hurt": True,
        },
        "COLLECTIBLE_BOOK_OF_BELIAL": {"stats": {"damage": 1}, "expire_room": True},
        "COLLECTIBLE_059": {
            "native_prerequisite_only": True,
            "character_before": "PLAYER_JUDAS",
            "prerequisite_items": ["COLLECTIBLE_BIRTHRIGHT"],
            "active_before": "COLLECTIBLE_BOOK_OF_REVELATIONS",
            "use_existing_active": True,
            "stats": {"damage": 1},
            "expire_room": True,
        },
        "COLLECTIBLE_SHOOP_DA_WHOOP": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "lasers": True,
            "enemy_hurt": True,
        },
        "COLLECTIBLE_BOBS_ROTTEN_HEAD": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "enemy_flags": ["FLAG_POISON"],
            "end_tick": 300,
        },
        "COLLECTIBLE_MONSTROS_TOOTH": {"enemies": 1, "enemy_damage": 120, "end_tick": 300},
        "COLLECTIBLE_CRACK_THE_SKY": {
            "enemies": 2,
            "enemy_hurt": True,
            "effects": ["CRACK_THE_SKY"],
        },
        "COLLECTIBLE_MONSTER_MANUAL": {"new_familiar": True},
        "COLLECTIBLE_MONEY_IS_POWER": {"coins_before": 50, "stats": {"damage": 1}},
        "COLLECTIBLE_WHORE_OF_BABYLON": {"health_before": 1, "stats": {"damage": 1, "speed": 1}},
        "COLLECTIBLE_EXPERIMENTAL_TREATMENT": {"random_stats": True},
        "COLLECTIBLE_MAGNETO": {"attract_pickup": True},
        "COLLECTIBLE_XRAY_VISION": {"secret_doors": True},
        "COLLECTIBLE_PINKING_SHEARS": {
            "flying": True,
            "familiars": {"ISAACS_BODY": 1},
            "enemies": 1,
            "enemy_hurt": True,
        },
        "COLLECTIBLE_THE_NAIL": {
            "stats": {"damage": 1, "speed": -1},
            "delta": {"soul": 1},
            "crush_rock": True,
            "enemies": 1,
            "contact_target": True,
            "enemy_hurt": True,
            "expire_room": True,
        },
        "COLLECTIBLE_MY_LITTLE_UNICORN": {
            "invulnerable": True,
            "enemies": 1,
            "contact_target": True,
            "enemy_hurt": True,
            "recover_tick": 270,
            "end_tick": 330,
        },
        "COLLECTIBLE_GAMEKID": {
            "invulnerable": True,
            "enemies": 1,
            "contact_target": True,
            "enemy_hurt": True,
            "enemy_flags": ["FLAG_FEAR"],
            "recover_tick": 285,
            "end_tick": 345,
        },
        "COLLECTIBLE_UNICORN_STUMP": {
            "invulnerable": True,
            "enemies": 1,
            "contact_target": True,
            "no_contact_damage": True,
            "recover_tick": 270,
            "end_tick": 330,
        },
        "COLLECTIBLE_BLOOD_RIGHTS": {
            "enemies": 2,
            "enemy_damage": 80,
            "delta": {"hearts": -2},
            "stats": {"delay": -1},
            "expire_room": True,
        },
        "CARD_CHAOS": {
            "moving_use": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_damage": 500,
            "end_tick": 300,
        },
        "CARD_REVERSE_TEMPERANCE": {"pill_callbacks": 5, "end_tick": 300},
        "CARD_REVERSE_DEATH": {"kill_before": 4, "minimum_helpers": 1, "use_tick": 120},
        "COLLECTIBLE_BOOK_OF_THE_DEAD": {
            "kill_before": 4,
            "minimum_helpers": 1,
            "use_tick": 120,
        },
        "CARD_SOUL_MAGDALENE": {
            "enemies": 2,
            "kill_after": True,
            "spawn_after_kill": {"5.10.2": [2, 2]},
            "drops_expire": True,
            "end_tick": 270,
        },
        "COLLECTIBLE_INFESTATION_2": {
            "enemies": 2,
            "kill_after": True,
            "familiars": {"BLUE_SPIDER": 2},
        },
        "COLLECTIBLE_CHARM_VAMPIRE": {
            "health_before": 2,
            "enemies": 13,
            "kill_after": True,
            "stats": {"damage": 1},
            "healed_after_kill": 1,
        },
        "COLLECTIBLE_CELTIC_CROSS": {"damage_trigger": True, "luck": 100, "shield_after_hit": True},
        "COLLECTIBLE_GIMPY": {
            "damage_trigger": True,
            "luck": 100,
            "spawn_after_hit": {"5.10.3": [1, 1]},
        },
        "COLLECTIBLE_BEST_BUD": {"damage_trigger": True, "familiars": {"BEST_BUD": 1}},
        "COLLECTIBLE_DEAD_BIRD": {
            "damage_trigger": True,
            "enemies": 1,
            "familiars": {"DEAD_BIRD": 1},
            "enemy_hurt": True,
            "observe_until": 297,
            "end_tick": 300,
        },
    }
)

for name, health, player_type in (
    ("1UP", 6, "PLAYER_ISAAC"),
    ("ANKH", 0, "PLAYER_XXX"),
    ("JUDAS_SHADOW", 0, "PLAYER_BLACKJUDAS"),
    ("LAZARUS_RAGS", 2, "PLAYER_LAZARUS2"),
):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "revive": True,
        "revive_hearts": health,
        "revive_type": player_type,
        "observe_until": 447,
        "end_tick": 450,
    }


# Bomb trials press the normal bomb action. The enemy and explosion evidence
# must establish the modifier's behavior as well as its replicated geometry.
for name, extra in {
    "MR_MEGA": {"bomb_damage": 185},
    "BOBBY_BOMB": {"bomb_homing": True},
    "BOBS_CURSE": {"enemy_flags": ["FLAG_POISON"]},
    "BUTT_BOMBS": {"enemy_flags": ["FLAG_CONFUSION"], "distant_bomb_target": True},
    "SAD_BOMBS": {"minimum_tears": 10, "radial": True},
    "HOT_BOMBS": {"effects": ["RED_CANDLE_FLAME"]},
    "BOMBER_BOY": {"cross_explosions": True},
    "SCATTER_BOMBS": {"spawns": {"4.": [5, 6]}},
    "STICKY_BOMBS": {"target_hp": 20, "minimum_spawned_familiars": {"BLUE_SPIDER": 1}},
    "BLOOD_BOMBS": {"effects": ["PLAYER_CREEP_RED"]},
    "BRIMSTONE_BOMBS": {"lasers": True},
    "GHOST_BOMBS": {"effects": ["HUNGRY_SOUL"]},
}.items():
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "bomb_trial": True,
        "enemies": 1,
        "enemy_hurt": True,
        "observe_until": 297,
        "end_tick": 300,
        **extra,
    }


for name, flag, extra in (
    ("PARASITE", "TEAR_SPLIT", {"split_tear_damage": True}),
    (
        "CRICKETS_BODY",
        "TEAR_QUADSPLIT",
        {"split_tear_damage": True, "stats": {"delay": -1, "range": -1}},
    ),
    (
        "RUBBER_CEMENT",
        "TEAR_BOUNCE",
        {"reverse": True, "wide_lane": True, "bounce_wall": True, "enemies": 0},
    ),
    ("TINY_PLANET", "TEAR_ORBIT", {"orbit_tears": True, "stats": {"range": 1}, "enemies": 0}),
    ("HOLY_LIGHT", "TEAR_LIGHT_FROM_HEAVEN", {"effects": ["CRACK_THE_SKY"]}),
    ("MYSTERIOUS_LIQUID", "TEAR_MYSTERIOUS_LIQUID_CREEP", {"effects": ["PLAYER_CREEP_GREEN"]}),
    ("EXPLOSIVO", "TEAR_STICKY", {"delayed_tear_explosion": True}),
    ("HEAD_OF_THE_KEEPER", "TEAR_GREED_COIN", {"spawns": {"5.20.": [1, 99]}}),
    ("COMPOUND_FRACTURE", "TEAR_BONE", {"split_tear_damage": True, "stats": {"range": 1}}),
    (
        "EYE_OF_BELIAL",
        "TEAR_BELIAL",
        {"piercing": True, "enemies": 2, "charged_damage": 2, "stats": {"range": 1}},
    ),
    ("JACOBS_LADDER", "TEAR_JACOBS", {"lasers": True}),
    ("EUTHANASIA", "TEAR_NEEDLE", {"enemy_damage": 500}),
    ("LITTLE_HORN", "TEAR_HORN", {"enemy_damage": 500}),
    ("TECHNOLOGY_ZERO", "TEAR_LASER", {"lasers": True, "target_distance": 200}),
    ("POP", "TEAR_POP", {"enemies": 0, "tear_decelerates": True}),
    ("HAEMOLACRIA", "TEAR_BURSTSPLIT", {"stats": {"damage": 1, "delay": 1}, "minimum_tears": 3}),
    ("LACHRYPHAGY", "TEAR_ABSORB", {"enemies": 0, "minimum_tears": 5, "tear_decelerates": True}),
    ("TRISAGION", "TEAR_LASERSHOT", {"lasers": True}),
    ("FLAT_STONE", "TEAR_HYDROBOUNCE", {"tear_bounces": True}),
    ("MUCORMYCOSIS", "TEAR_SPORE", {"delayed_tear_explosion": True}),
    (
        "IMMACULATE_HEART",
        "TEAR_ORBIT_ADVANCED",
        {"stats": {"damage": 1}, "delta": {"max_hearts": 2}, "orbit_tears": True},
    ),
    ("URANUS", "TEAR_ICE", {"target_hp": 3, "enemy_hurt": True}),
    ("OCULAR_RIFT", "TEAR_RIFT", {"effects": ["RIFT"]}),
):
    rules = {
        "shoot": True,
        "enemies": 1,
        "hit_target": True,
        "enemy_hurt": True,
        "tear_flags": [flag],
        "luck": 100,
        "shoot_until": 420,
        "observe_until": 477,
        "end_tick": 480,
        **extra,
    }
    if not rules["enemies"]:
        rules.pop("enemy_hurt")
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = rules
for name, bonus in (("CHEMICAL_PEEL", 2), ("BLOOD_CLOT", 1)):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {"shoot": True, "alternating_damage": bonus}
TRIGGER_EFFECTS["COLLECTIBLE_TECH_5"] = {
    "shoot": True,
    "lasers": True,
    "enemies": 1,
    "hit_target": True,
    "enemy_hurt": True,
    "shoot_until": 420,
    "observe_until": 477,
    "end_tick": 480,
}
TRIGGER_EFFECTS["COLLECTIBLE_HEAD_OF_KRAMPUS"] = {
    "lasers": True,
    "enemies": 1,
    "hit_target": True,
    "enemy_hurt": True,
}
TRIGGER_EFFECTS["COLLECTIBLE_SULFUR"] = {
    "shoot": True,
    "lasers": True,
    "enemies": 1,
    "hit_target": True,
    "enemy_hurt": True,
    "shoot_until": 160,
}
TRIGGER_EFFECTS["COLLECTIBLE_DEAD_TOOTH"] = {
    "shoot": True,
    "enemies": 1,
    "enemy_flags": ["FLAG_POISON"],
    "enemy_hurt": True,
}


TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_BLANK_CARD": {
            "pocket_card": "CARD_LOVERS",
            "pocket_retained": True,
            "spawns": {"5.10.1": [2, 2]},
        },
        "COLLECTIBLE_PLACEBO": {
            "pocket_pill": "PILLEFFECT_BALLS_OF_STEEL",
            "pocket_retained": True,
            "delta": {"soul": 4},
        },
        "COLLECTIBLE_263": {
            "pocket_card": "RUNE_BERKANO",
            "pocket_retained": True,
            "familiars": {"ABYSS_LOCUST": 3},
        },
        "COLLECTIBLE_TAROT_CLOTH": {
            "pocket_card": "CARD_LOVERS",
            "use_pocket": True,
            "spawns": {"5.10.1": [3, 3]},
        },
        "COLLECTIBLE_CAR_BATTERY": {
            "active_before": "COLLECTIBLE_BOOK_OF_REVELATIONS",
            "use_existing_active": True,
            "delta": {"soul": 4},
        },
        "COLLECTIBLE_NINE_VOLT": {
            "active_before": "COLLECTIBLE_BOOK_OF_REVELATIONS",
            "charge_before": 0,
            "use_existing_active": True,
            "acquired_charge": 6,
            "after_charge": 1,
            "delta": {"soul": 2},
        },
        "COLLECTIBLE_BATTERY_PACK": {
            "active_before": "COLLECTIBLE_D6",
            "charge_before": 0,
            "acquired_charge": 6,
            "spawns": {"5.90.": [2, 4]},
        },
        "COLLECTIBLE_BOOSTER_PACK": {"physical_pickup": True, "spawns": {"5.300.": [5, 5]}},
        "COLLECTIBLE_BOX": {
            "physical_pickup": True,
            "spawns": {
                "5.10.": [1, 1],
                "5.20.": [1, 1],
                "5.30.": [1, 1],
                "5.40.": [1, 1],
                "5.70.": [1, 1],
                "5.300.": [1, 1],
                "5.350.": [1, 1],
            },
        },
        "COLLECTIBLE_RED_KEY": {"red_rooms": True, "wall_use": True},
        "CARD_CRACKED_KEY": {"red_rooms": True, "wall_use": True},
        "CARD_SOUL_CAIN": {
            "red_rooms": True,
            "wall_use": True,
            "locked_doors": True,
            "open_doors": True,
        },
    }
)


TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_LATCH_KEY": {
            "stats": {"luck": 1},
            "delta": {"soul": 2},
            "spawns": {"5.30.": [2, 2]},
        },
        "COLLECTIBLE_MATCH_BOOK": {
            "delta": {"soul": 2},
            "spawns": {"5.40.": [3, 3], "5.350.41": [1, 1]},
        },
        "COLLECTIBLE_BELLY_BUTTON": {
            "delta": {"trinket_slots": 1},
            "spawns": {"5.350.": [1, 1]},
        },
        "COLLECTIBLE_SAUSAGE": {
            "delta": {"max_hearts": 2},
            "stats": {"damage": 1, "delay": -1, "speed": 1, "range": 1, "luck": 1, "shot_speed": 1},
        },
        "COLLECTIBLE_PLUTO": {
            "stats": {"delay": -1, "scale_x": -1},
            "shoot": True,
        },
        "COLLECTIBLE_ADRENALINE": {"health_before": 1, "stats": {"damage": 1}},
        "COLLECTIBLE_GREEDS_GULLET": {"coins_before": 50, "delta": {"max_hearts": 4}},
        "COLLECTIBLE_DARK_PRINCES_CROWN": {
            "health_before": 2,
            "stats": {"delay": -1, "range": 1, "shot_speed": 1},
        },
        "COLLECTIBLE_HEARTBREAK": {
            "delta": {"broken": 3},
            "stats": {"damage": 1},
            "prevent_fatal": True,
        },
        "COLLECTIBLE_LEO": {"crush_rock": True},
        "COLLECTIBLE_TROPICAMIDE": {"shoot": True, "stats": {"range": 1}, "larger_tears": True},
        "COLLECTIBLE_8_INCH_NAILS": {
            "shoot": True,
            "stats": {"damage": 1},
            "tear_flags": ["TEAR_KNOCKBACK"],
        },
        "COLLECTIBLE_STAPLER": {"shoot": True, "stats": {"damage": 1}, "single_eye": True},
        "COLLECTIBLE_APPLE": {
            "shoot": True,
            "luck": 100,
            "charged_damage": 4,
            "stats": {"delay": -1},
        },
        "COLLECTIBLE_TOUGH_LOVE": {"shoot": True, "luck": 100, "charged_damage": 3.2},
        "COLLECTIBLE_GODS_FLESH": {
            "shoot": True,
            "luck": 100,
            "tear_flags": ["TEAR_GODS_FLESH"],
            "enemy_flags": ["FLAG_SHRINK"],
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
        },
        "COLLECTIBLE_KNOCKOUT_DROPS": {
            "shoot": True,
            "luck": 100,
            "tear_flags": ["TEAR_PUNCH"],
            "enemy_flags": ["FLAG_CONFUSION"],
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
        },
        "COLLECTIBLE_GHOST_PEPPER": {
            "shoot": True,
            "luck": 100,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "effects": ["BLUE_FLAME"],
        },
        "COLLECTIBLE_BIRDS_EYE": {
            "shoot": True,
            "luck": 100,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "effects": ["RED_CANDLE_FLAME"],
        },
        "COLLECTIBLE_BALL_OF_TAR": {
            "shoot": True,
            "luck": 100,
            "enemies": 1,
            "hit_target": True,
            "enemy_flags": ["FLAG_SLOW"],
            "effects": ["PLAYER_CREEP_BLACK"],
        },
        "COLLECTIBLE_SERPENTS_KISS": {
            "shoot": True,
            "luck": 100,
            "enemies": 1,
            "hit_target": True,
            "enemy_flags": ["FLAG_POISON"],
            "enemy_hurt": True,
        },
        "COLLECTIBLE_DADS_RING": {"enemies": 1, "enemy_flags": ["FLAG_FREEZE"]},
        "COLLECTIBLE_LEPROSY": {"damage_trigger": True, "new_familiar": True},
        "COLLECTIBLE_MYSTERY_EGG": {"damage_trigger": True, "friendly_enemies": True},
        "COLLECTIBLE_GIANT_CELL": {"damage_trigger": True, "new_familiar": True},
        "COLLECTIBLE_VENGEFUL_SPIRIT": {"damage_trigger": True, "familiars": {"WISP": 1}},
        "COLLECTIBLE_HALLOWED_GROUND": {"damage_trigger": True, "grid_spawn": "GRID_POOP"},
        "COLLECTIBLE_LUSTY_BLOOD": {
            "enemies": 2,
            "kill_after": True,
            "stats": {"damage": 1},
            "expire_room": True,
        },
        "COLLECTIBLE_JUMPER_CABLES": {
            "empty_active": True,
            "enemies": 15,
            "kill_after": True,
            "after_charge": 1,
        },
        "COLLECTIBLE_VASCULITIS": {
            "enemies": 2,
            "kill_after": True,
            "include_room_tears": True,
            "minimum_tears": 4,
            "radial": True,
        },
        "COLLECTIBLE_QUINTS": {"enemies": 5, "kill_after": True, "minimum_familiars": 5},
        "COLLECTIBLE_BONE_SPURS": {"enemies": 2, "kill_after": True, "new_familiar": True},
        "COLLECTIBLE_JAR_OF_FLIES": {
            "kill_before": 4,
            "use_tick": 120,
            "familiars": {"BLUE_FLY": 4},
        },
        "COLLECTIBLE_POTATO_PEELER": {
            "delta": {"max_hearts": -2},
            "stats": {"damage": 1, "range": 1},
            "familiars": {"CUBE_OF_MEAT_1": 1},
            "effects": ["PLAYER_CREEP_RED"],
        },
        "COLLECTIBLE_BROWN_NUGGET": {"new_familiar": True, "enemies": 1, "enemy_hurt": True},
        "COLLECTIBLE_SPRINKLER": {
            "new_familiar": True,
            "enemies": 2,
            "enemy_hurt": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_FRIEND_FINDER": {
            "friendly_enemies": True,
            "enemies": 1,
            "enemy_hurt": True,
            "shoot": True,
            "hit_target": True,
            "shoot_until": 420,
            "observe_until": 477,
            "end_tick": 480,
        },
        "COLLECTIBLE_DELIRIOUS": {"friendly_enemies": True, "enemies": 1, "enemy_hurt": True},
        "COLLECTIBLE_LEMEGETON": {"familiars": {"ITEM_WISP": 1}},
        "COLLECTIBLE_SUMPTORIUM": {"delta": {"hearts": -1}, "familiars": {"BLOOD_BABY": 1}},
        "COLLECTIBLE_KEEPERS_BOX": {"shop_spawn": True},
        "COLLECTIBLE_BROKEN_GLASS_CANNON": {"active_replaced": "COLLECTIBLE_GLASS_CANNON"},
        "COLLECTIBLE_INNER_CHILD": {
            "revive": True,
            "revive_hearts": 1,
            "revive_type": "PLAYER_ISAAC",
            "observe_until": 447,
            "end_tick": 450,
            "stats": {"speed": 1, "scale_x": -1},
        },
        "COLLECTIBLE_PLAN_C": {
            "enemies": 2,
            "enemy_damage": 1000,
            "dies": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_BIBLE": {"flying": True, "flying_expire_room": True, "expire_room": True},
        "COLLECTIBLE_MAGIC_FINGERS": {
            "enemies": 2,
            "enemy_damage": 34,
            "delta": {"coins": -1},
            "coins_before": 10,
        },
        "COLLECTIBLE_BLUE_BOX": {"spawns": {"5.10.3": [2, 2]}},
        "COLLECTIBLE_UNDEFINED": {"teleport_any": True, "end_tick": 300},
        "COLLECTIBLE_D8": {"random_stats": True},
        "COLLECTIBLE_SPIDER_BUTT": {"enemies": 2, "enemy_damage": 20, "enemy_flags": ["FLAG_SLOW"]},
        "COLLECTIBLE_MEGA_BEAN": {
            "enemies": 2,
            "enemy_damage": 200,
            "enemy_flags": ["FLAG_FREEZE"],
        },
        "COLLECTIBLE_FLUSH": {"enemies": 2, "removed_enemies": 2, "spawns": {"245.": [2, 2]}},
        "COLLECTIBLE_SCISSORS": {
            "new_familiar": True,
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
        },
        "COLLECTIBLE_BOX_OF_FRIENDS": {
            "familiars": {"DEMON_BABY": 1},
            "expires_at": 240,
            "expire_room": True,
        },
        "CARD_REVERSE_HANGED_MAN": {
            "stats": {"speed": -1},
            "shoot": True,
            "enemies": 2,
            "kill_after": True,
            "kill_with_tears": True,
            "spawn_after_kill": {"5.20.": [2, 3]},
            "shot_volley": 3,
            "expires_at": 990,
            "observe_until": 960,
            "end_tick": 1050,
        },
        "CARD_REVERSE_STRENGTH": {
            "enemies": 1,
            "enemy_flags": ["FLAG_WEAKNESS"],
            "movement_rate": -1,
            "vulnerability": 2,
            "expires_at": 990,
            "end_tick": 1050,
        },
        "CARD_REVERSE_CHARIOT": {
            "immobile_shooting": True,
            "shield_trial": True,
            "stats": {"delay": -1},
            "recover_tick": 390,
            "expires_at": 390,
            "end_tick": 450,
        },
        "CARD_REVERSE_SUN": {
            "flying": True,
            "shoot": True,
            "tear_flags": ["TEAR_SPECTRAL"],
            "stats": {"damage": 1},
            "delta": {"bone": 3, "max_hearts": -6},
        },
    }
)


for name in ("PHD", "LUCKY_FOOT", "VIRGO"):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "pill_conversion": {
            "PILLEFFECT_SPEED_DOWN": "PILLEFFECT_SPEED_UP",
            "PILLEFFECT_TEARS_DOWN": "PILLEFFECT_TEARS_UP",
        },
    }
TRIGGER_EFFECTS["COLLECTIBLE_PHD"].update(
    {
        "health_before": 2,
        "delta": {"hearts": 4},
        "spawns": {"5.70.": [1, 1]},
        "identify_pills": True,
    }
)
TRIGGER_EFFECTS["COLLECTIBLE_LUCKY_FOOT"]["stats"] = {"luck": 1}
TRIGGER_EFFECTS["COLLECTIBLE_VIRGO"].update(
    {"damage_trigger": True, "luck": 100, "shield_after_hit": True}
)
TRIGGER_EFFECTS["COLLECTIBLE_FALSE_PHD"] = {
    "pill_conversion": {
        "PILLEFFECT_SPEED_UP": "PILLEFFECT_SPEED_DOWN",
        "PILLEFFECT_TEARS_UP": "PILLEFFECT_TEARS_DOWN",
    },
    "identify_pills": True,
    "delta": {"soul": 2},
    "pocket_pill": "PILLEFFECT_SPEED_UP",
    "use_pocket": True,
    "stats": {"speed": -1, "damage": 1},
}
TRIGGER_EFFECTS["COLLECTIBLE_STITCHES"] = {
    "swap_familiar": "STITCHES",
    "use_tick": 120,
    "observe_until": 237,
    "end_tick": 240,
}


for name in ("SERPENTS_KISS", "GODS_FLESH"):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name].update(
        {"shoot_until": 420, "observe_until": 477, "end_tick": 480}
    )
TRIGGER_EFFECTS["COLLECTIBLE_3_DOLLAR_BILL"].update(
    {"shoot_until": 840, "observe_until": 897, "end_tick": 900}
)


TRIGGER_EFFECTS["CARD_SOUL_LAZARUS"] = {
    "revival_card": True,
    "end_tick": 450,
    "observe_until": 447,
}
for name, duration in (("CARD_SOUL_SAMSON", 300), ("COLLECTIBLE_BERSERK", 150)):
    TRIGGER_EFFECTS[name] = {
        "shoot": True,
        "knives": True,
        "enemies": 1,
        "target_hp": 10000,
        "enemy_hurt": True,
        "stats": {"damage": 1, "speed": 1},
        "expires_at": duration + 120,
        "shoot_until": duration + 90,
        "observe_until": duration + 117,
        "end_tick": duration + 180,
    }
for name, duration in (("CARD_SOUL_JUDAS", 90), ("COLLECTIBLE_DARK_ARTS", 30)):
    TRIGGER_EFFECTS[name] = {
        "enemies": 1,
        "contact_target": True,
        "contact_tick": 72,
        "enemy_hurt": True,
        "timed_invincible": {"during": [66, 75], "after": duration + 90},
        "observe_until": duration + 117,
        "end_tick": duration + 180,
    }
for name in ("CARD_REVERSE_MAGICIAN", "COLLECTIBLE_SOUL"):
    TRIGGER_EFFECTS[name] = {"repel_projectile": True}
for name in (
    "RUNE_BLANK",
    "RUNE_SHARD",
    "CARD_REVERSE_WHEEL_OF_FORTUNE",
    "COLLECTIBLE_DEAD_SEA_SCROLLS",
):
    TRIGGER_EFFECTS[name] = {
        "random_native_effect": True,
        "loose_pickups": True,
        "rocks": 2,
        "health_before": 2,
        "observe_map": True,
        "curse_before": "CURSE_OF_DARKNESS",
        "inventory_prerequisite": True,
        "observe_until": 297,
        "end_tick": 300,
    }


TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_GOLDEN_RAZOR": {
            "coins_before": 10,
            "delta": {"coins": 0},
            "stats": {"damage": 1},
            "expire_room": True,
        },
        "COLLECTIBLE_MOMS_BOX": {
            "stats": {"luck": 1},
            "spawns": {"5.350.": [1, 1]},
            "trinket_before": "TRINKET_CURVED_HORN",
            "trinket_multiplier": 2,
        },
        "COLLECTIBLE_CLICKER": {"inventory_prerequisite": True, "changes_character": True},
        "COLLECTIBLE_D4": {"inventory_prerequisite": True, "reroll_inventory": True},
        "COLLECTIBLE_D100": {
            "inventory_prerequisite": True,
            "reroll_inventory": True,
            "loose_pickups": True,
            "reroll_pickups": True,
            "reroll_pedestals": True,
        },
        "COLLECTIBLE_D10": {"enemies": 2, "downgrade_enemies": True},
        "COLLECTIBLE_D12": {"rocks": 6, "reroll_grids": True},
        "COLLECTIBLE_DATAMINER": {"random_stats": True, "glitched_pedestal": True},
        "COLLECTIBLE_VOID": {"absorb_pedestal": True, "positive_stats": 2},
        "COLLECTIBLE_ABYSS": {"absorb_pedestal": True, "familiars": {"ABYSS_LOCUST": 1}},
        "COLLECTIBLE_COMPOST": {
            "loose_pickups": True,
            "consume_pickups": True,
            "minimum_familiars": 4,
        },
        "COLLECTIBLE_CROOKED_PENNY": {"loose_pickups": True, "crooked_penny": True},
        "COLLECTIBLE_SACRIFICIAL_ALTAR": {
            "prerequisite_items": ["COLLECTIBLE_BROTHER_BOBBY", "COLLECTIBLE_SISTER_MAGGY"],
            "sacrifice_familiars": True,
            "spawns": {"5.100.": [2, 2]},
        },
        "COLLECTIBLE_PLUM_FLUTE": {
            "familiars": {"BABY_PLUM": 1},
            "enemies": 2,
            "enemy_hurt": True,
            "observe_until": 357,
            "expires_at": 420,
            "end_tick": 450,
        },
        "COLLECTIBLE_ANIMA_SOLA": {
            "enemies": 1,
            "effects": ["ANIMA_CHAIN"],
            "movement_rate": -1,
            "effect_expires": 240,
            "end_tick": 270,
        },
        "COLLECTIBLE_120_VOLT": {"enemies": 2, "lasers": True, "enemy_hurt": True},
        "COLLECTIBLE_MONSTRANCE": {"enemies": 2, "enemy_hurt": True},
        "COLLECTIBLE_CIRCLE_OF_PROTECTION": {
            "enemies": 2,
            "enemy_hurt": True,
            "repel_projectile": True,
            "reflect_projectiles": True,
            "include_room_tears": True,
        },
        "COLLECTIBLE_NUMBER_TWO": {
            "shoot": True,
            "spawns": {"4.": [1, 2]},
            "shoot_until": 240,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_EVIL_EYE": {
            "shoot": True,
            "luck": 100,
            "effects": ["EVIL_EYE"],
            "shoot_until": 840,
            "observe_until": 897,
            "end_tick": 900,
        },
        "COLLECTIBLE_EYE_SORE": {
            "shoot": True,
            "minimum_volley": 2,
            "shoot_until": 420,
            "observe_until": 477,
            "end_tick": 480,
        },
        "COLLECTIBLE_LEAD_PENCIL": {
            "shoot": True,
            "minimum_volley": 8,
            "shoot_until": 600,
            "observe_until": 657,
            "end_tick": 660,
        },
        "COLLECTIBLE_LARGE_ZIT": {
            "shoot": True,
            "tear_flags": ["TEAR_SLOW"],
            "strong_tear": 2,
            "shoot_until": 600,
            "observe_until": 657,
            "end_tick": 660,
        },
        "COLLECTIBLE_SINUS_INFECTION": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "tear_flags": ["TEAR_BOOGER"],
            "enemy_hurt": True,
            "shoot_until": 420,
            "observe_until": 777,
            "end_tick": 780,
            "damage_after_shooting": [450, 480],
        },
        "COLLECTIBLE_PARASITOID": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "tear_flags": ["TEAR_EGG"],
            "enemy_hurt": True,
            "minimum_familiars": 1,
            "effects": ["PLAYER_CREEP_WHITE"],
            "shoot_until": 420,
            "observe_until": 477,
            "end_tick": 480,
        },
        "COLLECTIBLE_SULFURIC_ACID": {
            "shoot": True,
            "enemies": 1,
            "spectral_target": True,
            "tear_flags": ["TEAR_ACID"],
            "enemy_hurt": True,
            "break_obstacle": True,
            "stats": {"damage": 1},
            "shoot_until": 600,
            "observe_until": 657,
            "end_tick": 660,
        },
        "COLLECTIBLE_TERRA": {
            "shoot": True,
            "enemies": 1,
            "spectral_target": True,
            "tear_flags": ["TEAR_ROCK"],
            "enemy_hurt": True,
            "break_obstacle": True,
            "stats": {"damage": 1},
            "shoot_until": 300,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_EYE_OF_GREED": {
            "coins_before": 10,
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_flags": ["FLAG_MIDAS_FREEZE"],
            "spends_coins": True,
            "strong_tear": 1.5,
            "shoot_until": 900,
            "observe_until": 957,
            "end_tick": 960,
        },
        "COLLECTIBLE_STYE": {"shoot": True, "eye_damage_multiplier": 9 / 7},
        "COLLECTIBLE_ANALOG_STICK": {
            "shoot": True,
            "stats": {"delay": -1},
            "diagonal_input": True,
        },
        "COLLECTIBLE_DULL_RAZOR": {
            "prerequisite_items": ["COLLECTIBLE_BLOODY_LUST"],
            "stats": {"damage": 1},
            "fake_damage": True,
        },
    }
)


for name, extra in {
    "FANNY_PACK": {"series_pickups": True},
    "OLD_BANDAGE": {"series_pickups": True},
    "BOZO": {"series_grid": "GRID_POOP"},
    "MARBLES": {"trinket_before": "TRINKET_CURVED_HORN", "series_smelt": True},
    "CAMBION_CONCEPTION": {"series_familiars": 4},
    "CONE_HEAD": {"series_blocks": True},
}.items():
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "repeat_damage": 90,
        "observe_until": 957,
        "end_tick": 960,
        **extra,
    }
TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_SCAPULAR": {
            "health_before": 2,
            "damage_trigger": True,
            "after_hit_soul": 2,
        },
        "COLLECTIBLE_MISSING_PAGE_2": {
            "low_health_after_acquire": [3, 0],
            "damage_trigger": True,
            "enemies": 2,
            "enemy_hurt": True,
        },
        "COLLECTIBLE_NEGATIVE": {
            "low_health_after_acquire": [1, 6],
            "soul_damage_trigger": True,
            "enemies": 2,
            "enemy_hurt": True,
            "stats": {"damage": 1},
        },
        "COLLECTIBLE_CROWN_OF_LIGHT": {
            "damage_trigger": True,
            "damage_buff_lost": True,
            "full_health_before": True,
        },
        "COLLECTIBLE_PURITY": {
            "damage_trigger": True,
            "aura_lifecycle": True,
            "expire_room": True,
            "end_tick": 300,
        },
        "COLLECTIBLE_EMPTY_VESSEL": {
            "health_before": 0,
            "flying": True,
            "delta": {"soul": 4},
        },
        "COLLECTIBLE_RED_STEW": {
            "health_before": 2,
            "stats": {"damage": 1},
            "healed": True,
            "buff_decays": True,
            "observe_until": 897,
            "end_tick": 900,
        },
        "COLLECTIBLE_EMPTY_HEART": {
            "health_before": 2,
            "floor_bonus": {"max_hearts": 2},
            "end_tick": 660,
        },
        "COLLECTIBLE_DREAM_CATCHER": {"floor_bonus": {"soul": 1}, "end_tick": 660},
        "COLLECTIBLE_BLOOD_OATH": {"floor_oath": True, "end_tick": 660},
        "COLLECTIBLE_ISAACS_TOMB": {"floor_pickup": "PICKUP_OLDCHEST", "end_tick": 660},
        "COLLECTIBLE_KEEPERS_KIN": {
            "rocks": 2,
            "destroy_fixture_rocks": True,
            "minimum_familiars": 4,
        },
        "COLLECTIBLE_DIRTY_MIND": {
            "poops": 2,
            "destroy_fixture_poops": True,
            "familiar_range": {"DIP": [2, 8]},
        },
        "COLLECTIBLE_GNAWED_LEAF": {"idle_shield": True, "end_tick": 330},
        "COLLECTIBLE_TOOTH_AND_NAIL": {
            "repeat_damage": 90,
            "series_blocks": True,
            "end_tick": 960,
        },
        "COLLECTIBLE_CRACKED_ORB": {
            "locked_doors": True,
            "damage_trigger": True,
            "open_doors": True,
            "observe_map": True,
            "reveals_room": True,
        },
    }
)


for name, familiar, extras in (
    ("ROBO_BABY", "ROBO_BABY", {"lasers": True}),
    ("ROBO_BABY_2", "ROBO_BABY_2", {"lasers": True}),
    ("LIL_BRIMSTONE", "LIL_BRIMSTONE", {"lasers": True, "shoot_until": 180}),
    ("LIL_ABADDON", "LIL_ABADDON", {"lasers": True, "shoot_until": 180}),
    ("LIL_MONSTRO", "LIL_MONSTRO", {"shoot_until": 180, "minimum_tears": 3}),
    ("BOILED_BABY", "BOILED_BABY", {"minimum_tears": 3}),
    ("FRUITY_PLUM", "FRUITY_PLUM", {"minimum_tears": 3}),
    ("ROTTEN_BABY", "ROTTEN_BABY", {"minimum_spawned_familiars": {"BLUE_FLY": 1}}),
    ("SISSY_LONGLEGS", "SISSY_LONGLEGS", {"minimum_spawned_familiars": {"BLUE_SPIDER": 1}}),
    ("DADDY_LONGLEGS", "DADDY_LONGLEGS", {"shoot": False}),
    ("BOBS_BRAIN", "BOBS_BRAIN", {"enemy_flags": ["FLAG_POISON"]}),
    ("BBF", "BBF", {"target_familiar": "BBF"}),
    (
        "HOLY_WATER",
        "HOLY_WATER",
        {"effects": ["PLAYER_CREEP_HOLYWATER"], "enemy_flags": ["FLAG_FREEZE"]},
    ),
    (
        "HEADLESS_BABY",
        "HEADLESS_BABY",
        {"effects": ["PLAYER_CREEP_RED"], "target_effect": "PLAYER_CREEP_RED"},
    ),
    (
        "DEPRESSION",
        "DEPRESSION",
        {
            "effects": ["PLAYER_CREEP_HOLYWATER_TRAIL"],
            "target_effect": "PLAYER_CREEP_HOLYWATER_TRAIL",
        },
    ),
):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "familiars": {familiar: 1},
        "shoot": True,
        "shoot_until": 420,
        "observe_until": 597,
        "end_tick": 600,
        "enemies": 1,
        "hit_target": True,
        "enemy_hurt": True,
        "include_room_tears": True,
        "suppress_player_tears": True,
        **extras,
    }
TRIGGER_EFFECTS["COLLECTIBLE_AQUARIUS"] = {
    "enemies": 1,
    "enemy_hurt": True,
    "effects": ["PLAYER_CREEP_HOLYWATER_TRAIL"],
    "target_effect": "PLAYER_CREEP_HOLYWATER_TRAIL",
    "observe_until": 357,
    "end_tick": 360,
}
TRIGGER_EFFECTS["COLLECTIBLE_ROBO_BABY"]["target_laser"] = True


TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_DOCTORS_REMOTE": {
            "shoot": True,
            "enemies": 1,
            "enemy_hurt": True,
            "target_effect": "TARGET",
            "effects": ["ROCKET"],
            "shoot_until": 120,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_EPIC_FETUS": {
            "shoot": True,
            "enemies": 1,
            "enemy_hurt": True,
            "target_effect": "TARGET",
            "effects": ["ROCKET"],
            "shoot_until": 240,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_PONY": {
            "moving_use": True,
            "flying": True,
            "stats": {"speed": 1},
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "dash": True,
        },
        "COLLECTIBLE_WHITE_PONY": {
            "moving_use": True,
            "flying": True,
            "stats": {"speed": 1},
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "dash": True,
            "effects": ["CRACK_THE_SKY"],
        },
        "COLLECTIBLE_SUPLEX": {
            "moving_use": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "dash": True,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_CANDLE": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "effects": ["BLUE_FLAME"],
            "effect_expires": 240,
            "end_tick": 270,
        },
        "COLLECTIBLE_RED_CANDLE": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "effects": ["RED_CANDLE_FLAME"],
            "effect_expires": 450,
            "end_tick": 480,
        },
        "COLLECTIBLE_GLASS_CANNON": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "tear_flags": ["TEAR_PIERCING", "TEAR_SPECTRAL"],
            "strong_tear": 10,
        },
        "COLLECTIBLE_BOOMERANG": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "enemy_flags": ["FLAG_FREEZE"],
        },
        "COLLECTIBLE_LARYNX": {"enemies": 2, "enemy_hurt": True},
        "COLLECTIBLE_MAMA_MEGA": {
            "rocks": 3,
            "destroy_rocks": True,
            "enemies": 2,
            "enemy_damage": 400,
            "consumed_active": True,
        },
        "COLLECTIBLE_BLACK_HOLE": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "effects": ["BLACK_HOLE"],
            "target_effect": "BLACK_HOLE",
            "effect_expires": 300,
            "observe_until": 270,
            "end_tick": 360,
        },
        "COLLECTIBLE_WAIT_WHAT": {
            "enemies": 2,
            "enemy_hurt": True,
            "rocks": 2,
            "destroy_rocks": True,
        },
        "COLLECTIBLE_PORTABLE_SLOT": {
            "coins_before": 30,
            "repeat_uses": 12,
            "any_drop": True,
            "observe_until": 447,
            "end_tick": 450,
        },
        "COLLECTIBLE_WOODEN_NICKEL": {
            "repeat_uses": 12,
            "spawns": {"5.20.": [1, 12]},
            "observe_until": 447,
            "end_tick": 450,
        },
        "COLLECTIBLE_FORTUNE_COOKIE": {
            "repeat_uses": 12,
            "any_drop": True,
            "observe_until": 447,
            "end_tick": 450,
        },
        "COLLECTIBLE_METRONOME": {
            "repeat_uses": 12,
            "random_native_effect": True,
            "inventory_prerequisite": True,
            "health_before": 2,
            "observe_until": 447,
            "end_tick": 450,
        },
        "COLLECTIBLE_WAVY_CAP": {
            "stats": {"delay": -1, "speed": -1},
            "visual_review": "distortion",
            "end_tick": 240,
        },
        "COLLECTIBLE_COUPON": {
            "loose_pickups": True,
            "priced_pickups": True,
            "free_pickup": True,
        },
        "COLLECTIBLE_ALABASTER_BOX": {
            "spawns": {"5.10.3": [3, 3], "5.100.": [2, 2]},
            "consumed_active": True,
        },
        "COLLECTIBLE_GELLO": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "new_familiar": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_DECAP_ATTACK": {
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "familiars": {"DECAP_ATTACK": 1},
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_SCOOPER": {
            "shoot": True,
            "enemies": 1,
            "enemy_hurt": True,
            "target_familiar": "PEEPER_2",
            "familiars": {"PEEPER_2": 1},
            "effects": ["PLAYER_CREEP_RED"],
            "observe_until": 357,
            "end_tick": 360,
        },
    }
)


for name in ("DOCTORS_REMOTE", "EPIC_FETUS", "CANDLE", "RED_CANDLE", "BOOMERANG", "BLACK_HOLE"):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name]["suppress_player_tears"] = True
TRIGGER_EFFECTS["COLLECTIBLE_GELLO"].update(
    {
        "suppress_player_tears": True,
        "include_room_tears": True,
        "minimum_tears": 1,
    }
)
TRIGGER_EFFECTS["COLLECTIBLE_SCOOPER"]["shoot"] = False
for name in ("COLLECTIBLE_HEADLESS_BABY", "COLLECTIBLE_DEPRESSION"):
    TRIGGER_EFFECTS[name]["shoot"] = False


TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_STOP_WATCH": {
            "enemies": 1,
            "movement_rate": -1,
            "passive_rate": True,
            "end_tick": 330,
        },
        "COLLECTIBLE_CENSER": {
            "enemies": 1,
            "enemy_flags": ["FLAG_SLOW"],
            "familiars": {"CENSER": 1},
        },
        "COLLECTIBLE_NIGHT_LIGHT": {
            "shoot": True,
            "face_target": True,
            "enemies": 1,
            "hit_target": True,
            "target_distance": 60,
            "enemy_flags": ["FLAG_SLOW"],
            "curse_before": "CURSE_OF_DARKNESS",
            "removes_curse": True,
        },
        "COLLECTIBLE_GODHEAD": {
            "shoot": True,
            "enemies": 1,
            "aim_target": True,
            "homing": True,
            "tear_flags": ["TEAR_HOMING", "TEAR_GLOW"],
            "enemy_hurt": True,
            "stats": {"damage": 1, "delay": 1, "shot_speed": -1},
        },
        "COLLECTIBLE_POLYPHEMUS": {
            "shoot": True,
            "shoot_until": 76,
            "enemies": 2,
            "piercing": True,
            "first_enemy_hp": 1,
            "overflow_damage": True,
            "stats": {"damage": 1, "delay": 1},
        },
        "COLLECTIBLE_HIVE_MIND": {
            "blue_flies_before": 2,
            "enemies": 1,
            "hit_target": True,
            "target_distance": 50,
            "enemy_damage": 28,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_LIBRA": {
            "delta": {"coins": 6, "bombs": 6, "keys": 6},
            "balanced_stats": True,
            "prerequisite_items": ["COLLECTIBLE_CRICKETS_HEAD"],
        },
        "COLLECTIBLE_ROCK_BOTTOM": {
            "active_before": "COLLECTIBLE_BOOK_OF_BELIAL",
            "use_existing_active": True,
            "retains_stat_buff": True,
            "expire_room": True,
        },
        "COLLECTIBLE_CONSOLATION_PRIZE": {"positive_stats": 1, "any_drop": True},
        "COLLECTIBLE_PISCES": {
            "shoot": True,
            "tear_flags": ["TEAR_KNOCKBACK"],
            "stats": {"delay": -1},
            "larger_tears": True,
        },
        "COLLECTIBLE_BATTERY": {
            "active_before": "COLLECTIBLE_D6",
            "charge_before": 6,
            "battery_pickups": 1,
            "overcharge": True,
            "end_tick": 300,
        },
    }
)


for name, familiar, extras in (
    ("FINGER", "FINGER", {}),
    ("SUCCUBUS", "SUCCUBUS", {"shoot": False, "target_familiar": "SUCCUBUS"}),
    ("WORM_FRIEND", "WORM_FRIEND", {"shoot": False, "effects": ["WORM_FRIEND_SNARE"]}),
):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "familiars": {familiar: 1},
        "shoot": True,
        "enemies": 1,
        "hit_target": True,
        "enemy_hurt": True,
        "suppress_player_tears": True,
        "shoot_until": 600,
        "observe_until": 897,
        "end_tick": 900,
        **extras,
    }
TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_SPEAR_OF_DESTINY": {
            "shoot": True,
            "suppress_player_tears": True,
            "enemies": 1,
            "effects": ["SPEAR_OF_DESTINY"],
            "target_effect": "SPEAR_OF_DESTINY",
            "enemy_hurt": True,
            "shoot_until": 300,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_JUICY_SACK": {
            "familiars": {"JUICY_SACK": 1},
            "effects": ["PLAYER_CREEP_WHITE"],
            "target_effect": "PLAYER_CREEP_WHITE",
            "enemies": 1,
            "enemy_flags": ["FLAG_SLOW"],
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_AKELDAMA": {
            "enemies": 1,
            "minimum_tears": 3,
            "tear_damage": 3.5,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_LINGER_BEAN": {
            "shoot": True,
            "effects": ["BROWN_CLOUD"],
            "shoot_until": 600,
            "target_effect": "BROWN_CLOUD",
            "enemies": 1,
            "enemy_hurt": True,
            "suppress_player_tears": True,
            "observe_until": 657,
            "end_tick": 660,
        },
        "COLLECTIBLE_EPIPHORA": {
            "shoot": True,
            "shoot_until": 480,
            "stat_progression": {"delay": -1},
            "observe_until": 477,
            "end_tick": 510,
        },
        "COLLECTIBLE_DEAD_EYE": {
            "shoot": True,
            "shoot_until": 360,
            "enemies": 1,
            "hit_target": True,
            "target_hp": 10000,
            "enemy_hurt": True,
            "stat_progression": {"damage": 1},
            "observe_until": 357,
            "end_tick": 390,
        },
        "COLLECTIBLE_EYE_DROPS": {
            "shoot": True,
            "shoot_until": 420,
            "alternating_cadence": True,
            "observe_until": 417,
            "end_tick": 450,
        },
        "COLLECTIBLE_EYE_OF_THE_OCCULT": {
            "shoot": True,
            "shoot_until": 180,
            "steered_tears": True,
            "stats": {"damage": 1, "range": 1, "shot_speed": -1},
            "observe_until": 237,
            "end_tick": 240,
        },
        "COLLECTIBLE_MIDAS_TOUCH": {
            "enemies": 1,
            "contact_target": True,
            "enemy_hurt": True,
            "coins_before": 99,
            "enemy_flags": ["FLAG_MIDAS_FREEZE"],
        },
        "COLLECTIBLE_E_COLI": {
            "enemies": 1,
            "contact_target": True,
            "spawns": {"245.": [1, 1]},
            "removed_enemies": 1,
        },
        "COLLECTIBLE_BRITTLE_BONES": {
            "damage_trigger": True,
            "bone_break": True,
            "minimum_tears": 5,
            "hit_stats": {"delay": -1},
            "include_room_tears": True,
        },
        "COLLECTIBLE_MONTEZUMAS_REVENGE": {
            "shoot": True,
            "shoot_until": 180,
            "enemies": 1,
            "behind_target": True,
            "target_laser": True,
            "lasers": True,
            "enemy_hurt": True,
            "suppress_player_tears": True,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_MEGA_BLAST": {
            "shoot": True,
            "shoot_until": 500,
            "enemies": 1,
            "hit_target": True,
            "target_hp": 10000,
            "lasers": True,
            "enemy_hurt": True,
            "suppress_player_tears": True,
            "expire_room": True,
            "room_tick": 240,
            "laser_persists_room": True,
            "observe_until": 210,
            "end_tick": 600,
        },
    }
)


TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_CRYSTAL_BALL": {"map": "world", "any_drop": True},
        "COLLECTIBLE_BOOK_OF_SECRETS": {
            "map": "full",
            "repeat_uses": 3,
            "observe_until": 207,
            "end_tick": 240,
        },
        "COLLECTIBLE_REMOTE_DETONATOR": {
            "bomb_trial": True,
            "use_tick": 210,
            "enemies": 1,
            "enemy_hurt": True,
            "delayed_detonation": True,
            "observe_until": 327,
            "end_tick": 330,
        },
        "COLLECTIBLE_PAUSE": {
            "enemies": 1,
            "movement_rate": -1,
            "release_pause": True,
            "end_tick": 360,
        },
        "COLLECTIBLE_MAGGYS_BOW": {
            "consume_pickup": {"variant": "PICKUP_HEART", "subtype": 2, "healing": 2},
            "health_before": 2,
        },
        "COLLECTIBLE_CANDY_HEART": {
            "consume_pickup": {
                "variant": "PICKUP_HEART",
                "subtype": 1,
                "healing": 2,
                "stats": True,
            },
            "health_before": 2,
        },
        "COLLECTIBLE_SOUL_LOCKET": {
            "consume_pickup": {"variant": "PICKUP_HEART", "subtype": 3, "soul": 2, "stats": True}
        },
        "COLLECTIBLE_IMMACULATE_CONCEPTION": {
            "consume_pickup": {"variant": "PICKUP_HEART", "subtype": 2, "count": 15},
            "minimum_familiars": 1,
            "observe_until": 657,
            "end_tick": 660,
        },
        "COLLECTIBLE_4_5_VOLT": {
            "empty_active": True,
            "enemies": 1,
            "target_hp": 10000,
            "hit_target": True,
            "shoot": True,
            "shoot_until": 900,
            "enemy_hurt": True,
            "damage_charges": True,
            "observe_until": 897,
            "end_tick": 930,
        },
        "COLLECTIBLE_STARTER_DECK": {"pocket_conversion": "cards"},
        "COLLECTIBLE_LITTLE_BAGGY": {"pocket_conversion": "pills"},
        "COLLECTIBLE_MISSING_NO": {
            "inventory_prerequisite": True,
            "reroll_inventory": True,
            "reroll_on_floor": True,
            "observe_until": 177,
            "end_tick": 570,
        },
        "COLLECTIBLE_GLITCHED_CROWN": {
            "generated_pedestals": True,
            "pedestal_cycle": 5,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_BINGE_EATER": {
            "generated_pedestals": True,
            "pedestal_cycle": 2,
            "food_cycle": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_TMTRAINER": {
            "generated_pedestals": True,
            "glitch_generated": True,
            "acquire_generated": True,
            "shoot": True,
            "shoot_until": 300,
            "expire_room": True,
            "room_tick": 330,
            "observe_until": 297,
            "end_tick": 450,
        },
    }
)


TRIGGER_EFFECTS["COLLECTIBLE_EVIL_CHARM"] = {
    "fireplace_trial": True,
    "stats": {"luck": 1},
    "end_tick": 480,
}


for name, visit, extras in (
    ("MORE_OPTIONS", {"room": "ROOM_TREASURE", "choice": True}, {"choice_pedestals": 2}),
    (
        "THERES_OPTIONS",
        {"room": "ROOM_BOSS", "kill_boss": True, "choice": True},
        {"choice_pedestals": 2},
    ),
    (
        "VANISHING_TWIN",
        {"room": "ROOM_BOSS", "kill_boss": True, "kill_tick": 720},
        {"copied_boss": True, "boss_pedestals": 2, "end_tick": 960, "observe_until": 957},
    ),
    ("MEMBER_CARD", {"room": "ROOM_SHOP", "stairs": True}, {"underground_shop": True}),
    ("STAIRWAY", {"ladder": True}, {"angel_shop": True}),
    ("CARD_READING", {"portal": True}, {"portal_destination": True}),
    (
        "BOOK_OF_REVELATIONS",
        {"room": "ROOM_BOSS", "kill_boss": True},
        {"rider_boss": True, "use_tick": 360, "delta": {"soul": 2}},
    ),
    (
        "SATANIC_BIBLE",
        {"room": "ROOM_BOSS", "kill_boss": True},
        {"devil_boss_reward": True, "use_tick": 360, "delta": {"soul": 2}},
    ),
    ("SOL", {"room": "ROOM_BOSS", "kill_boss": True}, {"boss_buff": True, "empty_active": True}),
    (
        "LUNA",
        {"room": "ROOM_SECRET", "moonlight": True},
        {"extra_secrets": True, "moonlight_buff": True},
    ),
):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "floor_visit": visit,
        "observe_map": True,
        "observe_until": 657,
        "end_tick": 660,
        **extras,
    }


TRIGGER_EFFECTS.update(INTERACTION_EFFECTS)
TRIGGER_EFFECTS.update(PROJECTILE_EFFECTS)
for name, other in (("KNIFE_PIECE_1", "KNIFE_PIECE_2"), ("KNIFE_PIECE_2", "KNIFE_PIECE_1")):
    TRIGGER_EFFECTS["COLLECTIBLE_" + name] = {
        "prerequisite_items": ["COLLECTIBLE_" + other],
        "familiars": {"KNIFE_FULL": 1},
        "shoot": True,
        "suppress_player_tears": True,
        "shoot_until": 150,
        "target_familiar": "KNIFE_FULL",
        "enemies": 1,
        "enemy_hurt": True,
        "observe_until": 297,
        "end_tick": 300,
    }
TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_TEAR_DETONATOR": {
            "shoot": True,
            "shoot_until": 90,
            "use_tick": 90,
            "minimum_tears": 6,
            "radial": True,
            "observe_until": 177,
            "end_tick": 180,
        },
        "COLLECTIBLE_FRIEND_BALL": {
            "shoot": True,
            "shoot_until": 300,
            "enemies": 1,
            "hit_target": True,
            "removed_enemies": 1,
            "friendly_enemies": True,
            "repeat_uses": 2,
            "repeat_interval": 180,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_SHARP_KEY": {
            "keys_before": 3,
            "shoot": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "resource_spent": {"keys": 1},
            "observe_until": 237,
            "end_tick": 240,
        },
        "COLLECTIBLE_SPIN_TO_WIN": {
            "familiars": {"SPIN_TO_WIN": 1},
            "target_familiar": "SPIN_TO_WIN",
            "enemies": 1,
            "enemy_hurt": True,
            "stats": {"speed": 1},
            "hold_ticks": 120,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_LIL_GURDY": {
            "familiars": {"LIL_GURDY": 1},
            "target_familiar": "LIL_GURDY",
            "shoot": True,
            "suppress_player_tears": True,
            "shoot_until": 140,
            "familiar_speed_after_release": 5,
            "enemies": 1,
            "enemy_hurt": True,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_SMART_FLY": {
            "familiars": {"SMART_FLY": 1},
            "damage_trigger": True,
            "target_familiar": "SMART_FLY",
            "enemies": 1,
            "enemy_hurt": True,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_BIRD_CAGE": {
            "familiars": {"BIRD_CAGE": 1},
            "damage_trigger": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "observe_until": 597,
            "end_tick": 600,
        },
        "COLLECTIBLE_INTRUDER": {
            "shoot": True,
            "suppress_player_tears": True,
            "shoot_until": 300,
            "minimum_volley": 4,
            "enemies": 1,
            "hit_target": True,
            "enemy_flags": ["FLAG_SLOW"],
            "enemy_hurt": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_CONTAGION": {
            "enemies": 3,
            "kill_after": True,
            "kill_limit": 1,
            "enemy_flags": ["FLAG_POISON"],
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_ATHAME": {
            "enemies": 9,
            "kill_after": True,
            "kill_limit": 8,
            "luck": 100,
            "lasers": True,
            "survivor_hurt": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_HUNGRY_SOUL": {
            "enemies": 9,
            "kill_after": True,
            "kill_limit": 8,
            "effects": ["HUNGRY_SOUL"],
            "survivor_hurt": True,
            "observe_until": 597,
            "end_tick": 600,
        },
        "COLLECTIBLE_SALVATION": {
            "enemies": 1,
            "hit_target": True,
            "target_distance": 60,
            "enemy_hurt": True,
            "effects": ["CRACK_THE_SKY"],
            "observe_until": 597,
            "end_tick": 600,
        },
    }
)
TRIGGER_EFFECTS["COLLECTIBLE_MEGA_BLAST"]["native_door"] = True
TRIGGER_EFFECTS["COLLECTIBLE_WAIT_WHAT"]["rocks_ahead"] = True
TRIGGER_EFFECTS["COLLECTIBLE_CRACK_THE_SKY"].update(
    {"repeat_uses": 5, "observe_until": 447, "end_tick": 450}
)
TRIGGER_EFFECTS["COLLECTIBLE_METRONOME"].update(
    {"repeat_uses": 5, "repeat_interval": 150, "observe_until": 897, "end_tick": 900}
)
TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_DEAD_CAT": {
            "revive": True,
            "revive_hearts": 2,
            "revive_type": "PLAYER_ISAAC",
            "remaining_lives": 8,
            "observe_until": 447,
            "end_tick": 450,
        },
        "COLLECTIBLE_GUPPYS_COLLAR": {
            "revive": True,
            "remaining_lives": 1,
            "revive_hearts": 1,
            "revive_type": "PLAYER_ISAAC",
            "rng_seed": 1,
            "observe_until": 447,
            "end_tick": 450,
        },
        "COLLECTIBLE_BEST_FRIEND": {
            "enemies": 1,
            "enemy_hurt": True,
            "target_bomb": True,
            "spawns": {"4.2.": [1, 1]},
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_NOTCHED_AXE": {
            "button_intervals": [
                [70, 80, "ACTION_SHOOTUP"],
                [110, 120, "ACTION_SHOOTUP"],
                [150, 160, "ACTION_SHOOTUP"],
            ],
            "axe": True,
            "enemies": 1,
            "hit_target": True,
            "target_distance": 30,
            "enemy_hurt": True,
            "crush_rock": True,
            "spent_charge": True,
            "floor_recharge": 64,
            "observe_until": 210,
            "end_tick": 600,
        },
        "COLLECTIBLE_BUTTER_BEAN": {
            "repel_projectile": True,
            "use_tick": 96,
            "observe_until": 177,
            "end_tick": 210,
        },
        "COLLECTIBLE_GLITTER_BOMBS": {
            "bomb_trial": True,
            "input_schedule": [[150 + n * 60, 154 + n * 60, "bomb"] for n in range(8)],
            "any_drop": True,
            "observe_until": 810,
            "end_tick": 840,
        },
        "COLLECTIBLE_FAST_BOMBS": {
            "bomb_trial": True,
            "input_schedule": [[78 + n * 9, 81 + n * 9, "bomb"] for n in range(6)],
            "spawns": {"4.": [5, 13]},
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_ROCKET_IN_A_JAR": {
            "shoot": True,
            "shoot_from": 60,
            "suppress_player_tears": True,
            "bomb_trial": True,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "spawns": {"4.19.": [1, 1]},
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_BOOK_OF_VIRTUES": {
            "active_before": "COLLECTIBLE_D6",
            "use_existing_active": True,
            "minimum_spawned_familiars": {"WISP": 1},
            "shoot": True,
            "suppress_player_tears": True,
            "minimum_tears": 1,
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "shoot_until": 300,
            "observe_until": 357,
            "end_tick": 360,
        },
    }
)


TRIGGER_EFFECTS.update(
    {
        "COLLECTIBLE_HEMOPTYSIS": {
            "button_intervals": [[70, 72, "ACTION_SHOOTUP"], [73, 100, "ACTION_SHOOTUP"]],
            "enemies": 1,
            "hit_target": True,
            "target_distance": 45,
            "suppress_player_tears": True,
            "enemy_hurt": True,
            "enemy_flags": ["FLAG_BRIMSTONE_MARKED"],
            "end_tick": 240,
        },
        "COLLECTIBLE_JAW_BONE": {
            "familiars": {"JAW_BONE": 1},
            "shoot": True,
            "suppress_player_tears": True,
            "shoot_until": 300,
            "enemies": 1,
            "target_familiar": "JAW_BONE",
            "enemy_hurt": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_SPIDER_MOD": {
            "familiars": {"SPIDER_MOD": 1},
            "enemies": 1,
            "target_familiar": "SPIDER_MOD",
            "enemy_flags": [
                "FLAG_POISON",
                "FLAG_SLOW",
                "FLAG_FEAR",
                "FLAG_CONFUSION",
                "FLAG_CHARM",
                "FLAG_FREEZE",
            ],
            "any_enemy_flag": True,
            "observe_until": 897,
            "end_tick": 900,
        },
        "COLLECTIBLE_LIL_SPEWER": {
            "familiars": {"LIL_SPEWER": 1},
            "button_intervals": [[90, 160, "ACTION_SHOOTUP"], [510, 580, "ACTION_SHOOTUP"]],
            "suppress_player_tears": True,
            "pocket_pill": "PILLEFFECT_SPEED_UP",
            "input_schedule": [[450, 456, "card"]],
            "enemies": 1,
            "target_effect_prefix": "PLAYER_CREEP_",
            "enemy_hurt": True,
            "creep_changes_after_pill": True,
            "observe_until": 957,
            "end_tick": 960,
        },
        "COLLECTIBLE_BUDDY_IN_A_BOX": {
            "familiars": {"BUDDY_IN_A_BOX": 1},
            "shoot": True,
            "suppress_player_tears": True,
            "minimum_tears": 2,
            "shoot_until": 700,
            "floor_reset": True,
            "familiar_tear_profiles": True,
            "observe_until": 717,
            "end_tick": 720,
        },
        "COLLECTIBLE_LIL_DELIRIUM": {
            "shoot": True,
            "suppress_player_tears": True,
            "minimum_tears": 1,
            "shoot_until": 960,
            "familiar_changes": "any",
            "observe_until": 957,
            "end_tick": 960,
        },
        "COLLECTIBLE_7_SEALS": {
            "enemies": 1,
            "familiar_changes": "any",
            "minimum_spawned_familiars": {"BLUE_FLY": 1},
            "observe_until": 957,
            "end_tick": 960,
        },
        "COLLECTIBLE_CURSED_EYE": {
            "shoot": True,
            "button_intervals": [[70, 150, "ACTION_SHOOTUP"]],
            "minimum_tears": 5,
            "observe_until": 240,
            "end_tick": 270,
        },
        "COLLECTIBLE_ACID_BABY": {
            "familiars": {"ACID_BABY": 1},
            "enemies": 2,
            "pocket_pill": "PILLEFFECT_SPEED_UP",
            "use_pocket": True,
            "enemy_flags": ["FLAG_POISON"],
            "enemy_hurt": True,
            "end_tick": 240,
        },
        "COLLECTIBLE_NANCY_BOMBS": {
            "bomb_trial": True,
            "input_schedule": [[150 + n * 60, 154 + n * 60, "bomb"] for n in range(10)],
            "random_bombs": True,
            "observe_until": 897,
            "end_tick": 900,
        },
        "COLLECTIBLE_MARKED": {
            "button_intervals": [[70, 85, "ACTION_SHOOTUP"]],
            "input_schedule": [[210, 214, "drop"]],
            "autofire_trial": True,
            "minimum_tears": 2,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_NEPTUNUS": {
            "shoot": True,
            "shoot_from": 180,
            "shoot_until": 600,
            "stored_tears_trial": True,
            "observe_until": 597,
            "end_tick": 600,
        },
        "COLLECTIBLE_MARS": {
            "button_intervals": [[70, 72, "ACTION_UP"], [73, 110, "ACTION_UP"]],
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "native_dash": True,
            "observe_until": 237,
            "end_tick": 240,
        },
        "COLLECTIBLE_ARIES": {
            "button_intervals": [[70, 110, "ACTION_UP"]],
            "enemies": 1,
            "hit_target": True,
            "enemy_hurt": True,
            "stats": {"speed": 1},
            "end_tick": 240,
        },
        "COLLECTIBLE_BREATH_OF_LIFE": {
            "hold_ticks": 180,
            "breath_lifecycle": True,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_JUPITER": {
            "target_effect": "SMOKE_CLOUD",
            "button_intervals": [[240, 270, "ACTION_UP"]],
            "enemies": 1,
            "hit_target": True,
            "target_distance": 70,
            "enemy_flags": ["FLAG_POISON"],
            "jupiter_speed": True,
            "observe_until": 417,
            "end_tick": 420,
        },
        "COLLECTIBLE_DOGMA": {
            "stats": {"speed": 1, "damage": 1, "flying": 1},
            "healed_total": 12,
        },
        "COLLECTIBLE_VOODOO_HEAD": {
            "observe_map": True,
            "floor_visit": {"generated": True},
            "extra_curse_rooms": True,
            "observe_until": 597,
            "end_tick": 600,
        },
        "COLLECTIBLE_LOST_SOUL": {
            "familiars": {"LOST_SOUL": 1},
            "floor_pickup_any": ["PICKUP_HEART", "PICKUP_COLLECTIBLE"],
            "observe_until": 597,
            "end_tick": 600,
        },
        "COLLECTIBLE_MINE_CRAFTER": {
            "enemies": 1,
            "hit_target": True,
            "target_distance": 55,
            "enemy_hurt": True,
            "repeat_uses": 2,
            "repeat_interval": 180,
            "repeat_without_recharge": True,
            "target_entity": "ENTITY_MOVABLE_TNT",
            "spawns": {"292.": [1, 1]},
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_MR_ME": {
            "button_intervals": [[70, 90, "ACTION_SHOOTUP"]],
            "suppress_player_tears": True,
            "enemies": 1,
            "hit_target": True,
            "target_distance": 60,
            "target_effect": "MR_ME",
            "cursor_target": "TARGET",
            "align_from": 240,
            "enemy_hurt": True,
            "effects": ["MR_ME"],
            "observe_until": 717,
            "end_tick": 720,
        },
        "COLLECTIBLE_ERASER": {
            "shoot": True,
            "suppress_player_tears": True,
            "keep_player_tear_variants": ["ERASER"],
            "enemies": 1,
            "hit_target": True,
            "removed_enemies": 1,
            "floor_recharge": 1,
            "observe_until": 210,
            "end_tick": 600,
        },
        "COLLECTIBLE_URN_OF_SOULS": {
            "shoot": True,
            "suppress_player_tears": True,
            "keep_player_tear_variants": ["FIRE"],
            "shoot_until": 400,
            "use_tick": 150,
            "hold_ticks": 180,
            "enemies": 9,
            "hit_target": True,
            "kill_after": True,
            "kill_limit": 8,
            "survivor_hurt": True,
            "observe_until": 447,
            "end_tick": 450,
        },
        "COLLECTIBLE_VADE_RETRO": {
            "enemies": 9,
            "kill_after": True,
            "kill_limit": 8,
            "survivor_hurt": True,
            "use_tick": 150,
            "effects": ["ENEMY_GHOST"],
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_ESAU_JR": {
            "inventory_prerequisite": True,
            "repeat_uses": 2,
            "repeat_interval": 180,
            "form_swap_trial": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_MULTIDIMENSIONAL_BABY": {
            "familiars": {"MULTIDIMENSIONAL_BABY": 1},
            "fire_through_familiar": "MULTIDIMENSIONAL_BABY",
            "minimum_tears": 2,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_ANGELIC_PRISM": {
            "familiars": {"ANGELIC_PRISM": 1},
            "fire_through_familiar": "ANGELIC_PRISM",
            "minimum_tears": 4,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_STAR_OF_BETHLEHEM": {
            "familiars": {"STAR_OF_BETHLEHEM": 1},
            "player_in_aura": "STAR_OF_BETHLEHEM",
            "shoot": True,
            "shoot_until": 300,
            "tear_flags": ["TEAR_HOMING"],
            "stats": {"damage": 1, "delay": -1},
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_CUBE_BABY": {
            "familiars": {"CUBE_BABY": 1},
            "kick_familiar": "CUBE_BABY",
            "button_intervals": [[70, 120, "ACTION_UP"]],
            "enemies": 1,
            "target_familiar": "CUBE_BABY",
            "enemy_hurt": True,
            "familiar_velocity": {"variant": "CUBE_BABY", "minimum": 5},
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_GB_BUG": {
            "familiars": {"GB_BUG": 1},
            "button_intervals": [
                interval
                for n in range(4)
                for interval in (
                    [70 + n * 120, 72 + n * 120, "ACTION_SHOOTUP"],
                    [73 + n * 120, 100 + n * 120, "ACTION_SHOOTUP"],
                )
            ],
            "align_from": 70,
            "suppress_player_tears": True,
            "enemies": 1,
            "target_familiar": "GB_BUG",
            "reroll_enemies": True,
            "observe_until": 597,
            "end_tick": 600,
        },
        "COLLECTIBLE_KING_BABY": {
            "prerequisite_items": ["COLLECTIBLE_BROTHER_BOBBY"],
            "familiars": {"KING_BABY": 1},
            "button_intervals": [[70, 150, "ACTION_SHOOTUP"], [100, 140, "ACTION_RIGHT"]],
            "suppress_player_tears": True,
            "enemies": 1,
            "behind_target": True,
            "enemy_hurt": True,
            "minimum_tears": 1,
            "king_baby_trial": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_BAG_OF_CRAFTING": {
            "character_before": "PLAYER_CAIN_B",
            "pocket_active": True,
            "crafting_trial": True,
            "use_tick": 90,
            "input_schedule": [[90 + n * 60, 96 + n * 60, "card"] for n in range(8)]
            + [[600, 720, "card"]],
            "button_intervals": [[110 + n * 60, 116 + n * 60, "ACTION_SHOOTUP"] for n in range(8)],
            "observe_until": 837,
            "end_tick": 840,
        },
        "COLLECTIBLE_HOLD": {
            "character_before": "PLAYER_BLUEBABY_B",
            "pocket_active": True,
            "hold_poop_trial": True,
            "input_schedule": [[240, 246, "card"]],
            "button_intervals": [[270, 276, "ACTION_SHOOTUP"]],
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_PLACENTA": {
            "placenta_trial": True,
            "rng_seed": 1,
            "observe_until": 7197,
            "end_tick": 7200,
        },
        "COLLECTIBLE_TELEKINESIS": {
            "repel_projectile": True,
            "reflect_projectiles": True,
            "projectile_offset": [0, -70],
            "projectile_velocity": [0, 4],
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_VENTRICLE_RAZOR": {
            "portal_pair_trial": True,
            "repeat_uses": 2,
            "repeat_interval": 180,
            "button_intervals": [[260, 276, "ACTION_DOWN"]],
            "observe_until": 477,
            "end_tick": 480,
        },
        "COLLECTIBLE_LIL_PORTAL": {
            "portal_feed_trial": True,
            "familiars": {"LIL_PORTAL": 1},
            "button_intervals": [
                interval
                for n in range(4)
                for interval in (
                    [90 + n * 120, 92 + n * 120, "ACTION_SHOOTUP"],
                    [93 + n * 120, 120 + n * 120, "ACTION_SHOOTUP"],
                )
            ]
            + [[600, 620, "ACTION_DOWN"]],
            "suppress_player_tears": True,
            "observe_until": 837,
            "end_tick": 840,
        },
        "COLLECTIBLE_PAY_TO_PLAY": {
            "coin_chest_trial": True,
            "coins_before": 20,
            "keys_before": 0,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_KEEPERS_SACK": {
            "paid_stats_trial": True,
            "coins_before": 99,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_POUND_OF_FLESH": {
            "floor_visit": {"room": "ROOM_SHOP"},
            "flesh_prices_trial": True,
            "observe_until": 597,
            "end_tick": 600,
        },
        "COLLECTIBLE_SPELUNKER_HAT": {
            "secret_adjacent": True,
            "secret_map_trial": True,
            "observe_map": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_DOG_TOOTH": {
            "secret_adjacent": True,
            "secret_sound_trial": True,
            "secret_sound_delay": 300,
            "stats": {"speed": 1, "damage": 1},
            "observe_until": 657,
            "end_tick": 660,
        },
        "COLLECTIBLE_YO_LISTEN": {
            "fairy_trial": True,
            "stats": {"luck": 1},
            "observe_until": 897,
            "end_tick": 900,
        },
        "COLLECTIBLE_BLANKET": {
            "floor_visit": {"room": "ROOM_BOSS"},
            "blanket_trial": True,
            "observe_until": 747,
            "end_tick": 750,
        },
        "COLLECTIBLE_MERCURIUS": {
            "native_door": True,
            "mercurius_trial": True,
            "stats": {"speed": 1},
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_SPIRIT_SHACKLES": {
            "low_health_after_acquire": [1, 0],
            "prevent_fatal": True,
            "shackles_trial": True,
            "null_effects": ["ID_SPIRIT_SHACKLES_SOUL", "ID_SPIRIT_SHACKLES_DISABLED"],
            "observe_until": 777,
            "end_tick": 780,
        },
        "COLLECTIBLE_STRAW_MAN": {
            "strawman_trial": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_RECALL": {
            "prerequisite_items": ["COLLECTIBLE_BIRTHRIGHT"],
            "character_before": "PLAYER_THEFORGOTTEN_B",
            "pocket_active": True,
            "pocket_subplayer": True,
            "recall_trial": True,
            "use_tick": 180,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_D7": {
            "entry_trial": 1,
            "clear_entries": True,
            "d7_trial": True,
            "use_tick": 240,
            "observe_until": 417,
            "end_tick": 420,
        },
        "COLLECTIBLE_BROKEN_SHOVEL": {
            "shovel_feet_trial": True,
            "use_tick": 600,
            "observe_until": 1017,
            "end_tick": 1020,
        },
        "COLLECTIBLE_BROKEN_SHOVEL_2": {
            "physical_pickup": True,
            "prerequisite_items": ["COLLECTIBLE_BROKEN_SHOVEL"],
            "completed_shovel_trial": True,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_MOMS_BRACELET": {
            "physical_shoot": True,
            "lift_rock": True,
            "use_tick": 90,
            "crush_rock": True,
            "button_intervals": [
                [80, 85, "ACTION_SHOOTUP"],
                [100, 115, "ACTION_UP"],
                [180, 190, "ACTION_SHOOTUP"],
            ],
            "suppress_player_tears": True,
            "enemies": 1,
            "hit_target": True,
            "target_distance": 100,
            "enemy_hurt": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_GUPPYS_EYE": {
            "guppy_preview_trial": True,
            "visual_review": "native_chest_contents_preview",
            "observe_until": 417,
            "end_tick": 420,
        },
        "COLLECTIBLE_FLIP": {
            "floor_visit": {"room": "ROOM_TREASURE"},
            "flip_pedestal_trial": True,
            "use_tick": 690,
            "observe_until": 837,
            "end_tick": 840,
        },
        "COLLECTIBLE_DEATHS_LIST": {
            "entry_trial": 1,
            "deaths_list_trial": True,
            "observe_until": 717,
            "end_tick": 720,
        },
        "COLLECTIBLE_BETRAYAL": {
            "betrayal_trial": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_MY_SHADOW": {
            "enemies": 1,
            "shadow_contact_trial": True,
            "friendly_enemies": True,
            "enemy_hurt": True,
            "button_intervals": [[90, 180, "ACTION_RIGHT"], [210, 300, "ACTION_LEFT"]],
            "observe_until": 597,
            "end_tick": 600,
        },
        "COLLECTIBLE_BLOOD_PUPPY": {
            "puppy_feed_trial": True,
            "observe_until": 1647,
            "end_tick": 1650,
        },
        "COLLECTIBLE_DINF": {
            "inventory_prerequisite": True,
            "reroll_inventory": True,
            "loose_pickups": True,
            "duplicate_one": True,
            "repeat_uses": 2,
            "repeat_interval": 120,
            "input_schedule": [[120, 124, "drop"]],
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_BACKSTABBER": {
            "shoot": True,
            "shoot_until": 240,
            "tear_flags": ["TEAR_BACKSTAB"],
            "enemies": 1,
            "hit_target": True,
            "target_velocity": [0, -2],
            "enemy_flags": ["FLAG_BLEED_OUT"],
            "enemy_hurt": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_BROKEN_MODEM": {
            "modem_projectiles_trial": True,
            "observe_until": 657,
            "end_tick": 660,
        },
        "COLLECTIBLE_IBS": {
            "ibs_trial": True,
            "enemies": 1,
            "hit_target": True,
            "target_hp": 3000,
            "enemy_hurt": True,
            "button_intervals": [[90 + n * 120, 180 + n * 120, "ACTION_SHOOTUP"] for n in range(4)],
            "observe_until": 657,
            "end_tick": 660,
        },
        "COLLECTIBLE_DUALITY": {
            "prerequisite_items": ["COLLECTIBLE_GOAT_HEAD"],
            "floor_visit": {"room": "ROOM_BOSS", "kill_boss": True},
            "deal_item_trial": "duality",
            "observe_until": 837,
            "end_tick": 840,
        },
        "COLLECTIBLE_REDEMPTION": {
            "prerequisite_items": ["COLLECTIBLE_GOAT_HEAD"],
            "floor_visit": {"room": "ROOM_BOSS", "kill_boss": True},
            "deal_item_trial": "redemption",
            "observe_until": 1077,
            "end_tick": 1080,
        },
        "COLLECTIBLE_SANGUINE_BOND": {
            "prerequisite_items": ["COLLECTIBLE_GOAT_HEAD"],
            "floor_visit": {"room": "ROOM_BOSS", "kill_boss": True},
            "deal_item_trial": "sanguine",
            "observe_until": 1437,
            "end_tick": 1440,
        },
        "COLLECTIBLE_EDENS_BLESSING": {
            "physical_pickup": True,
            "eden_next_run": True,
            "stats": {"delay": -1},
            "observe_until": 177,
            "end_tick": 180,
        },
        "COLLECTIBLE_DIVINE_INTERVENTION": {
            "button_intervals": [[70, 72, "ACTION_SHOOTUP"], [73, 100, "ACTION_SHOOTUP"]],
            "suppress_player_tears": True,
            "effects": ["DIVINE_INTERVENTION"],
            "repel_projectile": True,
            "reflect_projectiles": True,
            "projectile_offset": [0, -40],
            "projectile_velocity": [0, 4],
            "observe_until": 237,
            "end_tick": 240,
        },
        "COLLECTIBLE_TAURUS": {
            "entry_trial": 1,
            "taurus_trial": True,
            "observe_until": 1797,
            "end_tick": 1800,
        },
        "COLLECTIBLE_ZODIAC": {
            "zodiac_trial": True,
            "floor_reset": True,
            "observe_until": 717,
            "end_tick": 720,
        },
        "COLLECTIBLE_BLACK_POWDER": {
            "button_intervals": [
                [90 + n * 48 + i * 12, 102 + n * 48 + i * 12, action]
                for n in range(2)
                for i, action in enumerate(
                    ("ACTION_RIGHT", "ACTION_UP", "ACTION_LEFT", "ACTION_DOWN")
                )
            ],
            "effects": ["PENTAGRAM_BLACKPOWDER"],
            "enemies": 1,
            "hit_target": True,
            "target_distance": 200,
            "target_effect": "PENTAGRAM_BLACKPOWDER",
            "enemy_hurt": True,
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_SHARD_OF_GLASS": {
            "damage_trigger": True,
            "shard_trial": True,
            "observe_until": 957,
            "end_tick": 960,
        },
        "COLLECTIBLE_ASTRAL_PROJECTION": {
            "damage_trigger": True,
            "enemies": 1,
            "hit_target": True,
            "astral_trial": True,
            "shoot": True,
            "shoot_until": 240,
            "observe_until": 297,
            "end_tick": 300,
        },
        "COLLECTIBLE_PURGATORY": {
            "enemies": 1,
            "hit_target": True,
            "purgatory_trial": True,
            "effects": ["PURGATORY"],
            "enemy_hurt": True,
            "observe_until": 897,
            "end_tick": 900,
        },
        "COLLECTIBLE_PASCHAL_CANDLE": {
            "entry_floor": True,
            "entry_trial": 2,
            "clear_entries": True,
            "paschal_trial": True,
            "observe_until": 897,
            "end_tick": 900,
        },
        "COLLECTIBLE_AZAZELS_RAGE": {
            "clear_count": 4,
            "confirm_entry_clear": True,
            "shoot": True,
            "shoot_from": 940,
            "shoot_until": 1030,
            "entry_floor": True,
            "entry_trial": 5,
            "clear_entries": True,
            "lasers": True,
            "observe_until": 1377,
            "end_tick": 1380,
        },
        "COLLECTIBLE_CHARGED_BABY": {
            "empty_active": True,
            "familiars": {"CHARGED_BABY": 1},
            "enemies": 1,
            "hit_target": True,
            "enemy_flags": ["FLAG_FREEZE"],
            "any_charge_event": True,
            "observe_until": 3897,
            "end_tick": 3900,
        },
        "COLLECTIBLE_KIDNEY_STONE": {
            "shoot": True,
            "shoot_until": 2100,
            "tear_variant": "STONE",
            "observe_until": 2157,
            "end_tick": 2160,
        },
        "COLLECTIBLE_BROKEN_WATCH": {
            "entry_floor": True,
            "entry_trial": 8,
            "watch_trial": True,
            "observe_until": 1737,
            "end_tick": 1740,
        },
        "COLLECTIBLE_TOXIC_SHOCK": {
            "entry_trial": 1,
            "enemies": 1,
            "enemy_flags": ["FLAG_POISON"],
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_CAMO_UNDIES": {
            "camo_uncloak": True,
            "entry_trial": 1,
            "enemies": 1,
            "enemy_flags": ["FLAG_CONFUSION"],
            "shoot": True,
            "shoot_from": 180,
            "shoot_until": 240,
            "stats": {"speed": 1, "damage": 1, "delay": -1},
            "observe_until": 357,
            "end_tick": 360,
        },
        "COLLECTIBLE_POKE_GO": {
            "entry_floor": True,
            "entry_trial": 8,
            "friendly_enemies": True,
            "rng_seed": 1,
            "observe_until": 1737,
            "end_tick": 1740,
        },
        "COLLECTIBLE_SATURNUS": {
            "entry_trial": 1,
            "minimum_tears": 7,
            "replicate_tears": True,
            "observe_until": 357,
            "end_tick": 360,
        },
    }
)


# Boss death animations finish before the native reward creates deal doors.
for name in ("DUALITY", "REDEMPTION", "SANGUINE_BOND"):
    recipe = TRIGGER_EFFECTS["COLLECTIBLE_" + name]
    recipe["deal_delay"] = DEAL_REWARD_SETTLE_TICKS
    recipe["observe_until"] += DEAL_REWARD_SETTLE_TICKS
    recipe["end_tick"] += DEAL_REWARD_SETTLE_TICKS
TRIGGER_EFFECTS["COLLECTIBLE_MOMS_BRACELET"]["button_intervals"].insert(0, [78, 100, "ACTION_UP"])


TRIGGER_EFFECTS.update(TRINKET_EFFECTS)
for camouflage in ("COLLECTIBLE_CAMO_UNDIES", "TRINKET_FADED_POLAROID"):
    TRIGGER_EFFECTS[camouflage]["camouflage_trial"] = True
    TRIGGER_EFFECTS[camouflage]["scenarios"] = {
        "single_holder": {},
        "both_hidden": {"peer_item": "COLLECTIBLE_CAMO_UNDIES", "entry_trial": 1},
    }
TRIGGER_EFFECTS["COLLECTIBLE_TMTRAINER"]["scenarios"] = {
    "seed-" + str(i + 1): {"run_seed": 100003 + i * 7919} for i in range(8)
}
TRIGGER_EFFECTS["COLLECTIBLE_BIRTHRIGHT"] = {"scenarios": BIRTHRIGHT_SCENARIOS}
TRIGGER_EFFECTS["COLLECTIBLE_CHAMPION_BELT"] = {
    **TRINKET_EFFECTS["TRINKET_PURPLE_HEART"],
    "stats": {"damage": 1},
}


def trigger_recipe(case):
    recipe = TRIGGER_EFFECTS.get(case.get("enum"), {})
    scenario = case.get("scenario")
    selected = recipe.get("scenarios", {})[scenario] if scenario else {}
    return {
        **{key: value for key, value in recipe.items() if key != "scenarios"},
        **(recipe.get("horse", {}) if case.get("horse") else {}),
        **selected,
    }


def trigger_checks(case, observations):
    rules = trigger_recipe(case)
    if not rules:
        return []
    checks = []
    remote_world = case.get("slot") == 0 and case.get("split") is True
    world_checks = {
        "friendly_enemy",
        "secret_doors",
        "enemy_movement",
        "enemy_health",
        "laser_attack",
        "knife_attack",
        "bomb_attack",
        "lasers_geometry",
        "knives_geometry",
        "explosives_geometry",
        "projectiles_geometry",
        "bombs",
        "tear_motion",
        "tear_appearance",
        "pickups",
        "pedestals",
        "poop_count",
        "rock_count",
        *rules.get("effects", []),
        *rules.get("familiars", {}),
        *rules.get("familiar_range", {}),
        *rules.get("minimum_spawned_familiars", {}),
    }

    def check(name, values):
        if (
            remote_world
            and name.removeprefix("replica:") in world_checks
            and name.startswith("replica:")
        ):
            return
        checks.append(
            {
                "name": "trigger:" + name,
                "status": "missing" if not values else "passed" if all(values) else "failed",
            }
        )

    def probes(role):
        values = []
        for event in observations.get(role, []):
            if event["event"] != "trigger_probe":
                continue
            value = dict(event)
            # The game's JSON encoder represents an empty Lua table as [].
            for name in (
                "tear_flags",
                "enemy_flags",
                "effects",
                "familiars",
                "spawned",
                "pickup_types",
                "null_effects",
                "grids",
                "pedestal_options",
            ):
                if value.get(name) == []:
                    value[name] = {}
            values.append(value)
        return values

    host, client = probes("host"), probes("client")
    before = next((e for e in host if e.get("label") == "before"), None)
    use_tick = case.get("use_tick", 60)
    after = [e for e in host if use_tick <= e["tick"] <= rules.get("observe_until", 177)]
    check("observations", [bool(before), len(after) >= 3, len(client) >= 3])
    if not before or not after:
        return checks
    interaction_checks(rules, observations, host, check)
    trinket_checks(rules, observations, host, check)
    birthright_checks(rules, observations, host, check)
    if rules.get("damage_source"):
        check(
            "native_effect_is_damage_source",
            [
                any(
                    e["event"] == "native_effect_damage_source"
                    and e["amount"] > 0
                    and e.get("source_type") == e["expected_type"]
                    and e.get("source_variant") == e["expected_variant"]
                    for e in observations.get("host", [])
                )
            ],
        )
    if rules.get("eden_next_run"):
        initial = next(
            (e for e in observations.get("host", []) if e["event"] == "eden_run_initial"), None
        )
        following = next(
            (e for e in observations.get("host", []) if e["event"] == "eden_next_run"), None
        )
        check(
            "blessing_grants_item_in_next_native_run",
            []
            if following is None
            else [initial is not None and following["count"] > initial["count"]],
        )
    if rules.get("ibs_trial"):
        check(
            "damage_and_release_trigger_native_ibs_effect",
            [
                any(
                    any(k.startswith(("245.", "4.")) and n > 0 for k, n in e["spawned"].items())
                    or e["effects"].get("FART", 0) > 0
                    or e["effects"].get("CREEP_LIQUID_POOP", 0) > 0
                    for e in after
                    if e["tick"] >= 180
                )
            ],
        )
    if rules.get("deaths_list_trial"):
        kills = [e for e in observations.get("host", []) if e["event"] == "marked_enemy_killed"]
        targets = next(
            (
                e["count"]
                for e in observations.get("host", [])
                if e["event"] == "deaths_list_native_targets"
            ),
            0,
        )
        check(
            "kills_follow_native_skull_marks",
            [targets > 0 and len(kills) == targets and len({e["seed"] for e in kills}) == targets],
        )
        check(
            "completing_deaths_list_grants_reward",
            [
                any(
                    e["pickup_count"] > before["pickup_count"]
                    or any(
                        (e[k] - before[k]) * (-1 if k == "delay" else 1) > 0.001
                        for k in ("damage", "delay", "speed", "range", "luck", "shot_speed")
                    )
                    for e in after
                    if e["tick"] >= 600
                )
            ],
        )
    if rules.get("shovel_feet_trial"):
        early = [e for e in host if 90 <= e["tick"] <= 570]
        late = [e for e in host if e["tick"] >= 810]
        check(
            "broken_shovel_summons_native_feet",
            [any(e["effects"].get("MOM_FOOT_STOMP", 0) > 0 for e in early)],
        )
        check(
            "active_use_stops_feet_for_room",
            [bool(late), all(e["effects"].get("MOM_FOOT_STOMP", 0) == 0 for e in late)],
        )
    if rules.get("completed_shovel_trial"):
        check(
            "two_parts_form_moms_shovel",
            [
                before["active_item"] == "COLLECTIBLE_BROKEN_SHOVEL",
                any(e["active_item"] == "COLLECTIBLE_MOMS_SHOVEL" for e in after),
            ],
        )
    if rules.get("shackles_trial"):
        ghost = [e for e in after if 100 <= e["tick"] <= 300]
        revived = [e for e in after if 450 <= e["tick"] <= 570]
        rearmed = [e for e in after if e["tick"] >= 690]
        check(
            "lethal_hit_enters_shackled_soul",
            [any(e["null_effects"].get("ID_SPIRIT_SHACKLES_SOUL") for e in ghost)],
        )
        check(
            "surviving_soul_returns_to_living_body",
            [
                bool(revived),
                all(
                    not e["dead"]
                    and not e["ghost"]
                    and not e["null_effects"].get("ID_SPIRIT_SHACKLES_SOUL")
                    for e in revived
                ),
            ],
        )
        check(
            "soul_heart_rearms_shackles",
            [
                any(e["null_effects"].get("ID_SPIRIT_SHACKLES_DISABLED") for e in revived),
                all(not e["null_effects"].get("ID_SPIRIT_SHACKLES_DISABLED") for e in rearmed),
            ],
        )
    if rules.get("taurus_trial"):
        check(
            "combat_gradually_increases_speed",
            [max(e["speed"] for e in after) > before["speed"] + 0.5],
        )
        check(
            "native_rage_then_expiry",
            [
                any(e["invincible"] for e in after),
                any(not e["invincible"] for e in after if e["tick"] >= 1700),
            ],
        )
        check(
            "native_rage_contact_damages_enemy",
            [any(e["event"] == "taurus_native_damage" for e in observations.get("host", []))],
        )
    if rules.get("zodiac_trial"):
        values = [e for e in observations.get("host", []) if e["event"] == "zodiac_effects"]
        first = [e["effects"] for e in values if 90 <= e["tick"] <= 210]
        second = [e["effects"] for e in values if 450 <= e["tick"] <= 690]
        check(
            "native_star_sign_effect_on_both_floors",
            [bool(first), bool(second), all(bool(v) for v in first + second)],
        )
        check("floor_rerolls_star_sign", [bool(first) and bool(second) and first[-1] != second[-1]])
    if rules.get("shard_trial"):
        bleeding = [e for e in host if 120 <= e["tick"] <= 720]
        healed = [e for e in host if e["tick"] >= 900]
        check("damage_starts_native_blood_tears", [any(e["tears"] for e in bleeding)])
        check(
            "bleeding_later_consumes_health",
            [bool(bleeding) and any(e["hearts"] < bleeding[0]["hearts"] for e in bleeding)],
        )
        check(
            "red_heart_healing_stops_bleeding", [bool(healed), all(not e["tears"] for e in healed)]
        )
    if rules.get("astral_trial"):
        active = [e for e in host if 100 <= e["tick"] <= 140]
        check(
            "damage_triggers_astral_flight",
            [not before["flying"], any(e["flying"] for e in active)],
        )
        updates = [t["updates"] for e in active for t in e["targets"]]
        check("astral_pauses_enemy_simulation", [len(updates) > 3 and max(updates) == min(updates)])

        def shot_ages(low, high):
            return {
                t["seed"]
                for e in host
                if low <= e["tick"] <= high
                for t in e["tears"]
                if t.get("age", 9999) <= 3
            }

        check(
            "astral_boosts_actual_firing_rate", [len(shot_ages(96, 138)) > len(shot_ages(180, 222))]
        )
        hits = [e for e in observations.get("host", []) if e["event"] == "astral_shield_result"]
        check(
            "astral_shield_absorbs_one_later_hit",
            [
                len(hits) == 2
                and hits[0]["after"] == hits[0]["before"]
                and hits[1]["after"] < hits[1]["before"]
            ],
        )
    if rules.get("purgatory_trial"):
        attempts = [
            e for e in observations.get("host", []) if e["event"] == "purgatory_crack_crossed"
        ]
        check("player_crosses_native_purgatory_crack", [bool(attempts)])
    if rules.get("clear_entries"):
        clears = [e for e in observations.get("host", []) if e["event"] == "native_entry_clear"]
        check(
            "native_combat_rooms_cleared",
            [
                len(clears) == rules.get("clear_count", rules["entry_trial"]),
                sum(e["killed"] > 0 for e in clears)
                >= rules.get("minimum_combat_clears", len(clears)),
            ],
        )
    if rules.get("confirm_entry_clear"):
        settled = [
            e for e in observations.get("host", []) if e["event"] == "native_entry_clear_confirmed"
        ]
        check(
            "native_rooms_actually_clear",
            [
                len(settled) == rules["clear_count"]
                and all(e["clear"] and e["alive"] == 0 for e in settled)
            ],
        )
    if rules.get("paschal_trial"):
        check(
            "clearing_rooms_increases_tears",
            [any(e["delay"] < before["delay"] for e in host if 650 <= e["tick"] <= 720)],
        )
        check(
            "damage_resets_paschal_bonus",
            [all(abs(e["delay"] - before["delay"]) < 0.01 for e in host if e["tick"] >= 810)],
        )
    if rules.get("familiar_tear_profiles"):

        def profiles(low, high):
            return {
                (
                    round(t["damage"], 3),
                    tuple(round(v, 3) for v in t["color"]),
                    round(t["scale"], 3),
                )
                for e in host
                if low <= e["tick"] <= high
                for t in e["tears"]
                if t.get("age", 0) > 0
            }

        early, late = profiles(90, 210), profiles(420, 690)
        check("new_floor_changes_familiar_tear_profile", [bool(early), bool(late), early != late])
    if rules.get("creep_changes_after_pill"):

        def creeps(low, high):
            return {
                name
                for e in host
                if low <= e["tick"] <= high
                for name, count in e["effects"].items()
                if count and name.startswith("PLAYER_CREEP_")
            }

        early, late = creeps(160, 400), creeps(580, 900)
        check("charged_release_fires_familiar_creep", [bool(early), bool(late)])
        check("pill_changes_familiar_creep", [early != late])
    if rules.get("familiar_changes"):
        wanted = rules["familiar_changes"]
        forms = {
            (f["variant"], f.get("subtype"))
            for e in after
            for f in e["familiar_positions"]
            if wanted == "any" or f["variant"] == wanted
        }
        check("native_familiar_changes_form", [len(forms) >= 2])
    if rules.get("random_bombs"):
        flags = {b.get("flags") for e in after for b in e["explosives"]}
        check("native_random_bomb_effects", [len(flags) >= 2])
    if rules.get("autofire_trial"):
        firing = [e for e in host if 120 <= e["tick"] <= 180]
        stopped = [e for e in host if e["tick"] >= 270]
        check("marked_fires_after_releasing_direction", [any(e["tears"] for e in firing)])
        check("drop_stops_marked_autofire", [not e["tears"] for e in stopped])
    if rules.get("stored_tears_trial"):

        def shots(low, high):
            return {t["seed"] for e in host if low <= e["tick"] <= high for t in e["tears"]}

        charged, spent = shots(180, 210), shots(540, 570)
        check(
            "stored_charge_increases_initial_firing_rate", [len(charged) > len(spent), bool(spent)]
        )
    if rules.get("native_dash"):
        check(
            "double_movement_input_triggers_dash",
            [any(abs(e["vx"]) + abs(e["vy"]) > 12 for e in after)],
        )
    if rules.get("breath_lifecycle"):
        check("held_breath_spends_charge", [any(e["charge"] == 0 for e in after)])
        check("empty_breath_grants_invincibility", [any(e["invincible"] for e in after)])
        check(
            "overholding_breath_causes_health_loss",
            [any(e["hearts"] < before["hearts"] for e in after if e["tick"] > 180)],
        )
    if rules.get("jupiter_speed"):
        idle = [e["speed"] for e in host if 180 <= e["tick"] <= 237]
        moving = [e["speed"] for e in host if 264 <= e["tick"] <= 270]
        check(
            "jupiter_speed_builds_idle_and_falls_moving",
            [bool(idle), bool(moving), max(idle, default=0) > min(moving, default=0)],
        )
    if rules.get("healed_total"):
        check(
            "native_health_refill",
            [any(e["hearts"] + e["soul"] == rules["healed_total"] for e in after)],
        )
    if rules.get("extra_curse_rooms"):
        late = [e for e in host if e["tick"] >= 450]
        check(
            "native_floor_adds_second_curse_room",
            [sum(r["type"] == 10 for r in e["map"]) >= 2 for e in late],
        )
    if rules.get("floor_pickup_any"):
        late = [e for e in host if e["tick"] >= 450]
        check(
            "living_familiar_grants_next_floor_reward",
            [
                any(
                    any(
                        e["pickup_types"].get(kind, 0) > 0
                        or kind == "PICKUP_COLLECTIBLE"
                        and any(
                            p["seed"] not in {q["seed"] for q in before["pedestals"]}
                            for p in e["pedestals"]
                        )
                        for kind in rules["floor_pickup_any"]
                    )
                    for e in late
                )
            ],
        )
        check("native_reward_floor_changed", [e["stage"] > before["stage"] for e in late])
    if rules.get("resource_spent"):
        ready = next((e for e in host if e["tick"] == use_tick - 3), None)
        for field, amount in rules["resource_spent"].items():
            check(
                "native_spends:" + field,
                [
                    ready is not None
                    and any(
                        e[field] == ready[field] - amount
                        for e in after
                        if e["tick"] >= use_tick + 30
                    )
                ],
            )
    if rules.get("form_swap_trial"):
        ready = next((e for e in host if e["tick"] == 57), before)
        alternate = [e for e in host if 120 <= e["tick"] <= 210]
        returned = [e for e in host if e["tick"] >= 300]
        check(
            "alternate_form_has_independent_inventory_and_flight",
            [e["inventory"] != ready["inventory"] and e["flying"] for e in alternate],
        )
        check(
            "second_use_restores_original_identity_and_inventory",
            [
                e["player_type"] == before["player_type"] and e["inventory"] == ready["inventory"]
                for e in returned
            ],
        )
    if rules.get("king_baby_trial"):
        held = [
            f
            for e in host
            if 105 <= e["tick"] <= 135
            for f in e["familiar_positions"]
            if f["variant"] == "KING_BABY"
        ]
        check(
            "king_baby_stays_while_holder_moves_and_shoots",
            [
                len(held) >= 3,
                max((f["x"] for f in held), default=0) - min((f["x"] for f in held), default=0) < 5,
            ],
        )
        check(
            "followers_aim_opposite_to_held_firing_direction",
            [
                any(
                    t["vy"] > 0
                    for e in host
                    if 90 <= e["tick"] <= 150
                    for t in e["tears"]
                    if t.get("age", 0) > 0
                )
            ],
        )
        check("followers_stop_after_release", [not e["tears"] for e in host if e["tick"] >= 300])
    if rules.get("familiar_velocity"):
        motion = rules["familiar_velocity"]
        check(
            "native_kick_accelerates_familiar",
            [
                any(
                    abs(f["vx"]) + abs(f["vy"]) >= motion["minimum"]
                    for e in after
                    for f in e["familiar_positions"]
                    if f["variant"] == motion["variant"]
                )
            ],
        )
    if rules.get("placenta_trial"):
        ready = next((e for e in host if e["tick"] == 90), None)
        check(
            "placenta_native_timed_healing",
            [
                ready is not None
                and ready["hearts"] == 1
                and any(e["hearts"] > 1 for e in after if e["tick"] > 300)
            ],
        )
    if rules.get("any_charge_event"):
        check(
            "charged_baby_native_combat_effect",
            [
                any(
                    e["charge"] > 0
                    or e["pickup_types"].get("PICKUP_LIL_BATTERY", 0) > 0
                    or e["enemy_flags"].get("FLAG_FREEZE", 0) > 0
                    for e in after
                    if e["tick"] > 300
                )
            ],
        )
    if rules.get("tear_variant"):
        check(
            "native_special_tear:" + rules["tear_variant"],
            [
                any(
                    t.get("variant_name") == rules["tear_variant"]
                    for e in after
                    for t in e["tears"]
                )
            ],
        )
    if rules.get("entry_trial"):
        visits = [
            e for e in observations.get("host", []) if e["event"] == "native_combat_room_visit"
        ]
        check("native_combat_room_entries", [len(visits) == rules["entry_trial"]])
    if rules.get("watch_trial"):
        check("native_room_watch_speed_changes", [any(e["watch_state"] in (1, 2) for e in after)])
    projectile_checks(rules, observations, host, check)
    if rules.get("familiar_speed_after_release"):
        check(
            "charged_familiar_launch",
            [
                any(
                    f["vx"] ** 2 + f["vy"] ** 2 > rules["familiar_speed_after_release"] ** 2
                    for e in after
                    if e["tick"] > rules["shoot_until"]
                    for f in e["familiar_positions"]
                )
            ],
        )
    if rules.get("survivor_hurt"):
        trials = [e for e in observations.get("host", []) if e["event"] == "fixture_kill_targets"]
        killed = set(trials[0]["seeds"]) if len(trials) == 1 else set()
        survivors = {t["seed"]: t["hp"] for t in before["targets"] if t["seed"] not in killed}
        check(
            "native_effect_damages_remaining_enemy",
            [
                len(killed) == rules["kill_limit"],
                bool(survivors),
                any(
                    sum(max(0, t["hp"]) for t in e["targets"] if t["seed"] in survivors)
                    < sum(survivors.values())
                    for e in after
                    if e["tick"] > 105
                ),
            ],
        )
    if not rules.get("reroll_enemies") and any(
        rules.get(name) for name in ("target_effect", "target_familiar", "target_laser")
    ):
        check(
            "native_target_alignment",
            [any(target.get("aligned", 0) > 0 for e in after for target in e.get("targets", []))],
        )
    if rules.get("spent_charge"):
        check(
            "native_hits_spend_active_charge",
            [any(0 < e["charge"] < rules["floor_recharge"] for e in after if e["tick"] >= 120)],
        )
    if rules.get("floor_recharge"):
        check(
            "next_floor_restores_tool_charge",
            [e["charge"] == rules["floor_recharge"] for e in host if e["tick"] >= 540],
        )
    if rules.get("floor_visit"):
        visit = rules["floor_visit"]
        kill_tick = visit.get("kill_tick", 480)
        entered = [e for e in host if 450 <= e["tick"] <= kill_tick - 3]
        reward_tick = kill_tick + (120 if rules.get("copied_boss") else 60)
        rewarded = [e for e in host if reward_tick <= e["tick"] <= reward_tick + 57]
        check(
            "generated_next_floor",
            [
                e.get("stage_name") == visit["stage"]
                if visit.get("stage")
                else e["stage"] == before["stage"] + 1
                for e in rewarded
            ],
        )
        if visit.get("room"):
            check("native_room_entry", [e["room_type"] == visit["room"] for e in entered])
        if visit.get("kill_boss"):
            kills = [
                e for e in observations.get("host", []) if e["event"] == "native_bosses_defeated"
            ]
            check("real_boss_death", [any(e["count"] > 0 for e in kills)])
        if rules.get("copied_boss"):
            check("native_boss_copy", [any(len(e["bosses"]) >= 2 for e in entered)])
        if rules.get("boss_pedestals"):
            check(
                "additional_boss_reward",
                [any(len(e["pedestals"]) >= rules["boss_pedestals"] for e in rewarded)],
            )
        if rules.get("choice_pedestals"):
            original_choices = {p["seed"] for e in rewarded for p in e["pedestals"]}
            choices = [e for e in observations.get("host", []) if e["event"] == "choose_reward"]
            chosen = choices[0]["seed"] if len(choices) == 1 else None
            check(
                "native_choice_pedestals",
                [
                    any(
                        len(e["pedestals"]) >= rules["choice_pedestals"]
                        and len({e["pedestal_options"].get(str(p["seed"])) for p in e["pedestals"]})
                        == 1
                        and all(
                            e["pedestal_options"].get(str(p["seed"]), 0) != 0
                            for p in e["pedestals"]
                        )
                        for e in rewarded
                    )
                ],
            )
            check(
                "choosing_removes_alternative",
                [
                    chosen in original_choices,
                    all(
                        all(
                            p["seed"] not in original_choices - {chosen}
                            and (
                                p["seed"] != chosen
                                or e["pedestal_options"].get(str(chosen), 0) == 0
                            )
                            for p in e["pedestals"]
                        )
                        for e in host
                        if e["tick"] >= 630
                    ),
                ],
            )
        if rules.get("rider_boss"):
            check(
                "rider_replaces_boss",
                [any(b["type"] in {63, 64, 65, 66, 82} for e in entered for b in e["bosses"])],
            )
        if rules.get("devil_boss_reward"):
            check(
                "boss_reward_becomes_devil_deal",
                [any(any(p["price"] < 0 for p in e["pedestals"]) for e in rewarded)],
            )
        if rules.get("boss_buff"):
            check(
                "sol_boss_rewards",
                [
                    any(
                        e["damage"] > before["damage"]
                        and e["luck"] >= before["luck"] + 1
                        and e["charge"] == 6
                        for e in rewarded
                    ),
                    all(
                        e["damage"] > before["damage"]
                        and e["luck"] >= before["luck"] + 1
                        and e["charge"] == 6
                        for e in host
                        if e["tick"] >= 600
                    ),
                ],
            )
        if rules.get("extra_secrets"):
            check(
                "additional_secret_rooms",
                [
                    all(sum(r["type"] == kind for r in e["map"]) >= 2 for kind in (7, 8))
                    for e in rewarded
                ],
            )
        if rules.get("moonlight_buff"):
            check(
                "moonlight_grants_stats_and_soul",
                [
                    any(
                        e["soul"] >= before["soul"] + 1 and e["delay"] < before["delay"]
                        for e in rewarded
                    )
                ],
            )
        if rules.get("underground_shop"):
            check(
                "member_card_underground_shop",
                [
                    e["room"] < 0 and e["room_type"] == "ROOM_SHOP" and bool(e["pickups"])
                    for e in rewarded
                ],
            )
        if rules.get("angel_shop"):
            check(
                "stairway_to_angel_shop",
                [
                    e["room"] < 0
                    and e["room_type"] == "ROOM_ANGEL"
                    and any(p["price"] > 0 for p in e["pickups"])
                    for e in rewarded
                ],
            )
        if rules.get("portal_destination"):
            check(
                "two_floor_portals",
                [any(e["effects"].get("PORTAL_TELEPORT", 0) == 2 for e in entered)],
            )
            check(
                "portal_reaches_special_room",
                [
                    e["room_type"] in {"ROOM_BOSS", "ROOM_TREASURE", "ROOM_SECRET", "ROOM_SHOP"}
                    for e in rewarded
                ],
            )
    if rules.get("fireplace_trial"):
        check(
            "fireplace_room_changed",
            [any(e["room"] != before["room"] for e in host if e["tick"] >= 240)],
        )
        contacts = [e for e in observations.get("host", []) if e["event"] == "fireplace_contact"]
        outcomes = [e for e in observations.get("host", []) if e["event"] == "fireplace_result"]
        check(
            "fireplace_contact_trials",
            [len(contacts) == 4 and all(e["hearts"] == 6 for e in contacts)],
        )
        for tick in (150, 390):
            actual = {e["slot"]: e["hearts"] for e in outcomes if e["tick"] == tick}
            check(
                "fireplace_immunity:" + str(tick),
                [actual.get(case["slot"]) == 6 and actual.get(1 - case["slot"], 6) < 6],
            )
    if rules.get("consume_pickup"):
        recipe = rules["consume_pickup"]
        trials = [e for e in host if e["label"] == "before_pickup"]
        check("native_pickup_trials", [len(trials) == recipe.get("count", 1)])
        for trial in trials:
            following = [e for e in host if trial["tick"] + 6 <= e["tick"] < trial["tick"] + 30]
            for field, key in (("hearts", "healing"), ("soul", "soul")):
                if key in recipe:
                    check(
                        "pickup:" + field + ":" + str(trial["tick"]),
                        [any(e[field] - trial[field] == recipe[key] for e in following)],
                    )
            if recipe.get("stats"):
                fields = ("damage", "delay", "speed", "range", "shot_speed", "luck")
                check(
                    "pickup:stat_bonus:" + str(trial["tick"]),
                    [
                        any(
                            any(
                                (e[f] - trial[f]) * (-1 if f == "delay" else 1) > 0.001
                                for f in fields
                            )
                            for e in following
                        )
                    ],
                )
    if rules.get("pocket_conversion"):
        cards = rules["pocket_conversion"] == "cards"
        field = "card" if cards else "pill"
        desired, forbidden = (300, 70) if cards else (70, 300)
        later = [e for e in host if 100 <= e["tick"] <= 150]
        check(
            "two_pocket_slots",
            [e["pocket_slots"] >= 2 and e[field] != 0 and e[field + "_second"] != 0 for e in later],
        )
        check(
            "native_consumable_conversion",
            [
                any(
                    any(p["variant"] == desired for p in e["pickups"])
                    and not any(p["variant"] == forbidden for p in e["pickups"])
                    for e in later
                )
            ],
        )
    if rules.get("damage_charges"):
        check(
            "damage_recharges_active",
            [before["charge"] == 0, any(e["charge"] > 0 and e["enemy_hp"] > 0 for e in after)],
        )
    if rules.get("generated_pedestals"):
        requests = [e for e in observations.get("host", []) if e["event"] == "generated_pedestal"]
        check("native_generated_pedestal", [len(requests) == 1])
        seed = requests[0]["seed"] if requests else None
        identities = {
            p["subtype"]
            for e in after
            if e["tick"] >= 93 and (not rules.get("acquire_generated") or e["tick"] < 180)
            for p in e["pedestals"]
            if p["seed"] == seed
        }
        if rules.get("pedestal_cycle"):
            check("native_pedestal_cycles", [len(identities) >= rules["pedestal_cycle"]])
        if rules.get("food_cycle"):
            check("cycles_to_food", [bool(identities & {16, 22, 23, 24, 25, 26, 346, 456})])
        if rules.get("glitch_generated"):
            check(
                "generated_glitched_identity",
                [bool(identities), all(i > 100000 or i < 0 for i in identities)],
            )
        if rules.get("acquire_generated"):
            check(
                "glitched_collectible_acquired",
                [any(e["generated_owned"] > 0 for e in host if 210 <= e["tick"] <= 300)],
            )
    if rules.get("reroll_on_floor"):
        previous = next((e for e in host if e["tick"] == 210), None)
        check(
            "floor_rerolls_inventory",
            [
                previous is not None
                and any(
                    e["stage"] > previous["stage"] and e["inventory"] != previous["inventory"]
                    for e in host
                    if e["tick"] >= 500
                )
            ],
        )
    if rules.get("delayed_detonation"):
        waiting = [e for e in host if 150 <= e["tick"] <= 195]
        detonated = [e for e in host if 240 <= e["tick"] <= 300]
        check("bomb_waits_for_active_input", [bool(e["explosives"]) for e in waiting])
        check("active_input_detonates_bomb", [not e["explosives"] for e in detonated])
    if rules.get("tear_damage"):
        check(
            "native_tear_damage",
            [abs(t["damage"] - rules["tear_damage"]) < 0.001 for e in after for t in e["tears"]],
        )
    for field, direction in rules.get("stat_progression", {}).items():
        early = [e[field] for e in host if 90 <= e["tick"] <= 120]
        late = [
            e[field]
            for e in host
            if rules["observe_until"] - 30 <= e["tick"] <= rules["observe_until"]
        ]
        check(
            "sustained_shooting:" + field,
            [(sum(late) / len(late) - sum(early) / len(early)) * direction > 0.01]
            if early and late
            else [],
        )
    if rules.get("alternating_cadence"):
        shots = {}
        for event in after:
            for tear in event["tears"]:
                shots.setdefault(tear["seed"], event["tick"] - tear["age"])
        ticks = sorted(set(shots.values()))
        gaps = [b - a for a, b in zip(ticks, ticks[1:])]
        check(
            "alternating_eye_cadence",
            [len(gaps) >= 10, len(set(gaps)) >= 2, min(gaps, default=99) < before["delay"]],
        )
    if rules.get("steered_tears"):
        earlier = {t["seed"]: t for e in host if 90 <= e["tick"] <= 99 for t in e["tears"]}
        check(
            "existing_tears_follow_changed_input",
            [
                any(
                    t["seed"] in earlier and earlier[t["seed"]]["vy"] < -1 and t["vx"] > 1
                    for e in host
                    if 105 <= e["tick"] <= 135
                    for t in e["tears"]
                )
            ],
        )
    if rules.get("bone_break"):
        acquired = [e for e in host if 63 <= e["tick"] < 90]
        broken = [e for e in host if 100 <= e["tick"] <= 150]
        check(
            "red_containers_become_bone_hearts",
            [e["bone"] == 6 and e["max_hearts"] == 0 for e in acquired],
        )
        check("native_hit_breaks_bone_heart", [any(e["bone"] == 5 for e in broken)])
    if rules.get("laser_persists_room"):
        later = [e for e in host if e["tick"] >= rules["room_tick"] + 60]
        check(
            "laser_survives_room_change",
            [any(e["room"] != before["room"] and e["laser_count"] > 0 for e in later)],
        )
    if rules.get("balanced_stats"):
        fields = ("speed", "damage", "delay", "range")
        check(
            "unbalanced_bonus_distributed",
            [
                any(
                    e["damage"] < before["damage"]
                    and sum(abs(e[f] - before[f]) > 0.001 for f in fields) >= 3
                    for e in after
                )
            ],
        )
    if rules.get("retains_stat_buff"):
        boosted = next((e for e in host if e["tick"] == 120), None)
        check(
            "native_temporary_damage_boost",
            [boosted is not None and boosted["damage"] > before["damage"]],
        )
        check(
            "rock_bottom_retains_expired_buff",
            [
                boosted is not None and abs(e["damage"] - boosted["damage"]) < 0.001
                for e in host
                if e["tick"] >= 240
            ],
        )
    if rules.get("overcharge"):
        for name, low, high, charge in (
            ("stored", 120, 177, 12),
            ("first_use", 189, 237, 6),
            ("second_use", 249, 297, 0),
        ):
            check(
                "battery:" + name,
                [e["charge"] + e["battery"] == charge for e in host if low <= e["tick"] <= high],
            )
    if rules.get("removes_curse"):
        check("removes_darkness", [before["curses"] != 0, all(e["curses"] == 0 for e in after)])
    if rules.get("overflow_damage"):
        check(
            "single_tear_overkill_pierces",
            [
                any(
                    e["enemy_count"] == 1 and e["enemy_hp"] < 500 and e["tear_count"] == 1
                    for e in after
                )
            ],
        )
    if rules.get("repeat_uses"):
        activations = [e for e in observations.get("host", []) if e["event"] == "use_callback"]
        if rules.get("repeat_without_recharge"):
            second = use_tick + rules["repeat_interval"]
            prior = [e for e in after if e["tick"] <= second]
            later = [e for e in after if e["tick"] >= second + 9]
            check(
                "native_secondary_detonation",
                [
                    len(activations) == 1,
                    bool(prior),
                    bool(later),
                    all(e["enemy_hp"] == before["enemy_hp"] for e in prior),
                    any(e["enemy_hp"] < before["enemy_hp"] for e in later),
                ],
            )
        else:
            check("repeated_native_uses", [len(activations) == rules["repeat_uses"]])
    if rules.get("any_drop"):
        check(
            "native_drop_reward", [any(e["pickup_count"] > before["pickup_count"] for e in after)]
        )
    if rules.get("dash"):
        check("native_dash_distance", [any(abs(e["y"] - before["y"]) > 50 for e in after)])
    if rules.get("free_pickup"):
        priced = {
            p["seed"]
            for p in before["pickups"] + before["pedestals"]
            if p["price"] not in (0, -1000)
        }
        check(
            "free_price_after_use",
            [
                bool(priced),
                any(
                    p["seed"] in priced and p["price"] in (0, -1000)
                    for e in after
                    for p in e["pickups"] + e["pedestals"]
                ),
            ],
        )
    if rules.get("repeat_damage"):
        trials = [e for e in observations.get("host", []) if e["event"] == "repeated_damage_trial"]
        check("repeated_damage_complete", [len(trials) == rules["repeat_damage"]])
        losses = [e["before"] - e["after"] for e in trials]
        check(
            "repeated_damage_applied",
            [any(loss == 1 for loss in losses), all(loss in (0, 1) for loss in losses)],
        )
        late = [e for e in host if e["tick"] >= 90]
        if rules.get("series_blocks"):
            check("periodic_or_chance_damage_block", [any(loss == 0 for loss in losses)])
        if rules.get("series_pickups"):
            check(
                "damage_creates_pickups",
                [any(e["pickup_count"] > before["pickup_count"] for e in late)],
            )
        if rules.get("series_grid"):
            check(
                "damage_creates_grid",
                [
                    any(
                        e["grids"].get(rules["series_grid"], 0)
                        > before["grids"].get(rules["series_grid"], 0)
                        for e in late
                    )
                ],
            )
        if rules.get("series_smelt"):
            check("damage_smelts_trinket", [any(e["smelted"] for e in late)])
        if rules.get("series_familiars"):
            check(
                "damage_grants_familiars",
                [
                    any(
                        e["familiar_count"] >= before["familiar_count"] + rules["series_familiars"]
                        for e in late
                    )
                ],
            )
    if rules.get("after_hit_soul"):
        check(
            "low_health_soul_reward",
            [any(e["soul"] == rules["after_hit_soul"] for e in host if 93 <= e["tick"] <= 150)],
        )
    if rules.get("soul_damage_trigger"):
        previous = next((e for e in host if e["label"] == "before_hit"), None)
        check(
            "soul_hit",
            [
                bool(previous)
                and any(e["soul"] == previous["soul"] - 1 for e in host if 93 <= e["tick"] <= 150)
            ],
        )
    if rules.get("damage_buff_lost"):
        boosted = [e for e in host if 60 <= e["tick"] < 90]
        lost = [e for e in host if 93 <= e["tick"] <= 150]
        check(
            "full_health_damage_boost",
            [bool(boosted) and all(e["damage"] > before["damage"] for e in boosted)],
        )
        check(
            "damage_buff_lost_on_hit",
            [all(abs(e["damage"] - before["damage"]) < 0.001 for e in lost)],
        )
    if rules.get("aura_lifecycle"):
        fields = ("damage", "delay", "speed", "range")
        for name, low, high in (("acquired", 60, 87), ("new_room", 240, 297)):
            check(
                "aura_stats:" + name,
                [any(e[f] != before[f] for f in fields) for e in host if low <= e["tick"] <= high],
            )
        check(
            "aura_lost_on_hit",
            [
                all(abs(e[f] - before[f]) < 0.001 for f in fields)
                for e in host
                if 93 <= e["tick"] <= 150
            ],
        )
    if rules.get("buff_decays"):
        early = next((e for e in host if e["tick"] == 90), None)
        late = next((e for e in host if e["tick"] == 870), None)
        check(
            "damage_buff_decays",
            [early is not None and late is not None and late["damage"] < early["damage"]],
        )
    if rules.get("healed"):
        check(
            "heals_all_red_hearts",
            [
                before["hearts"] < before["max_hearts"],
                all(e["hearts"] == e["max_hearts"] for e in after),
            ],
        )
    if rules.get("floor_bonus") or rules.get("floor_oath") or rules.get("floor_pickup"):
        previous = next((e for e in host if e["label"] == "before_floor"), None)
        late = [e for e in host if e["tick"] >= 600]
        check(
            "native_floor_changed",
            [
                bool(previous)
                and bool(late)
                and all(e["stage"] == previous["stage"] + 1 for e in late)
            ],
        )
        for field, delta in rules.get("floor_bonus", {}).items():
            check(
                "floor_reward:" + field,
                [previous is not None and e[field] == previous[field] + delta for e in late],
            )
        if rules.get("floor_oath"):
            check(
                "oath_health_and_stats",
                [
                    previous is not None
                    and e["hearts"] == 1
                    and e["damage"] > previous["damage"]
                    and e["speed"] > previous["speed"]
                    for e in late
                ],
            )
        if rules.get("floor_pickup"):
            check(
                "floor_pickup",
                [any(e["pickup_types"].get(rules["floor_pickup"], 0) >= 1 for e in late)],
            )
    if rules.get("idle_shield"):
        check(
            "idle_blocks_damage",
            [e["hearts"] == before["hearts"] for e in host if 123 <= e["tick"] <= 180],
        )
        check(
            "shooting_removes_idle_shield",
            [e["hearts"] == before["hearts"] - 1 for e in host if e["tick"] >= 273],
        )
    if rules.get("reveals_room"):
        check(
            "damage_reveals_room", [any(e["map"] != before["map"] for e in after if e["tick"] > 90)]
        )
    if rules.get("changes_character"):
        check("character_changes", [any(e["player_type"] != before["player_type"] for e in after)])
    if rules.get("reroll_inventory"):
        check(
            "inventory_rerolled",
            [
                bool(before["inventory"]),
                any(
                    e["inventory"] != before["inventory"] and e["breakfast_count"] == 0
                    for e in after
                ),
            ],
        )
    if rules.get("downgrade_enemies") or rules.get("reroll_enemies"):
        check(
            "enemies_downgraded",
            [
                bool(before["enemy_types"]),
                any(
                    bool(e["enemy_types"])
                    and sum(e["enemy_types"].values()) == sum(before["enemy_types"].values())
                    and e["enemy_types"] != before["enemy_types"]
                    for e in after
                ),
            ],
        )
    if rules.get("reroll_grids"):
        prepared_grids = next((e for e in host if e["tick"] == 57), None)
        check(
            "grids_rerolled",
            [
                prepared_grids is not None
                and any(e["grids"] != prepared_grids["grids"] for e in after)
            ],
        )
    if rules.get("glitched_pedestal"):
        check(
            "glitched_pedestal",
            [
                any(
                    p["subtype"] < 0 or p["subtype"] > 0xFFFFFFFF // 2
                    for e in after
                    for p in e["pedestals"]
                )
            ],
        )
    if rules.get("absorb_pedestal"):
        check(
            "pedestal_absorbed", [bool(before["pedestals"]), any(not e["pedestals"] for e in after)]
        )
    if rules.get("consume_pickups"):
        check(
            "pickups_consumed", [len(before["pickups"]) >= 4, any(not e["pickups"] for e in after)]
        )
    if rules.get("crooked_penny"):
        check(
            "crooked_penny_outcome",
            [
                any(
                    (
                        len(e["pedestals"]) == 2 * len(before["pedestals"])
                        and len(e["pickups"]) == 2 * len(before["pickups"])
                    )
                    or (not e["pedestals"] and len(e["pickups"]) == 1 and e["coin_value"] == 1)
                    for e in after
                )
            ],
        )
    if rules.get("sacrifice_familiars"):
        check(
            "familiars_sacrificed",
            [before["familiar_count"] >= 2, any(e["familiar_count"] == 0 for e in after)],
        )
    if rules.get("trinket_multiplier"):
        check(
            "held_trinket_amplified",
            [
                before["trinket_multiplier"] == 1,
                all(e["trinket_multiplier"] == rules["trinket_multiplier"] for e in after),
            ],
        )
    if rules.get("effect_expires"):
        for effect in rules.get("effects", []):
            check(
                "effect_expired:" + effect,
                [
                    e["effects"].get(effect, 0) == 0
                    for e in host
                    if e["tick"] >= rules["effect_expires"]
                ],
            )
    if rules.get("minimum_volley"):
        check(
            "additional_tear_volley",
            [any(sum(t["age"] <= 3 for t in e["tears"]) >= rules["minimum_volley"] for e in after)],
        )
    if rules.get("strong_tear"):
        check(
            "strong_tear",
            [
                any(
                    t["damage"] >= e["damage"] * rules["strong_tear"] - 0.01
                    for e in after
                    for t in e["tears"]
                )
            ],
        )
    if rules.get("damage_after_shooting"):
        low, high = rules["damage_after_shooting"]
        values = [e for e in host if low <= e["tick"] <= high]
        check(
            "attached_tear_continues_damage",
            [len(values) > 1 and values[-1]["enemy_hp"] < values[0]["enemy_hp"]],
        )
        check(
            "only_attached_tears_remain",
            [
                bool(values) and values[0]["tear_flags"].get("TEAR_BOOGER", 0) > 0,
                all(len(e["tears"]) == e["tear_flags"].get("TEAR_BOOGER", 0) for e in values),
            ],
        )
    if rules.get("break_obstacle"):
        check(
            "tear_breaks_rock",
            [
                any(e["obstacle_intact"] for e in host if e["tick"] < use_tick),
                any(not e["obstacle_intact"] for e in after),
            ],
        )
    if rules.get("spends_coins"):
        check("tear_spends_coin", [any(e["coins"] < before["coins"] for e in after)])
    if rules.get("eye_damage_multiplier"):
        damage = [t["damage"] for e in after for t in e["tears"]]
        check(
            "different_eye_damage",
            [
                any(abs(d - before["damage"]) < 0.01 for d in damage),
                any(
                    abs(d - before["damage"] * rules["eye_damage_multiplier"]) < 0.01
                    for d in damage
                ),
            ],
        )
    if rules.get("fake_damage"):
        check(
            "fake_damage_preserves_health",
            [e["hearts"] == before["hearts"] and e["soul"] == before["soul"] for e in after],
        )
    if rules.get("diagonal_input"):
        check(
            "diagonal_input_aim",
            [any(t["vx"] > 1 and t["vy"] < -1 for e in after for t in e["tears"])],
        )
    if rules.get("random_native_effect"):
        previous = next((e for e in host if e.get("label") == "before_random"), None)
        fields = (
            "hearts",
            "soul",
            "max_hearts",
            "damage",
            "delay",
            "speed",
            "range",
            "charge",
            "coins",
            "bombs",
            "keys",
            "room",
            "stage",
            "curses",
            "map",
            "familiar_count",
            "invincible",
            "grids",
            "pickups",
            "pedestals",
            "breakfast_count",
        )
        check(
            "native_random_result",
            [
                bool(previous)
                and any(
                    any(e[f] != previous[f] for f in fields) for e in after if e["tick"] > use_tick
                )
            ],
        )
    if rules.get("revival_card"):
        uses = [e for e in observations.get("host", []) if e["event"] == "use_callback"]
        check("manual_card_activation", [len(uses) == 1])
        check(
            "fatal_hit_precedes_automatic_revival",
            [any(e["dead"] and e["card"] == case["id"] for e in host if 240 < e["tick"] < 300)],
        )
        for low, high in ((150, 230), (330, 440)):
            check(
                "revival_card:" + str(low),
                [
                    e["hearts"] == 1 and not e["dead"] and not e["ghost"] and e["card"] == 0
                    for e in host
                    if low <= e["tick"] <= high
                ],
            )
        check(
            "fatal_hit_with_card_held",
            [
                any(
                    e["event"] == "held_card_fatal_damage"
                    and e["card"] == case["id"]
                    and e["hearts"] == 1
                    for e in observations.get("host", [])
                )
            ],
        )
    if rules.get("timed_invincible"):
        timing = rules["timed_invincible"]
        check(
            "timed_invulnerability",
            [
                e["invincible"]
                for e in host
                if timing["during"][0] <= e["tick"] <= timing["during"][1]
            ],
        )
        check(
            "invulnerability_expires",
            [not e["invincible"] for e in host if e["tick"] >= timing["after"]],
        )
    if rules.get("repel_projectile"):
        check(
            "incoming_projectile_spawned",
            [any(e["event"] == "incoming_projectile" for e in observations.get("host", []))],
        )
        check(
            "projectile_repulsion",
            [
                any(
                    (p["x"] - e["x"]) * p["vx"] + (p["y"] - e["y"]) * p["vy"] > 1
                    for e in after
                    for p in (
                        e["projectiles"] + e["tears"]
                        if rules.get("reflect_projectiles")
                        else e["projectiles"]
                    )
                )
            ],
        )
    if rules.get("pill_conversion"):
        check(
            "native_pill_baseline",
            [v["actual"] == v["original"] for v in before["pill_conversions"]],
        )
        check(
            "pills_converted",
            [
                bool(e["pill_conversions"])
                and all(v["actual"] == v["expected"] for v in e["pill_conversions"])
                for e in after
            ],
        )
        if rules.get("identify_pills"):
            check(
                "pills_identified",
                [all(v["identified"] for v in e["pill_conversions"]) for e in after],
            )
    if rules.get("swap_familiar"):
        previous = next((e for e in host if e.get("label") == "before_swap"), None)
        familiar = (
            next(
                (
                    f
                    for f in previous["familiar_positions"]
                    if f["variant"] == rules["swap_familiar"]
                ),
                None,
            )
            if previous
            else None
        )
        check(
            "familiar_moved_before_swap",
            [bool(familiar) and abs(familiar["x"] - previous["x"]) > 40],
        )
        check(
            "holder_teleported_to_familiar",
            [
                bool(familiar)
                and any(
                    abs(e["x"] - familiar["x"]) < 5 and abs(e["y"] - familiar["y"]) < 5
                    for e in after
                    if e["tick"] > use_tick
                )
            ],
        )
        check(
            "familiar_teleported_to_holder",
            [
                bool(previous)
                and any(
                    f["variant"] == rules["swap_familiar"]
                    and abs(f["x"] - previous["x"]) < 5
                    and abs(f["y"] - previous["y"]) < 5
                    for e in after
                    if e["tick"] > use_tick
                    for f in e["familiar_positions"]
                )
            ],
        )
        check(
            "swap_grants_invulnerability",
            [
                previous is not None and previous["damage_cooldown"] == 0,
                any(
                    e["damage_cooldown"] > 0 for e in after if use_tick < e["tick"] <= use_tick + 3
                ),
                any(
                    e["hearts"] == before["hearts"]
                    for e in after
                    if use_tick + 4 < e["tick"] < use_tick + 15
                ),
                any(e["hearts"] == before["hearts"] - 1 for e in after if e["tick"] > 210),
                len([e for e in observations.get("host", []) if e["event"] == "swap_damage_trial"])
                == 2,
            ],
        )
    if rules.get("friendly_enemies"):
        check(
            "friendly_enemy_created",
            [any(e["friendly_count"] > before["friendly_count"] for e in after)],
        )
        check("replica:friendly_enemy", [any(e["friendly_count"] > 0 for e in client)])
    if rules.get("active_replaced"):
        check(
            "active_item_replaced",
            [any(e.get("active_item") == rules["active_replaced"] for e in after)],
        )
        check(
            "replica:active_replaced",
            [any(e.get("active_item") == rules["active_replaced"] for e in client)],
        )
    if rules.get("shop_spawn"):
        check(
            "purchasable_pickup_created",
            [any(p["price"] > 0 for e in after for p in e["pickups"] + e["pedestals"])],
        )
    if rules.get("larger_tears"):
        check(
            "larger_tears",
            [
                any(
                    t["scale"] > before["initial_tear_scale"] + 0.1
                    for e in after
                    for t in e["tears"]
                )
            ],
        )
    if rules.get("single_eye"):
        newborn = [t for e in after for t in e["tears"] if t["age"] <= 2]
        check(
            "same_eye_origin", [len(newborn) >= 2, all(t["x"] > before["x"] + 2 for t in newborn)]
        )
    if rules.get("shot_volley"):
        births = {}
        for e in after:
            for t in e["tears"]:
                births.setdefault(e["tick"] - t["age"], set()).add(t["seed"])
        check(
            "shot_volley",
            [sum(len(seeds) == rules["shot_volley"] for seeds in births.values()) >= 2],
        )
    if rules.get("prevent_fatal") and not rules.get("shackles_trial"):
        check(
            "fatal_damage_replaced",
            [
                any(
                    e["broken"] >= before["broken"] + 5 and not e["dead"] and not e["ghost"]
                    for e in after
                    if e["tick"] >= 120
                )
            ],
        )
    if rules.get("vulnerability"):
        hits = [e for e in observations.get("host", []) if e["event"] == "vulnerability_hit"]
        for tick, factor in ((120, rules["vulnerability"]), (1000, 1)):
            hit = next((e for e in hits if e["tick"] == tick), None)
            check(
                "damage_multiplier:" + str(tick),
                [
                    hit is not None
                    and any(
                        abs(e["enemy_hp"] - hit["before"] + 10 * factor) < 0.01
                        for e in host
                        if tick < e["tick"] < tick + 10
                    )
                ],
            )
    if rules.get("immobile_shooting"):
        early = [e for e in host if 90 <= e["tick"] <= 150]
        late = [e for e in host if e["tick"] >= rules["recover_tick"]]
        check(
            "immobile",
            [max(e["x"] for e in early) - min(e["x"] for e in early) < 2] if early else [],
        )
        check("can_shoot_while_immobile", [any(e["tear_count"] > 0 for e in early)])
        check("movement_recovers", [any(abs(e["x"] - before["x"]) > 10 for e in late)])
        check(
            "invulnerability_blocks_damage",
            [e["hearts"] == before["hearts"] for e in early if e["tick"] > 120],
        )
        check(
            "invulnerability_expires",
            [e["hearts"] == before["hearts"] - 1 for e in late if e["tick"] > 420],
        )
        check(
            "shield_damage_attempts",
            [
                len(
                    [
                        e
                        for e in observations.get("host", [])
                        if e["event"] == "shield_damage_attempt"
                    ]
                )
                == 2
            ],
        )
    if rules.get("visual_review"):
        check("visual_review:" + rules["visual_review"], [])
    if rules.get("red_rooms"):
        check("red_room_created", [any(e["red_rooms"] > before["red_rooms"] for e in after)])
    if rules.get("pocket_retained"):
        field = "card" if rules.get("pocket_card") else "pill"
        check(
            "pocket_consumable_retained",
            [before[field] != 0, all(e[field] == before[field] for e in after)],
        )
    if "acquired_charge" in rules:
        acquired = [e for e in host if 45 <= e["tick"] < use_tick]
        check(
            "pickup_recharges_active",
            [before["charge"] == 0, any(e["charge"] == rules["acquired_charge"] for e in acquired)],
        )
    if "after_charge" in rules:
        check(
            "charge_after_native_use",
            [any(e["charge"] == rules["after_charge"] for e in after if e["tick"] > use_tick)],
        )
    if rules.get("pill_callbacks"):
        used = [
            e
            for e in observations.get("host", [])
            if e["event"] == "trigger_pill" and e["tick"] >= use_tick
        ]
        check("native_pill_effects", [len(used) == rules["pill_callbacks"]])
        check(
            "replica_does_not_use_pills",
            [not any(e["event"] == "trigger_pill" for e in observations.get("client", []))],
        )
    if rules.get("revive"):
        killed = [e for e in host if 90 <= e["tick"] <= 180]
        alive = [e for e in host if e["tick"] >= 390]
        check("native_death", [any(e["dead"] for e in killed)])
        check(
            "native_revival",
            [
                not e["dead"]
                and not e["ghost"]
                and e["visible"]
                and e["player_type"] == rules["revive_type"]
                and e["hearts"] == rules["revive_hearts"]
                for e in alive
            ],
        )
        check(
            "life_consumed",
            [
                e["extra_lives"] == rules.get("remaining_lives", before["extra_lives"])
                for e in alive
            ],
        )
    if rules.get("shield_after_hit"):
        check("damage_shield", [any(e["invincible"] for e in after if e["tick"] > 90)])
    if rules.get("kill_after"):
        remaining = (
            (rules.get("enemies", 0) - rules["kill_limit"]) if rules.get("kill_limit") else 0
        )
        check(
            "native_enemy_deaths",
            [any(e["enemy_count"] <= remaining for e in after if e["tick"] > 100)],
        )
        for prefix, (low, high) in rules.get("spawn_after_kill", {}).items():
            count = max(
                sum(n for key, n in e["spawned"].items() if key.startswith(prefix)) for e in after
            )
            check("kill_reward:" + prefix, [low <= count <= high])
        if rules.get("drops_expire"):
            check(
                "kill_reward_expires",
                [
                    not any(p["variant"] == 10 and p["subtype"] == 2 for p in e["pickups"])
                    for e in host
                    if e["tick"] >= 240
                ],
            )
    if rules.get("minimum_helpers"):
        check(
            "corpse_helpers",
            [
                any(
                    e["friendly_count"] + e["familiar_count"]
                    >= before["friendly_count"]
                    + before["familiar_count"]
                    + rules["minimum_helpers"]
                    for e in after
                )
            ],
        )
    if rules.get("healed_after_kill"):
        check(
            "kill_heals",
            [
                any(
                    e["hearts"] == before["hearts"] + rules["healed_after_kill"]
                    for e in after
                    if e["tick"] > 100
                )
            ],
        )
    for field, delta in rules.get("delta", {}).items():
        check("delta:" + field, [any(abs(e[field] - before[field] - delta) < 0.001 for e in after)])
    for field, direction in rules.get("stats", {}).items():
        check("stat:" + field, [any((e[field] - before[field]) * direction > 0.001 for e in after)])
    for flag in rules.get("tear_flags", []):
        check("tear:" + flag, [any(e["tear_flags"].get(flag, 0) > 0 for e in after)])
    if rules.get("homing"):
        check("homing_trajectory", [any(abs(t["vx"]) > 0.5 for e in after for t in e["tears"])])
    if rules.get("minimum_tears"):
        check("tear_count", [max(e["tear_count"] for e in after) >= rules["minimum_tears"]])
    if rules.get("charged_damage"):
        check(
            "charged_tear_damage",
            [
                any(
                    t["damage"] >= before["damage"] * rules["charged_damage"] - 0.01
                    for e in after
                    for t in e["tears"]
                )
            ],
        )
    if rules.get("bomb_attack"):
        check("fired_bombs", [any(e["explosives"] for e in after)])
        check("bomb_weapon_replaces_tears", [not e["tears"] for e in after])
    if rules.get("bomb_trial"):
        bombs = [b for e in after for b in e["explosives"]]
        check("native_bomb_placed", [bool(bombs)])
        if rules.get("bomb_damage"):
            check("bomb_explosion_damage", [b["damage"] >= rules["bomb_damage"] for b in bombs])
        if rules.get("bomb_homing"):
            check(
                "bomb_homes_toward_target",
                [any(b["x"] > before["x"] + 15 and b["y"] < before["y"] - 10 for b in bombs)],
            )
        if rules.get("cross_explosions"):
            check(
                "additional_explosions", [max(e["spawned"].get("1000.1.0", 0) for e in after) >= 5]
            )
    if rules.get("knives"):
        check("knife_attack", [any(e["knives"] for e in after)])
    if rules.get("controlled_tear"):
        first = next((e for e in after if e["tick"] >= 72 and e["tears"]), None)
        last = next((e for e in reversed(after) if e["tick"] <= 138 and e["tears"]), None)
        check(
            "controlled_tear_moves",
            [
                bool(first),
                bool(last),
                bool(first and last)
                and first["tears"][0]["seed"] == last["tears"][0]["seed"]
                and last["tears"][0]["y"] < first["tears"][0]["y"] - 40,
            ],
        )
    if rules.get("random_tears"):
        fingerprints = {tuple(t["flags"]) for e in after for t in e["tears"]}
        check("varying_tear_effects", [len(fingerprints) >= 2])
    if rules.get("any_charge_event"):
        pass
    elif rules.get("any_enemy_flag"):
        check("native_random_enemy_status", [any(e["enemy_flags"] for e in after)])
    else:
        for flag in rules.get("enemy_flags", []):
            if (
                rules.get("camouflage_trial")
                and case.get("scenario") == "single_holder"
                and not case.get("split")
            ):
                # Native local co-op only confuses enemies when every player
                # in their room is hidden. Check the visible peer prerequisite.
                peers = [
                    e["players"].get(str(1 - case.get("slot", 0)), {})
                    for e in observations.get("host", [])
                    if e["event"] == "camouflage_actor_state"
                ]
                check(
                    "camouflage_visible_peer_alive",
                    [
                        bool(peers),
                        all(
                            p.get("visible")
                            and not p.get("dead")
                            and not p.get("ghost")
                            and not p.get("camo")
                            for p in peers
                        ),
                    ],
                )
                check(
                    "visible_peer_prevents_global_confusion",
                    [all(e["enemy_flags"].get(flag, 0) == 0 for e in after)],
                )
                continue
            check(
                "enemy:" + flag,
                [
                    any(
                        e["enemy_flags"].get(flag, 0)
                        >= rules["enemies"] - rules.get("kill_limit", 0)
                        for e in after
                    )
                ],
            )
    if rules.get("movement_rate"):

        def rate(low, high):
            window = [e for e in host if low <= e["tick"] <= high and e["targets"]]
            if len(window) < 2:
                return None
            first, last = window[0], window[-1]
            seed = first["targets"][0]["seed"]
            target = next((t for t in last["targets"] if t["seed"] == seed), None)
            return (
                (target["x"] - first["targets"][0]["x"]) / (last["tick"] - first["tick"])
                if target
                else None
            )

        baseline, affected = (
            rate(240, 270) if rules.get("passive_rate") else rate(51, 57),
            rate(90, 120),
        )
        check(
            "enemy_movement_rate",
            []
            if baseline is None or affected is None
            else [baseline > 0.5, (affected - baseline) * rules["movement_rate"] > 0.2],
        )
        if rules.get("release_pause"):
            resumed = rate(240, 270)
            check(
                "shooting_releases_pause",
                [resumed is not None and baseline is not None and abs(resumed - baseline) < 0.2],
            )
        if rules.get("rate_lifecycle"):
            room_rate, floor_rate = rate(270, 300), rate(630, 660)
            check(
                "room_rate",
                []
                if room_rate is None or baseline is None
                else [
                    (room_rate - baseline) * rules["movement_rate"] > 0.2
                    if rules.get("rate_persists_room")
                    else abs(room_rate - baseline) < 0.2
                ],
            )
            check(
                "floor_rate_reset",
                []
                if floor_rate is None or baseline is None
                else [abs(floor_rate - baseline) < 0.2],
            )
        if rules.get("rate_recurrence"):
            for low in (990, 1890):
                repeated = rate(low, low + 30)
                check(
                    "repeated_rate:" + str(low),
                    []
                    if repeated is None or baseline is None
                    else [(repeated - baseline) * rules["movement_rate"] > 0.2],
                )
    if rules.get("puberty"):
        check("adulthood", [before["adult"] is False, any(e["adult"] is True for e in after)])
    if rules.get("paralysis"):
        early = [e for e in after if 75 <= e["tick"] <= 105]
        late = [e for e in host if e["tick"] >= rules["recover_tick"]]
        check(
            "paralyzed",
            [
                abs(e["x"] - before["x"]) < 2
                and abs(e["y"] - before["y"]) < 2
                and e["tear_count"] == 0
                for e in early
            ],
        )
        check("movement_recovers", [any(abs(e["x"] - before["x"]) > 10 for e in late)])
        check("firing_recovers", [any(e["tear_count"] > 0 for e in late)])
    if rules.get("invulnerable"):
        early = [e for e in after if 75 <= e["tick"] <= 105]
        late = [e for e in host if e["tick"] >= rules["recover_tick"]]
        check("invulnerable", [e["invincible"] is True for e in early])
        check("fire_suppressed", [not e["tears"] for e in early])
        check("contact_protection", [e["hearts"] == before["hearts"] for e in early])
        check(
            "invulnerability_expires",
            [e["invincible"] is False for e in late],
        )
        check("firing_recovers", [any(e["tears"] for e in late)])
    if rules.get("no_contact_damage"):
        check("no_contact_damage", [e["enemy_hp"] == before["enemy_hp"] for e in after])
    if rules.get("poop_trail"):
        check("poop_trail", [any(e["poop_count"] > before["poop_count"] for e in after)])
    if rules.get("diagonal"):
        shots = [tear for e in after for tear in e["tears"]]
        check("diagonal_shots", [any(t["vx"] > 1 for t in shots), any(t["vx"] < -1 for t in shots)])
    if rules.get("back_shot") or rules.get("four_directions") or rules.get("radial"):
        shots = [t for e in after for t in e["tears"]]
        for axis in (
            ("vx", "vy") if rules.get("four_directions") or rules.get("radial") else ("vy",)
        ):
            for sign in (-1, 1):
                check(f"shot_direction:{axis}:{sign}", [any(t[axis] * sign > 2 for t in shots)])
    if rules.get("tear_damage_bonus"):
        shots = [t for e in after for t in e["tears"]]
        expected = before["damage"] + rules["tear_damage_bonus"]
        check("radial_damage", [abs(t["damage"] - expected) < 0.01 for t in shots])
    if rules.get("teleport_any"):
        check(
            "teleported", [any(e["room"] != before["room"] for e in host if e["tick"] > use_tick)]
        )
    if rules.get("teleport_type"):
        check(
            "teleport_destination",
            [
                any(
                    e["room"] != before["room"] and e["room_type"] == rules["teleport_type"]
                    for e in host
                    if e["tick"] > use_tick
                )
            ],
        )
    if rules.get("consume_pedestals"):
        check(
            "pedestals_consumed",
            [bool(before["pedestals"]), any(not e["pedestals"] for e in after)],
        )
    if rules.get("positive_random_stat"):
        fields = ("damage", "delay", "speed", "range", "shot_speed", "luck")
        check(
            "stat_reward",
            [
                any(
                    (e[field] - before[field]) * (-1 if field == "delay" else 1) > 0.001
                    for e in after
                    for field in fields
                )
            ],
        )
    if rules.get("destroy_rocks"):
        prepared = [e for e in host if 48 <= e["tick"] < use_tick]
        check(
            "rocks_destroyed",
            [
                any(e["rock_count"] >= rules["rocks"] for e in prepared),
                any(e["rock_count"] == 0 for e in after),
            ],
        )
    if rules.get("grid_spawn"):
        check(
            "grid:" + rules["grid_spawn"],
            [any(e["grids"].get(rules["grid_spawn"], 0) > 0 for e in after)],
        )
    if rules.get("free_pickups"):
        check(
            "prices_removed",
            [
                any(p["price"] != 0 for p in before["pickups"] + before["pedestals"]),
                any(all(p["price"] == 0 for p in e["pickups"] + e["pedestals"]) for e in after),
            ],
        )
    if rules.get("open_doors"):
        check(
            "doors_opened",
            [
                any(d["locked"] for d in before["doors"]),
                any(
                    e["doors"] and all(d["open"] and not d["locked"] for d in e["doors"])
                    for e in after
                ),
            ],
        )
    if rules.get("secret_doors"):

        def secret_doors(event):
            return [d for d in event["doors"] if d["type"] in ("ROOM_SECRET", "ROOM_SUPERSECRET")]

        initial = secret_doors(before)
        check("hidden_entrance_precondition", [bool(initial), any(not d["open"] for d in initial)])
        check(
            "secret_entrances_open",
            [any(secret_doors(e) and all(d["open"] for d in secret_doors(e)) for e in after)],
        )
    if rules.get("map"):

        def revealed(event):
            rooms = [r for r in event["map"] if required_flags(rules["map"], r["type"])]
            return bool(rooms) and all(
                r["flags"] & required_flags(rules["map"], r["type"]) for r in rooms
            )

        check("map_revealed", [not revealed(before), any(revealed(e) for e in after)])
    if rules.get("removed_enemies"):
        check(
            "enemies_removed",
            [
                before["enemy_count"] >= rules["removed_enemies"],
                any(
                    e["enemy_count"] == before["enemy_count"] - rules["removed_enemies"]
                    for e in after
                ),
            ],
        )
    if rules.get("drop_resources"):
        check(
            "inventory_dropped",
            [
                before["coins"] > 0 and before["bombs"] > 0 and before["keys"] > 0,
                any(e["coins"] == e["bombs"] == e["keys"] == 0 and e["hearts"] == 1 for e in after),
            ],
        )
    if rules.get("expires_at"):
        late = [e for e in host if e["tick"] >= rules["expires_at"]]
        for field in (*rules.get("stats", {}), *rules.get("delta", {})):
            check("timed_expiry:" + field, [abs(e[field] - before[field]) < 0.001 for e in late])
        if rules.get("flying") and not rules.get("flying_expire_room"):
            check("timed_expiry:flight", [e["flying"] == before["flying"] for e in late])
        for familiar in rules.get("familiars", {}):
            check(
                "timed_expiry:" + familiar,
                [
                    e["familiars"].get(familiar, 0) == before["familiars"].get(familiar, 0)
                    for e in late
                ],
            )
    if rules.get("repeated_effect"):
        windows = (range(120, 600), range(900, 1500))
        check(
            "repeated_effect",
            [
                any(
                    e["effects"].get(rules["repeated_effect"], 0) > 0
                    for e in after
                    if e["tick"] in window
                )
                for window in windows
            ],
        )
        if rules.get("repeated_effect_expiry"):
            check(
                "repeated_effect_expires",
                [
                    e["effects"].get(rules["repeated_effect"], 0) == 0
                    for e in host
                    if e["tick"] >= rules["repeated_effect_expiry"]
                ],
            )
    if rules.get("hazard_trial"):
        check(
            "hazard_damages_holder",
            [any(e["hearts"] < before["hearts"] for e in after if e["tick"] < 300)],
        )
    if rules.get("repeat_active"):
        prior = next((e for e in host if e.get("label") == "before_repeat"), None)
        check("previous_native_use", [prior is not None and prior["soul"] - before["soul"] == 2])
        check(
            "repeats_previous_effect",
            [] if prior is None else [any(e["soul"] - prior["soul"] == 2 for e in after)],
        )
    if rules.get("lasers"):
        check("laser_attack", [any(e["laser_count"] > 0 for e in after)])
    if rules.get("damage_trigger"):
        previous = next((e for e in host if e.get("label") == "before_hit"), None)
        hurt = [e for e in host if 93 <= e["tick"] <= 150]
        check(
            "damage_triggered",
            [
                bool(previous),
                bool(hurt),
                bool(previous)
                and any(
                    (rules.get("bone_break") and e["bone"] == previous["bone"] - 1)
                    or e["hearts"] + e["soul"]
                    == previous["hearts"] + previous["soul"] - 1 + rules.get("after_hit_soul", 0)
                    for e in hurt
                ),
            ],
        )
        if previous:
            for field, direction in rules.get("hit_stats", {}).items():
                check(
                    "on_hit:" + field,
                    [any((e[field] - previous[field]) * direction > 0.001 for e in hurt)],
                )
            if rules.get("charge_after_hit"):
                check(
                    "on_hit:charge",
                    [
                        any(
                            e["charge"] - previous["charge"] == rules["charge_after_hit"]
                            for e in hurt
                        )
                    ],
                )
            for prefix, (low, high) in rules.get("spawn_after_hit", {}).items():
                initial = sum(n for key, n in previous["spawned"].items() if key.startswith(prefix))
                count = max(
                    (
                        sum(n for key, n in e["spawned"].items() if key.startswith(prefix))
                        - initial
                        for e in hurt
                    ),
                    default=0,
                )
                check("on_hit:spawn:" + prefix, [low <= count <= high])
        if rules.get("floor_reset"):
            late = [e for e in host if e["tick"] >= 500]
            check("next_floor", [any(e["stage"] > before["stage"] for e in late)])
            for field in rules.get("hit_stats", {}):
                check("floor_reset:" + field, [abs(e[field] - before[field]) < 0.001 for e in late])
        if rules.get("drops_expire"):
            check(
                "drops_expire",
                [e["pickup_count"] == before["pickup_count"] for e in host if e["tick"] >= 160],
            )
    tracks = {}
    if rules.get("duplicate_pickups") or rules.get("duplicate_one"):
        expected = (
            before["pickup_count"] * 2
            if rules.get("duplicate_pickups")
            else before["pickup_count"] + 1
        )
        check(
            "pickups_duplicated",
            [before["pickup_count"] >= 4, any(e["pickup_count"] == expected for e in after)],
        )
    if rules.get("duplicate_pedestals"):
        check(
            "pedestals_duplicated",
            [
                bool(before["pedestals"]),
                any(len(e["pedestals"]) == len(before["pedestals"]) * 2 for e in after),
            ],
        )
    if rules.get("rune_drop"):
        check("rune_drop", [any(e["rune_drops"] > 0 for e in after)])
    if rules.get("split_enemies"):
        check(
            "enemies_split",
            [
                before["enemy_count"] == 2,
                any(
                    e["enemy_count"] == 4 and all(abs(t["hp"] - 200) < 0.01 for t in e["targets"])
                    for e in after
                ),
            ],
        )
    if rules.get("reroll_pickups"):
        check(
            "pickups_rerolled",
            [
                len(before["pickups"]) >= 4,
                sum(before["pickups"] != e["pickups"] for e in after) >= 2,
            ],
        )
    if rules.get("reroll_pedestals"):
        check(
            "pedestals_rerolled",
            [
                bool(before["pedestals"]),
                any(
                    e["pedestals"] != before["pedestals"]
                    and (e["pedestals"] or rules.get("can_remove_pedestal"))
                    for e in after
                ),
            ],
        )
    if rules.get("spindown"):
        check(
            "spindown",
            [
                any(
                    e["pedestals"]
                    and all(item["enum"] == "COLLECTIBLE_DESSERT" for item in e["pedestals"])
                    for e in after
                )
            ],
        )
    if rules.get("cycling_pedestal"):
        choices = {item["subtype"] for e in after for item in e["pedestals"]}
        check("pedestal_cycles", [len(choices) >= 2])
    if rules.get("remove_oldest"):
        check(
            "oldest_removed",
            [before["breakfast_count"] == 1, any(e["breakfast_count"] == 0 for e in after)],
        )
    if rules.get("sell_room"):
        check("room_sold", [any(not e["pedestals"] and e["coin_value"] >= 15 for e in after)])
    if rules.get("convert_pickups"):
        variant = rules["convert_pickups"]
        expected = before["pickup_count"] + before["enemy_count"]
        check(
            "pickups_and_enemies_converted",
            [
                expected >= 6,
                any(
                    e["enemy_count"] == 0 and e["pickup_types"].get(variant, 0) >= expected
                    for e in after
                ),
            ],
        )
    if rules.get("fill_poop"):
        check("room_filled", [any(e["poop_count"] >= 30 for e in after)])
    if rules.get("rock_spawns"):
        check(
            "rocks_spawned",
            [any(e["rock_count"] >= before["rock_count"] + rules["rock_spawns"] for e in after)],
        )
    if rules.get("dies"):
        check("user_dies", [any(e["dead"] or e["ghost"] for e in after)])
    for effect in rules.get("null_effects", []):
        check("null_effect:" + effect, [any(e["null_effects"].get(effect) is True for e in after)])
    if rules.get("flying"):
        check("flight", [before["flying"] is False, any(e["flying"] is True for e in after)])
    for event in after:
        for tear in event["tears"]:
            tracks.setdefault(tear["seed"], []).append((event["tick"], tear))
    if rules.get("split_tear_damage"):
        check(
            "split_tear_damage",
            [any(0 < tear["damage"] < e["damage"] * 0.6 for e in after for tear in e["tears"])],
        )
    if rules.get("alternating_damage"):
        damage = [tear["damage"] for e in after for tear in e["tears"]]
        check(
            "left_and_right_eye_damage",
            [
                any(abs(d - before["damage"]) < 0.01 for d in damage),
                any(abs(d - before["damage"] - rules["alternating_damage"]) < 0.01 for d in damage),
            ],
        )
    if rules.get("orbit_tears"):
        check(
            "orbit_trajectory",
            [
                any(
                    any(v["vx"] > 1 for _, v in track) and any(v["vx"] < -1 for _, v in track)
                    for track in tracks.values()
                )
            ],
        )
    if rules.get("tear_decelerates"):
        check(
            "tears_decelerate",
            [
                any(
                    abs(track[0][1]["vx"]) + abs(track[0][1]["vy"])
                    > abs(track[-1][1]["vx"]) + abs(track[-1][1]["vy"]) + 1
                    for track in tracks.values()
                )
            ],
        )
    if rules.get("tear_bounces"):
        check(
            "tear_bounces_from_ground",
            [
                any(
                    any(b["height"] > a["height"] + 1 for (_, a), (_, b) in zip(track, track[1:]))
                    and any(
                        b["height"] < a["height"] - 1 for (_, a), (_, b) in zip(track, track[1:])
                    )
                    for track in tracks.values()
                )
            ],
        )
    if rules.get("delayed_tear_explosion"):
        check(
            "delayed_damage",
            [any(e["enemy_hp"] < before["enemy_hp"] - 60 for e in after if e["tick"] > 180)],
        )
    if rules.get("reverse"):
        axis = "vx" if rules.get("wide_lane") else "vy"
        check(
            "returning_tears",
            [
                any(
                    any(t[axis] < -1 for _, t in track) and any(t[axis] > 1 for _, t in track)
                    for track in tracks.values()
                )
            ],
        )
    if rules.get("damage_growth"):
        check(
            "damage_grows_with_distance",
            [
                any(
                    track[-1][1]["damage"] > track[0][1]["damage"] + 0.5
                    for track in tracks.values()
                )
            ],
        )
    if rules.get("damage_decay"):
        check(
            "damage_decays_with_distance",
            [
                any(
                    track[0][1]["damage"] > track[-1][1]["damage"] + 0.5
                    for track in tracks.values()
                )
            ],
        )
    if rules.get("hold_release"):
        check(
            "held_then_released",
            [
                any(
                    any(t < 100 and abs(v["vx"]) + abs(v["vy"]) < 0.5 for t, v in track)
                    and any(t > 110 and abs(v["vx"]) + abs(v["vy"]) > 5 for t, v in track)
                    for track in tracks.values()
                )
            ],
        )
    if rules.get("wrap"):
        check(
            "wraps_room_boundary",
            [
                any(
                    abs(b["y"] - a["y"]) > 200
                    for track in tracks.values()
                    for (_, a), (_, b) in zip(track, track[1:])
                )
            ],
        )
    if rules.get("beam"):
        moving = [e for e in after if 96 <= e["tick"] <= 110 and e["tears"]]
        check(
            "beam_follows_player",
            [all(abs(t["x"] - e["x"]) < 12 for t in e["tears"]) for e in moving],
        )
        check("beam_movement", [any(e["x"] > before["x"] + 15 for e in moving)])
    if rules.get("attract_pickup"):
        check(
            "pickup_attracted",
            [
                any(
                    e.get("attracted_x", 9999) < before.get("attracted_x", -9999) - 10
                    for e in after
                )
            ],
        )
    if rules.get("spectral_target") and not rules.get("break_obstacle"):
        check("rock_remains", [e.get("obstacle_intact") is True for e in after])
    if rules.get("piercing") and not rules.get("overflow_damage"):
        check(
            "damages_both_inline_targets",
            [any(sum(enemy["hp"] < 500 for enemy in e.get("targets", [])) >= 2 for e in after)],
        )
    if rules.get("enemy_hurt") or rules.get("enemy_damage"):
        initial = before["enemy_hp"]
        damage = rules.get("enemy_damage", 1)
        check("enemy_damage", [initial > 0, any(e["enemy_hp"] <= initial - damage for e in after)])
    if rules.get("cursor_target"):
        check(
            "native_cursor_targets_enemy",
            [any(target.get("cursor_aligned", 0) > 0 for e in after for target in e["targets"])],
        )
    for effect in rules.get("effects", []):
        check("effect:" + effect, [any(e["effects"].get(effect, 0) > 0 for e in after)])
    for familiar, count in rules.get("familiars", {}).items():
        check(
            "familiar:" + familiar,
            [
                any(
                    e["familiars"].get(familiar, 0) - before["familiars"].get(familiar, 0) == count
                    for e in after
                )
            ],
        )
    if rules.get("minimum_familiars") or rules.get("new_familiar"):
        count = rules.get("minimum_familiars", 1)
        check(
            "familiars_added",
            [any(e["familiar_count"] >= before["familiar_count"] + count for e in after)],
        )
    for familiar, minimum in rules.get("minimum_spawned_familiars", {}).items():
        check(
            "familiar:" + familiar,
            [
                any(
                    e["familiars"].get(familiar, 0)
                    >= before["familiars"].get(familiar, 0) + minimum
                    for e in after
                )
            ],
        )
    for familiar, (low, high) in rules.get("familiar_range", {}).items():
        counts = [
            e["familiars"].get(familiar, 0) - before["familiars"].get(familiar, 0) for e in after
        ]
        check("familiar:" + familiar, [low <= max(counts, default=0) <= high])
    for prefix, (low, high) in rules.get("spawns", {}).items():
        counts = [
            sum(n for key, n in e["spawned"].items() if key.startswith(prefix)) for e in after
        ]
        check("spawn:" + prefix, [low <= max(counts, default=0) <= high])
    if rules.get("charged"):
        check("charged", [before["charge"] == 0, any(e["charge"] >= 6 for e in after)])
    if rules.get("active_charge_unchanged"):
        check("charge_preserved", [e["charge"] == before["charge"] for e in after])
    if rules.get("smelt"):
        check(
            "smelted",
            [before["trinket"] != 0, any(e["trinket"] == 0 and e["smelted"] for e in after)],
        )
    if rules.get("returned_pill"):
        check("returned_pill", [any(e["returned_pills"] > 0 for e in after)])
    if rules.get("random_stats") or rules.get("positive_stats"):
        fields = ("damage", "delay", "speed", "range", "shot_speed", "luck", "max_hearts")
        changes = [
            (after[-1][field] - before[field]) * (-1 if field == "delay" else 1) for field in fields
        ]
        if rules.get("positive_stats"):
            check("positive_stats", [sum(v > 0.001 for v in changes) >= rules["positive_stats"]])
        else:
            check(
                "random_stat_directions",
                [any(v > 0.001 for v in changes), any(v < -0.001 for v in changes)],
            )
    if rules.get("crush_rock"):
        check("rock_crushed", [any(e.get("rock_crushed") is True for e in host)])
    if rules.get("expire_room"):
        restored = [e for e in host if e["tick"] >= rules.get("room_tick", 180) + 60]
        check("room_changed", [any(e["room"] != before["room"] for e in restored)])
        for field in rules.get("stats", {}):
            check("expired:" + field, [abs(e[field] - before[field]) < 0.001 for e in restored])
        for field in rules.get("hit_stats", {}):
            check("expired:" + field, [abs(e[field] - before[field]) < 0.001 for e in restored])
        for effect in rules.get("null_effects", []):
            check("expired:" + effect, [e["null_effects"].get(effect) is False for e in restored])
        if rules.get("flying_expire_room"):
            check("expired:flight", [e["flying"] == before["flying"] for e in restored])
    # Check player state at matching serialized ticks. A missing peer is not a
    # pass. Transient attack entities are checked for appearance separately.
    authority = {e["tick"]: e for e in host if e.get("label") == "captured"}
    pairs = [
        (authority[e["tick"]], e)
        for e in client
        if e["tick"] in authority and e["tick"] >= use_tick
    ]
    check("matched_snapshots", [len(pairs) >= 2])
    visible_pairs = [(a, b) for a, b in pairs if b.get("room_visible", True)]
    if remote_world:
        check("remote_room_shell", [any(not b.get("room_visible", True) for _, b in pairs)])
    else:
        check("visible_snapshots", [len(visible_pairs) >= 2])
    if rules.get("secret_doors"):
        check("replica:secret_doors", [a["doors"] == b["doors"] for a, b in visible_pairs])
    if rules.get("red_rooms"):
        check("replica:red_rooms", [a["red_rooms"] == b["red_rooms"] for a, b in pairs])
    if rules.get("map") or rules.get("reveals_room") or rules.get("floor_visit"):
        check("replica:map", [a["map"] == b["map"] for a, b in pairs])
    if rules.get("floor_visit"):
        check("replica:room_type", [a["room_type"] == b["room_type"] for a, b in visible_pairs])
        check(
            "replica:boss_count", [len(a["bosses"]) == len(b["bosses"]) for a, b in visible_pairs]
        )
    if rules.get("overcharge"):
        check("replica:stored_battery", [a["battery"] == b["battery"] for a, b in pairs])
    if rules.get("pill_conversion"):
        check("replica:pill_conversion", [a["pill_mapping"] == b["pill_mapping"] for a, b in pairs])
    if rules.get("swap_familiar"):
        check(
            "replica:teleport_position",
            [abs(a["x"] - b["x"]) < 0.01 and abs(a["y"] - b["y"]) < 0.01 for a, b in pairs],
        )
    if rules.get("movement_rate"):
        motion = []
        for a, b in visible_pairs:
            actual = {t["seed"]: t for t in b["targets"]}
            motion.append(
                all(
                    t["seed"] in actual
                    and all(abs(t[f] - actual[t["seed"]][f]) < 0.01 for f in ("x", "y"))
                    for t in a["targets"]
                )
            )
        check("replica:enemy_movement", motion)
    world_rules = (
        "trinket_loot",
        "floor_visit",
        "loose_pickups",
        "reroll_pedestals",
        "spindown",
        "cycling_pedestal",
        "remove_oldest",
        "sell_room",
        "convert_pickups",
        "fill_poop",
        "rock_spawns",
        "grid_spawn",
        "destroy_rocks",
        "priced_pickups",
        "spawn_after_hit",
        "spawn_after_kill",
        "shop_spawn",
        "random_native_effect",
        "absorb_pedestal",
        "consume_pickups",
        "crooked_penny",
        "glitched_pedestal",
        "reroll_grids",
        "repeat_damage",
        "floor_pickup",
        "destroy_fixture_rocks",
        "destroy_fixture_poops",
    )
    if any(rules.get(name) for name in world_rules):
        for field in ("pickups", "pedestals", "poop_count", "rock_count"):

            def state(probe):
                value = probe[field]
                if field == "pedestals":
                    # Lua enum aliases can name the same numeric collectible.
                    # Gameplay identity, price and native seed must still agree.
                    return [{k: v for k, v in item.items() if k != "enum"} for item in value]
                return value

            check("replica:" + field, [state(a) == state(b) for a, b in visible_pairs])
    if rules.get("changes_character"):
        check("replica:character", [a["player_type"] == b["player_type"] for a, b in pairs])
    if rules.get("consumed_active"):
        check(
            "active_consumed",
            [any(e.get("active_item") == "COLLECTIBLE_NULL" for e in after if e["tick"] < 120)],
        )
        check(
            "next_active_has_empty_charge",
            [
                e.get("active_item") == "COLLECTIBLE_D6" and e["charge"] == 0
                for pair in pairs
                for e in pair
                if e["tick"] >= 129
            ],
        )
    if rules.get("reroll_inventory") or rules.get("sacrifice_familiars"):
        check("replica:inventory", [a["inventory"] == b["inventory"] for a, b in pairs])
    if rules.get("enemy_hurt") or rules.get("enemy_damage") or rules.get("enemy_flags"):
        check(
            "replica:enemy_health",
            [abs(a["enemy_hp"] - b["enemy_hp"]) < 0.01 for a, b in visible_pairs],
        )
    if rules.get("lasers"):
        check("replica:laser_attack", [any(e["laser_count"] > 0 for e in client)])
    if rules.get("knives"):
        check("replica:knife_attack", [any(e["knives"] for e in client)])
    if rules.get("bomb_attack"):
        check("replica:bomb_attack", [any(e["explosives"] for e in client)])
    for name, group in (
        ("lasers", "lasers"),
        ("knives", "knives"),
        ("bomb_attack", "explosives"),
        ("bomb_trial", "explosives"),
        ("repel_projectile", "projectiles"),
    ):
        if not rules.get(name):
            continue
        matched = []
        for a, b in visible_pairs:
            actual = {e["seed"]: e for e in b[group]}
            for expected in a[group]:
                value = actual.get(expected["seed"])
                matched.append(
                    value is not None
                    and all(
                        abs(v - value[field]) < 0.01
                        for field, v in expected.items()
                        if field != "flags"
                    )
                )
        check("replica:" + group + "_geometry", matched)
    if any(
        prefix.startswith("4.")
        for group in ("spawns", "spawn_after_hit")
        for prefix in rules.get(group, {})
    ):

        def bomb_geometry(probe):
            return [{k: v for k, v in bomb.items() if k != "flags"} for bomb in probe["explosives"]]

        check("replica:bombs", [bomb_geometry(a) == bomb_geometry(b) for a, b in visible_pairs])
    for field in (
        {
            "hearts",
            "max_hearts",
            "charge",
            "damage",
            "delay",
            "speed",
            "range",
            "shot_speed",
            "luck",
        }
        | set(rules.get("delta", {}))
        | set(rules.get("stats", {}))
    ):
        check(
            "replica:" + field,
            [
                abs(a[field] - b[field]) < 0.001
                for a, b in pairs
                if not (
                    field == "charge"
                    and rules.get("consumed_active")
                    and a.get("active_item") == b.get("active_item") == "COLLECTIBLE_NULL"
                    or field == "hearts"
                    and rules.get("dies")
                    and a.get("ghost")
                    and b.get("ghost")
                )
            ],
        )
    if rules.get("dies"):
        # Native ghost conversion owns hidden inventory; its red-heart sentinel
        # is not a living player's synchronized health contract.
        check("replica:ghost_conversion", [a["ghost"] == b["ghost"] for a, b in pairs])
    if (
        rules.get("tear_flags")
        or rules.get("replicate_tears")
        or rules.get("fire_through_familiar")
        or (
            rules.get("shoot")
            and not any(rules.get(kind) for kind in ("lasers", "knives", "bomb_attack", "axe"))
            and (not rules.get("suppress_player_tears") or rules.get("minimum_tears"))
        )
        or rules.get("radial")
        or rules.get("invulnerable")
    ):
        # Replica tears follow authoritative trajectories and appearance; they
        # intentionally do not execute the authority's collision/status flags.
        matched, motion, appearance = 0, [], []
        for authority_probe, replica_probe in visible_pairs:
            actual = list(replica_probe["tears"])
            for expected in authority_probe["tears"]:
                # Native split tears can share InitSeed. Match every sibling
                # once; a seed-keyed dict silently discards mirrored siblings.
                candidates = [
                    i for i, tear in enumerate(actual) if tear["seed"] == expected["seed"]
                ]
                if not candidates:
                    motion.append(False)
                    continue
                index = next(
                    (
                        i
                        for i in candidates
                        if all(
                            abs(actual[i][f] - expected[f]) < 0.01 for f in ("x", "y", "vx", "vy")
                        )
                    ),
                    candidates[0],
                )
                tear = actual.pop(index)
                matched += 1
                motion.append(
                    all(abs(tear[f] - expected[f]) < 0.01 for f in ("x", "y", "vx", "vy"))
                )
                if "color" in tear and "color" in expected:
                    appearance.append(
                        all(abs(a - b) < 0.01 for a, b in zip(tear["color"], expected["color"]))
                    )
                if "scale" in expected:
                    appearance.append(
                        "scale" in tear and abs(tear["scale"] - expected["scale"]) < 0.01
                    )
        check("replica:tear_motion", motion if matched else [])
        check("replica:tear_appearance", appearance)
    for group, names in (
        ("effects", rules.get("effects", [])),
        ("familiars", rules.get("familiars", {})),
        ("familiars", rules.get("minimum_spawned_familiars", {})),
        ("familiars", rules.get("familiar_range", {})),
    ):
        for name in names:
            check("replica:" + name, [any(e[group].get(name, 0) > 0 for e in client)])
    return checks
