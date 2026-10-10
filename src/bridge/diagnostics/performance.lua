-- Instrument existing operations without changing their values or errors.
return function(native, clock)
    local active = native.diagnostics_enabled and native.diagnostics_enabled()
    local profile = {}
    local sampledAt = -math.huge
    function profile.wrap(name, fn)
        if not active then
            return fn
        end
        return function(...)
            local start = clock()
            local result = table.pack(fn(...))
            native.diagnostics_sample(name, clock() - start)
            return table.unpack(result, 1, result.n)
        end
    end
    function profile.counter(name, value)
        if active then
            native.diagnostics_counter(name, value)
        end
    end
    function profile.resources()
        if active then
            local now = clock()
            if now - sampledAt >= 1000 then
                sampledAt = now
                native.diagnostics_counter(
                    "lua_heap_bytes",
                    math.floor(collectgarbage("count") * 1024)
                )
            end
        end
    end
    return profile
end
