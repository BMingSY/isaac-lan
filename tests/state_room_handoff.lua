-- Repeated ordinary door walks; only setup positions bypass normal input.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, slot = config.host, config.host and 0 or 1
local json = require("json")
local state = assert(_IsaacLanState)
local frame, gate = _IsaacLanFrame, native.net_gate
local linked, chosen, started, finished = false, false, false, false
local began = Isaac.GetTime()
local home, away, activeCase, direction
local firstSetup, spacing, walkAfter, walkUntil = 60, 90, 30, 75
local guestCases, totalCases = 6, 8
local invisibleDistance, fastest = 0, 0
local inward = { Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) }
local buttons = { 4, 1, 8, 2 }
local trace, applyStart, syncStart, syncCost, switchCount = nil, nil, nil, nil, 0
local function log(event, data)
    data = data or {}
    data.event, data.time, data.role = event, Isaac.GetTime(), host and "host" or "client"
    Isaac.DebugString("LAN_HANDOFF " .. json.encode(data))
end
local function upvalue(fn, key)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if name == key then
            return value
        elseif not name then
            break
        end
    end
    error("Missing observation point: " .. key)
end
local doors = upvalue(state.render, "doorPresentation")
local beginDoor, arriveDoor, drawDoor = doors.begin, doors.arrive, doors.render
doors.begin = function()
    if not trace and not host then
        trace = { case = activeCase, begin = Isaac.GetTime() }
    end
    return beginDoor()
end
doors.arrive = function()
    if trace and not trace.arrive then
        trace.arrive = Isaac.GetTime()
        trace.wait = applyStart and applyStart - trace.begin or 0
        trace.native = syncCost or 0
        trace.applyBegin = applyStart
    end
    return arriveDoor()
end
doors.render = function()
    drawDoor()
    if not trace then
        return
    end
    local now, alpha = Isaac.GetTime(), doors.alpha()
    if alpha >= 0.999 then
        trace.black = trace.black or now
    end
    if trace.arrive then
        local player = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
        local position = player.Position
        if not trace.entry then
            trace.entry = { x = position.X, y = position.Y }
        end
        if doors.movementBlocked() then
            invisibleDistance =
                math.max(invisibleDistance, position:Distance(Vector(trace.entry.x, trace.entry.y)))
        end
        if trace.previous and now > trace.previous.time then
            fastest = math.max(
                fastest,
                position:Distance(Vector(trace.previous.x, trace.previous.y))
                    * 1000
                    / (now - trace.previous.time)
            )
        end
        trace.previous = { x = position.X, y = position.Y, time = now }
        trace.draw = trace.draw or now
        if alpha < 0.999 and trace.black and not trace.reveal then
            trace.reveal = now
        end
        if not doors.movementBlocked() then
            trace.ready = trace.ready or now
        end
        if alpha <= 0 and trace.ready then
            trace.total_ms = now - trace.begin
            trace.ready_ms = trace.ready - trace.begin
            trace.hold_ms = trace.ready - trace.draw
            trace.wait_ms = trace.wait
            trace.native_ms = trace.native
            trace.apply_ms = trace.applyEnd - trace.applyBegin
            trace.draw_wait_ms = trace.draw - trace.applyEnd
            trace.reveal_ms = now - trace.draw
            trace.black_ms = trace.black and (trace.reveal or now) - trace.black or 0
            log("result", trace)
            trace = nil
        end
    end
end
local apply, sync = state.apply, native.rooms_sync
state.apply = function(...)
    applyStart, syncCost = Isaac.GetTime(), nil
    local accepted = apply(...)
    if trace and trace.arrive and not trace.applyEnd then
        trace.applyEnd = Isaac.GetTime()
    end
    return accepted
end
native.rooms_sync = function(...)
    syncStart = Isaac.GetTime()
    local result = sync(...)
    syncCost = Isaac.GetTime() - syncStart
    return result
end
local function actor(seat, fn)
    assert(native.rooms_with_player(seat, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(seat)])), Game():GetRoom())
    end, 1))
end
local function selected(room, target)
    for index = 0, 7 do
        local door = room:GetDoor(index)
        if door and door.TargetRoomIndex >= 0 and door.TargetRoomType == RoomType.ROOM_DEFAULT then
            local dest = Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex, 0).SafeGridIndex
            if not target or dest == target then
                return door, index, dest
            end
        end
    end
    error("Missing ordinary doorway")
end
local function target(index)
    return index % 2 == 1 and away or home
end
local function owner(index)
    return index <= guestCases and 1 or 0
end
local priorRoom
function _IsaacLanFrame()
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if not linked and Isaac.GetTime() - began > 15000 then
        linked = true
        Isaac.DebugString("LAN_NETWORK MENU_READY")
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
    end
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and not started
        and s.phase == 2
        and s.players == 2
        and s.ready0 == 1
        and s.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    local held = 0
    if s.prepared and s.verified >= firstSetup then
        local t = s.verified
        local index = math.floor((t - firstSetup) / spacing) + 1
        local elapsed = (t - firstSetup) % spacing
        if index ~= activeCase then
            activeCase, direction = index, nil
        end
        if
            index <= totalCases
            and owner(index) == slot
            and elapsed >= walkAfter
            and elapsed < walkUntil
        then
            if not direction then
                actor(slot, function(player, room)
                    local nearest, distance
                    for doorSlot = 0, 7 do
                        local door = room:GetDoor(doorSlot)
                        if door and door:IsOpen() then
                            local d = player.Position:Distance(door.Position)
                            if not distance or d < distance then
                                nearest, distance = doorSlot, d
                            end
                        end
                    end
                    assert(nearest)
                    direction = buttons[nearest % 4 + 1]
                end)
                log("walk", { case = index, tick = t, ping = s.ping1 })
            end
            held = direction
        end
        local current = native.rooms_positions()[tostring(slot)]
        if current then
            if priorRoom and current.index ~= priorRoom then
                switchCount = switchCount + 1
                log("switch", { case = index, tick = t, room = current.index })
            end
            priorRoom = current.index
        end
        if index > totalCases and not finished then
            assert(
                switchCount == (host and totalCases - guestCases or guestCases),
                "Missing ordinary door arrivals"
            )
            assert(not trace, "Door reveal did not complete")
            assert(invisibleDistance < 1, "Arrival moved before visibility")
            assert(fastest < 340, "Arrival replay accelerated beyond ordinary walking")
            log("motion", { invisible_distance = invisibleDistance, fastest = fastest })
            finished = true
            Isaac.DebugString("LAN_NETWORK HANDOFF PASS ordinary door walks and reveal completion")
        end
    end
    native.test_gamepad(held)
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if not host or not native.rooms_ready() then
            return
        end
        if t == 30 then
            Game():GetLevel():RemoveCurses(Game():GetLevel():GetCurses())
            actor(0, function(player, room)
                home = Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex
                local _, _, dest = selected(room)
                away = dest
                player.Position = room:GetCenterPos()
            end)
        end
        for seat = 0, 1 do
            actor(seat, function(_, room)
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity:ToNPC() then
                        entity:Remove()
                    end
                end
                room:SetClear(true)
            end)
        end
        local index = math.floor((t - firstSetup) / spacing) + 1
        if index >= 1 and index <= totalCases then
            local elapsed = (t - firstSetup) % spacing
            if elapsed == 0 then
                actor(owner(index), function(player, room)
                    local door, doorSlot = selected(room, target(index))
                    door:Open()
                    player.Position = door.Position + inward[doorSlot % 4 + 1] * 40
                    player.Velocity = Vector.Zero
                end)
            elseif elapsed == spacing - 5 then
                assert(
                    native.rooms_positions()[tostring(owner(index))].index == target(index),
                    "Door walk failed"
                )
            end
        end
    end, collect, restore, present, beginFloor)
end
