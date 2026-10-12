-- Minimal vanilla enum fixtures for components loaded without the game.
-- Keep scenario inputs/expected wire values literal so ID drift stays visible.
-- Reference: https://wofsauge.github.io/IsaacDocs/rep/enums/EntityType.html
return {
    EntityType = {
        ENTITY_PLAYER = 1,
        ENTITY_TEAR = 2,
        ENTITY_FAMILIAR = 3,
        ENTITY_BOMB = 4,
        ENTITY_PICKUP = 5,
        ENTITY_LASER = 7,
        ENTITY_KNIFE = 8,
        ENTITY_PROJECTILE = 9,
        ENTITY_MOTHERS_SHADOW = 867,
        ENTITY_EFFECT = 1000,
    },
    EntityFlag = { FLAG_DONT_OVERWRITE = 2097152 },
    PickupVariant = { PICKUP_COLLECTIBLE = 100 },
    PlayerType = {
        PLAYER_BLUEBABY_B = 25,
        PLAYER_XXX_B = 25,
        PLAYER_LAZARUS_B = 29,
        PLAYER_LAZARUS2_B = 38,
    },
    EffectVariant = { DOGMA_ORB = 172 },
    LevelStage = { STAGE5 = 10, STAGE8 = 13 },
    StageType = { STAGETYPE_ORIGINAL = 0, STAGETYPE_WOTL = 1 },
    RoomType = {
        ROOM_MINIBOSS = 6,
        ROOM_SECRET = 7,
        ROOM_SUPERSECRET = 8,
        ROOM_CURSE = 10,
        ROOM_CHALLENGE = 11,
    },
    DoorVariant = { DOOR_UNLOCKED = 8 },
    TrinketType = { TRINKET_FLAT_FILE = 151 },
    CollectibleType = {
        COLLECTIBLE_BLACK_CANDLE = 260,
        COLLECTIBLE_ISAACS_HEART = 276,
        COLLECTIBLE_TOOTH_AND_NAIL = 663,
        COLLECTIBLE_BAG_OF_CRAFTING = 710,
    },
}
