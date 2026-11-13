-- Select only ordinary combat rooms after native generation has settled.
return function(deps)
    local enums, rules = deps.enums, deps.rules
    -- Room-template spawn IDs differ from GridEntityType. Only ordinary
    -- terrain is replaceable; route markers/buttons/stairs remain native.
    local terrain = {
        rock = 1000,
        bombRock = 1001,
        altRock = 1002,
        tnt = 1300,
        redPoop = 1490,
        rainbowPoop = 1494,
        poopChunks = 1495,
        goldPoop = 1496,
        blackPoop = 1497,
        poop = 1500,
        solidRock = 1900,
        spikes = 1930,
        timedSpikes = 1931,
        web = 1940,
        pit = 3000,
    }
    local terrainTypes = {}
    for _, kind in pairs(terrain) do
        terrainTypes[kind] = true
    end
    local function ordinary(desc)
        return desc
            and desc.Data
            and desc.SafeGridIndex >= 0
            and desc.Data.Type == enums.room.ROOM_DEFAULT
            and (desc.Flags & enums.descriptor.FLAG_RED_ROOM) == 0
    end
    local function replaceable(desc, start)
        if
            not ordinary(desc)
            or desc.SafeGridIndex == start
            or desc.VisitedCount ~= 0
            or desc.Data.Shape ~= enums.shape.ROOMSHAPE_1x1
            or desc.Data.Subtype ~= 0
            or desc.Flags
                    & ~(enums.descriptor.FLAG_HAS_WATER | enums.descriptor.FLAG_USE_ALTERNATE_BACKDROP)
                ~= 0
        then
            return false
        end
        -- Whitelist ordinary layouts. Keep all special markers, fireplaces,
        -- pickups, machines and route structures, including modded entities.
        local spawns = desc.Data.Spawns
        for index = 0, spawns.Size - 1 do
            local entries = spawns:Get(index).Entries
            for entry = 0, entries.Size - 1 do
                local spawn = entries:Get(entry)
                local kind = spawn.Type
                local ordinaryTerrain = terrainTypes[kind]
                    and spawn.Variant == 0
                    and spawn.Subtype == 0
                local decoration = kind == 0
                    and spawn.Variant >= 10
                    and spawn.Variant <= 30
                    and spawn.Subtype == 0
                if
                    not ordinaryTerrain
                    and not decoration
                    and (
                        kind < enums.entity.ENTITY_GAPER
                        or kind >= enums.entity.ENTITY_MINECART
                        or kind == enums.entity.ENTITY_FIREPLACE
                    )
                then
                    return false
                end
            end
        end
        return true
    end
    local function select(level, random)
        local candidates, connections = {}, {}
        for index = 0, 168 do
            local desc = level:GetRoomByIdx(index, 0)
            if ordinary(desc) and desc.SafeGridIndex == index then
                local neighbors, quest = deps.native.room_connections(index)
                connections[index] = neighbors or {}
                if not quest and replaceable(desc, level:GetStartingRoomIndex()) then
                    local mirror = level:GetRoomByIdx(index, 1)
                    -- A missing mirror descriptor must not count as a room.
                    if
                        not mirror
                        or not mirror.Data
                        or mirror.SafeGridIndex ~= index
                        or mirror.ListIndex == desc.ListIndex
                        or (mirror.SafeGridIndex == index and replaceable(mirror, -1))
                    then
                        candidates[#candidates + 1] = index
                    end
                end
            end
        end
        return rules.selectPair(candidates, connections, random)
    end
    local function install(level, pair, restore)
        if not deps.native.room_empty_pair(pair[1], pair[2], restore and 1 or 0) then
            return false
        end
        for _, index in ipairs(pair) do
            for dimension = 0, 1 do
                local desc = level:GetRoomByIdx(index, dimension)
                if desc and desc.Data and desc.SafeGridIndex == index then
                    desc.Clear, desc.NoReward = true, true
                end
            end
        end
        return true
    end
    return { select = select, install = install, replaceable = replaceable }
end
