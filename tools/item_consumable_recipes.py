"""Native use scenarios. Preconditions are independent of the item under test."""

# Temporary buffs must also disappear when their holder changes rooms. Spawn
# rules count actual objects immediately after native use, then compare peers.
CONSUMABLE_RECIPES = {
    "CARD_SUN": {
        "resources": {"hearts": 2},
        "exact": {"hearts": "max_hearts"},
        "enemy_damage": 100,
    },
    "RUNE_DAGAZ": {"delta": {"soul": 2}},
    "CARD_FOOL": {"teleport": "start"},
    "CARD_EMPEROR": {"teleport": ["ROOM_BOSS"]},
    "CARD_HERMIT": {"teleport": ["ROOM_SHOP"]},
    "CARD_STARS": {"teleport": ["ROOM_TREASURE"]},
    "CARD_MOON": {"teleport": ["ROOM_SECRET"]},
    "CARD_JOKER": {"teleport": ["ROOM_DEVIL", "ROOM_ANGEL"]},
    "CARD_EMPRESS": {
        "stats": {"damage": 1, "speed": 1},
        "expire_room": ["damage", "speed"],
    },
    "CARD_HIEROPHANT": {"spawns": {"5.10.3": (2, 2)}},
    "CARD_LOVERS": {"spawns": {"5.10.1": (2, 2)}},
    "CARD_JUSTICE": {
        "spawns": {"5.10.": (1, 1), "5.20.": (1, 1), "5.30.": (1, 1), "5.40.": (1, 1)},
    },
    "CARD_WHEEL_OF_FORTUNE": {"spawns": {"6.1.|6.3.|6.16.": (1, 1)}},
    "CARD_STRENGTH": {
        "stats": {"max_hearts": 1, "hearts": 1, "damage": 1, "speed": 1, "range": 1},
        "expire_room": ["max_hearts", "damage", "speed", "range"],
    },
    "CARD_HANGED_MAN": {"stats": {"flying": 1}, "expire_room": ["flying"]},
    "CARD_DEATH": {"enemy_damage": 40},
    "CARD_TEMPERANCE": {"spawns": {"6.2.": (1, 1)}},
    "CARD_DEVIL": {"stats": {"damage": 1}, "expire_room": ["damage"]},
    "CARD_TOWER": {"spawns": {"4.3.": (6, 6)}, "delayed_spawn": True},
    "CARD_JUDGEMENT": {"spawns": {"6.4.|6.5.|6.7.|6.9.|6.13.|6.18.": (1, 1)}},
    "CARD_CLUBS_2": {"resources": {"bombs": 5}, "double": ["bombs"]},
    "CARD_DIAMONDS_2": {"resources": {"coins": 7}, "double": ["coins"]},
    "CARD_SPADES_2": {"resources": {"keys": 3}, "double": ["keys"]},
    "CARD_HEARTS_2": {"resources": {"hearts": 3}, "double": ["hearts"]},
    "CARD_ANCIENT_RECALL": {"spawns": {"5.300.": (3, 3)}},
    "CARD_REVERSE_HIEROPHANT": {"spawns": {"5.10.11": (2, 2)}},
    "CARD_REVERSE_JUSTICE": {"spawns": {"5.60.": (2, 4)}},
    "CARD_REVERSE_JUDGEMENT": {"spawns": {"6.10.": (1, 1)}},
    "CARD_QUEEN_OF_HEARTS": {"spawns": {"5.10.1": (1, 20)}},
    "CARD_SOUL_KEEPER": {"spawns": {"5.20.": (1, 25)}},
    "COLLECTIBLE_DECK_OF_CARDS": {"pocket": "card"},
    "COLLECTIBLE_MOMS_BOTTLE_OF_PILLS": {"pocket": "pill"},
    "COLLECTIBLE_ANARCHIST_COOKBOOK": {"spawns": {"4.3.": (6, 6)}, "delayed_spawn": True},
    "COLLECTIBLE_GUPPYS_PAW": {
        "resources": {"hearts": 99},
        "delta": {"max_hearts": -2, "hearts": -2, "soul": 6},
    },
    "COLLECTIBLE_CONVERTER": {
        "resources": {"hearts": 99, "soul": 4},
        "delta": {"max_hearts": 2, "hearts": 2, "soul": -2},
    },
    "COLLECTIBLE_GUPPYS_HEAD": {
        "stats": {"owned_blue_flies": 1},
        "range_delta": {"owned_blue_flies": (2, 4)},
        "reunite": True,
    },
    "COLLECTIBLE_BOX_OF_SPIDERS": {
        "stats": {"owned_blue_spiders": 1},
        # Repentance+ doubled the original two-to-four spider count.
        "range_delta": {"owned_blue_spiders": (4, 8)},
        "reunite": True,
    },
    "COLLECTIBLE_PRAYER_CARD": {
        "delta": {"eternal": 1},
        "eternal_lifecycle": True,
    },
    "COLLECTIBLE_YUM_HEART": {
        "team_hearts": 2,
        "resources": {"hearts": 2},
        "delta": {"hearts": 2},
        "team_delta": {"hearts": 1},
        "team_same_room": True,
    },
    "PILLEFFECT_FULL_HEALTH": {
        "resources": {"hearts": 2},
        "exact": {"hearts": "max_hearts"},
        "horse": {"delta": {"soul": 6}},
    },
    "PILLEFFECT_HEMATEMESIS": {
        "resources": {"hearts": 6},
        "exact": {"hearts": 2},
        "spawns": {"5.10.1": (1, 4)},
        "horse": {"spawns": {"5.10.1": (4, 7)}},
    },
    "PILLEFFECT_FRIENDS_TILL_THE_END": {
        "stats": {"owned_blue_flies": 1},
        "delta": {"owned_blue_flies": 3},
        "reunite": True,
        # Repentance+ grants twelve; the older EID horse-pill table says six.
        "horse": {"delta": {"owned_blue_flies": 12}},
    },
    "PILLEFFECT_LARGER": {
        "stats": {"scale_x": 1, "scale_y": 1},
        "unchanged": ["size"],
    },
    "PILLEFFECT_SMALLER": {"stats": {"scale_x": -1, "scale_y": -1, "size": -1}},
    "PILLEFFECT_BOMBS_ARE_KEYS": {
        "resources": {"bombs": 4, "keys": 8},
        "golden_bomb": True,
        "golden_lifecycle": True,
        "swap": [["bombs", "keys"], ["golden_bomb", "golden_key"]],
        "horse": {"swap_multiplier": 1.5},
    },
    "PILLEFFECT_I_FOUND_PILLS": {
        "unchanged": [
            "damage",
            "delay",
            "speed",
            "range",
            "shot_speed",
            "luck",
            "hearts",
            "max_hearts",
            "soul",
            "coins",
            "bombs",
            "keys",
        ],
    },
}


def consumable_recipe(case):
    recipe = CONSUMABLE_RECIPES.get(case.get("enum"), {})
    recipe = {**recipe, **(recipe.get("horse", {}) if case.get("horse") else {})}
    if recipe.get("team_same_room") and case.get("split"):
        recipe["team_delta"] = {field: 0 for field in recipe["team_delta"]}
    return recipe
