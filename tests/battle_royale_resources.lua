local root = assert(arg[1])
local rules = dofile(root .. "/src/bridge/compat/challenges/battle_royale_rules.lua")
local factory = dofile(root .. "/src/bridge/compat/challenges/battle_royale_resources.lua")
local enums = {
    room = {
        ROOM_DEFAULT = 1,
        ROOM_SHOP = 2,
        ROOM_TREASURE = 4,
        ROOM_BOSS = 5,
        ROOM_ARCADE = 9,
        ROOM_LIBRARY = 12,
    },
    shape = { ROOMSHAPE_1x1 = 1 },
}
local targets = { [4] = 16, [2] = 8, [12] = 4, [9] = 4 }
for seed = 1, 16 do
    local rng = seed
    local function random(low, high)
        if not high then
            low, high = 1, low
        end
        rng = (rng * 48271) % 2147483647
        return low + rng % (high - low + 1)
    end
    local rooms, candidates, original, changes = {}, {}, {}, 0
    for index = 0, 168 do
        rooms[index] = {
            GridIndex = index,
            SafeGridIndex = index,
            VisitedCount = index == 84 and 1 or 0,
            Data = { Type = 1, Shape = 1 },
        }
        if index ~= 100 and index ~= 101 then
            candidates[#candidates + 1] = index
        end
    end
    rooms[100].Data.Type, rooms[101].Data.Type = 5, 5
    local layout = {
        boss = 100,
        finalBoss = 101,
        spawns = { 0, 12, 156, 168 },
        zones = rules.plan(candidates, random),
    }
    local protected = { [84] = true, [100] = true, [101] = true, [layout.zones[4]] = true }
    for _, index in ipairs(layout.spawns) do
        protected[index] = true
    end
    for index, kind in pairs({ [20] = 4, [30] = 4, [40] = 2, [50] = 12, [60] = 9 }) do
        if not protected[index] then
            rooms[index].Data.Type, original[index] = kind, kind
        end
    end
    local function neighbors(index)
        local result = {}
        for _, delta in ipairs({ { -1, 0 }, { 0, -1 }, { 1, 0 }, { 0, 1 } }) do
            local x, y = index % 13 + delta[1], index // 13 + delta[2]
            if x >= 0 and x < 13 and y >= 0 and y < 13 then
                result[#result + 1] = y * 13 + x
            end
        end
        return result
    end
    local populate = factory({
        rules = rules,
        enums = enums,
        random = random,
        native = {
            room_connections = neighbors,
            room_special_template = function(index, kind, variant, value)
                assert(
                    not protected[index] and not original[index] and rooms[index].VisitedCount == 0
                )
                assert(
                    rooms[index].Data.Type == 1 and targets[kind] and variant == -1 and value > 0
                )
                -- Failed template selection leaves the original room intact.
                if index == 13 then
                    return false
                end
                rooms[index].Data.Type = kind
                changes = changes + 1
                return true
            end,
        },
    })
    local level = {
        GetRoomByIdx = function(_, index)
            return rooms[index]
        end,
    }
    populate(level, layout)
    local totals, inside = {}, {}
    local bounds = rules.bounds(layout.zones, 2)
    for index, room in pairs(rooms) do
        local kind = room.Data.Type
        totals[kind] = (totals[kind] or 0) + 1
        if
            index % 13 >= bounds.left
            and index % 13 <= bounds.right
            and index // 13 >= bounds.top
            and index // 13 <= bounds.bottom
        then
            inside[kind] = (inside[kind] or 0) + 1
        end
    end
    for kind, target in pairs(targets) do
        assert(
            totals[kind] == target and inside[kind] >= target // 2,
            "Resource quota or first-circle supply missing"
        )
    end
    for index, kind in pairs(original) do
        assert(rooms[index].Data.Type == kind)
    end
    assert(rooms[layout.zones[4]].Data.Type == 1 and rooms[84].Data.Type == 1)
    for _, start in ipairs(layout.spawns) do
        local frontier, seen, found = { start }, { [start] = true }, false
        for _ = 1, 3 do
            local nextLayer = {}
            for _, index in ipairs(frontier) do
                for _, target in ipairs(neighbors(index)) do
                    local kind = rooms[target].Data.Type
                    if not seen[target] then
                        seen[target] = true
                        found = found or kind == 4
                        if kind == 1 or kind == 2 or kind == 4 then
                            nextLayer[#nextLayer + 1] = target
                        end
                    end
                end
            end
            frontier = nextLayer
        end
        assert(found, "A spawn lacks a free route to a nearby treasure room")
    end
    local before = changes
    populate(level, layout)
    assert(changes == before, "Repeated planning must not add more resources")
end
print("PASS resource quotas, native rooms, safe routes, random circles and repeated planning")
