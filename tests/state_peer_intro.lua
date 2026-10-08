-- Original Greed intro must render only for occupants of its simulated room.
local native = assert(_IsaacLan)
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local frame = _IsaacLanFrame
local renders, linked, chosen, finished, intros = 0, false, false, false, 0
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = frame()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.prepared and s.verified >= 100 and s.verified <= 240 then
        if native.presentation_active() then
            assert(not host, "Remote Greed intro took over host viewport")
            intros = intros + 1
        end
    end
    if s.verified >= 400 and not finished then
        if not host then
            assert(intros > 5, "Guest native intro did not play")
        end
        finished = true
        report("PASS peer native intro isolation")
    end
    return s
end
local sent, boss = 0, nil
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local level = Game():GetLevel()
    for i = 0, level:GetRooms().Size - 1 do
        local d = level:GetRooms():Get(i)
        if d.Data.Type == RoomType.ROOM_BOSS then
            boss = d.SafeGridIndex
            break
        end
    end
    assert(boss, "Native boss room is missing")
    return gate(capture, function(t, n, b)
        before(t, n, b)
        if t == 30 then
            assert(native.rooms_move(1, 71, 0, -1))
        end
        if t == 80 then
            assert(native.rooms_with_player(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Remove()
                    end
                end
                Game():GetRoom():SetClear(false)
            end))
        end
        if t == 100 then
            assert(native.rooms_move(1, boss, 0, -1))
            report("NATIVE_BOSS_ROOM")
        end
    end, function(slot, t)
        local bytes = collect(slot, t)
        if t >= 110 and t < 150 and slot == 1 then
            local events = native.presentation_events(slot)
            assert(#events > 0, "Native boss did not emit intro event")
            sent = sent + 1
            assert(#native.presentation_events(0) == 0, "Host received remote intro event")
        end
        return bytes
    end, restore, present, beginFloor)
end
