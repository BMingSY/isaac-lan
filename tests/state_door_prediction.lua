local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local json = require("json")
local base, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local home, away, direction, started = nil, nil, 0, false
local lastRoom, arriving
local arrivals, invisibleDistance, fastest = 0, 0, 0
local priorPosition, priorTime
local inward = { Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) }
local buttons = { 4, 1, 8, 2 }
local function log(event, data)
    data = data or {}
    data.event = event
    data.time = Isaac.GetTime()
    data.role = host and "host" or "client"
    Isaac.DebugString("LAN_DOORS " .. json.encode(data))
end
local function actor(slot, fn)
    return native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end, 1)
end
local function clear(room)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:ToNPC() then
            e:Remove()
        end
    end
    room:SetClear(true)
end
local function selected(room, target)
    for slot = 0, 7 do
        local d = room:GetDoor(slot)
        if d and d.TargetRoomIndex >= 0 and d.TargetRoomType == RoomType.ROOM_DEFAULT then
            local dest = Game():GetLevel():GetRoomByIdx(d.TargetRoomIndex, 0).SafeGridIndex
            if not target or dest == target then
                return d, slot, dest
            end
        end
    end
    error("No appropriate doorway")
end
local function place(slot, target)
    actor(slot, function(p, room)
        clear(room)
        local d, index = selected(room, target)
        d:Open()
        p.Position = d.Position + inward[index % 4 + 1] * 40
        p.Velocity = Vector.Zero
    end)
end
local function mask(slot)
    local result = 0
    actor(slot, function(p, room)
        local best, dist
        for i = 0, 7 do
            local d = room:GetDoor(i)
            if d and d:IsOpen() and (not dist or p.Position:Distance(d.Position) < dist) then
                best, dist = i, p.Position:Distance(d.Position)
            end
        end
        assert(best)
        result = buttons[best % 4 + 1]
    end)
    return result
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = base()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    local t = s.verified

    local moving = (not host and (t >= 60 and t < 105 or t >= 210 and t < 255))
        or (host and t >= 390 and t < 435)
    if moving and not started then
        direction = mask(host and 0 or 1)
        started = true
    elseif not moving then
        direction = 0
        started = false
    end
    local input = direction
    if not host and t >= 400 and t < 420 then
        input = 4
    elseif not host and t >= 420 and t < 440 then
        input = 8
    end
    native.test_gamepad(input)
    if s.prepared and t >= 30 then
        actor(host and t >= 350 and 0 or 1, function(p, room)
            local roomID = Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex
            local now = Isaac.GetTime()
            if not host and t < 325 then
                if lastRoom and lastRoom ~= roomID then
                    arrivals = arrivals + 1
                    arriving = { at = now, position = p.Position }
                    priorPosition, priorTime = nil, nil
                    log("arrival", { tick = t, room = roomID, x = p.Position.X, y = p.Position.Y })
                end
                lastRoom = roomID
                if arriving then
                    local age = now - arriving.at
                    if age <= 80 then
                        invisibleDistance =
                            math.max(invisibleDistance, p.Position:Distance(arriving.position))
                    end
                    if age <= 300 and priorTime and now > priorTime then
                        fastest = math.max(
                            fastest,
                            p.Position:Distance(priorPosition) * 1000 / (now - priorTime)
                        )
                    end
                end
                priorPosition, priorTime = p.Position, now
            end
            local pose = not host and _IsaacLanState.actorPose(p)
            local doors = {}
            for i = 0, 7 do
                local d = room:GetDoor(i)
                if d then
                    doors[#doors + 1] =
                        { slot = i, x = d.Position.X, y = d.Position.Y, target = d.TargetRoomIndex }
                end
            end
            log("render", {
                tick = t,
                room = Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex,
                x = p.Position.X,
                y = p.Position.Y,
                vx = p.Velocity.X,
                vy = p.Velocity.Y,
                body = p:GetSprite():GetAnimation(),
                frame = p:GetSprite():GetFrame(),
                cooldown = p.ControlsCooldown,
                controls = p.ControlsEnabled,
                input = input,
                doors = doors,
                ping = s.ping1,
                authority = pose and { x = pose.x, y = pose.y } or false,
            })
        end)
    end
    if t >= 600 and not finished then
        if not host then
            log(
                "arrival_result",
                { arrivals = arrivals, invisibleDistance = invisibleDistance, fastest = fastest }
            )
            assert(arrivals == 2, "Missing new and resident destination coverage")
            assert(invisibleDistance < 1, "Arrival moved during the reveal: " .. invisibleDistance)
            assert(fastest < 340, "Arrival replay accelerated beyond ordinary walking: " .. fastest)
        end
        finished = true
        Isaac.DebugString("LAN_NETWORK PASS feedback observation complete")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, b)
        before(t, n, b)
        if t == 30 then
            Game():GetLevel():RemoveCurses(Game():GetLevel():GetCurses())
            actor(0, function(p, room)
                clear(room)
                home = Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex
                local d, slot, dest = selected(room)
                away = dest
                p.Position = Vector(320, 280)
            end)
            place(1, away)
        elseif t == 175 then
            assert(native.rooms_positions()["1"].index == away, "First door did not finish")
            place(1, home)
        elseif t == 325 then
            assert(native.rooms_positions()["1"].index == home, "Resident door did not finish")
            actor(1, function(p)
                p.Position = Vector(320, 280)
                p.Velocity = Vector.Zero
            end)
        elseif t == 360 then
            place(0, away)
        elseif t == 510 then
            assert(native.rooms_positions()["0"].index == away, "Host door did not finish")
        end
    end, collect, restore, present, beginFloor)
end

return {
    done = function()
        return finished
    end,
}
