local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/runtime/session.lua")
local function environment(interrupt)
    local lifecycle, events
    events = {}
    local function effect(name)
        return function()
            events[#events + 1] = name
            if interrupt then
                interrupt(name, lifecycle)
            end
        end
    end
    lifecycle = factory({
        start = effect("start"),
        enableRooms = effect("rooms"),
        gate = effect("gate"),
        restoreRooms = effect("restore"),
        close = function(preserve)
            events[#events + 1] = preserve == 1 and "save-close" or "close"
        end,
    })
    return lifecycle, events
end
local lifecycle, events = environment()
assert(not lifecycle.active() and not lifecycle.ready())
assert(not lifecycle.prepare() and not lifecycle.gameStarted())
assert(lifecycle.launch() and not lifecycle.launch())
assert(not lifecycle.ready() and not lifecycle.prepare())
assert(lifecycle.gameStarted() and not lifecycle.gameStarted())
assert(lifecycle.initializing() and lifecycle.prepare())
assert(lifecycle.ready() and not lifecycle.prepare() and not lifecycle.launch())
lifecycle.close(1)
assert(not lifecycle.active() and not lifecycle.ready())
assert(table.concat(events, ",") == "start,rooms,gate,restore,save-close")
-- Continue/rejoin uses the same gate, even when start invokes callbacks inline.
local immediate = environment(function(name, current)
    if name == "start" then
        assert(current.gameStarted() and current.prepare())
    end
end)
assert(immediate.launch() and immediate.ready())
local replace = true
local replaced = environment(function(name, current)
    if name == "restore" and replace then
        replace = false
        current.close()
        assert(current.launch())
    end
end)
assert(replaced.launch() and replaced.gameStarted() and not replaced.prepare())
assert(replaced.active() and not replaced.ready() and not replaced.initializing())
assert(replaced.gameStarted() and replaced.prepare(), "Old completion advanced the new run")
-- Cancellation at every native boundary must stop the old generation. A new
-- run can then prepare from scratch, without an old completion marking ready.
for _, boundary in ipairs({ "start", "rooms", "gate", "restore" }) do
    local cancel = true
    local current, trace = environment(function(name, session)
        if name == boundary and cancel then
            session.close()
        end
    end)
    if boundary == "start" then
        assert(not current.launch())
    else
        assert(current.launch() and current.gameStarted() and not current.prepare())
    end
    assert(not current.active() and not current.ready())
    assert(trace[#trace] == "close")
    cancel = false
    assert(current.launch() and current.gameStarted() and current.prepare() and current.ready())
end
-- Native failures propagate once and never retry partial preparation on poll.
for _, boundary in ipairs({ "start", "rooms", "gate", "restore" }) do
    local fail = true
    local current = environment(function(name)
        if name == boundary and fail then
            error("native failure at " .. name)
        end
    end)
    local ok, reason = pcall(function()
        current.launch()
        current.gameStarted()
        current.prepare()
    end)
    assert(not ok and reason:find(boundary, 1, true))
    assert(current.active() and not current.ready())
    assert(not current.launch() and not current.prepare())
    current.close()
    fail = false
    assert(current.launch() and current.gameStarted() and current.prepare())
end
print("PASS startup, inline callbacks, cancellation, failures and new generations")
