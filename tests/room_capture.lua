-- Exercise shared room capture with separate rooms, dimensions and floor reuse.
local root = assert(arg[1])
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local active, calls = 0, 0
local current = { X = 0, Y = 1 }
local entity = {
    Type = 10,
    Exists = function()
        return true
    end,
}
local room = {
    GetWaterCurrent = function()
        return current
    end,
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
    room_rails = function()
        return string.rep(string.char(active), 448)
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
}, enums.EntityType)
local one = capture(1, 10, 0, { dimension = 0, index = 84 })
assert(one == capture(2, 10, 0, { dimension = 0, index = 84 }) and calls == 1)
assert(one[3][1][1] == 1)
assert(one[8][1] == 0 and one[8][2] == 1)
assert(one[9] == string.rep("\1", 448))
assert(#one == 9, "Current and rails must occupy distinct room fields")
assert(capture(2, 10, 0, { dimension = 0, index = 85 }) ~= one and calls == 2)
assert(capture(3, 10, 0, { dimension = 1, index = 84 }) ~= one and calls == 3)
current.Y = 0
local nextTick = capture(1, 11, 0, { dimension = 0, index = 84 })
assert(nextTick[8][2] == 0 and one[8][2] == 1, "Room current view is mutable/stale")
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
}, enums.EntityType)
assert(fresh(1, 11, 1, { dimension = 0, index = 84 }) ~= nextTick and calls == 6)

-- Native room ambience survives both reconciliation passes and never enters
-- the snapshot. A real projectile still uses normal authority ownership.
local spray = { Type = 1000, Exists = entity.Exists }
local objects, captures, reclaimed = { spray, entity }, 0, 0
local function localEffect(e)
    return e == spray
end
Isaac.GetRoomEntities = function()
    return objects
end
local filtered = dofile(root .. "/src/bridge/sync/room.lua")(native, function(e)
    assert(e == entity, "Local ambience was serialized")
    captures = captures + 1
    return { 1, e.Type, 0, 0 }
end, function()
    error("No grids")
end, {
    capture = function()
        return "return"
    end,
}, enums.EntityType, localEffect)
entity.Variant, entity.SubType = 0, 0
function entity:GetData()
    return {}
end
for tick = 1, 3 do
    local value = filtered(1, tick, tick == 3 and 1 or 0, { dimension = 0, index = tick })
    assert(#value[3] == 1 and value[3][1][2] == 10)
    dofile(root .. "/src/bridge/sync/entities.lua")(enums.EntityType, enums.PickupVariant)(
        value[3],
        {
            ref = function(id)
                return id == 1 and entity or nil
            end,
            key = function(e)
                return e
            end,
            entities = function()
                return objects
            end,
            localEffect = localEffect,
            discard = function()
                error("Retained ambience/authority entity was discarded")
            end,
            reclaim = function()
                reclaimed = reclaimed + 1
            end,
            spawn = function()
                error("Existing authority entity was respawned")
            end,
            apply = function() end,
        }
    )
end
assert(captures == 3 and reclaimed == 0, "Ambient particles forced native room cleanup")
print("PASS room views capture once per room/tick and clear on tick/floor changes")
