-- One protected pair exercises chat requests, native entries and floor cleanup.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, frame = config.host, _IsaacLanFrame
local frames, linked, chosen, done = 0, false, false, false
local current, caseNumber, finished, seen = nil, 0, {}, 0
local function report(text)
    Isaac.DebugString("LAN_TP " .. text)
end
local function actor(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
local function roomOf(slot)
    return assert(native.rooms_positions()[tostring(slot)])
end
local function existing(kind)
    local level = Game():GetLevel()
    if kind == RoomType.ROOM_ERROR then
        local desc = level:GetRoomByIdx(GridRooms.ROOM_ERROR_IDX, 0)
        return desc.Data and desc or nil
    end
    if kind == RoomType.ROOM_ANGEL or kind == RoomType.ROOM_DEVIL then
        local desc = level:GetRoomByIdx(GridRooms.ROOM_DEVIL_IDX, 0)
        return desc.Data and desc.Data.Type == kind and desc or nil
    end
    local rooms = level:GetRooms()
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if
            desc.Data
            and desc.Data.Type == kind
            and desc.SafeGridIndex ~= level:GetStartingRoomIndex()
        then
            return desc
        end
    end
end
local function coordinate(index)
    local start = Game():GetLevel():GetStartingRoomIndex()
    return string.format("/tp r %d %d", index % 13 - start % 13, start // 13 - index // 13)
end
local function destination(command, kind)
    return function()
        local desc = assert(existing(kind), "Missing generated room for " .. command)
        return command, desc.SafeGridIndex
    end
end
local function start()
    return "/tp r 0 0", Game():GetLevel():GetStartingRoomIndex()
end
local cases = {
    {
        name = "list",
        text = "普通房",
        setup = function()
            return "/tp l", roomOf(1).index
        end,
    },
    {
        name = "empty-cell",
        text = "没有已生成",
        setup = function()
            return "/tp r 12 12", roomOf(1).index
        end,
    },
    {
        name = "coordinates",
        setup = function()
            local desc = assert(existing(RoomType.ROOM_DEFAULT))
            return coordinate(desc.SafeGridIndex), desc.SafeGridIndex
        end,
    },
    { name = "return-start", setup = start },
    { name = "ultra-secret", setup = destination("/tp us", RoomType.ROOM_ULTRASECRET) },
    { name = "return-hidden", setup = start },
    { name = "shop", setup = destination("/tp sh", RoomType.ROOM_SHOP) },
    {
        name = "host-to-guest",
        owner = 0,
        near = true,
        setup = function()
            return "/tp 2p", roomOf(1).index
        end,
    },
    {
        name = "same-room-player",
        near = true,
        setup = function()
            native.api_with_owner(0, function()
                local room = Game():GetRoom()
                Isaac.GetPlayer(0).Position =
                    room:FindFreePickupSpawnPosition(room:GetCenterPos() - Vector(100, 0), 0, true)
            end)
            native.api_with_owner(1, function()
                local room = Game():GetRoom()
                Isaac.GetPlayer(0).Position =
                    room:FindFreePickupSpawnPosition(room:GetCenterPos() + Vector(100, 0), 0, true)
            end)
            return "/tp 1p", roomOf(0).index
        end,
    },
    { name = "split-again", setup = start },
    {
        name = "uninitialized-angel",
        text = "尚未生成天使房",
        setup = function()
            assert(not existing(RoomType.ROOM_ANGEL) and not existing(RoomType.ROOM_DEVIL))
            return "/tp a", roomOf(1).index
        end,
    },
    {
        name = "generated-angel",
        setup = function()
            native.api_with_owner(0, function()
                Game():GetLevel():InitializeDevilAngelRoom(true, false)
            end)
            return destination("/tp a", RoomType.ROOM_ANGEL)()
        end,
    },
    {
        name = "preserve-angel",
        text = "尚未生成恶魔房",
        setup = function()
            assert(existing(RoomType.ROOM_ANGEL))
            return "/tp d", roomOf(1).index
        end,
    },
    { name = "error-room", setup = destination("/tp e", RoomType.ROOM_ERROR) },
    { name = "return-error", setup = start },
    {
        name = "generated-red",
        setup = function()
            local red
            native.api_with_owner(0, function()
                local level, room = Game():GetLevel(), Game():GetRoom()
                local before = {}
                for index = 0, 168 do
                    before[index] = level:GetRoomByIdx(index, 0).Data ~= nil
                end
                for slot = 0, 7 do
                    if level:MakeRedRoomDoor(roomOf(0).index, slot) then
                        local door = room:GetDoor(slot)
                        local index = door and door.TargetRoomIndex
                        if index and index >= 0 and not before[index] then
                            assert(level:GetRoomByIdx(index, 0).Data)
                            red = index
                            return
                        end
                    end
                end
            end)
            assert(red, "No new red room was created by the fixture")
            return coordinate(red), red
        end,
    },
    {
        name = "maze-exact-target",
        setup = function()
            Game():GetLevel():AddCurse(LevelCurse.CURSE_OF_MAZE, false)
            return start()
        end,
    },
    {
        name = "maze-coordinates",
        setup = function()
            local desc = assert(existing(RoomType.ROOM_DEFAULT))
            return coordinate(desc.SafeGridIndex), desc.SafeGridIndex
        end,
    },
    {
        name = "maze-reunion",
        near = true,
        setup = function()
            return "/tp 1p", roomOf(0).index
        end,
    },
}
local function sendCase(number)
    local case = cases[number]
    local command, index = case.setup()
    local owner = case.owner or 1
    local other = roomOf(1 - owner)
    _IsaacLanChatOutput(
        string.format(
            "TP_CASE %d %d %d %d %d |%s",
            number,
            owner,
            index,
            other.index,
            other.dimension,
            command
        ),
        { audience = "party" }
    )
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
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
    assert(status.phase ~= 4 and status.phase ~= 9, tostring(status.error))
    if done or not status.prepared or status.phase ~= 3 or status.verified < 40 then
        return status
    end
    if host then
        for slot = 0, 1 do
            actor(slot):SetMinDamageCooldown(10000)
        end
    end
    native.chat_ui_open(true)
    local messages = _IsaacLanChatMessages()
    for i = seen + 1, #messages do
        local message = messages[i]
        if not message.command then
            local number, owner, index, other, dimension, command =
                message.text:match("^TP_CASE (%d+) (%d+) (-?%d+) (-?%d+) (%d+) |(.+)$")
            if number then
                number, owner = tonumber(number), tonumber(owner)
                current = {
                    number = number,
                    owner = owner,
                    index = tonumber(index),
                    other = tonumber(other),
                    dimension = tonumber(dimension),
                    started = Isaac.GetTime(),
                    message = i,
                }
                if (host and owner == 0) or (not host and owner == 1) then
                    assert(_IsaacLanChatSubmit(command))
                end
            end
            local ack = message.text:match("^TP_DONE (%d+)$")
            if ack then
                finished[tonumber(ack)] = true
            end
            if message.text == "TP_FLOOR_READY" then
                finished.floor = true
            end
            if message.text == "TP_ALL_DONE" then
                done = true
                report("PASS teleport commands")
            end
        end
    end
    seen = #messages
    if done then
        return status
    end
    if current and not current.checked then
        local elapsed = Isaac.GetTime() - current.started
        assert(elapsed < 15000, "Timed out: " .. cases[current.number].name)
        local position = roomOf(current.owner)
        if elapsed >= 900 and position.index == current.index and position.dimension == 0 then
            local case = cases[current.number]
            local other = roomOf(1 - current.owner)
            assert(
                other.index == current.other and other.dimension == current.dimension,
                "Stationary teammate moved"
            )
            if case.near then
                assert(
                    (actor(0).Position - actor(1).Position):Length() < 90,
                    "Player teleport did not arrive nearby"
                )
            end
            local isOwner = host and current.owner == 0 or not host and current.owner == 1
            if isOwner then
                local output = ""
                for i = current.message + 1, #messages do
                    if not messages[i].command then
                        output = output .. messages[i].text .. "\n"
                    end
                end
                assert(
                    output:find(case.text or "已传送至", 1, true),
                    "Missing command result: " .. output
                )
            end
            current.checked = true
            report("PASS " .. case.name .. " index=" .. position.index)
            if not host then
                assert(_IsaacLanChatSubmit("TP_DONE " .. current.number))
            end
        end
    end
    if host and (caseNumber == 0 or current and current.checked and finished[caseNumber]) then
        if caseNumber < #cases then
            caseNumber = caseNumber + 1
            sendCase(caseNumber)
        elseif not finished.floorStarted then
            finished.floorStarted = true
            native.api_with_owner(0, function()
                Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
            end)
        elseif Game():GetLevel():GetStage() == 2 and finished.floor then
            assert(roomOf(0).index == Game():GetLevel():GetStartingRoomIndex())
            _IsaacLanChatOutput("TP_ALL_DONE", { audience = "party" })
        end
    end
    if
        not host
        and caseNumber == 0
        and current
        and current.number == #cases
        and current.checked
        and Game():GetLevel():GetStage() == 2
        and native.api_info().ready == 1
    then
        caseNumber = #cases
        finished.floorMessage = #messages
        assert(_IsaacLanChatSubmit("/tp r 0 0"))
    end
    if not host and finished.floorMessage and not finished.floor then
        for i = finished.floorMessage + 1, #messages do
            if not messages[i].command and messages[i].text:find("已在", 1, true) then
                assert(roomOf(1).index == Game():GetLevel():GetStartingRoomIndex())
                finished.floor = true
                assert(_IsaacLanChatSubmit("TP_FLOOR_READY"))
                report("PASS floor cleanup")
                break
            end
        end
    end
    return status
end
