-- Moving Box views, occupied crawlspace reentry and X-ray combat doors.
local native, config = _IsaacLan, _IsaacLanTest
local input = _IsaacLanTestInput
local fields = _IsaacLanModules["sync/fields"]
local schema = _IsaacLanModules["sync/world_schema"]
local host, frame, gate = config.host, _IsaacLanFrame, native.net_gate
local chosen, linked, finished = false, false, false
local renders = 0
local origin, other, large, secret, adjacent, stairs
local fullSamples, emptySamples = 0, 0
local function report(text)
    Isaac.DebugString("LAN_NETWORK FEEDBACK_NOVEMBER " .. text)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end))
end
local function move(slot, index)
    assert(native.rooms_move(slot, index, 0, -1))
end
local function clear(room)
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) or entity.Type == EntityType.ENTITY_PICKUP then
            entity:Remove()
        end
    end
    room:SetClear(true)
end
local function box(p)
    local bytes = assert(native.items_active_data(p:GetSprite()))
    assert(#bytes == 33, "Incomplete active item view")
    return bytes:byte(33) == 1
end
local function useBox(p)
    p:SetActiveCharge(4)
    p:UseActiveItem(CollectibleType.COLLECTIBLE_MOVING_BOX, UseFlag.USE_NOANIM)
end
_IsaacLanFrame = function()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and tostring(config.port) or ("127.0.0.1:" .. config.port)
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    native.test_gamepad(0)
    return status
end
local function advance(t)
    if not native.rooms_ready() then
        return
    end
    if t == 30 then
        local level = Game():GetLevel()
        origin = level:GetStartingRoomIndex()
        level:RemoveCurses(level:GetCurses())
        for i = 0, level:GetRooms().Size - 1 do
            local d = level:GetRooms():Get(i)
            if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= origin then
                other = other or d.SafeGridIndex
                if d.Data.Shape >= RoomShape.ROOMSHAPE_1x2 then
                    large = large or d.SafeGridIndex
                end
            elseif d.Data and d.Data.Type == RoomType.ROOM_SECRET then
                secret = d.SafeGridIndex
            end
        end
        assert(other and large and secret, "Seed lacks fixture rooms")
        actor(1, function(p, room)
            clear(room)
            p:AddCollectible(CollectibleType.COLLECTIBLE_MOVING_BOX, 4, false)
            for i = 1, 4 do
                Isaac.Spawn(
                    EntityType.ENTITY_PICKUP,
                    PickupVariant.PICKUP_COIN,
                    CoinSubType.COIN_PENNY,
                    room:GetCenterPos() + Vector(i * 25, 50),
                    Vector.Zero,
                    nil
                )
            end
        end)
        for slot = 0, 1 do
            actor(slot, function(p, room)
                p:SetMinDamageCooldown(10000)
                p.Position, p.Velocity =
                    room:GetClampedPosition(room:GetTopLeftPos() + Vector(80, 80), 30), Vector.Zero
            end)
        end
    elseif t == 90 then
        actor(1, useBox)
    elseif t == 150 then
        actor(1, function(p)
            assert(box(p), "Native box did not store pickups")
        end)
        move(1, other)
    elseif t == 230 then
        actor(1, function(p, room)
            clear(room)
            assert(box(p), "Cross-room box lost contents")
            useBox(p)
        end)
    elseif t == 290 then
        actor(1, function(p)
            assert(not box(p), "Box did not empty")
            local coins = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, -1)
            assert(#coins == 4, "Box contents were lost or duplicated")
        end)
        report("PASS box store transfer unpack")
        move(0, large)
        move(1, large)
    elseif t == 360 then
        actor(1, function(p, room)
            clear(room)
            local pos = room:GetClampedPosition(room:GetBottomRightPos() - Vector(100, 100), 20)
            local index = room:GetGridIndex(pos)
            room:RemoveGridEntity(index, 0, false)
            room:Update()
            assert(room:SpawnGridEntity(index, GridEntityType.GRID_STAIRS, 0, 123, 0))
            stairs = room:GetGridPosition(index)
            assert(stairs.X > 400, "Staircase does not exercise out-of-crawlspace coordinates")
            p.Position, p.Velocity = stairs + Vector(60, 0), Vector.Zero
        end)
    elseif t == 490 or t == 680 or t == 860 then
        -- The default room rule leaves the other player upstairs. The next
        -- staircase crossing must join the already initialized crawlspace.
        for slot = t == 490 and 1 or 0, 1 do
            assert(
                native.rooms_positions()[tostring(slot)].index == GridRooms.ROOM_DUNGEON_IDX,
                "Crawlspace entry failed: slot="
                    .. slot
                    .. " room="
                    .. native.rooms_positions()[tostring(slot)].index
            )
            actor(slot, function(p, room)
                assert(
                    room:GetType() == RoomType.ROOM_DUNGEON and p.Position.X < 400,
                    "Resident entry retained source coordinates"
                )
                p.Position, p.Velocity = Vector(240, 160), Vector.Zero
            end)
        end
        report("PASS crawlspace arrival tick=" .. t)
        if t == 490 then
            assert(native.rooms_positions()["0"].index == large)
        elseif t < 860 then
            move(0, large)
        else
            move(0, origin)
            move(1, secret)
        end
    elseif t == 540 or t == 730 then
        actor(0, function(p)
            p.Position, p.Velocity = stairs + Vector(60, 0), Vector.Zero
        end)
    elseif t == 930 then
        actor(1, function(_, room)
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door.TargetRoomType == RoomType.ROOM_DEFAULT then
                    adjacent = adjacent or door.TargetRoomIndex
                end
            end
        end)
        assert(adjacent)
        move(0, adjacent)
        move(1, origin)
    elseif t == 1000 then
        actor(0, function(p, room)
            clear(room)
            Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, room:GetCenterPos(), Vector.Zero, nil)
            room:SetClear(false)
            p.Position = room:GetTopLeftPos() + Vector(60, 60)
        end)
        actor(1, function(p)
            p:AddCollectible(CollectibleType.COLLECTIBLE_XRAY_VISION)
        end)
        move(1, adjacent)
    elseif t == 1100 then
        actor(1, function(_, room)
            local found = false
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door.TargetRoomIndex == secret then
                    assert(door:IsOpen(), "X-ray secret entrance was sealed after resident entry")
                    found = true
                end
            end
            assert(found)
        end)
        report("PASS X-ray occupied combat entrance")
    elseif t == 1200 then
        finished = true
        report("PASS authority")
    end
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local function captureInput()
        local t = _IsaacLanStatus().verified
        local at = native.rooms_positions()[host and "0" or "1"]
        local walking = not host and t >= 370 and t < 460
            or host and ((t >= 550 and t < 650) or (t >= 740 and t < 830))
        return input.buttons(
            walking and at and at.index >= 0 and (1 << ButtonAction.ACTION_LEFT) or 0,
            0
        )
    end
    return gate(
        captureInput,
        function(t, n, bytes)
            before(t, n, bytes)
            advance(t)
        end,
        collect,
        function(bytes, t, ack, between, stable)
            local result = restore(bytes, t, ack, between, stable)
            if result == false then
                return false
            end
            local view = schema.unpack(_IsaacLanState.decode(bytes, stable), t)
            for _, value in ipairs(view.actors) do
                local inv = value[fields.actor.inventory]
                local expected = inv[fields.inventory.activeData]
                local p = Isaac.GetPlayer(value[fields.actor.index])
                assert(
                    native.items_active_data(p:GetSprite()) == expected,
                    "Replica active/HUD state differs"
                )
                if expected:byte(33) == 1 then
                    fullSamples = fullSamples + 1
                else
                    emptySamples = emptySamples + 1
                end
            end
            if t >= 1200 and not finished then
                assert(fullSamples > 10 and emptySamples > 10, "Missing box state observations")
                finished = true
                report("PASS replica box states and room arrivals")
            end
            return result
        end,
        present,
        beginFloor
    )
end
return {
    done = function()
        return finished
    end,
}
