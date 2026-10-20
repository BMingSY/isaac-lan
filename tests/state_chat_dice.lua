-- One owned native pair: dice rendering, room delivery, split and reunion.
local native = assert(_IsaacLan)
local config = assert(_IsaacLanTest)
local host, port = config.host, config.port
local frame = _IsaacLanFrame
local frames, playing, linked, chosen, done = 0, 0, false, false, false
local origin
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local function has(prefix)
    for _, message in ipairs(_IsaacLanChatMessages()) do
        if not message.command and message.text:sub(1, #prefix) == prefix then
            return message
        end
    end
end
local function result(prefix)
    local message = assert(has(prefix), "Missing result: " .. prefix)
    assert(message.bubble)
    report("CHAT_DICE result=" .. message.text)
    return message.text
end
local function split()
    local positions = native.rooms_positions()
    origin = assert(positions["0"]).index
    local rooms = Game():GetLevel():GetRooms()
    for index = 0, rooms.Size - 1 do
        local room = rooms:Get(index)
        if
            room.Data
            and room.SafeGridIndex ~= origin
            and room.Data.Type == RoomType.ROOM_DEFAULT
        then
            assert(native.rooms_move(1, room.SafeGridIndex, 0, -1))
            return
        end
    end
    error("No destination for room delivery check")
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
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
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if status.phase == 4 or status.phase == 9 then
        report("FAILED " .. status.error)
    end
    if done or not status.prepared or status.phase ~= 3 or status.verified < 40 then
        return status
    end
    playing = playing + 1
    for index = 0, Game():GetNumPlayers() - 1 do
        Isaac.GetPlayer(index):SetMinDamageCooldown(10000)
    end
    if playing == 30 then
        native.chat_ui_open(true)
    elseif playing == 60 and not host then
        assert(_IsaacLanChatSubmit("/2d6"))
    elseif playing == 150 then
        local text = result("2P 掷骰：2D6 = ")
        local first, second, total = text:match("%[(%d+) %+ (%d+)%] = (%d+)$")
        first, second, total = tonumber(first), tonumber(second), tonumber(total)
        assert(first and first >= 1 and first <= 6 and second >= 1 and second <= 6)
        assert(total == first + second)
    elseif playing == 180 and not host then
        assert(_IsaacLanChatSubmit("/1d6+2d3"))
    elseif playing == 270 then
        local text = result("2P 掷骰：D6 + 2D3 = ")
        local first, second, third, total = text:match("= (%d+) %+ %[(%d+) %+ (%d+)%] = (%d+)$")
        first, second, third, total =
            tonumber(first), tonumber(second), tonumber(third), tonumber(total)
        assert(first and first >= 1 and first <= 6)
        assert(second >= 1 and second <= 3 and third >= 1 and third <= 3)
        assert(total == first + second + third)
    elseif playing == 300 and not host then
        assert(_IsaacLanChatSubmit("/d100b2"))
    elseif playing == 390 then
        local text = result("2P 掷骰：D100b2 = ")
        local first, second, third, selected = text:match("%[(%d+), (%d+), (%d+)%] → (%d+)$")
        first, second, third, selected =
            tonumber(first), tonumber(second), tonumber(third), tonumber(selected)
        assert(first and first % 10 == second % 10 and second % 10 == third % 10)
        assert(selected >= 1 and selected <= 100 and selected == math.min(first, second, third))
    elseif playing == 420 and host then
        assert(_IsaacLanChatSubmit("/d100p"))
    elseif playing == 510 then
        local text = result("1P 掷骰：D100p = ")
        local first, second, selected = text:match("%[(%d+), (%d+)%] → (%d+)$")
        first, second, selected = tonumber(first), tonumber(second), tonumber(selected)
        assert(first and first % 10 == second % 10)
        assert(selected >= 1 and selected <= 100 and selected == math.max(first, second))
    elseif playing == 540 and not host then
        assert(_IsaacLanChatSubmit("同房消息 --room"))
    elseif playing == 630 then
        result("【房间】同房消息")
    elseif playing == 660 and host then
        split()
    elseif playing == 840 then
        local positions = native.rooms_positions()
        assert(positions["0"].index ~= positions["1"].index, "Players did not split")
        assert(_IsaacLanChatSubmit(host and "房主分房消息 --room" or "/d6 --room"))
        assert(_IsaacLanChatSubmit(host and "全队对照房主" or "全队对照客机"))
    elseif playing == 960 then
        assert(has("全队对照房主") and has("全队对照客机"))
        if host then
            result("【房间】房主分房消息")
            assert(not has("【房间】2P 掷骰：D6 = "), "Host received another room's roll")
        else
            result("【房间】2P 掷骰：D6 = ")
            assert(not has("【房间】房主分房消息"), "Guest received another room's text")
        end
    elseif playing == 1020 and host then
        assert(native.rooms_move(1, origin, 0, -1))
    elseif playing == 1200 then
        local positions = native.rooms_positions()
        assert(positions["0"].index == positions["1"].index, "Players did not reunite")
        if not host then
            assert(_IsaacLanChatSubmit("/2d3 --room"))
        end
    elseif playing == 1320 then
        result("【房间】2P 掷骰：2D3 = ")
        done = true
        report("PASS chat dice and room scope")
    end
    return status
end
