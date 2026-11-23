return function(native)
    if not native.crime_view then
        return
    end
    local function snapshot()
        local state = native.crime_view()
        assert(type(state) == "string", "Crime mode view is unavailable")
        return state
    end
    local function apply(value)
        assert(type(value) == "string" and native.crime_view(value), "Invalid crime mode view")
    end
    return { snapshot = snapshot, apply = apply }
end
