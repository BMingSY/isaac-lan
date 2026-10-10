-- Ordered, built-in rules. Adapters never own the epoch barrier or cleanup.
return function(adapters)
    local ids = {}
    for _, adapter in ipairs(adapters) do
        assert(type(adapter.id) == "string" and not ids[adapter.id], "Duplicate transition adapter")
        assert(type(adapter.matches) == "function" and type(adapter.begin) == "function")
        ids[adapter.id] = true
    end
    return {
        begin = function(native, event)
            for _, adapter in ipairs(adapters) do
                if adapter.matches(event) then
                    adapter.begin(native, event)
                    return adapter.id
                end
            end
        end,
    }
end
