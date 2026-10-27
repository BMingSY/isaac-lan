local root = assert(arg[1])
local runtime = dofile(root .. "/tests/fixtures/api_runtime.lua")(root)
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local factory = dofile(root .. "/src/bridge/runtime/teleport.lua")
local chatFactory = dofile(root .. "/src/bridge/runtime/chat.lua")
local wire = dofile(root .. "/src/bridge/runtime/chat_wire.lua")
local dice = dofile(root .. "/src/bridge/runtime/chat_dice.lua")
local host, guest = runtime.peer(0), runtime.peer(1)
local descriptors, lookup, origin, moves, cancellations = {}, {}, 84, {}, {}
local connected, run, rejectMove, blockedTiles = 3, string.rep("a", 32), false, {}
local function vector(x, y)
    return { X = x, Y = y }
end
local function add(index, kind, shape, dimension, safe, offMap)
    local desc = {
        GridIndex = index,
        SafeGridIndex = safe or index,
        ListIndex = #descriptors + 1,
        hash = #descriptors + 100,
        Data = { Type = kind or 1, Shape = shape or 1 },
        VisitedCount = 0,
        Clear = false,
    }
    descriptors[#descriptors + 1] = desc
    desc.offMap = offMap
    lookup[(dimension or 0) .. ":" .. desc.SafeGridIndex] = desc
    return desc
end
local level = {}
function level:GetStartingRoomIndex()
    return origin
end
function level:GetRooms()
    local values = {}
    for _, desc in ipairs(descriptors) do
        if not desc.offMap then
            values[#values + 1] = desc
        end
    end
    return {
        Size = #values,
        Get = function(_, index)
            return values[index + 1]
        end,
    }
end
function level:GetRoomByIdx(index, dimension)
    return lookup[(index < 0 and 0 or dimension) .. ":" .. index] or { Data = nil }
end
local room = {}
function room:GetGridSize()
    return 4
end
function room:GetGridPosition(index)
    return vector(100 + index * 40, 120)
end
function room:IsPositionInRoom(point, radius)
    return point.X - radius >= 60
        and point.X + radius <= 260
        and point.Y - radius >= 80
        and point.Y + radius <= 160
end
function room:GetGridCollisionAtPos(point)
    local index = math.floor((point.X - 80) / 40)
    return blockedTiles[index] and 1 or 0
end
for _, peer in ipairs({ host, guest }) do
    local native = peer.env._IsaacLan
    local info = native.api_info
    native.api_info = function()
        local value = info()
        value.connected, value.runId = connected, run
        return value
    end
    peer.env.Game = function()
        assert(peer.slot == 0, "A guest queried authoritative rooms")
        assert(peer.scope ~= nil, "Room query escaped its owner's scope")
        return {
            GetNumPlayers = function()
                return peer.extraBody and 2 or 1
            end,
            GetRoom = function()
                return room
            end,
            GetLevel = function()
                return level
            end,
        }
    end
    local player = peer.env.Isaac.GetPlayer
    peer.env.Isaac.GetPlayer = function(index)
        return index == 1 and peer.extraBody or player(index)
    end
    native.rooms_teleport = function(owner, index, dimension)
        assert(peer.slot == 0, "A guest migrated a player")
        moves[#moves + 1] = { owner = owner, index = index, dimension = dimension }
        if rejectMove then
            return false
        end
        peer.queuedMove = moves[#moves]
        return true
    end
    native.api_cancel_move = function(owner, index, dimension)
        cancellations[#cancellations + 1] = { owner, index, dimension }
        peer.queuedMove = nil
    end
    peer.teleport = factory({
        native = native,
        enums = {
            room = enums.RoomType,
            shape = enums.RoomShape,
            grid = enums.GridRooms,
        },
        game = peer.env.Game,
        player = peer.env.Isaac.GetPlayer,
        hash = peer.env.GetPtrHash,
        placeNear = dofile(root .. "/src/bridge/runtime/room_placement.lua")({
            native = native,
            game = peer.env.Game,
            player = peer.env.Isaac.GetPlayer,
            vector = vector,
            collision = enums.GridCollisionClass,
        }),
        output = function(...)
            return peer.chat.output(...)
        end,
    })
    peer.chat = chatFactory({
        teleport = peer.teleport,
        limits = { characters = 60, commandBytes = 2048, history = 200, dice = 999 },
        nonce = native.api_nonce,
        clock = function()
            return peer.now
        end,
        info = function()
            local value = native.api_info()
            value.hosting = value.authority
            return value
        end,
        context = function(slot)
            return peer.positions[tostring(slot)]
        end,
        send = native.api_send,
        receive = native.api_receive,
        dice = dice,
        execute = function()
            error("Teleport ran a console command")
        end,
    }, wire)
end
local function reset()
    host.chat.reset()
    guest.chat.reset()
    descriptors, lookup, moves, cancellations = {}, {}, {}, {}
    origin, connected, run, rejectMove, blockedTiles = 84, 3, string.rep("a", 32), false, {}
    for _, peer in ipairs({ host, guest }) do
        peer.inbox, peer.sent, peer.epoch, peer.now, peer.ready = {}, {}, 1, 0, 1
        peer.queuedMove, peer.extraBody = nil, nil
        peer.positions =
            { ["0"] = { index = 84, dimension = 0 }, ["1"] = { index = 84, dimension = 0 } }
    end
    for i, actor in ipairs(runtime.actors) do
        actor.Position, actor.Velocity, actor.Size, actor.hash =
            vector(140, 120), vector(5, 6), 10, i * 11
    end
    add(84).VisitedCount = 1
end
local function poll()
    host.chat.poll()
    guest.chat.poll()
end
local function command(text, peer)
    peer = peer or guest
    local before = #peer.chat.messages
    assert(peer.chat.submit(text))
    poll()
    host.chat.step()
    poll()
    local lines = {}
    for i = before + 1, #peer.chat.messages do
        if not peer.chat.messages[i].command then
            lines[#lines + 1] = peer.chat.messages[i].text
        end
    end
    return table.concat(lines, "\n")
end
local function arrive()
    local move = assert(host.queuedMove, "No native room migration was queued")
    host.queuedMove = nil
    for _, peer in ipairs({ host, guest }) do
        peer.positions[tostring(move.owner)] = { index = move.index, dimension = move.dimension }
    end
    host.chat.step()
    poll()
end
local function moved(owner, index, dimension)
    local move = assert(moves[#moves])
    assert(move.owner == owner and move.index == index and move.dimension == (dimension or 0))
    arrive()
end
reset()
for _, text in ipairs({
    "/tp r",
    "/tp r 0",
    "/tp r 0 1 2",
    "/tp r nan 0",
    "/tp r 1.5 0",
    "/tp r 1e0 0",
    "/tp r 0 13",
    "/tp r 99999999999999999999 0",
    "/tp 0p",
    "/tp 5p",
    "/tp r 0x1 0",
    "/tp us extra",
}) do
    assert(not guest.chat.submit(text), "Accepted malformed target: " .. text)
end
assert(#moves == 0 and #host.inbox == 0)
guest.ready = 0
assert(command("/tp"):find("ultrasecret/us", 1, true))
assert(#guest.sent == 0, "Local help reached the host")
guest.ready = 1
-- Signed coordinates use the starting room, even from another current room.
add(71, 2)
add(85, 4)
add(95)
command("/TP ROOM +0 +1")
moved(1, 71)
assert(host.positions["0"].index == 84)
command("/tp r 1 0")
moved(1, 85)
command("/tp r -2 -1")
moved(1, 95)
command("/tp ST")
moved(1, 84)
assert(command("/tp r 0 0"):find("已在", 1, true))
assert(command("/tp r 12 0"):find("没有已生成", 1, true))
local count = #moves
assert(command("/tp r 0 -1"):find("没有已生成", 1, true))
assert(#moves == count, "Empty map cell generated a room")
-- Large-room occupied cells resolve to one descriptor; every L cutout is empty.
for _, case in ipairs({
    { shape = 4, safe = 28, cells = { { -4, 4 }, { -4, 3 } }, hole = { -3, 4 } },
    { shape = 6, safe = 28, cells = { { -4, 4 }, { -3, 4 } }, hole = { -4, 3 } },
    { shape = 8, safe = 28, cells = { { -4, 4 }, { -3, 4 }, { -4, 3 }, { -3, 3 } } },
    { shape = 9, safe = 29, cells = { { -3, 4 }, { -4, 3 }, { -3, 3 } }, hole = { -4, 4 } },
    { shape = 10, safe = 28, cells = { { -4, 4 }, { -4, 3 }, { -3, 3 } }, hole = { -3, 4 } },
    { shape = 11, safe = 28, cells = { { -4, 4 }, { -3, 4 }, { -3, 3 } }, hole = { -4, 3 } },
    { shape = 12, safe = 28, cells = { { -4, 4 }, { -3, 4 }, { -4, 3 } }, hole = { -3, 3 } },
}) do
    reset()
    add(28, 1, case.shape, 0, case.safe)
    for _, cell in ipairs(case.cells) do
        command(string.format("/tp r %d %d", cell[1], cell[2]))
        moved(1, case.safe)
        command("/tp st")
        moved(1, 84)
    end
    if case.hole then
        assert(
            command(string.format("/tp r %d %d", case.hole[1], case.hole[2])):find(
                "没有已生成",
                1,
                true
            )
        )
    end
end
reset()
add(71, 2)
add(85, 2)
assert(command("/tp sh"):find("多个目标", 1, true))
assert(#moves == 0)
local list = command("/tp l")
assert(
    list:find("商店 (0, 1) 未探索", 1, true) and list:find("商店 (1, 0) 未探索", 1, true)
)
assert(#host.chat.messages == 0, "Private list leaked to the host")
-- Existing hidden/red rooms are accepted, without cards, doors or generation.
add(42, 29)
command("/tp us")
moved(1, 42)
add(86)
command("/tp r 2 0")
moved(1, 86)
assert(command("/tp a"):find("尚未生成天使房", 1, true))
add(-1, 15, 1, 0, nil, true)
command("/tp a")
moved(1, -1)
assert(command("/tp d"):find("尚未生成恶魔房", 1, true))
assert(command("/tp e"):find("尚未生成错误房", 1, true))
add(-2, 3, 1, 0, nil, true)
command("/tp error")
moved(1, -2)
command("/tp st")
moved(1, 84)
-- Coordinates use the caller's dimension; off-map deals use their real dimension.
reset()
add(84, 1, 1, 1)
add(71, 2, 1, 0)
add(71, 4, 1, 1)
for _, peer in ipairs({ host, guest }) do
    peer.positions["1"].dimension = 1
end
assert(command("/tp sh"):find("尚未生成商店", 1, true))
command("/tp t")
moved(1, 71, 1)
add(-1, 14, 1, 0, nil, true)
command("/tp d")
moved(1, -1, 0)
-- Player travel uses the authenticated sender, including same-room placement.
reset()
runtime.actors[1].Position = vector(180, 120)
blockedTiles[2] = true
host.extraBody = { Position = vector(220, 120), Velocity = vector(1, 1), Size = 10 }
assert(command("/tp 1P"):find("已传送至 1P", 1, true))
assert(runtime.actors[1].Position.X == 180, "Target player moved")
assert(runtime.actors[2].Position.X == 140 and runtime.actors[2].Velocity.X == 0)
assert(host.extraBody.Position.X == 140 and host.extraBody.Velocity.X == 0)
assert(#moves == 0)
host.extraBody = nil
add(71)
for _, peer in ipairs({ host, guest }) do
    peer.positions["0"] = { index = 71, dimension = 0 }
end
command("/tp 1p")
runtime.actors[1].Position = vector(220, 120)
moved(1, 71)
assert(runtime.actors[2].Position.X == 220, "Landing used the stale target position")
-- Duplicate packets execute only once and later requests cannot replace active travel.
reset()
add(71)
assert(guest.chat.submit("/tp r 0 1"))
local replay = host.inbox[1]
host.inbox[2] = replay
poll()
host.chat.step()
host.chat.step()
assert(#moves == 1)
assert(command("/tp st"):find("尚未完成", 1, true))
moved(1, 71)
-- Stale source requests are rejected before any room migration.
for _, mutate in ipairs({
    function()
        host.epoch = host.epoch + 1
    end,
    function()
        run = string.rep("b", 32)
    end,
    function()
        host.positions["1"].index = 71
    end,
    function()
        connected = 1
    end,
    function()
        host.positions["1"].dimension = 1
    end,
}) do
    reset()
    add(71)
    assert(guest.chat.submit("/tp r 0 1"))
    poll()
    mutate()
    host.chat.step()
    assert(#moves == 0)
end
-- Arrival transactions expire, clear on reset, and never cancel a new floor's move.
reset()
add(71)
command("/tp r 0 1")
host.now = 3001
host.chat.step()
poll()
assert(
    not host.queuedMove
        and guest.chat.messages[#guest.chat.messages].text:find("未完成", 1, true)
)
command("/tp r 0 1")
local before = #cancellations
host.epoch = 2
host.chat.step()
assert(#cancellations == before, "Stale cancellation touched a new world")
host.queuedMove = nil
guest.epoch = 2
command("/tp r 0 1")
host.chat.reset()
assert(not host.queuedMove)
host.chat.step()
assert(#host.chat.messages == 0)
-- Target departure/disconnect or a changed source body cancels pending placement.
for _, mutate in ipairs({
    function()
        host.positions["0"].index = 85
    end,
    function()
        connected = 2
    end,
    function()
        runtime.actors[2].hash = 99
    end,
}) do
    reset()
    add(71)
    for _, peer in ipairs({ host, guest }) do
        peer.positions["0"].index = 71
    end
    command("/tp 1p")
    mutate()
    host.chat.step()
    poll()
    assert(not host.queuedMove)
    assert(guest.chat.messages[#guest.chat.messages].text:find("已取消", 1, true))
    assert(runtime.actors[2].Position.X == 140)
end
reset()
add(71)
command("/tp r 0 1")
local positions = host.env._IsaacLan.rooms_positions
host.env._IsaacLan.rooms_positions = function()
    error("Unavailable room view")
end
host.chat.step()
host.env._IsaacLan.rooms_positions = positions
poll()
assert(not host.queuedMove)
assert(guest.chat.messages[#guest.chat.messages].text:find("已取消", 1, true))
command("/tp r 0 1")
moved(1, 71)
reset()
add(71)
rejectMove = true
assert(command("/tp r 0 1"):find("目标房间不可用", 1, true))
rejectMove = false
command("/tp r 0 1")
moved(1, 71)
print("TELEPORT TESTS PASSED")
