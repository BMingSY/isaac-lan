-- Reuse one host/client pair for crawlspace gathering, remote cache evaluation
-- and Flip's native alternate pedestal, then verify floor cleanup.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, frame = config.host, assert(_IsaacLanFrame)
local fields = assert(_IsaacLanModules["sync/fields"])
local Entity, Sprite, Room = fields.entity, fields.sprite, fields.room
local frames, linked, chosen, done = 0, false, false, false
local controls, start, other, treasure = 0
local cacheChecked, flipSamples, floorFrames = false, 0, 0
local input = native.input_bot
native.input_bot = function()
    return input(1, controls)
end
local function report(text)
    Isaac.DebugString("LAN_FEEDBACK " .. text)
end
local function actor(slot, fn)
    assert(native.api_with_owner(slot, function()
        fn(Isaac.GetPlayer(0), Game():GetRoom(), Game():GetLevel())
    end))
end
local function position(slot, x, y)
    actor(slot, function(p)
        p.Position, p.Velocity = Vector(x, y), Vector.Zero
    end)
end
local function together(index)
    for slot = 0, 1 do
        assert(
            native.rooms_positions()[tostring(slot)].index == index,
            "Wrong gathered destination"
        )
    end
end
local function visibleFlips()
    local count = 0
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type == EntityType.ENTITY_PICKUP and e.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            local visible = native.pickup_flip_visual(e:GetSprite())
            if visible then
                count = count + 1
            end
        end
    end
    return count
end
local gate = native.net_gate
native.net_gate = function(capture, apply, collect, restore, present, stage)
    return gate(
        capture,
        function(t, n, bytes)
            apply(t, n, bytes)
            if not host then
                return
            end
            if t == 30 then
                local level = Game():GetLevel()
                start = level:GetStartingRoomIndex()
                local rooms = level:GetRooms()
                for i = 0, rooms.Size - 1 do
                    local d = rooms:Get(i)
                    if
                        d.Data
                        and d.Data.Type == RoomType.ROOM_DEFAULT
                        and d.SafeGridIndex ~= start
                    then
                        other = other or d.SafeGridIndex
                    elseif d.Data and d.Data.Type == RoomType.ROOM_TREASURE then
                        treasure = d.SafeGridIndex
                    end
                end
                assert(other and treasure)
                position(0, 580, 280) -- Outside the destination crawlspace's right boundary.
                actor(1, function(p, room)
                    local index = room:GetGridIndex(Vector(240, 280))
                    room:RemoveGridEntity(index, 0, false)
                    room:Update()
                    assert(room:SpawnGridEntity(index, GridEntityType.GRID_STAIRS, 0, 123, 0))
                    p.Position, p.Velocity =
                        room:GetGridPosition(index) + Vector(60, 0), Vector.Zero
                end)
            end
            if t == 130 or t == 175 then
                together(GridRooms.ROOM_DUNGEON_IDX)
                actor(0, function(p, room, level)
                    assert(room:GetType() == RoomType.ROOM_DUNGEON and p.Position.X < 400)
                    assert(level.DungeonReturnRoomIndex == start)
                end)
                report("CHECKED crawlspace landing tick=" .. t)
            end
            if t == 180 then
                position(1, 120, 200)
            end
            if t == 275 then
                assert(
                    native.rooms_positions()["1"].index == start,
                    "Ladder returned to the wrong room"
                )
                assert(native.rooms_teleport(0, start, 0))
                report("CHECKED native ladder return")
            end
            if t == 320 then
                position(1, 580, 280)
                assert(native.rooms_teleport(0, GridRooms.ROOM_DUNGEON_IDX, 0))
            end
            if t == 420 then
                together(GridRooms.ROOM_DUNGEON_IDX)
                report("CHECKED resolved crawlspace re-entry with host as entrant")
                for slot = 0, 1 do
                    assert(native.rooms_teleport(slot, start, 0))
                end
            end
            if t == 480 then
                together(start)
                actor(0, function(p, room)
                    -- Remove the previous case's entrance before exercising movement.
                    room:RemoveGridEntity(room:GetGridIndex(Vector(240, 280)), 0, false)
                    room:Update()
                    room:SetClear(false)
                    p:ChangePlayerType(PlayerType.PLAYER_EDEN_B)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_AKELDAMA)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_TRANSCENDENCE)
                    p:SetMinDamageCooldown(10000)
                    local enemy = Isaac.Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        0,
                        Vector(520, 280),
                        Vector.Zero,
                        nil
                    )
                    enemy:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                    enemy.HitPoints = 10000
                end)
                actor(1, function(p)
                    p:ChangePlayerType(PlayerType.PLAYER_THELOST)
                    p:SetMinDamageCooldown(10000)
                end)
            end
            if t == 600 then
                actor(0, function()
                    assert(
                        #Isaac.FindByType(EntityType.ENTITY_TEAR) >= 3,
                        "Akeldama did not produce a chain"
                    )
                end)
                assert(native.rooms_teleport(0, other, 0))
            end
            if t == 650 then
                actor(0, function(p)
                    p:RemoveCollectible(CollectibleType.COLLECTIBLE_TRANSCENDENCE)
                end)
                report("REMOVE flight while Akeldama owner is remote")
            end
            if t == 700 then
                assert(native.rooms_teleport(0, start, 0))
            end
            if t == 730 then
                together(start)
                actor(1, function(p)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_AKELDAMA)
                end)
                report("CHECKED Akeldama owner reunion")
            end
            if t == 770 then
                assert(native.rooms_teleport(1, other, 0))
            end
            if t == 810 then
                assert(native.rooms_teleport(0, other, 0))
            end
            if t == 850 then
                together(other)
                for slot = 0, 1 do
                    actor(slot, function(p)
                        p:RemoveCollectible(CollectibleType.COLLECTIBLE_AKELDAMA)
                    end)
                end
                report("CHECKED both Akeldama owners and cleanup")
            end
            if t == 900 then
                actor(1, function(p)
                    p:ChangePlayerType(PlayerType.PLAYER_LAZARUS_B)
                end)
                assert(native.rooms_teleport(1, treasure, 0))
            end
            if t == 970 or t == 1090 then
                together(treasure)
                actor(1, function()
                    assert(visibleFlips() > 0, "Flip alternate was not generated")
                end)
                report("CHECKED Flip alternate tick=" .. t)
            end
            if t == 1010 then
                actor(1, function(p)
                    p:UseActiveItem(
                        CollectibleType.COLLECTIBLE_FLIP,
                        UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER
                    )
                end)
            end
            if t == 1130 then
                actor(1, function(p)
                    p:ChangePlayerType(PlayerType.PLAYER_ISAAC)
                    p:RemoveCollectible(
                        CollectibleType.COLLECTIBLE_FLIP,
                        true,
                        ActiveSlot.SLOT_POCKET
                    )
                end)
            end
            if t == 1190 then
                actor(1, function()
                    assert(visibleFlips() == 0, "Flip alternate survived removal")
                end)
            end
            if t == 1220 then
                actor(0, function(p)
                    Game():StartStageTransition(false, RoomTransitionAnim.FADE, p)
                end)
            end
        end,
        collect,
        function(bytes, ...)
            local result = restore(bytes, ...)
            if not result or host then
                return result
            end
            local view = _IsaacLanState.decode(bytes)
            local tick = view[2]
            if tick >= 670 and tick < 700 and not cacheChecked then
                assert(native.rooms_with_player(0, function()
                    local p, room = Isaac.GetPlayer(0), Game():GetRoom()
                    assert(room:GetGridWidth() > 0 and room:GetType() == RoomType.ROOM_DEFAULT)
                    -- Exercise the exact cache branch from the reported native stack,
                    -- including an old flying flag before a flight-losing refresh.
                    p.CanFly = true
                    p:AddCacheFlags(CacheFlag.CACHE_FLYING)
                    p:EvaluateItems()
                end, 1))
                cacheChecked = true
                report("CHECKED remote cache evaluation")
            end
            if tick >= 940 and tick < 1200 then
                local expected = {}
                for _, e in ipairs(view[11][Room.entities]) do
                    expected[e[Entity.id]] = e
                end
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if
                        e.Type == EntityType.ENTITY_PICKUP
                        and e.Variant == PickupVariant.PICKUP_COLLECTIBLE
                    then
                        local state = expected[e:GetData().__isaac_lan_replica]
                        if state then
                            local value = state[Entity.compatibility]
                            local visible, alternate = native.pickup_flip_visual(e:GetSprite())
                            assert(visible == (value ~= false), "Replica lost Flip visibility")
                            if visible then
                                assert(alternate:GetFilename() == value[Sprite.path])
                                assert(
                                    native.sprite_state(alternate) == value[Sprite.native],
                                    "Replica Flip sprite differs"
                                )
                                flipSamples = flipSamples + 1
                            end
                        end
                    end
                end
            end
            return result
        end,
        present,
        stage
    )
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    if status.phase == 2 then
        if host then
            _IsaacLanCommand("room_options", "8")
        end
        if not chosen and status.roomOptions == 8 then
            chosen = true
            _IsaacLanCommand("choose", "0:1")
        end
        if host and status.players == 2 and status.ready0 == 1 and status.ready1 == 1 then
            _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
        end
    end
    assert(status.phase ~= 4 and status.phase ~= 9, tostring(status.error))
    controls = 0
    if status.phase == 3 and status.prepared then
        local t, slot = status.verified, host and "0" or "1"
        local at = native.rooms_positions()[slot]
        if not host and t >= 35 and t < 130 and at and at.index >= 0 then
            controls = 1
        elseif not host and t >= 185 and t < 275 and at and at.index < 0 then
            controls = 4
        elseif t >= 480 and t < 850 then
            controls = ({ 1, 4, 2, 8 })[(t // 20) % 4 + 1]
        end
        if
            Game():GetLevel():GetStage() >= 2
            and native.rooms_ready()
            and native.api_info().ready == 1
        then
            floorFrames = floorFrames + 1
        end
        if not done and floorFrames >= 120 then
            assert(host or (cacheChecked and flipSamples > 20), "Missing replica checks")
            done = true
            report("PASS regression probes")
        end
    end
    return status
end
