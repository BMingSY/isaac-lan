local root = assert(arg[1])
local types = dofile(root .. "/tests/fixtures/game_enums.lua").RoomType
local gatherFlag = 8
local allGatherFlag = 16
local info = {
    active = 1,
    authority = 1,
    ready = 1,
    runId = "run",
    worldEpoch = 1,
    roomOptions = gatherFlag,
    players = 4,
    connected = 15,
    nowMs = 0,
}
local positions, kinds, queued, moves, cancelled, refused = {}, {}, {}, {}, {}, {}
local scope, unavailable
local actors, placements = {}, {}
local function vector(x, y)
    return { X = x, Y = y }
end
local function enter(slot, index, kind, dimension)
    positions[tostring(slot)] = { index = index, dimension = dimension or 0 }
    kinds[slot] = kind or types.ROOM_DEFAULT
end
local native = {
    api_info = function()
        return info
    end,
    net_room_options = function()
        return {
            { key = "lootRoll", flag = 4 },
            { key = "sharedClearCharge", flag = 2 },
            { key = "specialRoomGather", flag = gatherFlag },
            { key = "allRoomGather", flag = 16 },
        }
    end,
    rooms_positions = function()
        return positions
    end,
    api_with_owner = function(slot, fn)
        assert(not scope, "Nested room scope")
        if slot == unavailable then
            return false
        end
        scope = slot
        fn()
        scope = nil
        return true
    end,
    rooms_teleport = function(slot, index, dimension)
        assert(not scope, "Gather must queue after leaving the room scope")
        assert((info.connected & (1 << slot)) ~= 0, "Disconnected player moved")
        if refused[slot] then
            return false
        end
        local move = { slot = slot, index = index, dimension = dimension }
        moves[#moves + 1] = move
        queued[slot] = queued[slot] or move
        return true
    end,
    api_cancel_move = function(slot, index, dimension)
        cancelled[#cancelled + 1] = slot
        local move = queued[slot]
        if move and move.index == index and move.dimension == dimension then
            queued[slot] = nil
        end
    end,
}
local function game()
    assert(scope ~= nil)
    return {
        GetNumPlayers = function()
            return #actors[scope]
        end,
        GetRoom = function()
            return {
                GetType = function()
                    return kinds[scope]
                end,
                GetGridSize = function()
                    return 10
                end,
                GetGridPosition = function(_, index)
                    return vector(40 + index * 40, 120)
                end,
                IsPositionInRoom = function(_, point, radius)
                    return point.X - radius >= 20 and point.X + radius <= 420
                end,
                GetGridCollisionAtPos = function()
                    return 0
                end,
            }
        end,
    }
end
local function player(index)
    return actors[assert(scope)][index + 1]
end
local placeNear = dofile(root .. "/src/bridge/runtime/room_placement.lua")({
    native = native,
    game = game,
    player = player,
    vector = vector,
    collision = { COLLISION_NONE = 0 },
})
local gather = dofile(root .. "/src/bridge/compat/rules/room_gather.lua")({
    native = native,
    roomTypes = types,
    game = game,
    player = player,
    placeNear = function(slot, target)
        placements[#placements + 1] = slot
        return placeNear(slot, target)
    end,
})
local unused = {
    reset = function() end,
    step = function()
        error("Unselected rule ran")
    end,
}
local allowed = true
local rules = dofile(root .. "/src/bridge/runtime/room_rules.lua")({
    native = native,
    allow = function(key)
        assert(key == "specialRoomGather" or key == "allRoomGather")
        return allowed
    end,
    allocation = unused,
    charge = unused,
    gather = gather,
})
local function setup(options)
    allowed = true
    rules.reset()
    positions, kinds, queued, moves, cancelled, refused = {}, {}, {}, {}, {}, {}
    actors, placements = {}, {}
    unavailable = nil
    info.active, info.authority, info.ready, info.connected = 1, 1, 1, 15
    info.roomOptions = options == nil and gatherFlag or options
    for slot = 0, 3 do
        enter(slot, 84)
        actors[slot] = { { Position = vector(40 + slot * 80, 120), Size = 10 } }
    end
    rules.step()
end
local function arrive(slot, kind)
    local move = assert(queued[slot], "Missing native request")
    enter(slot, move.index, kind, move.dimension)
    queued[slot] = nil
end
local function complete(kind)
    for slot = 0, 3 do
        if queued[slot] then
            arrive(slot, kind)
        end
    end
    rules.step()
end
local function starts(owner, index, kind, dimension)
    enter(owner, index, kind, dimension)
    rules.step()
end

-- Every original special type, including off-map deals/errors and ultra secret.
for kind = types.ROOM_SHOP, types.ROOM_ULTRASECRET do
    setup()
    local index = kind == types.ROOM_ERROR and -2
        or (kind == types.ROOM_ANGEL or kind == types.ROOM_DEVIL) and -1
        or 85
    starts(2, index, kind)
    assert(#moves == 3 and not queued[2])
    for _, move in ipairs(moves) do
        assert(move.index == index and move.dimension == 0)
    end
    rules.step() -- action-step and post-frame observe the same commit
    assert(#moves == 3, "Duplicate observation repeated the gather")
    complete(kind)
    rules.step()
    enter(0, 84) -- Free to leave while teammates remain in the special room.
    rules.step()
    assert(#moves == 3 and not next(queued), "Gather arrivals tethered a leaving player")
    starts(0, index, kind)
    assert(#moves == 3, "Players already together were teleported again")
    enter(0, 84)
    enter(1, 84)
    rules.step()
    starts(1, index, kind)
    assert(#moves == 4 and queued[0], "Re-entering did not gather again")
end

setup()
starts(1, 85, types.ROOM_DEFAULT) -- Includes ordinary red rooms.
starts(1, 86, 0)
starts(1, 87, types.ROOM_ULTRASECRET + 1)
assert(#moves == 0, "Ordinary, null or non-vanilla rooms gathered")
-- Same index in another dimension is a real entry; use the entrant's type.
starts(1, 87, types.ROOM_SHOP, 1)
assert(#moves == 3 and moves[1].index == 87 and moves[1].dimension == 1)
complete(types.ROOM_SHOP)
-- A new saved/restored baseline and a rejoining player are not new entries.
rules.reset()
enter(0, 88, types.ROOM_BOSS)
rules.step()
assert(#moves == 3)
info.connected = 14
rules.step()
enter(0, 89, types.ROOM_TREASURE)
info.connected = 15
rules.step()
assert(#moves == 3)

setup()
info.connected = 7
enter(0, 85, types.ROOM_SHOP)
starts(1, 86, types.ROOM_BOSS)
assert(#moves == 2 and queued[1].index == 85 and queued[2].index == 85)
assert(not queued[0] and not queued[3], "Simultaneous entries or dormant slot duplicated moves")
arrive(1, types.ROOM_SHOP)
rules.step()
assert(#moves == 2 and queued[2], "Partial arrival started a second gathering")
enter(1, 84)
arrive(2, types.ROOM_SHOP)
rules.step()
rules.step()
assert(#moves == 2, "A later arrival pulled an exiting teammate back")

setup()
unavailable = 0
starts(0, 85, types.ROOM_SHOP)
assert(#moves == 0, "Unavailable scope invented a destination")
unavailable = nil
refused[2] = true
starts(1, 86, types.ROOM_BOSS)
assert(#moves == 2 and not queued[2], "Rejected move entered the waiting set")
queued[0] = nil
enter(0, 87, types.ROOM_SHOP) -- Another native action won the first destination.
rules.step()
assert(queued[0].index == 86 and queued[3], "Existing native move prevented gathering")
arrive(0, types.ROOM_BOSS)
info.connected = 7
rules.step()
assert(not next(queued), "Disconnected follower retained a move")

setup()
queued[1] = { slot = 1, index = -1, dimension = 0 } -- Native Joker is still animating.
starts(0, 85, types.ROOM_SHOP)
arrive(1, types.ROOM_DEVIL)
arrive(2, types.ROOM_SHOP)
arrive(3, types.ROOM_SHOP)
rules.step()
assert(#moves == 4 and queued[1].index == 85, "An earlier card stranded the follower")
arrive(1, types.ROOM_SHOP)
rules.step()
rules.step()
assert(#moves == 4 and not next(queued), "Card completion repeated the gathering")

for _, change in ipairs({
    function()
        enter(0, 84) -- Inviting player leaves before the queued migration.
    end,
    function()
        info.connected = 14
    end,
    function()
        info.nowMs = info.nowMs + 3000
    end,
    function()
        info.roomOptions = 0
    end,
    function()
        info.ready = 0
    end,
    function()
        info.active = 0
    end,
}) do
    setup()
    starts(0, 85, types.ROOM_SHOP)
    change()
    rules.step()
    assert(not next(queued), "Invalid gather left native requests queued")
end
for _, change in ipairs({
    function()
        info.worldEpoch = info.worldEpoch + 1
    end,
    function()
        info.runId = info.runId .. "+"
    end,
    function()
        info.authority = 0
    end,
}) do
    setup()
    starts(0, 85, types.ROOM_SHOP)
    change()
    -- The backend discards old moves at this boundary. Never cancel new ones.
    queued = {}
    local count = #cancelled
    rules.step()
    assert(#cancelled == count and #moves == 3, "Old gather crossed authority/run/epoch")
end
for _, property in ipairs({ "active", "authority", "ready", "roomOptions" }) do
    setup()
    info[property] = 0
    starts(0, 85, types.ROOM_SHOP)
    assert(#moves == 0, "Disabled or replica rule moved players")
end
setup(0)
starts(0, 85, types.ROOM_SHOP)
info.roomOptions = gatherFlag
rules.step()
assert(#moves == 0, "Enabling the rule retroactively treated a baseline as an entry")
setup()
allowed = false
starts(0, 85, types.ROOM_SHOP)
assert(#moves == 0, "A challenge veto must take precedence over the lobby toggle")
setup()
starts(0, 85, types.ROOM_SHOP)
allowed = false
rules.step()
assert(not next(queued), "Challenge veto must cancel a pending gather")

-- The stronger rule works independently and takes precedence when both are on.
for _, options in ipairs({ allGatherFlag, allGatherFlag | gatherFlag }) do
    for owner = 0, 3 do
        for _, kind in ipairs({ types.ROOM_DEFAULT, types.ROOM_SHOP, types.ROOM_ERROR }) do
            setup(options)
            starts(owner, kind == types.ROOM_ERROR and -2 or 85, kind)
            assert(#moves == 3 and not queued[owner], "Any participant must gather the others")
            assert(#placements == 0, "Placement preceded the native arrival")
            rules.step()
            assert(#moves == 3, "Repeated state duplicated the gathering")
            complete(kind)
            assert(#placements == 3)
            for slot = 0, 3 do
                assert(actors[slot][1].Position.X == actors[owner][1].Position.X)
            end
            rules.step()
            assert(#moves == 3 and #placements == 3, "Forced arrivals started another gathering")
            starts((owner + 1) % 4, 84) -- Returning to an ordinary room also gathers.
            assert(#moves == 6)
            complete()
            assert(not next(queued) and #moves == 6)
        end
    end
end

setup(allGatherFlag)
starts(2, 84, types.ROOM_DEFAULT, 1)
assert(#moves == 3 and moves[1].dimension == 1, "Dimension-only entry was ignored")
actors[2][1].Position = vector(360, 120) -- Read the leader at arrival, not at departure.
actors[1][2] = { Position = vector(40, 120), Size = 20 }
complete()
assert(actors[1][2].Position.X == 360 and actors[1][2].Velocity.X == 0)
assert(actors[0][1].Position.X == 360, "Gather landed at a stale leader position")

-- A new departure during a partially completed batch replaces the old target.
for _, owner in ipairs({ 0, 1 }) do
    setup(allGatherFlag)
    starts(0, 85)
    arrive(1)
    rules.step()
    starts(owner, 86)
    assert(#moves == 6 and not queued[owner], "An exit during gathering was swallowed")
    for slot = 0, 3 do
        assert(slot == owner or queued[slot].index == 86, "Old destination survived retargeting")
    end
    complete()
    assert(#moves == 6 and not next(queued))
end
setup(allGatherFlag)
starts(0, 85)
arrive(1)
starts(0, 86) -- Leader exits in the same observation as an automatic arrival.
assert(#moves == 6 and queued[1].index == 86 and queued[2].index == 86)
complete()

setup(allGatherFlag)
info.connected = 7
enter(0, 85)
starts(1, 86)
assert(#moves == 2 and queued[1].index == 85 and queued[2].index == 85 and not queued[3])
complete()
assert(not next(queued), "Simultaneous exits bounced players between rooms")

setup(allGatherFlag)
queued[1] = { slot = 1, index = -1, dimension = 0 }
starts(0, 85)
arrive(1, types.ROOM_DEVIL)
arrive(2)
arrive(3)
rules.step()
assert(#moves == 4 and queued[1].index == 85, "An in-flight card broke all-room gathering")
complete()
assert(#moves == 4 and not next(queued))

for _, change in ipairs({
    function()
        info.connected = 14
    end,
    function()
        info.nowMs = info.nowMs + 3000
    end,
    function()
        info.roomOptions = 0
    end,
    function()
        info.ready = 0
    end,
    function()
        info.active = 0
    end,
    function()
        allowed = false
    end,
}) do
    setup(allGatherFlag)
    starts(0, 85)
    change()
    rules.step()
    assert(not next(queued), "Invalid all-room gather retained a request")
end
for _, change in ipairs({
    function()
        info.worldEpoch = info.worldEpoch + 1
    end,
    function()
        info.runId = info.runId .. "+"
    end,
    function()
        info.authority = 0
    end,
}) do
    setup(allGatherFlag)
    starts(0, 85)
    change()
    queued = {}
    local count = #cancelled
    rules.step()
    assert(#cancelled == count and #moves == 3, "Old gathering crossed a lifecycle boundary")
end
setup(allGatherFlag)
info.connected = 14
rules.step()
enter(0, 85)
info.connected = 15
rules.step()
assert(#moves == 0, "Reconnection was treated as a departure")
info.worldEpoch = info.worldEpoch + 1
enter(1, 85)
rules.step()
assert(#moves == 0, "Restored floor positions caused gathering")
starts(1, 86)
assert(#moves == 3, "All-room gathering did not resume on the new floor")
setup(0)
starts(0, 85)
info.roomOptions = allGatherFlag
rules.step()
assert(#moves == 0, "Enabling all-room gathering replayed old departures")
setup(allGatherFlag)
info.authority = 0
starts(1, 85)
assert(#moves == 0, "Replica ran all-room gathering")
print("PASS room gathering: special/all rooms, safe landing, repeated exits and lifecycle")
