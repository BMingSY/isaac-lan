local root = assert(arg[1])
local labels, rectangles = {}, 0
Vector = function(x, y)
    return { X = x, Y = y }
end
Color = function(...)
    return { ... }
end
KColor = Color
Sprite = function()
    return {
        Load = function() end,
        SetFrame = function() end,
        Render = function(_, position)
            rectangles = rectangles + 1
            assert(position.X >= 0 and position.X <= 480 and position.Y >= 0 and position.Y <= 270)
        end,
    }
end
Isaac = {
    GetScreenWidth = function()
        return 480
    end,
    GetScreenHeight = function()
        return 270
    end,
}
local font = {
    GetStringWidthUTF8 = function(_, value)
        return utf8.len(value) * 8
    end,
    DrawStringScaledUTF8 = function(_, value)
        labels[value] = true
    end,
}
local progress = dofile(root .. "/src/bridge/presentation/vote_progress.lua")()
local render = dofile(root .. "/src/bridge/presentation/animation_skip.lua")(progress)
render({ skipVotes = 0, skipMembers = 3 }, font)
render({ skipVotes = 4, skipMembers = 4 }, font)
assert(rectangles == 0, "Idle or single-player skip drew a vote indicator")
for players = 2, 4 do
    labels, rectangles = {}, 0
    render({ skipVotes = 1, skipMembers = (1 << players) - 1 }, font)
    assert(labels["跳过 1/" .. players] and labels[">>"] and rectangles > 0)
end
labels = {}
progress(5, 7, font, function() end)
assert(labels["2/3"], "Shared ring changed the restart count")
print("PASS skip and restart vote indicators: participant counts, idle, solo and screen bounds")
