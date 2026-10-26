-- Portable view fields; changing tuple layouts also changes this version.
local names = {
    "version",
    "tick",
    "frame",
    "stage",
    "stageType",
    "connected",
    "locations",
    "map",
    "actors",
    "slot",
    "room",
    "sound",
    "progress",
    "epoch",
    "presentation",
    "items",
    "curses",
    "greed",
    "deals",
    "pills",
    "glitched",
    "captured",
    "combat",
    "challenge",
}
local version = 37
local VERSION_FIELD, TICK_FIELD = 1, 2
return {
    VERSION = version,
    pack = function(view)
        local values = { [VERSION_FIELD] = version }
        for index = TICK_FIELD, #names do
            local value = view[names[index]]
            if names[index] == "captured" and value == nil then
                value = 0 -- Portable fixtures may have no monotonic clock.
            end
            if names[index] == "combat" and value == nil then
                value = string.pack(">I4", 0)
            end
            if names[index] == "challenge" and value == nil then
                value = false
            end
            assert(value ~= nil, "Missing world field: " .. names[index])
            values[index] = value
        end
        return values
    end,
    unpack = function(values, tick)
        assert(
            type(values) == "table"
                and #values == #names
                and values[VERSION_FIELD] == version
                and values[TICK_FIELD] == tick,
            "Invalid state schema"
        )
        local view = {}
        for index, name in ipairs(names) do
            view[name] = values[index]
        end
        assert(type(view.captured) == "number" and view.captured >= 0, "Invalid capture clock")
        return view
    end,
}
