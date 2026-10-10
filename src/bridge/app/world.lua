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
local reconcileEntities = performance.wrap("apply.entities", modules["sync/entities"])
local reconcileGrids = performance.wrap("apply.grids", modules["sync/grids"])
local npcState = assert(modules["sync/npc"])
local curses = assert(modules["sync/curses"])
local greed = assert(modules["compat/routes/greed"])(function()
    return Game()
end)
local crawlspace = assert(modules["compat/routes/crawlspace"])(function()
    return Game():GetLevel()
end, Vector)
local forms = assert(modules["compat/characters/lazarus"])(native, function(index)
    return Isaac.GetPlayer(index)
end)
local poop = assert(modules["compat/characters/blue_baby"])(native)
state.encode, state.decode = encode, decode
local entityCodec = assert(modules["sync/entity_codec"])(
    native,
    assert(modules["sync/entity_schema"]),
    npcState,
    assert(modules["compat/bosses/dogma"])(Vector)
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
local pack = string.pack
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
})
local inventory = performance.wrap("capture.inventory", inventoryState.capture)
local applyInventory = performance.wrap("apply.inventory", inventoryState.apply)
local lastInventory = {}
local actorsPresentation = assert(modules["presentation/actors"])(native, function(path)
    return Isaac.GetCostumeIdByPath(path)
end, applySprite)
local motionPresentation = assert(modules["presentation/motion"])(native, actorsPresentation, {
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
local function roomState(slot)
    local value
    assert(native.rooms_with_player(slot, function()
        local room = Game():GetRoom()
        local entities, grids = {}, {}
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:Exists() and e.Type ~= 1 then
                entities[#entities + 1] = entity(e)
            end
        end
        for index = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(index)
            if grid then
                local door = grid:ToDoor()
                local extra = door
                        and {
                            door.Slot,
                            door.TargetRoomIndex,
                            door.CurrentRoomType,
                            door.TargetRoomType,
                            door.Direction,
                            door:IsLocked(),
                            door.Busted,
                            door.ExtraVisible,
                            sprite(assert(native.door_sprite(door:GetSprite()))),
                        }
                    or false
                grids[#grids + 1] = {
                    index,
                    grid:GetType(),
                    grid:GetVariant(),
                    grid.State,
                    grid.CollisionClass,
                    grid.VarData,
                    sprite(grid:GetSprite()),
                    grid:GetSaveState().SpawnSeed,
                    extra,
                }
            end
        end
        value = {
            room:IsClear(),
            room:GetFrameCount(),
            entities,
            grids,
            native.music_state(),
            native.room_layout(),
            crawlspace.capture(),
        }
    end))
    return value
end
local captureTick, captureActors, captureVisuals = nil, {}, {}
function state.capture(slot, tick)
    performance.resources()
    local game = Game()
    local level = game:GetLevel()
    local locations = native.rooms_positions()
    local loc = {}
    if captureTick ~= tick then
        captureTick = tick
        captureActors = {}
        captureVisuals = {}
    end
    local actors = {}
    local view = assert(locations[tostring(slot)])
    for index = 0, game:GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(index)
        local base = captureActors[index]
        if not base then
            base = {
                index,
                p.ControllerIndex,
                entity(p, false),
                inventory(p),
                {},
                false,
                poop.capture(p),
            }
            captureActors[index] = base
        end
        local position = locations[tostring(p.ControllerIndex - 1)]
        if position and position.index == view.index and position.dimension == view.dimension then
            local full = captureVisuals[index]
            if not full then
                local visuals = {}
                for _, s in
                    ipairs(
                        assert(
                            native.actor_sprites(index, p:GetSprite()),
                            "Native actor visual layout mismatch"
                        )
                    )
                do
                    visuals[#visuals + 1] = sprite(s)
                end
                full = {
                    index,
                    p.ControllerIndex,
                    entity(p),
                    base[4],
                    visuals,
                    assert(native.actor_pose(p:GetSprite())),
                    base[7],
                }
                captureVisuals[index] = full
            end
            actors[#actors + 1] = full
        else
            actors[#actors + 1] = base
        end
    end
    for player = 0, 3 do
        local at = locations[tostring(player)]
        if at then
            local position = Isaac.GetPlayer(native.rooms_heads()[tostring(player)]).Position
            loc[#loc + 1] = { player, at.dimension, at.index, position.X, position.Y }
        end
    end
    modules["compat/items/black_candle"](level, actors, CollectibleType.COLLECTIBLE_BLACK_CANDLE)
    local map = {}
    local rooms = level:GetRooms()
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        for dimension = 0, 2 do
            local match = level:GetRoomByIdx(d.SafeGridIndex, dimension)
            if match and match.Data and match.ListIndex == d.ListIndex then
                map[#map + 1] = {
                    d.SafeGridIndex,
                    d.DisplayFlags,
                    d.VisitedCount,
                    d.Clear,
                    d.ClearCount,
                    d.Flags,
                    dimension,
                    native.map_pickups(d.SafeGridIndex, dimension),
                    native.room_layout(d.SafeGridIndex, dimension),
                }
                break
            end
        end
    end
    return encode(worldSchema.pack({
        tick = tick,
        frame = game:GetFrameCount(),
        stage = level:GetStage(),
        stageType = level:GetStageType(),
        connected = native.rooms_connected(),
        locations = loc,
        map = map,
        actors = actors,
        slot = slot,
        room = roomState(slot),
        sound = audioPresentation.capture(slot),
        progress = native.net_progress(),
        epoch = native.net_floor_epoch(),
        presentation = native.presentation_events(slot),
        items = itemPresentation.capture(slot),
        curses = curses.capture(level),
        greed = greed.capture(),
    }))
end
local replicas, motion = {}, {}
local replicaRoom, receivedTick = nil, -1
local actorVisuals = {}
local function ref(identifier)
    local pointer = replicas[identifier]
    return pointer and pointer.Ref or nil
end
local function discard(e)
    -- J460 can keep a removed NPC in its floor-render queue for one update.
    -- Its replica has no native death update to turn that pose into gore;
    -- hiding before removal prevents baking the old silhouette into the floor.
    e.Visible = false
    e:Remove()
end
local function applyEntity(e, v, now)
    entityCodec.apply(e, v)
    -- Preserve ownership through EntityPtr; local allocation indices are never IDs.
    replicas[v[1]] = EntityPtr(e)
    local prior = motion[v[1]]
    motion[v[1]] = {
        from = prior and prior.target or vec(v[6]),
        target = vec(v[6]),
        display = prior and prior.display or vec(v[6]),
        velocity = vec(v[7]),
        at = now,
        actor = e.Type == 1,
        controller = e.Type == 1 and e:ToPlayer().ControllerIndex or -1,
        prediction = e.Type == 1 and (prior and prior.prediction or prediction.new(vec(v[6]))),
        doorway = prior and prior.doorway,
    }
end
local floor = assert(modules["runtime/floor"])(native, assert(modules["compat/routes/home"]))
local transitions = assert(modules["compat/transitions"])({
    assert(modules["compat/routes/home"]),
    assert(modules["compat/items/hourglass"]),
    assert(modules["compat/items/r_key"]),
})
state.beginFloor = assert(modules["runtime/transitions"])(native, floor, transitions, function()
    return Game():GetLevel()
end, function()
    greed.reset()
    motion = {}
    actorVisuals = {}
    replicaRoom = nil
end)
function state.apply(bytes, tick, ack)
    performance.resources()
    if floor.waiting() then
        return false
    end
    local value = worldSchema.unpack(decode(bytes), tick)
    local game = Game()
    local level = game:GetLevel()
    if not floor.ready(level, value.epoch, value.stage, value.stageType) then
        return false
    end
    -- Register every generated descriptor before room transfer or map caching.
    -- Offscreen red rooms must also have a valid native list/cell index.
    for _, d in ipairs(value.map) do
        assert(native.room_layout(d[9]))
    end
    assert(native.room_layout(value.room[6]))
    local parts = { pack(">BB", value.connected, #value.locations) }
    for _, p in ipairs(value.locations) do
        parts[#parts + 1] = pack(">Bi4i4ff", table.unpack(p))
    end
    assert(native.rooms_sync(table.concat(parts)))
    local positions = native.rooms_positions()
    local localPosition = assert(positions[tostring(value.slot)])
    local key = localPosition.dimension .. ":" .. localPosition.index
    local roomChanged = key ~= replicaRoom
    if roomChanged then
        -- Reset before applying actors: room snapshots exclude player entities.
        -- Clearing afterward used to lose the arrival's player motion record.
        motion = {}
        replicaRoom = key
        motionPresentation.reset()
    end
    native.state_clock(value.frame)
    assert(native.net_progress(value.progress))
    local now = Isaac.GetTime() / 1000
    for _, actor in ipairs(value.actors) do
        local p = forms.resolve(actor[1], actor[4], actor[2])
        assert(
            p and p.ControllerIndex == actor[2],
            "Replica actor roster differs: index="
                .. actor[1]
                .. " expectedController="
                .. actor[2]
                .. " actualController="
                .. (p and p.ControllerIndex or -1)
                .. " expectedType="
                .. actor[4][1]
                .. " actualType="
                .. (p and p:GetPlayerType() or -1)
        )
        if p:IsCoopGhost() ~= actor[4][9] then
            assert(native.actor_ghost(actor[1], actor[4][9] and 1 or 0))
        end
        local encoded = encode({ actor[4][1], actor[4][2], actor[4][6] })
        -- Item/health setters and familiars stay in this actor's room. The
        -- native resource broadcast restores the whole team's shared pool;
        -- subsequent actor snapshots see the same count and apply no delta.
        assert(native.rooms_with_player(actor[2] - 1, function()
            applyInventory(p, actor[4], lastInventory[actor[3][1]] ~= encoded or tick % 30 == 0)
        end, 1))
        lastInventory[actor[3][1]] = encoded
        applyEntity(p, actor[3], now)
        actorsPresentation.apply(p, actor)
        poop.apply(p, actor[7])
    end
    forms.prune(replicas, motion, lastInventory, value.actors)
    actorVisuals = value.actors
    -- Inventory setters can clear local curses. The shared authoritative mask
    -- must win after those native side effects, before map/HUD caching.
    local cursesChanged = curses.apply(level, value.curses)
    greed.apply(value.greed)
    local mapChanged = roomChanged or cursesChanged
    for _, d in ipairs(value.map) do
        local ok, pickupsChanged = native.map_pickups(d[8])
        assert(ok)
        mapChanged = mapChanged or pickupsChanged
        local descriptor = level:GetRoomByIdx(d[1], d[7])
        if descriptor and descriptor.Data then
            mapChanged = mapChanged
                or descriptor.DisplayFlags ~= d[2]
                or descriptor.VisitedCount ~= d[3]
                or descriptor.Clear ~= d[4]
                or descriptor.Flags ~= d[6]
            descriptor.DisplayFlags, descriptor.VisitedCount, descriptor.Clear, descriptor.ClearCount, descriptor.Flags =
                d[2], d[3], d[4], d[5], d[6]
        end
    end
    -- DisplayFlags already contain the host's visibility result. Recomputing
    -- it here both overrides that result and walks transient empty descriptors
    -- while the replica is replacing a room.
    assert(native.rooms_with_player(value.slot, function()
        local room = game:GetRoom()
        local data = value.room
        crawlspace.apply(data[7])
        reconcileEntities(data[3], {
            ref = ref,
            spawn = function(v, spawner, subtype)
                return game:Spawn(v[2], v[3], vec(v[6]), vec(v[7]), spawner, subtype, v[5])
            end,
            discard = discard,
            apply = function(e, v)
                applyEntity(e, v, now)
            end,
            entities = Isaac.GetRoomEntities,
        })
        assert(native.door_slot(-1))
        reconcileGrids(data[4], {
            get = function(index)
                return room:GetGridEntity(index)
            end,
            size = function()
                return room:GetGridSize()
            end,
            remove = function(index)
                assert(native.grid_remove(index))
            end,
            spawn = function(v)
                if v[9] then
                    assert(native.door_slot(v[9][1], v[1]))
                else
                    room:SpawnGridEntity(v[1], v[2], v[3], v[8] ~= 0 and v[8] or 1, v[6])
                end
            end,
            apply = function(grid, v)
                -- Door variants change when locks/bars change. Preserve the
                -- native door-slot pointer instead of destroying that door.
                if grid:GetVariant() ~= v[3] then
                    assert(native.grid_variant(grid:GetSprite(), v[3]))
                end
                if v[9] then
                    local door = assert(grid:ToDoor())
                    local d = v[9]
                    if door.CurrentRoomType ~= d[3] or door.TargetRoomType ~= d[4] then
                        door:SetRoomTypes(d[3], d[4])
                    end
                    if door:IsLocked() ~= d[6] then
                        door:SetLocked(d[6])
                    end
                    door.Slot, door.TargetRoomIndex, door.Direction = d[1], d[2], d[5]
                    assert(native.door_slot(d[1], v[1], grid:GetSprite()))
                    door.Busted, door.ExtraVisible = d[7], d[8]
                    applySprite(assert(native.door_sprite(door:GetSprite())), d[9])
                end
                grid.State, grid.CollisionClass, grid.VarData = v[4], v[5], v[6]
                applySprite(grid:GetSprite(), v[7])
            end,
        })
        room:SetClear(data[1])
        assert(native.music_state(data[5]))
        if mapChanged then
            assert(native.map_refresh())
        end
    end))
    for identifier, p in pairs(replicas) do
        if not p.Ref then
            replicas[identifier] = nil
            motion[identifier] = nil
            lastInventory[identifier] = nil
        end
    end
    performance.counter("entities", #value.room[3])
    performance.counter("grids", #value.room[4])
    performance.counter("map_rooms", #value.map)
    for _, m in pairs(motion) do
        if m.actor and m.controller == value.slot + 1 then
            m.prediction:confirm(m.target, ack, m.velocity * 60)
        end
    end
    receivedTick = tick
    assert(native.rooms_with_player(value.slot, function()
        audioPresentation.apply(value.sound, tick)
    end))
    assert(native.presentation_events(value.presentation))
    itemPresentation.apply(value.slot, value.items)
    state.lastTick = tick
    return true
end
function state.present(input, sequence)
    greed.present()
    return motionPresentation.present(input, sequence, actorVisuals, motion, ref, receivedTick)
end
function state.reset()
    native.sound_reset()
    native.presentation_reset()
    native.rewind_reset()
    audioPresentation.reset()
    entityCodec.reset()
    replicas = {}
    motion = {}
    lastInventory = {}
    actorsPresentation.reset()
    actorVisuals = {}
    replicaRoom = nil
    receivedTick = -1
    motionPresentation.reset()
    greed.reset()
    floor.reset()
    captureTick = nil
    captureActors = {}
    captureVisuals = {}
end
