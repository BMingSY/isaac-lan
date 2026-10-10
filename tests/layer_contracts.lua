local root = assert(arg[1])
local function module(name)
    return dofile(root .. "/src/bridge/" .. name .. ".lua")
end
local codec, schema = module("sync/codec"), module("sync/world_schema")
-- Shared curses and Greed waves extend the portable world view to schema 12.
local tuple = { 12, 42, 80, 6, 4, 3, {}, {}, {}, 1, {}, {}, "progress", 7, "events", {}, 5, false }
local view = schema.unpack(tuple, 42)
assert(view.slot == 1 and view.stage == 6 and view.epoch == 7 and view.curses == 5)
assert(codec.encode(schema.pack(view)) == codec.encode(tuple))
assert(not pcall(schema.unpack, tuple, 41))
local malformed = { table.unpack(tuple) }
malformed[1] = 11
assert(not pcall(schema.unpack, malformed, 42))
malformed[1], malformed[19] = 12, true
assert(not pcall(schema.unpack, malformed, 42))
view.room = nil
assert(not pcall(schema.pack, view))

local order, ready, stage, stageType = {}, true, 6, 4
local native = {
    rooms_ready = function()
        return ready
    end,
    rooms_begin_floor = function(same, animation)
        order[#order + 1] = "floor:" .. same .. ":" .. animation
        return true
    end,
    rewind_begin = function(bytes)
        assert(bytes == "native checkpoint")
        order[#order + 1] = "rewind"
        return true
    end,
    r_key_begin = function()
        order[#order + 1] = "r-key"
        return true
    end,
    rooms_begin_cinematic = function()
        order[#order + 1] = "cinematic"
        return true
    end,
}
local level = {
    GetStage = function()
        return stage
    end,
    GetStageType = function()
        return stageType
    end,
    SetStage = function(_, s, t)
        stage, stageType = s, t
        order[#order + 1] = "set-stage"
    end,
}
local home = module("compat/routes/home")
local floor = module("runtime/floor")(native, home)
local adapters = { home, module("compat/items/hourglass"), module("compat/items/r_key") }
local compatibility = module("compat/transitions")(adapters)
assert(not pcall(module("compat/transitions"), { home, home }))
local begin = module("runtime/transitions")(native, floor, compatibility, function()
    return level
end, function()
    order[#order + 1] = "reset"
end)
assert(begin(8, 4, 4, 0, false))
assert(table.concat(order, ",") == "reset,set-stage,floor:0:0")
assert(not begin(8, 1, 0, 0, false, false, true) and #order == 3)
assert(not begin(7, 1, 0, 0, false) and #order == 3)
ready = false
assert(floor.waiting() and not floor.ready(level, 8, 4, 4))
ready = true
assert(floor.ready(level, 8, 4, 4))
for index, event in ipairs({
    { "native checkpoint", false, 0, "rewind" },
    { false, true, 0, "r-key" },
    { false, false, 25, "cinematic" },
    -- Preserve the existing precedence for an event carrying overlapping flags.
    { "native checkpoint", true, 25, "cinematic" },
    { "native checkpoint", true, 0, "rewind" },
}) do
    order = {}
    assert(begin(8 + index, 1, 0, 12, true, event[1], event[2], event[3]))
    assert(table.concat(order, ",") == "reset," .. event[4])
end
native.rewind_begin = function()
    return false
end
order = {}
assert(not pcall(begin, 20, 1, 0, 12, false, "native checkpoint"))
assert(
    table.concat(order, ",") == "reset",
    "Native failure must not fall through to another operation"
)
assert(not begin(20, 1, 0, 0, false), "A failed accepted epoch must not run twice")
floor.reset()
assert(begin(1, 1, 0, 0, false), "A new run must clear the previous epoch barrier")

-- Execute the extracted render entry with no entity updates. It must still
-- decode native held input and select the local room without global unpack.
local rendered, now, statusCalls = 0, 1000, 0
local env = setmetatable({
    Vector = function(x, y)
        return {
            X = x,
            Y = y,
            Length = function()
                return 0
            end,
        }
    end,
    Isaac = {
        GetTime = function()
            return now
        end,
    },
    Game = function()
        return {
            GetRoom = function()
                return {
                    IsMirrorWorld = function()
                        return false
                    end,
                }
            end,
        }
    end,
    _IsaacLanStatus = function()
        statusCalls = statusCalls + 1
        return { pause = 0, slot = 1 }
    end,
}, { __index = _G })
local motion = assert(loadfile(root .. "/src/bridge/presentation/motion.lua", "t", env))()({
    rooms_with_player = function(slot, fn)
        assert(slot == 1)
        fn()
        rendered = rendered + 1
        return true
    end,
}, {}, {
    vector = env.Vector,
    player = function()
        error("An empty view must not access actors")
    end,
    clock = env.Isaac.GetTime,
    status = env._IsaacLanStatus,
    room = function()
        return env.Game():GetRoom()
    end,
})
local input = string.pack(">I2I2I2I2", 0, 65535, 0, 0)
motion.present(input, 1, {}, {}, function() end, -1)
assert(rendered == 0 and statusCalls == 0)
motion.present(input, 1, {}, {}, function() end, 1)
assert(rendered == 1 and statusCalls == 1)
now = 1016
motion.present(input, 2, {}, {}, function() end, 1)
assert(rendered == 2)
assert(not pcall(motion.present, "short", 2, {}, {}, function() end, 1))
motion.reset()

-- Consolidated native fixtures must initialize in the ordinary game sandbox.
-- File exports are optional diagnostics; they cannot gate movement assertions.
for _, name in ipairs({ "state_motion", "state_floor_items", "state_mod_integrations" }) do
    local frame, gate = function() end, function() end
    local sandbox = setmetatable({
        io = false,
        _IsaacLanTest = { host = false, port = "30320" },
        _IsaacLanFrame = frame,
        _IsaacLan = { net_gate = gate, api_send = function() end, api_receive = function() end },
        _IsaacLanModules = { ["api/codec"] = module("api/codec") },
        IsaacLAN = {
            RegisterMod = function()
                return { Unregister = function() end }
            end,
        },
        Isaac = { AddCallback = function() end },
        ModCallbacks = { MC_POST_RENDER = 1 },
    }, { __index = _G })
    assert(loadfile(root .. "/tests/" .. name .. ".lua", "t", sandbox))()
    assert(sandbox._IsaacLanFrame ~= frame and sandbox._IsaacLan.net_gate ~= gate)
end
print("PASS stable world wire fields and coordinated compatibility transitions")
