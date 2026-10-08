-- Real held input, continuous motion and door arrivals in an isolated native game.
local native = assert(_IsaacLan)
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(s)
    Isaac.DebugString("LAN_NETWORK " .. s)
end
local baseFrame = _IsaacLanFrame
local renders, linked, chosen, done = 0, false, false, false
local origin, exitSlot
local authority, ack, roomIndex = Vector(0, 0), -1, -1
local velocity, buttons = Vector(0, 0), 0
local out = assert(io.open("./lan-test-digest-local-movement.csv", "w"))
out:write("time,tick,ack,room,buttons,x,y,authority_x,authority_y,vx,vy\n")
local entered, entryPosition, minimumDoorDistance = false, nil, math.huge
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = baseFrame()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    buttons = 0
    if not host and s.prepared then
        local t = s.verified
        if t >= 50 and t < 80 then
            buttons = 8
        elseif t >= 100 and t < 130 then
            buttons = 4
        elseif t >= 160 and t < 170 then
            buttons = 2
        elseif t >= 180 and t < 190 then
            buttons = 1
        elseif t >= 230 and not entered then
            native.rooms_with_player(1, function()
                local room = Game():GetRoom()
                for slot = 0, 7 do
                    local door = room:GetDoor(slot)
                    if door and door:IsOpen() then
                        exitSlot = slot
                        break
                    end
                end
            end)
            assert(exitSlot)
            buttons = ({ 4, 1, 8, 2 })[exitSlot % 4 + 1]
        end
    end
    native.test_gamepad(buttons)
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.verified >= 350 and not done then
        done = true
        if not host then
            assert(entered, "Physical input never crossed the open door")
            assert(minimumDoorDistance < 19, "Local actor was clipped before the open doorway")
        end
        out:flush()
        report("PASS local movement and door arrival")
    end
    return s
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    origin = Game():GetLevel():GetCurrentRoomIndex()
    return gate(capture, function(t, n, b)
        before(t, n, b)
        if t == 0 then
            for i = 0, 1 do
                local p = Isaac.GetPlayer(i)
                p.Position, p.Velocity = Vector(300, 210 + i * 70), Vector(0, 0)
                p:SetMinDamageCooldown(10000)
            end
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type ~= 1 then
                    e:Remove()
                end
            end
            Game():GetRoom():SetClear(true)
        end
        if t == 220 then
            native.rooms_with_player(1, function()
                local room = Game():GetRoom()
                for slot = 0, 7 do
                    local door = room:GetDoor(slot)
                    if door and door:IsOpen() then
                        local inward = (
                            { Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) }
                        )[slot % 4 + 1]
                        local p = Isaac.GetPlayer(native.rooms_heads()["1"])
                        p.Position, p.Velocity = door.Position + inward * 70, Vector(0, 0)
                        break
                    end
                end
            end)
        end
    end, function(slot, t)
        local bytes = collect(slot, t)
        local v = _IsaacLanState.decode(bytes)
        local actor = v[9][2][3]
        authority, velocity = Vector(table.unpack(actor[6])), Vector(table.unpack(actor[7]))
        roomIndex = native.rooms_positions()["1"].index
        return bytes
    end, function(bytes, t, sequence)
        if restore(bytes, t, sequence) == false then
            return false
        end
        local v = _IsaacLanState.decode(bytes)
        local actor = v[9][2][3]
        authority, velocity = Vector(table.unpack(actor[6])), Vector(table.unpack(actor[7]))
        roomIndex, ack = native.rooms_positions()["1"].index, sequence
        if roomIndex ~= origin and not entered then
            assert(t >= 230, "Movement fixture entered a door before its crossing phase")
            entered = true
            entryPosition = authority
            report("ARRIVED room=" .. roomIndex)
        end
    end, present, beginFloor)
end
Isaac.AddCallback({ Name = "Local movement observer" }, ModCallbacks.MC_POST_RENDER, function()
    local s = _IsaacLanStatus()
    if not s.prepared or not native.rooms_ready() then
        return
    end
    local p = Isaac.GetPlayer(native.rooms_heads()["1"])
    if not host and s.verified >= 230 and roomIndex == origin and exitSlot then
        -- MC_POST_RENDER already runs in the local room's render scope.
        -- Nested rooms_with_player is deliberately rejected by the native API.
        minimumDoorDistance = math.min(
            minimumDoorDistance,
            p.Position:Distance(Game():GetRoom():GetDoor(exitSlot).Position)
        )
    elseif not host and entryPosition then
        assert(p.Position:Distance(entryPosition) < 25, "Old-room movement ran past the arrival")
    end
    out:write(
        string.format(
            "%.3f,%d,%d,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
            Isaac.GetTime() / 1000,
            s.verified,
            ack,
            roomIndex,
            buttons,
            p.Position.X,
            p.Position.Y,
            authority.X,
            authority.Y,
            velocity.X,
            velocity.Y
        )
    )
end)
