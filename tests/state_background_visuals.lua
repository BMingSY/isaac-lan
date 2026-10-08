local native = assert(_IsaacLan)
local owner = { Name = "Isolated local HUD and room animation regression" }
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(s)
    Isaac.DebugString("LAN_NETWORK " .. s)
end
local frames, joined, chosen, done, tick = 0, false, false, false, -1
local ready = false
local original = _IsaacLanFrame
function _IsaacLanFrame()
    frames = frames + 1
    if not joined and frames >= (host and 300 or 600) then
        joined = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = original()
    tick = s.verified
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.verified >= 850 and not done then
        done = true
        report("PASS background room color isolation")
    end
    return s
end
local gate = native.net_gate
local origin, destinations = nil, {}
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        function()
            return string.rep("\0", 34)
        end,
        function(t, n, b)
            before(t, n, b)
            for i = 0, Game():GetNumPlayers() - 1 do
                local p = Isaac.GetPlayer(i)
                p:SetMinDamageCooldown(60)
                p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
            end
            if t == 10 then
                origin = Game():GetLevel():GetCurrentRoomIndex()
                local rooms = Game():GetLevel():GetRooms()
                for i = 0, rooms.Size - 1 do
                    local d = rooms:Get(i)
                    if
                        d.SafeGridIndex ~= origin
                        and (
                            d.Data.Type == RoomType.ROOM_DEFAULT
                            or d.Data.Type == RoomType.ROOM_TREASURE
                            or d.Data.Type == RoomType.ROOM_SHOP
                        )
                    then
                        destinations[#destinations + 1] = d.SafeGridIndex
                    end
                end
            end
            if t >= 100 and t <= 750 and t % 45 == 10 then
                assert(native.rooms_move(1, destinations[(t // 45) % #destinations + 1], 0, 0))
                report("BACKGROUND transfer tick=" .. t)
            end
            if t == 90 then
                report("VISUAL_READY")
            end
        end,
        collect,
        function(bytes, t, ack)
            if restore(bytes, t, ack) == false then
                return false
            end
            if t >= 90 and not ready then
                ready = true
                report("VISUAL_READY")
            end
        end,
        present,
        beginFloor
    )
end
