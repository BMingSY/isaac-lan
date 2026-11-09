-- Native curse doors and Salvation across occupied rooms and repeated exits.
local native, input, config = _IsaacLan, _IsaacLanTestInput, _IsaacLanTest
local frame, gate, host = _IsaacLanFrame, _IsaacLan.net_gate, config.host
local renders, linked, chosen, finished = 0, false, false, false
local step, at, curse, adjacent, walkTarget, health = 0, 0
local checks, snapshots, crossings = 0, 0, 0
local walkDirection = -1
local flatFile, salvation = TrinketType.TRINKET_FLAT_FILE, CollectibleType.COLLECTIBLE_SALVATION
local function report(s)
    Isaac.DebugString("LAN_NETWORK SIDE item-room-effects " .. s)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end))
end
local function clear(p, room)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:IsActiveEnemy(false) or e.Type == EntityType.ENTITY_PICKUP then
            e:Remove()
        end
    end
    room:SetClear(true)
    p.Position, p.Velocity = room:GetCenterPos(), Vector.Zero
end
local function canonical(index)
    local desc = Game():GetLevel():GetRoomByIdx(index, 0)
    return desc and desc.Data and desc.SafeGridIndex or index
end
local function doorTo(room, target)
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door and canonical(door.TargetRoomIndex) == target then
            return door
        end
    end
    error("Missing curse-room connection")
end
local function inspect(slot)
    actor(slot, function(_, room)
        local holders, halos, expected = false, 0, 0
        local owners = {}
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            holders = holders or p:HasTrinket(flatFile)
            if p:HasCollectible(salvation) then
                owners[p.InitSeed], expected = true, expected + 1
            end
        end
        local doors = 0
        for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
            local door = room:GetDoor(i)
            if door and door:IsRoomType(RoomType.ROOM_CURSE) then
                doors = doors + 1
                assert(
                    door.VarData == (holders and 1 or 0),
                    "Curse spikes disagree with present holders"
                )
            end
        end
        assert(doors > 0, "Curse doorway was not exercised")
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if
                e.Type == EntityType.ENTITY_EFFECT
                and e.Variant == EffectVariant.HALO
                and e.SubType == 6
                and e:Exists()
            then
                halos = halos + 1
                assert(
                    e.Parent and owners[e.Parent.InitSeed],
                    "Salvation halo stayed behind without its holder"
                )
                assert(
                    e.Position:Distance(e.Parent.Position) < 10,
                    "Salvation halo detached from its holder"
                )
            end
        end
        assert(halos == expected, "Salvation halo missing or duplicated")
        checks = checks + 1
    end)
end
local function move(slot, target)
    assert(native.rooms_move(slot, target, 0, -1))
end
local function startWalk(target)
    actor(1, function(p, room)
        local door = doorTo(room, target)
        walkDirection = ({ 0, 2, 1, 3 })[door.Direction + 1]
        p.Position = door.Position - (door.Position - room:GetCenterPos()):Normalized() * 25
        p.Velocity = Vector.Zero
        health = p:GetHearts() + p:GetSoulHearts()
    end)
    walkTarget = target
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "1XJTX49A:0:0:0:0:0")
    end
    native.test_gamepad(0)
    if step == 12 and not finished then
        assert(checks >= 18 and (host or snapshots > 100), "Room-effect observations incomplete")
        finished = true
        report("PASS checks=" .. checks .. " crossings=" .. crossings)
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(function()
        local mask = 0
        if not host and walkTarget and walkDirection >= 0 then
            mask = 1 << walkDirection
        end
        local values = {}
        for action = 0, input.actionCount - 1 do
            values[action] = (mask & (1 << action)) ~= 0 and input.maxValue or 0
        end
        return input.encode({ values = values })
    end, function(t, n, bytes)
        before(t, n, bytes)
        if not native.rooms_ready() or t < 30 then
            return
        end
        assert(t < 2500, "Item room effects timed out")
        if step == 0 then
            local rooms = Game():GetLevel():GetRooms()
            for i = 0, rooms.Size - 1 do
                local d = rooms:Get(i)
                if d.Data.Type == RoomType.ROOM_CURSE then
                    curse = d.SafeGridIndex
                end
            end
            assert(curse, "Seed did not generate a curse room")
            move(1, curse)
            step, at = 1, t
        elseif step == 1 and t - at > 40 then
            actor(1, function(p, room)
                clear(p, room)
                for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                    local d = room:GetDoor(i)
                    if d and d.TargetRoomIndex >= 0 then
                        adjacent = canonical(d.TargetRoomIndex)
                        break
                    end
                end
                p:AddTrinket(flatFile)
                p:AddCollectible(salvation)
                p:AddMaxHearts(12)
                p:AddHearts(12)
            end)
            assert(adjacent)
            move(0, adjacent)
            step, at = 2, t
        elseif t - at > 120 then
            if walkTarget then
                assert(
                    native.rooms_positions()["1"].index == walkTarget,
                    "Normal input did not cross curse doorway expected="
                        .. walkTarget
                        .. " actual="
                        .. native.rooms_positions()["1"].index
                )
                actor(1, function(p)
                    local current = p:GetHearts() + p:GetSoulHearts()
                    assert(
                        step == 11 and current < health or step ~= 11 and current == health,
                        "Curse doorway damage disagrees with holder presence"
                    )
                end)
                crossings, walkTarget = crossings + 1, nil
            end
            for slot = 0, 1 do
                inspect(slot)
            end
            report("CHECK step=" .. step .. " tick=" .. t)
            if step == 2 then
                move(0, curse)
            elseif step == 3 then
                startWalk(adjacent)
            elseif step == 4 then
                startWalk(curse)
            elseif step == 5 then
                move(0, adjacent)
            elseif step == 6 then
                startWalk(adjacent)
            elseif step == 7 then
                actor(0, function(p)
                    p:AddTrinket(flatFile)
                end)
                startWalk(curse)
            elseif step == 8 then
                actor(1, function(p)
                    p:TryRemoveTrinket(flatFile)
                end)
            elseif step == 9 then
                actor(0, function(p)
                    p:TryRemoveTrinket(flatFile)
                end)
                actor(1, function(p)
                    p:RemoveCollectible(salvation)
                end)
            elseif step == 10 then
                startWalk(adjacent)
            end
            step, at = step + 1, t
        elseif t - at == 30 and step >= 2 and not walkTarget then
            for slot = 0, 1 do
                actor(slot, clear)
            end
        end
    end, function(slot, t)
        local bytes, stable = collect(slot, t)
        if not bytes then
            return bytes, stable
        end
        return string.pack(">s4", bytes) .. _IsaacLanState.encode({
            step,
            at,
            walkTarget or false,
            crossings,
            walkDirection,
        }),
            stable
    end, function(bytes, t, ack, between, stable)
        local body, offset = string.unpack(">s4", bytes)
        local meta = _IsaacLanState.decode(bytes:sub(offset))
        if restore(body, t, ack, between, stable) == false then
            return false
        end
        step, at, walkTarget, crossings, walkDirection = meta[1], meta[2], meta[3], meta[4], meta[5]
        snapshots = snapshots + 1
        if step >= 2 and t - at > 60 and not walkTarget then
            inspect(1)
        end
        return true
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
