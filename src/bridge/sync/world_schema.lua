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
}
local version = 11
return {
    VERSION = version,
    pack = function(view)
        local values = { version }
        for index = 2, #names do
            local value = view[names[index]]
            assert(value ~= nil, "Missing world field: " .. names[index])
            values[index] = value
        end
        return values
    end,
    unpack = function(values, tick)
        assert(
            type(values) == "table"
                and #values == #names
                and values[1] == version
                and values[2] == tick,
            "Invalid state schema"
        )
        local view = {}
        for index, name in ipairs(names) do
            view[name] = values[index]
        end
        return view
    end,
}
