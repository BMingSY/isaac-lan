local events = {
    SessionReady = true,
    LocalPlayersChanged = true,
    LocalRoomChanged = true,
    ViewUpdated = true,
    StateReset = true,
}
return function(bridge)
    local listeners = {}
    local lifecycle = {}
    function lifecycle.on(id, event, fn)
        assert(events[event] and type(fn) == "function", "invalid_subscription")
        local listener = { id = id, fn = fn, active = true }
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], listener)
        return function()
            listener.active = false
        end
    end
    function lifecycle.emit(event, context)
        -- Snapshot the subscription list: additions take effect on the next event.
        local callbacks = {}
        for _, listener in ipairs(listeners[event] or {}) do
            callbacks[#callbacks + 1] = listener
        end
        for _, listener in ipairs(callbacks) do
            if listener.active then
                local ok, reason = pcall(function()
                    if event == "StateReset" then
                        listener.fn(bridge.copy(context))
                    else
                        bridge.withView(function()
                            listener.fn(bridge.copy(context))
                        end)
                    end
                end)
                if not ok then
                    listener.active = false
                    bridge.log(
                        listener.id .. " event=" .. event .. " disabled=" .. tostring(reason)
                    )
                end
            end
        end
        local retained = {}
        for _, listener in ipairs(listeners[event] or {}) do
            if listener.active then
                retained[#retained + 1] = listener
            end
        end
        listeners[event] = retained
    end
    function lifecycle.remove(id)
        for _, list in pairs(listeners) do
            for _, listener in ipairs(list) do
                if listener.id == id then
                    listener.active = false
                end
            end
        end
    end
    return lifecycle
end
