-- One protected pair: actual door input, native cards and chat entries share
-- the production rule. Both peers assert every destination before advancing.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local allRooms = config.gatherAllRooms == true
local host, base = config.host, _IsaacLanFrame
local input, controls = native.input_bot, 0
local frames, linked, configured, chosen, done = 0, false, false, false, false
local current, caseNumber, seen, acknowledged = nil, 0, 0, {}
local flag, shopSource, crawlspaceSource, crawlspaceEntrance
local cardRetry = false
for _, rule in ipairs(native.net_room_options()) do
    if rule.key == (allRooms and "allRoomGather" or "specialRoomGather") then
        assert(rule.name == (allRooms and "所有房间集合" or "特殊房间集合"))
        assert(rule.shortName == (allRooms and "全程集合" or "集合"))
        flag = rule.flag
    end
end
assert(flag, "Missing lobby rule")
native.input_bot = function()
    return input(done and 0 or 1, controls)
end
local function report(text)
    Isaac.DebugString("LAN_GATHER " .. text)
end
local function roomOf(slot)
    return assert(native.rooms_positions()[tostring(slot)])
end
local teleport = native.rooms_teleport
native.rooms_teleport = function(slot, index, dimension)
    if current and current.cardPending and slot == 1 and index == current.index then
        if roomOf(1).index == GridRooms.ROOM_DEVIL_IDX then
            cardRetry = current.cardQueued == true
        else
            current.cardQueued = true
        end
    end
    return teleport(slot, index, dimension)
end
local function actor(slot, fn)
    assert(native.api_with_owner(slot, function()
        fn(Isaac.GetPlayer(0), Game():GetRoom(), Game():GetLevel())
    end))
end
local function existing(kind)
    local level = Game():GetLevel()
    if kind == RoomType.ROOM_ERROR or kind == RoomType.ROOM_ANGEL then
        local index = kind == RoomType.ROOM_ERROR and GridRooms.ROOM_ERROR_IDX
            or GridRooms.ROOM_DEVIL_IDX
        local desc = level:GetRoomByIdx(index, 0)
        assert(desc.Data and desc.Data.Type == kind)
        return desc.SafeGridIndex
    end
    local rooms = level:GetRooms()
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if
            desc.Data
            and desc.Data.Type == kind
            and desc.SafeGridIndex ~= level:GetStartingRoomIndex()
        then
            return desc.SafeGridIndex
        end
    end
    error("Missing generated room type " .. kind)
end
local function coordinate(index)
    local start = Game():GetLevel():GetStartingRoomIndex()
    return string.format("/tp r %d %d", index % 13 - start % 13, start // 13 - index // 13)
end
local function target(command, kind)
    return function()
        return command, existing(kind)
    end
end
local function start()
    return "/tp r 0 0", Game():GetLevel():GetStartingRoomIndex()
end
local inward = { Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) }
local movement = { 1, 4, 2, 8 }
local function walkTo(owner, index)
    local direction
    actor(owner, function(player, room, level)
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity:ToNPC() then
                entity:Remove()
            end
        end
        room:SetClear(true)
        player:AddKeys(1)
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and level:GetRoomByIdx(door.TargetRoomIndex, 0).SafeGridIndex == index then
                player.Position = door.Position + inward[slot % 4 + 1] * 45
                player.Velocity = Vector.Zero
                direction = movement[slot % 4 + 1]
                break
            end
        end
    end)
    return "walk " .. assert(direction, "Missing actual door"), index
end
-- Prepare the native grid before its room update, matching the crawlspace
-- regression fixture's authority callback boundary.
local gate = native.net_gate
native.net_gate = function(capture, apply, collect, restore, present, stage)
    return gate(capture, function(tick, count, bytes)
        apply(tick, count, bytes)
        if host and allRooms and tick == 30 then
            crawlspaceSource = roomOf(1).index
            actor(0, function(player)
                player.Position, player.Velocity = Vector(580, 280), Vector.Zero
            end)
            actor(1, function(player, room)
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity:ToNPC() then
                        entity:Remove()
                    end
                end
                room:SetClear(true)
                local index = room:GetGridIndex(Vector(240, 280))
                room:RemoveGridEntity(index, 0, false)
                room:Update()
                assert(room:SpawnGridEntity(index, GridEntityType.GRID_STAIRS, 0, 123, 0))
                crawlspaceEntrance = room:GetGridPosition(index)
                player.Position = crawlspaceEntrance + Vector(60, 0)
                player.Velocity = Vector.Zero
            end)
        end
    end, collect, restore, present, stage)
end
local cases = {
    {
        name = "crawlspace-enter",
        allOnly = true,
        setup = function()
            local entrance = assert(crawlspaceEntrance, "Missing prepared crawlspace entrance")
            return string.format("stairs %g %g", entrance.X, entrance.Y), GridRooms.ROOM_DUNGEON_IDX
        end,
    },
    {
        name = "crawlspace-return",
        allOnly = true,
        setup = function()
            actor(1, function(player)
                player.Position, player.Velocity = Vector(120, 200), Vector.Zero
            end)
            return "walk 4", assert(crawlspaceSource)
        end,
    },
    {
        name = "ordinary",
        split = true,
        setup = function()
            local index = existing(RoomType.ROOM_DEFAULT)
            return coordinate(index), index
        end,
    },
    { name = "guest-shop", setup = target("/tp sh", RoomType.ROOM_SHOP) },
    { name = "leave-special", owner = 0, split = true, setup = start },
    { name = "reenter-special", owner = 0, setup = target("/tp sh", RoomType.ROOM_SHOP) },
    {
        name = "door-source",
        split = true,
        setup = function()
            actor(1, function(_, room, level)
                for slot = 0, 7 do
                    local door = room:GetDoor(slot)
                    local desc = door and level:GetRoomByIdx(door.TargetRoomIndex, 0)
                    if desc and desc.Data and desc.Data.Type == RoomType.ROOM_DEFAULT then
                        shopSource = desc.SafeGridIndex
                        break
                    end
                end
            end)
            return coordinate(assert(shopSource)), shopSource
        end,
    },
    { name = "host-before-door", owner = 0, split = true, specialOnly = true, setup = start },
    {
        name = "walk-shop",
        setup = function()
            return walkTo(1, existing(RoomType.ROOM_SHOP))
        end,
    },
    {
        name = "walk-ordinary",
        owner = 0,
        allOnly = true,
        setup = function()
            return walkTo(0, assert(shopSource))
        end,
    },
    { name = "ultra-secret", setup = target("/tp us", RoomType.ROOM_ULTRASECRET) },
    { name = "host-secret", owner = 0, setup = target("/tp s", RoomType.ROOM_SECRET) },
    { name = "boss", setup = target("/tp b", RoomType.ROOM_BOSS) },
    {
        name = "angel",
        setup = function()
            actor(0, function(_, _, level)
                level:InitializeDevilAngelRoom(true, false)
            end)
            return target("/tp a", RoomType.ROOM_ANGEL)()
        end,
    },
    { name = "host-before-card", owner = 0, split = true, setup = start },
    { name = "guest-before-card", split = true, specialOnly = true, setup = start },
    {
        name = "joker",
        owner = 0,
        setup = function()
            return "joker", GridRooms.ROOM_DEVIL_IDX
        end,
    },
    { name = "error", setup = target("/tp e", RoomType.ROOM_ERROR) },
    { name = "leave-error", owner = 0, split = true, setup = start },
    {
        name = "ordinary-red",
        owner = 0,
        split = true,
        setup = function()
            local red
            actor(0, function(_, room, level)
                local before = {}
                for index = 0, 168 do
                    before[index] = level:GetRoomByIdx(index, 0).Data ~= nil
                end
                for slot = 0, 7 do
                    if level:MakeRedRoomDoor(roomOf(0).index, slot) then
                        local door = room:GetDoor(slot)
                        local index = door and door.TargetRoomIndex
                        local desc = index and level:GetRoomByIdx(index, 0)
                        if
                            desc
                            and not before[index]
                            and desc.Data
                            and desc.Data.Type == RoomType.ROOM_DEFAULT
                        then
                            red = desc.SafeGridIndex
                            break
                        end
                    end
                end
            end)
            return coordinate(assert(red, "Missing ordinary red room")), red
        end,
    },
    {
        name = "simultaneous",
        owner = 0,
        setup = function()
            return "pair", existing(RoomType.ROOM_SHOP)
        end,
    },
    {
        name = "card-in-flight",
        owner = 0,
        setup = function()
            return "pending-card", existing(RoomType.ROOM_TREASURE)
        end,
    },
    {
        name = "floor",
        owner = 0,
        setup = function()
            return "floor", Game():GetLevel():GetStartingRoomIndex()
        end,
    },
    { name = "post-floor-shop", setup = target("/tp sh", RoomType.ROOM_SHOP) },
}
local selected = {}
for _, case in ipairs(cases) do
    if not (allRooms and case.specialOnly or not allRooms and case.allOnly) then
        selected[#selected + 1] = case
    end
end
cases = selected
local function sendCase(number)
    local case = cases[number]
    local command, index = case.setup()
    local owner = case.owner or 1
    local other = not allRooms and case.split and roomOf(1 - owner).index or index
    _IsaacLanChatOutput(
        string.format("GATHER_CASE %d %d %d %d |%s", number, owner, index, other, command),
        { audience = "party" }
    )
end
local function execute(command, owner)
    if command:sub(1, 1) == "/" then
        assert(_IsaacLanChatSubmit(command))
    elseif command:match("^walk ") then
        controls = assert(tonumber(command:match("^walk (%d+)$")))
    elseif command:match("^stairs ") then
        local x, y = command:match("^stairs (%S+) (%S+)$")
        current.entrance = Vector(assert(tonumber(x)), assert(tonumber(y)))
    elseif command == "joker" then
        actor(owner, function(player)
            player:UseCard(Card.CARD_JOKER, UseFlag.USE_NOANIM)
        end)
    elseif command == "pair" then
        assert(native.rooms_teleport(0, existing(RoomType.ROOM_SHOP), 0))
        assert(native.rooms_teleport(1, existing(RoomType.ROOM_TREASURE), 0))
    elseif command == "pending-card" then
        current.cardPending = true
        actor(1, function(player)
            player:UseCard(Card.CARD_JOKER, UseFlag.USE_NOANIM)
        end)
        assert(native.rooms_teleport(0, existing(RoomType.ROOM_TREASURE), 0))
    elseif command == "floor" then
        actor(owner, function(player)
            Game():StartStageTransition(false, RoomTransitionAnim.FADE, player)
        end)
    else
        error("Unknown fixture command " .. command)
    end
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
    local status = base()
    if status.phase == 2 then
        if host and not configured then
            configured = true
            _IsaacLanCommand("room_options", tostring(flag))
        end
        if status.roomOptions == flag and not chosen then
            chosen = true
            _IsaacLanCommand("choose", "0:1")
        end
        if host and status.players == 2 and status.ready0 == 1 and status.ready1 == 1 then
            _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
        end
    end
    assert(status.phase ~= 4 and status.phase ~= 9, tostring(status.error))
    if done or status.phase ~= 3 or not status.prepared or status.verified < 40 then
        return status
    end
    local info = native.api_info()
    assert(info.roomOptions == flag, "Peer lost the selected room rule")
    if info.ready ~= 1 then
        return status
    end
    if host then
        for slot = 0, 1 do
            actor(slot, function(player)
                player:SetMinDamageCooldown(10000)
            end)
        end
    end
    local messages = _IsaacLanChatMessages()
    for i = seen + 1, #messages do
        local message = messages[i]
        if not message.command then
            local number, owner, index, other, command =
                message.text:match("^GATHER_CASE (%d+) (%d+) (-?%d+) (-?%d+) |(.+)$")
            if number then
                current = {
                    number = tonumber(number),
                    owner = tonumber(owner),
                    index = tonumber(index),
                    other = tonumber(other),
                    started = Isaac.GetTime(),
                }
                if (host and current.owner == 0) or (not host and current.owner == 1) then
                    execute(command, current.owner)
                end
            end
            local ack = message.text:match("^GATHER_DONE (%d+)$")
            if ack then
                acknowledged[tonumber(ack)] = true
            end
            if message.text == "GATHER_ALL_DONE" then
                done, controls = true, 0
                report("PASS " .. (allRooms and "all" or "special") .. " room rule")
            end
        end
    end
    seen = #messages
    if done then
        return status
    end
    if current and not current.checked then
        local case = cases[current.number]
        local elapsed = Isaac.GetTime() - current.started
        assert(elapsed < 15000, "Timed out: " .. case.name)
        local position, other = roomOf(current.owner), roomOf(1 - current.owner)
        local expected, peerExpected = current.index, current.other
        local floorReady = case.name ~= "floor" or Game():GetLevel():GetStage() == 2
        if case.name == "floor" and floorReady then
            expected = Game():GetLevel():GetStartingRoomIndex()
            peerExpected = expected
        end
        if position.index == expected then
            controls = 0
        elseif
            current.entrance and (host and current.owner == 0 or not host and current.owner == 1)
        then
            assert(native.rooms_with_player(current.owner, function()
                local player = Isaac.GetPlayer(0)
                local delta = current.entrance - player.Position
                local entryTolerance = 6
                -- Stand on the entrance until its native opening completes.
                -- A fixed direction can walk past a still-closed hatch.
                if math.abs(delta.X) > entryTolerance then
                    controls = delta.X < 0 and 1 or 2
                elseif math.abs(delta.Y) > entryTolerance then
                    controls = delta.Y < 0 and 4 or 8
                else
                    controls = 0
                end
            end, 1))
        end
        if
            elapsed >= 1200
            and floorReady
            and position.index == expected
            and other.index == peerExpected
        then
            assert(position.dimension == 0 and other.dimension == 0)
            if host and case.name == "card-in-flight" then
                assert(cardRetry, "Fixture did not exercise the pending native card")
            end
            if host and case.name == "crawlspace-enter" then
                actor(0, function(player, room, level)
                    assert(room:GetType() == RoomType.ROOM_DUNGEON and player.Position.X < 400)
                    assert(level.DungeonReturnRoomIndex == crawlspaceSource)
                end)
            end
            if host and allRooms and case.name ~= "floor" then
                local leader
                actor(current.owner, function(player)
                    leader = player.Position
                end)
                actor(1 - current.owner, function(player)
                    local maxLandingDistance = 100
                    assert(
                        player.Position:Distance(leader) <= maxLandingDistance,
                        "Follower did not land near the departing player: " .. case.name
                    )
                end)
            end
            current.checked = true
            report(
                "PASS "
                    .. case.name
                    .. " owner="
                    .. current.owner
                    .. " index="
                    .. position.index
                    .. " other="
                    .. other.index
            )
            if not host then
                assert(_IsaacLanChatSubmit("GATHER_DONE " .. current.number))
            end
        end
    end
    if host and (caseNumber == 0 or current and current.checked and acknowledged[caseNumber]) then
        if caseNumber < #cases then
            caseNumber = caseNumber + 1
            sendCase(caseNumber)
        else
            _IsaacLanChatOutput("GATHER_ALL_DONE", { audience = "party" })
        end
    end
    return status
end
