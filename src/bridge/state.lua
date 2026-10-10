-- Host-owned gameplay, explicit portable state, and client-only presentation.
-- No Lua source, native pointers or Mod tables are transferred over the wire.
local native = assert(_IsaacLan)
local prediction = assert(_IsaacLanPrediction)
local state = {}
_IsaacLanState = state
local modules = assert(_IsaacLanModules)
local codec = assert(modules["state/codec"])
local encode, decode = codec.encode, codec.decode
local npcState = assert(modules["state/npc"])
local forms = assert(modules["state/forms"])(native, function(index)
    return Isaac.GetPlayer(index)
end)
local poop = assert(modules["state/poop"])(native)
state.encode, state.decode = encode, decode
function _IsaacLanRoomEntered()
    local room = Game():GetRoom()
    if room:IsClear() then
        return
    end
    -- Joining a resident room bypasses the global native door transition.
    -- Reapply its combat entry boundary without regenerating its contents.
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then
            door:Close(true)
        end
    end
    if room:GetType() == RoomType.ROOM_BOSS then
        for index = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(index)
            if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then
                grid.State = 0
                grid:GetSprite():Play("Closed", true)
            end
        end
    end
end
local pack, unpack = string.pack, string.unpack
local function vector(v)
    return { v.X, v.Y }
end
local function vec(v)
    return Vector(v[1], v[2])
end
local function color(c)
    return { c.R, c.G, c.B, c.A, c.RO, c.GO, c.BO }
end
local function col(c)
    return Color(table.unpack(c))
end
local nextID = 1
local function id(e)
    if not e or not e:Exists() then
        return 0
    end
    local d = e:GetData()
    if not d.__isaac_lan_entity then
        d.__isaac_lan_entity = nextID
        nextID = nextID + 1
    end
    return d.__isaac_lan_entity
end
local common = {
    "HitPoints",
    "MaxHitPoints",
    "CollisionDamage",
    "Visible",
    "FlipX",
    "DepthOffset",
    "Mass",
    "Size",
    "SpriteRotation",
}
local schema = {
    [1] = {
        "Damage",
        "MaxFireDelay",
        "FireDelay",
        "ShotSpeed",
        "MoveSpeed",
        "Luck",
        "CanFly",
        "TearHeight",
        "TearRange",
        "TearFallingSpeed",
        "TearFallingAcceleration",
        "HeadFrameDelay",
        "ControlsEnabled",
    },
    [2] = { "FallingAcceleration", "FallingSpeed", "Height", "Rotation", "Scale", "WaitFrames" },
    [3] = {
        "State",
        "FireCooldown",
        "HeadFrameDelay",
        "MoveDirection",
        "ShootDirection",
        "LastDirection",
        "OrbitAngleOffset",
        "OrbitLayer",
        "OrbitSpeed",
    },
    [4] = { "ExplosionDamage", "RadiusMultiplier", "IsFetus" },
    [5] = {
        "AutoUpdatePrice",
        "Charge",
        "OptionsPickupIndex",
        "Price",
        "ShopItemId",
        "State",
        "Timeout",
        "Touched",
        "Wait",
    },
    -- J460 exposes SampleLaser as userdata, not a boolean property.
    -- The native sampling flag and path are already carried by laser_path.
    [7] = {
        "Angle",
        "AngleDegrees",
        "LastAngleDegrees",
        "MaxDistance",
        "Radius",
        "Timeout",
        "LaserLength",
        "Shrink",
        "DisableFollowParent",
        "CurveStrength",
        "GridHit",
    },
    [8] = {
        "Rotation",
        "RotationOffset",
        "Scale",
        "Charge",
        "MaxDistance",
        "PathFollowSpeed",
        "PathOffset",
    },
    [9] = {
        "Height",
        "FallingSpeed",
        "FallingAccel",
        "Scale",
        "Damage",
        "Acceleration",
        "HomingStrength",
        "CurvingStrength",
    },
    [1000] = {
        "State",
        "Timeout",
        "LifeSpan",
        "Rotation",
        "Scale",
        "FallingAcceleration",
        "FallingSpeed",
        "m_Height",
        "MinRadius",
        "MaxRadius",
    },
    npc = { "State", "StateFrame", "I1", "I2", "ProjectileCooldown", "ProjectileDelay", "Scale" },
}
local function typed(e)
    if e.Type == 1 then
        return e:ToPlayer(), schema[1]
    elseif e.Type == 2 then
        return e:ToTear(), schema[2]
    elseif e.Type == 3 then
        return e:ToFamiliar(), schema[3]
    elseif e.Type == 4 then
        return e:ToBomb(), schema[4]
    elseif e.Type == 5 then
        return e:ToPickup(), schema[5]
    elseif e.Type == 7 then
        return e:ToLaser(), schema[7]
    elseif e.Type == 8 then
        return e:ToKnife(), schema[8]
    elseif e.Type == 9 then
        return e:ToProjectile(), schema[9]
    elseif e.Type == 1000 then
        return e:ToEffect(), schema[1000]
    elseif e:ToNPC() then
        return e:ToNPC(), schema.npc
    end
    return e, {}
end
local function fields(object, names)
    local result = {}
    for i, name in ipairs(names) do
        local v = object[name]
        if type(v) ~= "number" and type(v) ~= "boolean" then
            error(
                "Unsupported entity field "
                    .. object.Type
                    .. "."
                    .. object.Variant
                    .. "."
                    .. object.SubType
                    .. "."
                    .. name
                    .. ": "
                    .. type(v)
            )
        end
        if type(v) == "number" then
            assert(
                v == v and math.abs(v) < math.huge,
                "Non-finite entity field "
                    .. object.Type
                    .. "."
                    .. object.Variant
                    .. "."
                    .. object.SubType
                    .. "."
                    .. name
            )
        end
        result[i] = v
    end
    return result
end
local function writeFields(object, names, values)
    assert(#names == #values, "Entity schema mismatch")
    for i, name in ipairs(names) do
        object[name] = values[i]
    end
end
local function sprite(s)
    return {
        s:GetFilename(),
        s:GetAnimation(),
        s:GetFrame(),
        s:GetOverlayAnimation(),
        s:GetOverlayFrame(),
        s.FlipX,
        s.FlipY,
        s.Rotation,
        vector(s.Scale),
        vector(s.Offset),
        color(s.Color),
        assert(native.sprite_state(s)),
    }
end
local function applySprite(s, v)
    if s:GetFilename() ~= v[1] then
        if v[1] == "" then
            s:Reset()
        else
            s:Load(v[1], true)
        end
    end
    if v[2] ~= "" then
        s:SetFrame(v[2], v[3])
    end
    if v[4] ~= "" then
        s:SetOverlayFrame(v[4], v[5])
    else
        s:RemoveOverlay()
    end
    s.FlipX, s.FlipY, s.Rotation = v[6], v[7], v[8]
    s.Scale = vec(v[9])
    s.Offset = vec(v[10])
    s.Color = col(v[11])
    local changed = assert(native.sprite_state(s, v[12]))
    for _, layer in ipairs(changed) do
        s:ReplaceSpritesheet(layer[1], layer[2])
    end
    if #changed > 0 then
        s:LoadGraphics()
    end
end
local itemPresentation = assert(modules["state/presentation"])(native, function()
    return Isaac.GetPlayer(0):GetSprite()
end, sprite, applySprite)
local function entity(e, visual)
    if visual == nil then
        visual = true
    end
    local object, names = typed(e)
    if visual then
        assert(native.entity_prepare(e:GetSprite()))
    end
    return {
        id(e),
        e.Type,
        e.Variant,
        e.SubType,
        e.InitSeed,
        vector(e.Position),
        vector(e.Velocity),
        fields(e, common),
        fields(object, names),
        visual and sprite(e:GetSprite()) or false,
        id(e.Parent),
        id(e.SpawnerEntity),
        id(e.Child),
        id(e.Target),
        vector(e.SpriteOffset),
        vector(e.SpriteScale),
        color(e.Color),
        e.FrameCount,
        e:GetEntityFlags(),
        e.Type == 7 and assert(native.laser_path(e:GetSprite())) or false,
        e.Type == 7 and vector(e:ToLaser().EndPoint) or false,
        visual and assert(native.entity_shadow(e:GetSprite())) or false,
        npcState.capture(e:ToNPC()),
    }
end
local inventoryState = assert(modules["state/inventory"])({
    config = function()
        return Isaac.GetItemConfig()
    end,
    activeType = ItemType.ITEM_ACTIVE,
    curse = NullItemID.ID_LOST_CURSE,
})
local inventory, applyInventory = inventoryState.capture, inventoryState.apply
local lastInventory, costumeIDs = {}, {}
local function costumeID(path)
    if costumeIDs[path] == nil then
        costumeIDs[path] = Isaac.GetCostumeIdByPath(path)
    end
    return costumeIDs[path]
end
local function actorSprites(p, actor)
    local sprites = assert(native.actor_sprites(actor[1], p:GetSprite()))
    local existing, desired = {}, {}
    for i = 11, #sprites do
        local path = sprites[i]:GetFilename()
        existing[path] = (existing[path] or 0) + 1
    end
    for i = 11, #actor[5] do
        local path = actor[5][i][1]
        desired[path] = (desired[path] or 0) + 1
    end
    -- Replica-side callbacks can add a null costume based on a provisional
    -- room before its authoritative contents arrive. The host owns actor
    -- appearance too; discard those stale costumes, not only ones we added.
    for path in pairs(existing) do
        if not desired[path] then
            local id = costumeID(path)
            if id >= 0 then
                p:TryRemoveNullCostume(id)
            end
        end
    end
    for path, count in pairs(desired) do
        local id = costumeID(path)
        if id >= 0 then
            for _ = 1, count - (existing[path] or 0) do
                p:AddNullCostume(id)
            end
        end
    end
    -- Adding/removing a costume can reallocate the native vector; reacquire
    -- its non-owning Sprite references before applying any animation state.
    return assert(native.actor_sprites(actor[1], p:GetSprite()))
end
local function applyActorVisuals(p, actor)
    if not actor[6] then
        return
    end
    local sprites = actorSprites(p, actor)
    -- Costume changes can rebuild the base body layers as well.
    applySprite(p:GetSprite(), actor[3][10])
    local used = {}
    for i, v in ipairs(actor[5]) do
        if i <= 3 then
            applySprite(sprites[i], v)
        elseif i > 10 then
            for j = 11, #sprites do
                if not used[j] and sprites[j]:GetFilename() == v[1] then
                    applySprite(sprites[j], v)
                    used[j] = true
                    break
                end
            end
        end
    end
    -- Charge bars (4..10) are local UI. An offscreen authority does not render
    -- their Charging/Charged layers; copying those stale layers every frame
    -- erases the replica's own charge display after players separate rooms.
    -- Native Render derives them from the replicated weapon charge below.
    assert(native.actor_pose(p:GetSprite(), actor[6]))
end
local hostLoops, replicaLoops, lastSound = {}, {}, 0
local function soundEvents(bytes)
    local result, cursor = {}, 1
    while cursor <= #bytes do
        local serial, tick, id, volume, delay, loop, pitch, pan
        serial, tick, id, volume, delay, loop, pitch, pan, cursor =
            unpack(">I4I4I4fI4Bff", bytes, cursor)
        result[#result + 1] = { serial, tick, id, volume, delay, loop, pitch, pan }
    end
    return result
end
local function captureSound(slot)
    local bytes = native.sound_events(slot)
    local loops = hostLoops[slot] or {}
    hostLoops[slot] = loops
    for _, event in ipairs(soundEvents(bytes)) do
        if event[6] ~= 0 then
            loops[event[3]] = event
        end
    end
    local playing = {}
    for id, event in pairs(loops) do
        if SFXManager():IsPlaying(id) then
            playing[#playing + 1] = event
        else
            loops[id] = nil
        end
    end
    return { bytes, playing }
end
local function applySound(value, tick)
    local sfx = SFXManager()
    for _, event in ipairs(soundEvents(value[1])) do
        if event[1] > lastSound then
            if event[6] == 0 and tick - event[2] <= 10 then
                sfx:Play(event[3], event[4], event[5], false, event[7], event[8])
            end
            lastSound = event[1]
        end
    end
    local playing = {}
    for _, event in ipairs(value[2]) do
        playing[event[3]] = true
        if not replicaLoops[event[3]] or not sfx:IsPlaying(event[3]) then
            sfx:Play(event[3], event[4], event[5], true, event[7], event[8])
        end
    end
    for id in pairs(replicaLoops) do
        if not playing[id] then
            sfx:Stop(id)
        end
    end
    replicaLoops = playing
end
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
        }
    end))
    return value
end
local captureTick, captureActors, captureVisuals = nil, {}, {}
function state.capture(slot, tick)
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
    return encode({
        10,
        tick,
        game:GetFrameCount(),
        level:GetStage(),
        level:GetStageType(),
        native.rooms_connected(),
        loc,
        map,
        actors,
        slot,
        roomState(slot),
        captureSound(slot),
        native.net_progress(),
        native.net_floor_epoch(),
        native.presentation_events(slot),
        itemPresentation.capture(slot),
    })
end
local replicas, motion = {}, {}
local replicaRoom, receivedAt, receivedTick, lastRender = nil, 0, -1, nil
local paused = false
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
    e.Variant, e.SubType = v[3], v[4]
    e.Position = vec(v[6])
    e.Velocity = vec(v[7])
    writeFields(e, common, v[8])
    local object, names = typed(e)
    writeFields(object, names, v[9])
    e.SpriteOffset = vec(v[15])
    e.SpriteScale = vec(v[16])
    e.Color = col(v[17])
    -- Entity.Color resets the Sprite color (including alpha/colorize). Apply
    -- the complete native visual state last so fading creep stays faded.
    if v[10] then
        applySprite(e:GetSprite(), v[10])
    end
    if v[22] then
        assert(native.entity_shadow(e:GetSprite(), v[22]))
    end
    if v[23] then
        local npc = assert(e:ToNPC())
        npcState.apply(npc, v[23])
    end
    -- Floor/wall flags tell EntityList::Update to bake and retire a sprite.
    -- Replicas instead keep receiving its pose/lifetime from the host. Baking
    -- an earlier death pose leaves a permanent silhouette in their backdrop.
    local floor, wall = EntityFlag.FLAG_RENDER_FLOOR, EntityFlag.FLAG_RENDER_WALL
    if e.Type == 1 then
        -- Actor lifecycle/persistence flags belong to this native allocation.
        -- Copying the authority's lifecycle bits can retire a live actor when
        -- temporary forms change. Only the visual blink override is replicated.
        local blink = EntityFlag.FLAG_NO_DAMAGE_BLINK
        e:ClearEntityFlags(blink)
        e:AddEntityFlags(v[19] & blink)
    else
        e:ClearEntityFlags(e:GetEntityFlags())
        e:AddEntityFlags(v[19] & ~(floor | wall))
    end
    if (v[19] & floor) ~= 0 then
        e.DepthOffset = e.DepthOffset - 10000
    end
    if e.Type == 7 then
        assert(native.laser_path(e:GetSprite(), v[20]))
        e:ToLaser().EndPoint = vec(v[21])
    end
    e.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    e.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
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
local floor = assert(modules["state/floor"])(native)
function state.beginFloor(epoch, stage, stageType, animation, same, rewind, rKey, cinematic)
    if not floor.begin(epoch) then
        return
    end
    motion = {}
    actorVisuals = {}
    replicaRoom = nil
    if cinematic == 25 then
        assert(native.rooms_begin_cinematic(), "Native Dogma interlude failed")
        return
    end
    if rewind and #rewind > 0 then
        assert(native.rewind_begin(rewind), "Native hourglass rewind failed")
        return
    end
    if rKey then
        assert(native.r_key_begin(), "Native R Key restart failed")
        return
    end
    Game():GetLevel():SetStage(stage, stageType)
    assert(native.rooms_begin_floor(same and 1 or 0, animation), "Native floor event failed")
end
function state.apply(bytes, tick, ack)
    if floor.waiting() then
        return false
    end
    local value = decode(bytes)
    assert(value[1] == 10 and value[2] == tick, "Invalid state schema")
    local game = Game()
    local level = game:GetLevel()
    if not floor.ready(level, value[14], value[4], value[5]) then
        return false
    end
    -- Register every generated descriptor before room transfer or map caching.
    -- Offscreen red rooms must also have a valid native list/cell index.
    for _, d in ipairs(value[8]) do
        assert(native.room_layout(d[9]))
    end
    assert(native.room_layout(value[11][6]))
    local parts = { pack(">BB", value[6], #value[7]) }
    for _, p in ipairs(value[7]) do
        parts[#parts + 1] = pack(">Bi4i4ff", table.unpack(p))
    end
    assert(native.rooms_sync(table.concat(parts)))
    local positions = native.rooms_positions()
    local localPosition = assert(positions[tostring(value[10])])
    local key = localPosition.dimension .. ":" .. localPosition.index
    local roomChanged = key ~= replicaRoom
    if roomChanged then
        -- Reset before applying actors: room snapshots exclude player entities.
        -- Clearing afterward used to lose the arrival's player motion record.
        motion = {}
        replicaRoom = key
        lastRender = nil
    end
    native.state_clock(value[3])
    assert(native.net_progress(value[13]))
    local now = Isaac.GetTime() / 1000
    for _, actor in ipairs(value[9]) do
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
        applyActorVisuals(p, actor)
        poop.apply(p, actor[7])
    end
    forms.prune(replicas, motion, lastInventory, value[9])
    actorVisuals = value[9]
    local mapChanged = roomChanged
    for _, d in ipairs(value[8]) do
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
    assert(native.rooms_with_player(value[10], function()
        local room = game:GetRoom()
        local data = value[11]
        modules["state/entities"](data[3], {
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
        modules["state/grids"](data[4], {
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
    for _, m in pairs(motion) do
        if m.actor and m.controller == value[10] + 1 then
            m.prediction:confirm(m.target, ack, m.velocity * 60)
        end
    end
    receivedAt, receivedTick = now, tick
    assert(native.rooms_with_player(value[10], function()
        applySound(value[12], tick)
    end))
    assert(native.presentation_events(value[15]))
    itemPresentation.apply(value[10], value[16])
    state.lastTick = tick
    return true
end
local outwardDirections = { Vector(-1, 0), Vector(0, -1), Vector(1, 0), Vector(0, 1) }
local function doorCorridor(room, position)
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door and door:IsOpen() then
            local outward = outwardDirections[slot % 4 + 1]
            local delta = door.Position - position
            local along = delta:Dot(outward)
            local across = math.abs(delta.X * outward.Y - delta.Y * outward.X)
            if along < 64 and along > -24 and across < 16 then
                return slot, outward, along
            end
        end
    end
end
local function clearForPlayer(room, position, aperture)
    local collision = room:GetGridCollisionAtPos(position)
    return collision == GridCollisionClass.COLLISION_NONE
        or collision == GridCollisionClass.COLLISION_WALL_EXCEPT_PLAYER
        or (aperture and collision == GridCollisionClass.COLLISION_WALL)
end
function state.present(input, sequence)
    if receivedTick < 0 then
        return
    end
    -- Native room and Mod presentation updates run after receiving a packet.
    -- Reassert authoritative actor poses at the render boundary so local
    -- callbacks cannot replace a body or start an unrelated dance.
    for _, actor in ipairs(actorVisuals) do
        local p = Isaac.GetPlayer(actor[1])
        if p and p.ControllerIndex == actor[2] then
            applyActorVisuals(p, actor)
        end
    end
    local now = Isaac.GetTime() / 1000
    local dt = lastRender and math.max(0, math.min(now - lastRender, 0.05)) or 0
    lastRender = now
    local status = _IsaacLanStatus()
    paused = status.pause ~= 0
    if paused then
        return
    end
    local values = { unpack(">I2I2I2I2", input) }
    local direction = Vector((values[2] - values[1]) / 65535, (values[4] - values[3]) / 65535)
    assert(native.rooms_with_player(status.slot, function()
        if Game():GetRoom():IsMirrorWorld() then
            direction.X = -direction.X
        end
    end))
    if direction:Length() > 1 then
        direction = direction:Normalized()
    end
    for identifier, m in pairs(motion) do
        local e = ref(identifier)
        if e then
            local age = math.max(0, now - m.at)
            local fraction = math.min(age * 30, 1)
            local position = m.from + (m.target - m.from) * fraction
            if m.actor and m.controller == status.slot + 1 then
                local p = e:ToPlayer()
                local controls = p.ControlsEnabled
                    and p:AreControlsEnabled()
                    and p:IsExtraAnimationFinished()
                if not controls then
                    m.prediction:reset(m.target, sequence - 1)
                    m.doorway = nil
                end
                position = m.prediction:step(
                    controls and direction or Vector(0, 0),
                    sequence,
                    p.MoveSpeed * (4.4117647 * 60),
                    dt
                )
                assert(native.rooms_with_player(status.slot, function()
                    local room = Game():GetRoom()
                    if m.doorway then
                        local door = room:GetDoor(m.doorway.slot)
                        if
                            not door
                            or not door:IsOpen()
                            or direction:Dot(m.doorway.outward) <= 0
                            or now - m.doorway.at > 0.5
                        then
                            m.doorway = nil
                        end
                    end
                    local slot, outward, along = doorCorridor(room, position)
                    local aperture = controls and slot ~= nil
                    if aperture and not m.doorway and direction:Dot(outward) > 0 and along < 18 then
                        m.doorway =
                            { slot = slot, outward = outward, at = now, position = position }
                    end
                    if m.doorway then
                        -- Await the host's room commit at the doorway. Do not
                        -- extrapolate a source-room walk into the destination.
                        position = m.doorway.position
                        m.prediction.velocity = Vector(0, 0)
                    end
                    if not aperture then
                        position = room:GetClampedPosition(position, math.max(5, e.Size))
                    end
                    if not p.CanFly and not clearForPlayer(room, position, aperture) then
                        -- Slide along blocked grids; returning to the older
                        -- authority position on every blocked frame flickers.
                        local x = Vector(position.X, m.display.Y)
                        local y = Vector(m.display.X, position.Y)
                        if clearForPlayer(room, x, aperture) then
                            position = x
                        elseif clearForPlayer(room, y, aperture) then
                            position = y
                        elseif clearForPlayer(room, m.display, aperture) then
                            position = m.display
                        else
                            position = m.target
                        end
                    end
                end))
                m.prediction:clip(position)
                m.display = position
            elseif age > 1 / 30 then
                position = position + m.velocity * math.min(age - 1 / 30, 0.1) * 30
            end
            e.Position = position
        end
    end
end
function state.reset()
    native.sound_reset()
    native.presentation_reset()
    native.rewind_reset()
    hostLoops = {}
    replicaLoops = {}
    lastSound = 0
    nextID = 1
    replicas = {}
    motion = {}
    lastInventory = {}
    costumeIDs = {}
    actorVisuals = {}
    replicaRoom = nil
    receivedTick = -1
    lastRender = nil
    floor.reset()
    captureTick = nil
    captureActors = {}
    captureVisuals = {}
end
