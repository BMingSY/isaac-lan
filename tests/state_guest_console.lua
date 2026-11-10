local native = assert(_IsaacLan)
local f = assert(io.open("./lan-test-role.txt"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt"))
local port = f:read("*l")
f:close()
local frame = _IsaacLanFrame
local renders, playing, linked, chosen = 0, 0, false, false
local done = false
local function report(s)
    Isaac.DebugString("LAN_NETWORK GUEST_CONSOLE " .. s)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if not s.prepared or s.phase ~= 3 or s.verified < 40 then
        return s
    end
    playing = playing + 1
    if playing == 1 then
        assert(_IsaacLanChatSubmit("/c giveitem c1"))
        if not host then
            assert(_IsaacLanChatSubmit("/c giveitem c166"))
            assert(_IsaacLanChatSubmit("/c giveitem t1"))
        end
    end
    if playing == 100 then
        report(
            "give host="
                .. Isaac.GetPlayer(0):GetCollectibleNum(1)
                .. " guest="
                .. Isaac.GetPlayer(1):GetCollectibleNum(1)
        )
        assert(
            Isaac.GetPlayer(0):GetCollectibleNum(1) == 1
                and Isaac.GetPlayer(1):GetCollectibleNum(1) == 1
        )
        assert(Isaac.GetPlayer(1):HasCollectible(166) and Isaac.GetPlayer(1):HasTrinket(1))
        if not host then
            assert(_IsaacLanChatSubmit("/c remove c1"))
            assert(_IsaacLanChatSubmit("/c remove c166"))
            assert(_IsaacLanChatSubmit("/c remove t1"))
        end
    end
    if playing == 200 then
        report(
            "remove host="
                .. Isaac.GetPlayer(0):GetCollectibleNum(1)
                .. " guest="
                .. Isaac.GetPlayer(1):GetCollectibleNum(1)
        )
        if not host then
            for _, m in ipairs(_IsaacLanChatMessages()) do
                report("CHAT " .. m.text)
            end
        end
        assert(
            Isaac.GetPlayer(0):GetCollectibleNum(1) == 1
                and Isaac.GetPlayer(1):GetCollectibleNum(1) == 0
        )
        assert(not Isaac.GetPlayer(1):HasCollectible(166) and not Isaac.GetPlayer(1):HasTrinket(1))
        report("PASS shared room passive, active and trinket removal")
    end
    if playing == 250 and host then
        local rooms = Game():GetLevel():GetRooms()
        for i = 0, rooms.Size - 1 do
            local d = rooms:Get(i)
            if
                d.Data
                and d.Data.Type == RoomType.ROOM_DEFAULT
                and d.SafeGridIndex ~= Game():GetLevel():GetCurrentRoomIndex()
            then
                assert(native.rooms_move(1, d.SafeGridIndex, 0, -1))
                break
            end
        end
    elseif playing == 330 and not host then
        assert(_IsaacLanChatSubmit("/c giveitem c1"))
    elseif playing == 430 then
        assert(
            Isaac.GetPlayer(0):GetCollectibleNum(1) == 1
                and Isaac.GetPlayer(1):GetCollectibleNum(1) == 1
        )
        if not host then
            assert(_IsaacLanChatSubmit("/c remove c1"))
        end
    elseif playing == 530 then
        assert(
            Isaac.GetPlayer(0):GetCollectibleNum(1) == 1
                and Isaac.GetPlayer(1):GetCollectibleNum(1) == 0
        )
        local rooms = native.rooms_positions()
        assert(rooms["0"].index ~= rooms["1"].index, "Split room fixture did not separate players")
        report("PASS split room command targets guest")
        done = true
        report("PASS probe complete")
    end
    return s
end
return {
    done = function()
        return done
    end,
}
