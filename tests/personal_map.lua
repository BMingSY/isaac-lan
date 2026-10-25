local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local Map = fields.map
local rooms, positions = {}, { [0] = 0, [1] = 168 }
for _, index in ipairs({ 0, 1, 84, 167, 168 }) do
    rooms[#rooms + 1] = {
        Data = {},
        SafeGridIndex = index,
        ListIndex = #rooms,
        DisplayFlags = 7,
        VisitedCount = 4,
    }
end
local function byIndex(index, dimension)
    for _, room in ipairs(rooms) do
        if room.SafeGridIndex == index and dimension == 0 then
            return room
        end
    end
end
local current, fail, refreshes = nil, false, 0
local mapEffects, everything = {}, false
local function readonly(room)
    return setmetatable({}, {
        __index = room,
        __newindex = function()
            error("Room list and current descriptors are read-only")
        end,
    })
end
local level = {
    GetStateFlag = function(_, flag)
        return mapEffects[flag] or false
    end,
    SetStateFlag = function(_, flag, value)
        mapEffects[flag] = value
    end,
    GetCanSeeEverything = function()
        return everything
    end,
    SetCanSeeEverything = function(_, value)
        everything = value
    end,
    GetRooms = function()
        return {
            Size = #rooms,
            Get = function(_, i)
                return readonly(rooms[i + 1])
            end,
        }
    end,
    GetRoomByIdx = function(_, index, dimension)
        return byIndex(index, dimension or 0)
    end,
    GetCurrentRoomDesc = function()
        return readonly(byIndex(positions[current], 0))
    end,
    GetCurrentRoomIndex = function()
        return positions[current]
    end,
    UpdateVisibility = function()
        if fail then
            error("native visibility failed")
        end
        for _, room in ipairs(rooms) do
            if
                everything
                or mapEffects[10]
                or room.VisitedCount > 0
                or math.abs(room.SafeGridIndex - positions[current]) == 1
            then
                room.DisplayFlags = 7
            end
        end
    end,
}
local visibility = dofile(root .. "/src/bridge/sync/map_visibility.lua")({
    fields = fields,
    levelFlags = {
        STATE_COMPASS_EFFECT = 7,
        STATE_MAP_EFFECT = 8,
        STATE_BLUE_MAP_EFFECT = 9,
        STATE_FULL_MAP_EFFECT = 10,
    },
    game = function()
        return {
            GetLevel = function()
                return level
            end,
        }
    end,
    native = {
        rooms_with_player = function(slot, fn, actorOnly)
            assert(actorOnly == 1)
            current = slot
            fn()
            current = nil
            return true
        end,
        map_refresh = function()
            refreshes = refreshes + 1
            return true
        end,
    },
})
visibility.observe(0)
visibility.observe(1)
local map = {}
for _, room in ipairs(rooms) do
    assert(room.DisplayFlags == 7 and room.VisitedCount == 4, "Observation changed authority state")
    map[#map + 1] = {
        [Map.index] = room.SafeGridIndex,
        [Map.display] = 7,
        [Map.visited] = 4,
        [Map.clear] = false,
        [Map.clearCount] = 0,
        [Map.flags] = 0,
        [Map.dimension] = 0,
        [Map.pickups] = "pickups",
        [Map.layout] = "layout",
    }
end
local first, second = visibility.project(map, 0), visibility.project(map, 1)
assert(first[1][Map.display] == 7 and first[5][Map.display] == 0)
assert(second[1][Map.display] == 0 and second[5][Map.display] == 7)
assert(map[5][Map.display] == 7 and first[5][Map.layout] == "layout")
positions[0] = 84
visibility.observe(0)
assert(visibility.project(map, 0)[3][Map.visited] == 1)
assert(visibility.project(map, 1)[3][Map.visited] == 0)
visibility.present(0, true)
assert(rooms[5].DisplayFlags == 0)
visibility.present(0, false)
assert(rooms[5].DisplayFlags == 7 and rooms[5].VisitedCount == 4 and refreshes == 2)
visibility.present(0, true, true)
assert(rooms[5].VisitedCount == 4, "Native gameplay must retain authoritative visit counts")
mapEffects[10], everything = true, true
rooms[5].DisplayFlags = 7
visibility.present(0, false, true)
assert(not mapEffects[10] and not everything, "Player mapping effects leaked to shared state")
visibility.observe(0)
visibility.observe(1)
assert(visibility.project(map, 0)[4][Map.display] == 7)
assert(
    visibility.project(map, 1)[3][Map.display] == 0,
    "Map effects were shared with another owner"
)
visibility.present(0, true)
assert(everything)
visibility.present(0, false)
assert(not everything)
fail = true
assert(not pcall(visibility.observe, 0))
assert(
    rooms[1].DisplayFlags == 7 and rooms[1].VisitedCount == 4,
    "Failure leaked borrowed map flags"
)
visibility.reset()
assert(visibility.project(map, 0)[1][Map.display] == 0, "New floor retained old discovery")
print("personal map projection and restoration tests passed")
