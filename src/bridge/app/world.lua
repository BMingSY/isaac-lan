-- Host-owned gameplay, explicit portable state, and client-only presentation.
-- No Lua source, native pointers or Mod tables are transferred over the wire.
local native = assert(_IsaacLan)
local prediction = assert(_IsaacLanPrediction)
local state = {}
_IsaacLanState = state
local modules = assert(_IsaacLanModules)
local codec = assert(modules["sync/codec"])
local performance = modules["diagnostics/performance"]
        and modules["diagnostics/performance"](native, function()
            return Isaac.GetTime()
        end)
    or {
        wrap = function(_, fn)
            return fn
        end,
        counter = function() end,
        resources = function() end,
    }
local encode = performance.wrap("encode", codec.encode)
local decode = performance.wrap("decode", codec.decode)
local reconcileEntities =
    performance.wrap("apply.entities", modules["sync/entities"](EntityType, PickupVariant))
local reconcileGrids = performance.wrap("apply.grids", modules["sync/grids"])
local npcState = assert(modules["sync/npc"])
local curses = assert(modules["sync/curses"])
local deals = assert(modules["sync/deals"])(native)
local pills = assert(modules["sync/pills"])(native)
local greed = assert(modules["compat/routes/greed"])(function()
    return Game()
end)
local crawlspace = assert(modules["compat/routes/crawlspace"])(function()
    return Game():GetLevel()
end, Vector)
local forms = assert(modules["compat/characters/lazarus"])(native, function(index)
    return Isaac.GetPlayer(index)
end, PlayerType)
local poop = assert(modules["compat/characters/blue_baby"])(native, PlayerType)
local craftingBag = assert(modules["compat/items/crafting_bag"])(native, CollectibleType)
local keeper = assert(modules["compat/characters/keeper"])(native, RoomType, PickupVariant)
state.encode, state.decode = encode, decode
local entityCodec = assert(modules["sync/entity_codec"])(
    native,
    assert(modules["sync/entity_schema"])(EntityType),
    npcState,
    assert(modules["compat/bosses/visuals"])(
        assert(modules["compat/bosses/dogma"])(Vector, EntityType, EffectVariant),
        assert(modules["compat/bosses/held_bombs"])(native, EntityType, function()
            return Isaac.GetRoomEntities()
        end)
    ),
    assert(modules["sync/entity_links"])(native, function()
        return Isaac.GetRoomEntities()
    end)
)
local entity, sprite, applySprite, vec =
    entityCodec.capture, entityCodec.sprite, entityCodec.applySprite, entityCodec.vec
entity = performance.wrap("capture.entity", entity)
sprite = performance.wrap("capture.sprite", sprite)
applySprite = performance.wrap("apply.sprite", applySprite)
entityCodec.apply = performance.wrap("apply.entity", entityCodec.apply)
function _IsaacLanRoomEntered()
    modules["runtime/room_entry"](
        Game():GetRoom(),
        RoomType.ROOM_BOSS,
        modules["compat/bosses/room_entry"],
        GridEntityType.GRID_TRAPDOOR
    )
end
local worldSchema = assert(modules["sync/world_schema"])
local itemPresentation = assert(modules["presentation/items"])(native, function()
    return Isaac.GetPlayer(0):GetSprite()
end, sprite, applySprite)
local inventoryState = assert(modules["sync/inventory"])({
    config = function()
        return Isaac.GetItemConfig()
    end,
    activeType = ItemType.ITEM_ACTIVE,
    curse = NullItemID.ID_LOST_CURSE,
    pockets = function(player, value)
        if value == nil then
            return native.actor_pockets(player:GetSprite())
        end
        return native.actor_pockets(player:GetSprite(), value)
    end,
})
local inventory = performance.wrap("capture.inventory", inventoryState.capture)
local applyInventory = performance.wrap("apply.inventory", inventoryState.apply)
local actorsPresentation = assert(modules["presentation/actors"])(native, function(path)
    return Isaac.GetCostumeIdByPath(path)
end, applySprite)
local motionPresentation = assert(modules["presentation/motion"])(native, actorsPresentation, {
    extraAnimationAllowsMovement = function(p, actor)
        local extra = actor[5][1]
        return craftingBag.allowsMovement(p, actor[8], extra and extra[2])
    end,
    vector = Vector,
    player = function(index)
        return Isaac.GetPlayer(index)
    end,
    clock = function()
        return Isaac.GetTime()
    end,
    status = function()
        return _IsaacLanStatus()
    end,
    room = function()
        return Game():GetRoom()
    end,
})
local audioPresentation = assert(modules["presentation/audio"])(native, function()
    return SFXManager()
end)
local captureState = assert(modules["sync/capture"])({
    native = native,
    encode = encode,
    schema = worldSchema,
    game = function()
        return Game()
    end,
    player = function(index)
        return Isaac.GetPlayer(index)
    end,
    entity = entity,
    inventory = inventory,
    sprite = sprite,
    poop = poop,
    craftingBag = craftingBag,
    curses = curses,
    greed = greed,
    deals = deals,
    pills = pills,
    audio = audioPresentation,
    items = itemPresentation,
    reconcileShared = function(level, actors)
        modules["compat/items/black_candle"](
            level,
            actors,
            CollectibleType.COLLECTIBLE_BLACK_CANDLE
        )
    end,
    roomFactory = function()
        return modules["sync/room"](
            native,
            entity,
            sprite,
            crawlspace,
            EntityType,
            entityCodec.localEffect
        )
    end,
})
function state.capture(slot, tick)
    performance.resources()
    return captureState.capture(slot, tick)
end
local home = assert(modules["compat/routes/home"])(LevelStage, StageType)
local floor = assert(modules["runtime/floor"])(native, home)
local transitions = assert(modules["compat/transitions"])({
    home,
    assert(modules["compat/items/hourglass"]),
    assert(modules["compat/items/r_key"]),
    assert(modules["compat/routes/victory_lap"]),
})
local replica = assert(modules["sync/replica"])({
    native = native,
    encode = encode,
    decode = decode,
    schema = worldSchema,
    floor = floor,
    performance = performance,
    entityCodec = entityCodec,
    vec = vec,
    prediction = prediction,
    pointer = function(entity)
        return EntityPtr(entity)
    end,
    hash = function(entity)
        return GetPtrHash(entity)
    end,
    playerType = EntityType.ENTITY_PLAYER,
    game = function()
        return Game()
    end,
    now = function()
        return Isaac.GetTime() / 1000
    end,
    entities = function()
        return Isaac.GetRoomEntities()
    end,
    forms = forms,
    applyInventory = applyInventory,
    actors = actorsPresentation,
    motion = motionPresentation,
    poop = poop,
    craftingBag = craftingBag,
    crawlspace = crawlspace,
    pills = pills,
    curses = curses,
    greed = greed,
    deals = deals,
    entitiesApply = reconcileEntities,
    gridsApply = reconcileGrids,
    applySprite = applySprite,
    audio = audioPresentation,
    items = itemPresentation,
    pose = modules["sync/actor_pose"],
})
state.beginFloor = assert(modules["runtime/transitions"])(native, floor, transitions, function()
    return Game():GetLevel()
end, function()
    greed.reset()
    deals.reset()
    replica.resetView()
    captureState.reset()
end)
function state.apply(bytes, tick, ack, betweenUpdates)
    if not replica.apply(bytes, tick, ack, betweenUpdates) then
        return false
    end
    state.lastTick = tick
    return true
end
function state.present(input, sequence)
    greed.present()
    local status = _IsaacLanStatus()
    if native.api_info().ready == 1 then
        keeper.present(status.slot)
    end
    return replica.present(input, sequence)
end
state.actorPose = replica.actorPose
function state.reset()
    native.sound_reset()
    native.presentation_reset()
    native.rewind_reset()
    audioPresentation.reset()
    entityCodec.reset()
    replica.reset()
    state.lastTick = nil
    greed.reset()
    deals.reset()
    floor.reset()
    captureState.reset()
end
