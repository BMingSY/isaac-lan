-- Walk through the native Downpour gate, then join and return in both orders.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local bossRoom, enteredAt, joined, leftGuest, leftHost
local checks = 0
local function report(s)
    Isaac.DebugString("LAN_NETWORK SECRET_EXIT " .. s)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(native.rooms_heads()[tostring(slot)]), Game():GetRoom())
    end, 1))
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
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
    local buttons = 0
    if
        s.prepared
        and native.api_info().ready == 1
        and not s.recovering
        and s.verified >= 180
        and s.verified < 280
        and not host
    then
        actor(1, function(p, room)
            for i = 0, 7 do
                local d = room:GetDoor(i)
                if d and d.TargetRoomType == RoomType.ROOM_SECRET_EXIT then
                    local v = d.Position - p.Position
                    buttons = math.abs(v.X) > math.abs(v.Y) and (v.X > 0 and 8 or 4)
                        or (v.Y > 0 and 2 or 1)
                end
            end
        end)
    end
    native.test_gamepad(buttons)
    if s.prepared and s.verified > 600 and not finished then
        assert(checks >= 30, "Secret-exit arrival and resident joins were not inspected")
        finished = true
        report("PASS native entrance and return door")
    end
    return s
end
local entrance, returnIndex
local function inspect(t, label)
    local room = Game():GetRoom()
    if room:GetType() == RoomType.ROOM_BOSS then
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomType == RoomType.ROOM_SECRET_EXIT then
                entrance = (slot % 4 + 2) % 4
                returnIndex = Game():GetLevel():GetCurrentRoomIndex()
            end
        end
    elseif room:GetType() == RoomType.ROOM_SECRET_EXIT then
        assert(entrance and returnIndex, "Secret exit was not reached through its native gate")
        local door = room:GetDoor(entrance)
        assert(
            door and door.TargetRoomIndex == returnIndex,
            "Secret-exit return door disagrees with arrival direction"
        )
        checks = checks + 1
    end
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if t == 30 then
            local rs = Game():GetLevel():GetRooms()
            for i = 0, rs.Size - 1 do
                local d = rs:Get(i)
                if d.Data.Type == RoomType.ROOM_BOSS then
                    local index = d.SafeGridIndex
                    bossRoom = index
                    for slot = 0, 1 do
                        assert(native.rooms_move(slot, index, 0, -1))
                    end
                    break
                end
            end
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:SetMinDamageCooldown(10000)
                    p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                    p.Position = Vector(200 + slot * 70, 360)
                    p:AddKeys(1)
                end)
            end
        elseif t == 75 then
            actor(0, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Kill()
                    end
                end
            end)
        elseif t == 165 then
            actor(1, function(p, room)
                for i = 0, 7 do
                    local d = room:GetDoor(i)
                    if d and d.TargetRoomType == RoomType.ROOM_SECRET_EXIT then
                        p.Position = d.Position
                            + (room:GetCenterPos() - d.Position):Normalized() * 65
                        p.Velocity = Vector.Zero
                    end
                end
            end)
        end
        local pos = native.rooms_positions()["1"]
        if t >= 200 and pos.index < 0 and not enteredAt then
            enteredAt = t
            actor(1, function(p)
                p.Position = Vector(200, 340)
                p.Velocity = Vector.Zero
            end)
        elseif enteredAt and t >= enteredAt + 60 and not joined then
            joined = true
            assert(native.rooms_move(0, pos.index, pos.dimension, -1))
            actor(0, function(p)
                p.Position = Vector(440, 340)
                p.Velocity = Vector.Zero
            end)
        elseif joined and t >= enteredAt + 90 and not leftGuest then
            leftGuest = true
            assert(native.rooms_move(1, bossRoom, 0, -1))
            actor(1, function(p)
                p.Position = Vector(200, 340)
                p.Velocity = Vector.Zero
            end)
        elseif leftGuest and t >= enteredAt + 120 and not leftHost then
            leftHost = true
            assert(native.rooms_move(0, bossRoom, 0, -1))
            actor(0, function(p)
                p.Position = Vector(440, 340)
                p.Velocity = Vector.Zero
            end)
        end
    end, function(slot, t)
        actor(slot, function()
            inspect(t, "HOST")
        end)
        return collect(slot, t)
    end, function(bytes, t, ack, between, stable)
        local ok = restore(bytes, t, ack, between, stable)
        if ok ~= false then
            actor(1, function()
                inspect(t, "CLIENT")
            end)
        end
        return ok
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
