local root = assert(arg[1])
local factory =
    dofile(root .. "/src/bridge/sync/capture.lua")(dofile(root .. "/src/bridge/sync/fields.lua"))
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local schema = dofile(root .. "/src/bridge/sync/world_schema.lua")
local epoch, revision, calls = 1, 1, {}
local function count(name)
    calls[name] = (calls[name] or 0) + 1
end
local positions = {
    ["0"] = { index = 84, dimension = 0 },
    ["1"] = { index = 84, dimension = 0 },
    ["2"] = { index = 85, dimension = 1 },
}
local players = {}
for index = 0, 2 do
    players[index] = {
        ControllerIndex = index + 1,
        Position = { X = index * 10, Y = 20 },
        GetSprite = function()
            return index
        end,
        GetBabySkin = function()
            return -1
        end,
    }
end
local descriptor = {
    SafeGridIndex = 84,
    ListIndex = 0,
    Data = true,
    DisplayFlags = 1,
    VisitedCount = 1,
    Clear = false,
    ClearCount = 0,
    Flags = 0,
}
local level = {
    GetStage = function()
        return revision
    end,
    GetStageType = function()
        return 0
    end,
    GetRooms = function()
        count("map")
        return {
            Size = 1,
            Get = function()
                return descriptor
            end,
        }
    end,
    GetRoomByIdx = function()
        return descriptor
    end,
}
local function shared(name)
    return {
        capture = function()
            count(name)
            return revision
        end,
    }
end
local deps = {
    encode = codec.encode,
    schema = schema,
    game = function()
        return {
            GetLevel = function()
                return level
            end,
            GetNumPlayers = function()
                return 3
            end,
            GetFrameCount = function()
                return revision * 2
            end,
        }
    end,
    player = function(index)
        return assert(players[index])
    end,
    entity = function(player, full)
        count("entity")
        return { player.ControllerIndex, full == nil, revision }
    end,
    inventory = function(player)
        count("inventory")
        return { player.ControllerIndex, revision }
    end,
    sprite = function(value)
        return { value }
    end,
    poop = shared("poop"),
    craftingBag = shared("bag"),
    temporaryEffects = {
        capture = function()
            count("effects")
            return { revision, revision + 1, 0 }
        end,
    },
    curses = shared("curses"),
    greed = shared("greed"),
    deals = shared("deals"),
    pills = shared("pills"),
    glitched = shared("glitched"),
    reconcileShared = function()
        count("reconcile")
    end,
    audio = {
        capture = function(slot)
            count("audio:" .. slot)
            return "sound:" .. slot
        end,
    },
    items = {
        capture = function(slot)
            count("items:" .. slot)
            return { slot }
        end,
    },
    roomFactory = function()
        count("room-cache")
        return function(_, _, _, at)
            return { at.dimension, at.index, revision }
        end
    end,
    native = {
        net_floor_epoch = function()
            return epoch
        end,
        rooms_positions = function()
            count("positions")
            return positions
        end,
        rooms_heads = function()
            count("heads")
            return { ["0"] = 0, ["1"] = 1, ["2"] = 2 }
        end,
        actor_sprites = function(index)
            return { index }
        end,
        actor_pose = function()
            return "pose"
        end,
        rooms_connected = function()
            count("connected")
            return 7
        end,
        map_pickups = function()
            count("pickups")
            return "pickups:" .. revision
        end,
        room_layout = function()
            count("layout")
            return "layout:" .. revision
        end,
        net_progress = function()
            count("progress")
            return "progress:" .. revision
        end,
        presentation_events = function(slot)
            count("events:" .. slot)
            return "events:" .. slot
        end,
    },
}
local capture = factory(deps)
local function view(slot, tick)
    local bytes = capture.capture(slot, tick)
    local result = schema.unpack(codec.decode(bytes), tick)
    assert(codec.encode(schema.pack(result)) == bytes, "Cached fragments changed wire encoding")
    return result, bytes
end
local first = view(0, 10)
local second = view(1, 10)
local third = view(2, 10)
for _, name in ipairs({
    "map",
    "positions",
    "heads",
    "connected",
    "pickups",
    "layout",
    "progress",
    "curses",
    "greed",
    "deals",
    "pills",
    "glitched",
    "reconcile",
}) do
    assert(calls[name] == 1, name .. " was recaptured for another peer")
end
assert(calls.inventory == 3 and calls.poop == 3 and calls.bag == 3 and calls.effects == 3)
assert(table.concat(first.actors[1][9], ",") == "1,2,0")
assert(codec.encode(first.actors[1][9]) == codec.encode(third.actors[1][9]))
assert(calls.entity == 6, "Base/visual actor tuples were not reused across views")
for slot = 0, 2 do
    assert(
        calls["audio:" .. slot] == 1
            and calls["events:" .. slot] == 1
            and calls["items:" .. slot] == 1
    )
end
assert(codec.encode(first.map) == codec.encode(second.map))
assert(first.actors[1][3][2] and not third.actors[1][3][2])
assert(not first.actors[3][3][2] and third.actors[3][3][2])
assert(first.room[2] == 84 and third.room[2] == 85)
assert(first.sound ~= second.sound and second.presentation ~= third.presentation)
-- The bytes must equal a fresh capture while the world is stable.
for slot = 0, 2 do
    local _, bytes = view(slot, 10)
    assert(factory(deps).capture(slot, 10) == bytes)
end
-- Same generation remains frozen; the next tick, floor epoch and explicit
-- new-run reset each invalidate common and actor caches independently.
revision = 2
assert(view(0, 10).stage == 1)
assert(view(0, 11).stage == 2)
epoch, revision = 2, 3
local floorView = view(0, 11)
assert(floorView.epoch == 2 and floorView.stage == 3 and floorView.actors[1][4][2] == 3)
revision = 4
capture.reset()
local resetView = view(0, 11)
assert(resetView.stage == 4 and resetView.map[1][8] == "pickups:4")
assert(first.stage == 1 and first.map[1][8] == "pickups:1", "New generation mutated an old view")
print("PASS common capture reuse, per-peer projections, wire equivalence and invalidation")
