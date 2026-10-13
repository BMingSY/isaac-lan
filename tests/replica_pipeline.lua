local root = assert(arg[1])
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local schema = dofile(root .. "/src/bridge/sync/world_schema.lua")
local trace, shared, scope, fail, waiting, epoch, roomIndex = {}, {}, nil, nil, false, 1, 84
local function record(name)
    trace[#trace + 1] = name
    assert(fail ~= name, "failure at " .. name)
    return true
end
local noop = function() end
local descriptor = { Data = true }
local level = {
    GetRoomByIdx = function()
        return descriptor
    end,
}
local room = {
    SetClear = function()
        record("clear")
    end,
}
local player = {
    Type = 1,
    ControllerIndex = 2,
    IsCoopGhost = function()
        return false
    end,
}
player.GetPlayerType = function()
    return 0
end
player.ToPlayer = function()
    return player
end
local vector
vector = function(value)
    return setmetatable({ value[1], value[2] }, {
        __mul = function(a, b)
            return vector({ a[1] * b, a[2] * b })
        end,
    })
end
local replica = dofile(root .. "/src/bridge/sync/replica.lua")({
    encode = codec.encode,
    decode = codec.decode,
    schema = schema,
    game = function()
        return {
            GetLevel = function()
                return level
            end,
            GetRoom = function()
                return room
            end,
        }
    end,
    now = function()
        return 1
    end,
    floor = {
        waiting = function()
            return waiting
        end,
        ready = function(_, incoming)
            return incoming == epoch
        end,
    },
    performance = { resources = noop, counter = noop },
    entityCodec = {
        apply = function()
            record("actor-state")
        end,
    },
    vec = vector,
    playerType = 1,
    pointer = function(p)
        return { Ref = p }
    end,
    prediction = {
        new = function()
            return {
                confirm = function()
                    record("confirm")
                end,
            }
        end,
    },
    forms = {
        resolve = function()
            record("resolve")
            return player
        end,
        prune = function()
            record("prune")
        end,
    },
    applyInventory = function()
        assert(scope == "actor", "Inventory escaped the actor's room")
        record("inventory")
        shared = { curses = -1, pills = -1, deals = -1, greed = -1 }
    end,
    actors = {
        apply = function()
            record("actor-view")
        end,
        reset = noop,
    },
    motion = {
        reset = function()
            record("motion-reset")
        end,
        present = function(_, _, actors, motion, _, tick)
            return tick, actors, motion
        end,
    },
    poop = { apply = noop },
    craftingBag = { apply = noop },
    crawlspace = {
        apply = function()
            record("crawlspace")
        end,
    },
    pills = {
        apply = function(value)
            record("pills")
            shared.pills = value
        end,
    },
    curses = {
        apply = function(_, value)
            record("curses")
            shared.curses = value
            return true
        end,
    },
    greed = {
        apply = function(value)
            record("greed")
            shared.greed = value
        end,
    },
    deals = {
        apply = function(value)
            record("deals")
            shared.deals = value
        end,
    },
    entitiesApply = function()
        assert(scope == "room")
        record("entities")
    end,
    gridsApply = function()
        record("grids")
    end,
    audio = {
        apply = function()
            assert(scope == "room")
            record("audio")
        end,
    },
    items = {
        apply = function()
            record("items")
        end,
    },
    native = {
        room_layout = function()
            return record("layout")
        end,
        rooms_sync = function()
            return record("locations")
        end,
        rooms_positions = function()
            return { ["1"] = { dimension = 0, index = roomIndex } }
        end,
        state_clock = function()
            record("clock")
        end,
        net_progress = function()
            return record("progress")
        end,
        rooms_with_player = function(slot, fn, actorOnly)
            assert(slot == 1 and not scope)
            scope = actorOnly and "actor" or "room"
            local ok, reason = pcall(fn)
            scope = nil
            assert(ok, reason)
            return true
        end,
        map_pickups = function()
            record("map")
            assert(
                shared.curses == 7
                    and shared.pills == "pills"
                    and shared.greed == 2
                    and shared.deals[1] == 0.5,
                "Map/HUD observed inventory side effects instead of host state"
            )
            return true, true
        end,
        door_slot = function()
            return true
        end,
        music_state = function()
            return record("music")
        end,
        map_refresh = function()
            return record("map-refresh")
        end,
        presentation_events = function()
            return record("events")
        end,
    },
})
local function packet(tick, nextEpoch)
    return codec.encode(schema.pack({
        tick = tick,
        frame = tick * 2,
        stage = 1,
        stageType = 0,
        connected = 3,
        locations = { { 1, 0, roomIndex, 10, 20 } },
        map = { { roomIndex, 1, 1, true, 1, 0, 0, "pickups", "layout" } },
        actors = {
            {
                0,
                2,
                { 123, 1, 0, 0, 1, { 10, 20 }, { 0, 0 } },
                { 0, {}, 0, {}, 0, {}, 0, {}, false },
                {},
                false,
                false,
                false,
            },
        },
        slot = 1,
        room = { true, 0, {}, {}, "music", "layout", false },
        sound = {},
        progress = "progress",
        epoch = nextEpoch or epoch,
        presentation = "events",
        items = {},
        curses = 7,
        greed = 2,
        deals = { 0.5, 0.25 },
        pills = "pills",
    }))
end
local expected =
    "layout,layout,locations,motion-reset,clock,progress,resolve,inventory,actor-state,actor-view,prune,pills,curses,greed,deals,map,crawlspace,entities,grids,clear,music,map-refresh,confirm,audio,events,items"
assert(replica.apply(packet(1), 1, 0))
assert(table.concat(trace, ",") == expected)
local tick, actors, motion = replica.present("", 0)
assert(tick == 1 and #actors == 1 and motion[123], "Room entry lost the arriving actor")
trace = {}
assert(replica.apply(packet(1), 1, 0))
assert(table.concat(trace, ",") == expected:gsub("motion%-reset,", ""))
trace = {}
assert(not replica.apply(packet(2, 2), 2, 0) and #trace == 0)
waiting = true
assert(not replica.apply("not even decoded while waiting", 2, 0) and #trace == 0)
waiting = false
assert(
    not pcall(replica.apply, packet(2), 3, 0) and #trace == 0,
    "Schema failure mutated native state"
)
-- A failure after native mutation must not commit a new tick or drain later
-- presentation queues. Native rollback is deliberately outside this contract.
fail = "music"
assert(not pcall(replica.apply, packet(2), 2, 0))
assert(trace[#trace] == "music" and not scope)
assert(replica.present("", 0) == 1)
fail, trace, roomIndex = nil, {}, 85
assert(replica.apply(packet(3), 3, 0))
assert(table.concat(trace, ",") == expected)
replica.resetView()
epoch, roomIndex = 2, 84
assert(not replica.apply(packet(4, 1), 4, 0))
assert(replica.apply(packet(4), 4, 0))
replica.reset()
local resetTick, resetActors, resetMotion = replica.present("", 0)
assert(resetTick == -1 and #resetActors == 0 and next(resetMotion) == nil)
print("PASS ordered replica restore, barriers, repeat/room/floor/reset and failure before commit")
