-- Exercise shared room capture with separate rooms, dimensions and floor reuse.
local root = assert(arg[1])
local active, calls = 0, 0
local entity = {
    Type = 10,
    Exists = function()
        return true
    end,
}
local room = {
    GetGridSize = function()
        return 0
    end,
    IsClear = function()
        return false
    end,
    GetFrameCount = function()
        return calls
    end,
}
Game = function()
    return {
        GetRoom = function()
            return room
        end,
    }
end
Isaac = {
    GetRoomEntities = function()
        return { entity }
    end,
}
local native = {
    rooms_with_player = function(slot, fn)
        active = slot
        calls = calls + 1
        fn()
        return true
    end,
    music_state = function()
        return "music"
    end,
    room_layout = function()
        return "layout"
    end,
}
local capture = assert(loadfile(root .. "/src/bridge/sync/room.lua"))()(native, function()
    return { active }
end, function()
    error("No grids")
end, {
    capture = function()
        return "return"
    end,
})
local one = capture(1, 10, 0, { dimension = 0, index = 84 })
assert(one == capture(2, 10, 0, { dimension = 0, index = 84 }) and calls == 1)
assert(one[3][1][1] == 1)
assert(capture(2, 10, 0, { dimension = 0, index = 85 }) ~= one and calls == 2)
assert(capture(3, 10, 0, { dimension = 1, index = 84 }) ~= one and calls == 3)
local nextTick = capture(1, 11, 0, { dimension = 0, index = 84 })
assert(nextTick ~= one and calls == 4)
assert(capture(2, 11, 0, { dimension = 0, index = 84 }) == nextTick and calls == 4)
assert(capture(1, 11, 1, { dimension = 0, index = 84 }) ~= nextTick and calls == 5)
local fresh = assert(loadfile(root .. "/src/bridge/sync/room.lua"))()(native, function()
    return { active }
end, function()
    error("No grids")
end, {
    capture = function()
        return "return"
    end,
})
assert(fresh(1, 11, 1, { dimension = 0, index = 84 }) ~= nextTick and calls == 6)
print("PASS room views capture once per room/tick and clear on tick/floor changes")
