-- Synthetic wire-shaped data isolates codec CPU cost from native gameplay.
return function(root)
    local schema = dofile(root .. "/src/bridge/sync/world_schema.lua")
    local function sprite(index)
        return {
            "gfx/tears/tear.anm2",
            "RegularTear",
            index % 8,
            "",
            0,
            false,
            false,
            0.0,
            { 1.0, 1.0 },
            { 0.0, 0.0 },
            { 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0 },
            string.rep("\0", 48),
        }
    end
    local function entity(index)
        return {
            index,
            2,
            0,
            0,
            1234 + index,
            { 10.5 + index, 20.25 },
            { 0.125, -0.125 },
            { 1.0, 1.0, 3.5, true, false, 0.0, 1.0, 5.0, 0.0 },
            { -0.1, 0.0, -30.0, 0.0, 1.0, 0 },
            sprite(index),
            0,
            0,
            0,
            0,
            { 0.0, 0.0 },
            { 1.0, 1.0 },
            { 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0 },
            42,
            0,
            false,
            false,
            string.rep("\0", 16),
            false,
            false,
            0,
        }
    end
    local result = {}
    for _, load in ipairs({
        { "baseline", 1, 0 },
        { "inventory-300", 300, 0 },
        { "inventory-500", 500, 0 },
        { "tears-500", 1, 500 },
        { "combined", 300, 500 },
    }) do
        local items, entities = {}, {}
        for i = 1, load[2] do
            items[i] = { i, 1 }
        end
        for i = 1, load[3] do
            entities[i] = entity(i)
        end
        local actor = { 0, 1, entity(10000), { 0, items, { { 0, 0 } }, { 0, 0 } }, {}, false }
        local room = { true, 42, entities, {}, "music", "layout", false, { 0.0, 0.0 }, "rails" }
        local state = schema.pack({
            tick = 42,
            frame = 84,
            stage = 1,
            stageType = 0,
            connected = 3,
            locations = { { 0, 0, 84, 10.5, 20.25 }, { 1, 0, 84, 20.5, 20.25 } },
            map = {},
            actors = { actor },
            slot = 1,
            room = room,
            sound = {},
            progress = "progress",
            epoch = 1,
            presentation = "",
            items = {},
            curses = 0,
            greed = {},
            deals = { 0.0, 0.0 },
            pills = string.rep("\0", 75),
            glitched = "",
        })
        result[#result + 1] = {
            name = load[1],
            value = state,
            memo = function()
                return { [actor] = false, [room] = false }
            end,
        }
    end
    return result
end
