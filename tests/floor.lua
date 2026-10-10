local root = assert(arg[1])
local nativeReady, stage, stageType, changes = true, 6, 4, 0
local native = {
    rooms_ready = function()
        return nativeReady
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
        stage, stageType, changes = s, t, changes + 1
    end,
}
local floor = dofile(root .. "/src/bridge/runtime/floor.lua")(
    native,
    dofile(root .. "/src/bridge/compat/routes/home.lua")
)
assert(floor.ready(level, 7, 6, 4))
-- A new Ascent snapshot can arrive before its reliable native transition.
assert(not floor.ready(level, 8, 6, 0))
assert(stage == 6 and stageType == 4 and changes == 0)
assert(floor.begin(8) and not floor.begin(8) and not floor.begin(7))
nativeReady = false
assert(floor.waiting() and not floor.ready(level, 8, 6, 0))
stage, stageType, nativeReady = 6, 0, true
assert(floor.ready(level, 8, 6, 0) and not floor.waiting())
assert(not floor.ready(level, 7, 6, 4))
assert(floor.begin(9))
stage, stageType = 4, 4
assert(floor.ready(level, 9, 4, 4))
-- Wrong native generation remains a visible error, rather than being hidden.
assert(not pcall(floor.ready, level, 9, 4, 0))
floor.reset()
stage, stageType = 13, 0
assert(floor.ready(level, 20, 13, 0))
assert(floor.ready(level, 20, 13, 1) and stageType == 1 and changes == 1)
assert(floor.ready(level, 20, 13, 1) and changes == 1)
assert(not floor.ready(level, 21, 13, 1))
print("PASS reliable Ascent floor barrier and in-place Home night")
