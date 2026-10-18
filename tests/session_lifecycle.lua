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
        canStart = function()
            return true
        end,
        fail = effect("failed"),
        start = effect("start"),
        bindPlayers = effect("players"),
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
assert(table.concat(events, ",") == "start,players,rooms,gate,restore,save-close")
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
for _, boundary in ipairs({ "start", "players", "rooms", "gate", "restore" }) do
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
for _, boundary in ipairs({ "start", "players", "rooms", "gate", "restore" }) do
    local fail = true
    local current, trace = environment(function(name)
        if name == boundary and fail then
            error("native failure at " .. name)
        end
    end)
    local ok, reason = pcall(function()
        current.launch()
        current.gameStarted()
        current.prepare()
    end)
    assert(ok, "A startup failure must not disable frontend polling")
    assert(trace[#trace] == "failed")
    assert(current.active() and not current.ready())
    assert(not current.launch() and not current.prepare())
    current.close()
    fail = false
    assert(current.launch() and current.gameStarted() and current.prepare())
end
print("PASS startup, inline callbacks, cancellation, failures and new generations")

-- Delayed native controller enumeration must not consume the launch generation.
local available, starts = false, 0
local deferred = factory({
    canStart = function()
        return available
    end,
    start = function()
        starts = starts + 1
    end,
    bindPlayers = function() end,
    enableRooms = function() end,
    gate = function() end,
    restoreRooms = function() end,
    close = function() end,
    fail = function(reason)
        error(reason)
    end,
})
assert(not deferred.launch() and not deferred.active() and starts == 0)
available = true
assert(deferred.launch() and starts == 1 and not deferred.launch())
-- Player initialization can dispatch native callbacks. A nested prepare must
-- not spawn the same guest twice or advance readiness before its owner exists.
local nested = environment(function(name, current)
    if name == "players" then
        assert(not current.initializing() and not current.prepare())
    end
end)
assert(nested.launch() and nested.gameStarted() and nested.prepare() and nested.ready())
-- A failed Continue binding can occur synchronously inside native start. The
-- outer successful call must not overwrite that failure or enable gameplay.
local continued, continuedEvents = environment(function(name, current)
    if name == "start" then
        assert(not current.gameStarted(true))
    elseif name == "players" then
        assert(not current.initializing() and not current.prepare())
        error("restored actor is missing")
    end
end)
assert(not continued.launch() and not continued.ready() and not continued.prepare())
assert(table.concat(continuedEvents, ",") == "start,players,failed")
print("PASS delayed controllers, reentrant roster initialization and recoverable startup failure")
