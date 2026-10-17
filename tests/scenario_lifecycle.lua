local root = assert(arg[1])
local createScenario = dofile(root .. "/tests/support/scenario.lua")
local registered, removed, releases = {}, {}, 0
local owner, foreign = {}, {}
Isaac = {
    AddCallback = function(who, id, callback)
        registered[#registered + 1] = { who, id, callback }
    end,
    RemoveCallback = function(who, id, callback)
        removed[#removed + 1] = { who, id, callback }
    end,
}
_IsaacLan = {
    test_gamepad = function(buttons)
        assert(buttons == 0)
        releases = releases + 1
    end,
}
_IsaacLanTest = { host = true, port = "1234" }
local originalOptions, originalAdd, originalRemove =
    _IsaacLanTest, Isaac.AddCallback, Isaac.RemoveCallback
local active, complete, calls, cleanups = false, false, 0, 0
local callback = function()
    assert(_IsaacLanTest.route == "first")
    calls = calls + 1
end
local scenario = createScenario(function()
    _IsaacLanTest.route = "first"
    Isaac.AddCallback(owner, 1, callback)
    return {
        done = function()
            return complete
        end,
        cleanup = function()
            assert(_IsaacLanTest.route == "first")
            cleanups = cleanups + 1
        end,
    }
end, function()
    return active
end)
assert(_IsaacLanTest == originalOptions and _IsaacLanTest.route == nil)
assert(Isaac.AddCallback == originalAdd and Isaac.RemoveCallback == originalRemove)
assert(not scenario.done())
registered[1][3]()
assert(calls == 0)
active = true
registered[1][3]()
assert(calls == 1)
scenario.call(function()
    Isaac.AddCallback(owner, 2, callback)
    Isaac.AddCallback(foreign, 3, callback)
    Isaac.RemoveCallback(owner, 1, callback)
end)
assert(removed[1][3] == registered[1][3], "Explicit removal must target the wrapper")
local ok, message = pcall(scenario.call, function()
    error("injected execution failure")
end)
assert(not ok and message:find("injected execution failure", 1, true))
assert(_IsaacLanTest == originalOptions and Isaac.AddCallback == originalAdd)
complete = true
assert(scenario.done())
scenario.cleanup()
scenario.cleanup()
assert(cleanups == 1 and releases == 1 and #removed == 2)
assert(removed[2][1] == owner and removed[2][2] == 2, "Foreign callbacks must survive")
registered[2][3]()
assert(calls == 1, "Retained callbacks must be inert after cleanup")

local before = #removed
ok = pcall(createScenario, function()
    Isaac.AddCallback(owner, 4, callback)
    error("load failed")
end)
assert(not ok and #removed == before + 1 and releases == 2)
assert(Isaac.AddCallback == originalAdd and _IsaacLanTest == originalOptions)
local failing = createScenario(function()
    assert(_IsaacLanTest.route == nil, "Scenario options leaked")
    Isaac.AddCallback(owner, 5, callback)
    return {
        done = function()
            return true
        end,
        cleanup = function()
            error("cleanup failed")
        end,
    }
end)
ok, message = pcall(failing.cleanup)
assert(not ok and message:find("cleanup failed", 1, true))
assert(
    #removed == before + 2 and releases == 3,
    "A failed cleanup must still release callbacks/input"
)
failing.cleanup()
assert(releases == 3)
print("PASS scenario ownership, options, callback removal, partial failure and idempotent cleanup")
