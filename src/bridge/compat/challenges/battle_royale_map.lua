-- Expand the game's existing floor through Red Key's native generation rules.
return function(deps)
    local rules, enums = deps.rules, deps.enums
    local width, cells = rules.width, rules.width * rules.width
    local corners = { 0, width - 1, cells - width, cells - 1 }
    local function descriptor(level, index)
        local room = level:GetRoomByIdx(index, 0)
        return room and room.Data and room.SafeGridIndex >= 0 and room or nil
    end
    local function ordinaryBoss(room)
        -- XL Depths also contains Mom. Its descriptor may sort before the
        -- ordinary boss, but cannot award the first point.
        local spawns = room.Data.Spawns
        for index = 0, spawns.Size - 1 do
            local entries = spawns:Get(index).Entries
            for entry = 0, entries.Size - 1 do
                if entries:Get(entry).Type == enums.entity.ENTITY_MOM then
                    return false
                end
            end
        end
        return true
    end
    local function build(level)
        -- Native generation can add lower-index rooms while scanning. Stop at
        -- its fixed point; failed doors (large rooms, secrets, edges) stay native.
        for _ = 1, cells do
            local count = level:GetRooms().Size
            for index = 0, cells - 1 do
                local room = descriptor(level, index)
                if room and room.SafeGridIndex == index then
                    for door = 0, 7 do
                        level:MakeRedRoomDoor(index, door)
                    end
                end
            end
            if level:GetRooms().Size == count then
                break
            end
        end
        local available, boss = {}, nil
        for index = 0, cells - 1 do
            local room = descriptor(level, index)
            if room and room.SafeGridIndex == index then
                if room.Data.Type == enums.room.ROOM_BOSS then
                    if ordinaryBoss(room) then
                        boss = boss or index
                    end
                else
                    available[#available + 1] = index
                end
            end
        end
        assert(boss and #available >= 4, "Battle royale floor is missing playable rooms")
        local spawns, used = {}, {}
        for _, corner in ipairs(corners) do
            local closest, distance
            for _, index in ipairs(available) do
                local d = math.abs(index % width - corner % width)
                    + math.abs(index // width - corner // width)
                if not used[index] and (not distance or d < distance) then
                    closest, distance = index, d
                end
            end
            spawns[#spawns + 1], used[closest] = closest, true
        end
        for index = #spawns, 2, -1 do
            local other = deps.random(index)
            spawns[index], spawns[other] = spawns[other], spawns[index]
        end
        local finalBoss
        for _, index in ipairs(available) do
            local room = descriptor(level, index)
            if
                not used[index]
                and index ~= rules.center
                and room.Data.Type == enums.room.ROOM_DEFAULT
                and room.Data.Shape == enums.shape.ROOMSHAPE_1x1
            then
                assert(
                    deps.native.room_special_template(
                        index,
                        enums.room.ROOM_BOSS,
                        rules.momRoomVariant,
                        deps.random(1, 2147483646)
                    ),
                    "Battle royale final boss template unavailable"
                )
                finalBoss = index
                break
            end
        end
        assert(finalBoss, "Battle royale floor is missing a final boss room")
        local candidates = {}
        for _, index in ipairs(available) do
            local room = descriptor(level, index)
            if
                index ~= finalBoss
                and room.Data.Type == enums.room.ROOM_DEFAULT
                and room.Data.Shape == enums.shape.ROOMSHAPE_1x1
            then
                candidates[#candidates + 1] = index
            end
        end
        return {
            boss = boss,
            finalBoss = finalBoss,
            spawns = spawns,
            zones = rules.plan(candidates, deps.random),
        }
    end
    local function escape(room)
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomType ~= enums.room.ROOM_BOSS then
                door:SetLocked(false)
                door:Open()
            end
        end
    end
    local function removeExits(room, boss)
        for index = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(index)
            if
                grid
                and (
                    grid:GetType() == enums.grid.GRID_TRAPDOOR
                    or (boss and grid:GetType() == enums.grid.GRID_STAIRS)
                )
            then
                room:RemoveGridEntity(index, 0, false)
            end
        end
        for _, entity in ipairs(deps.entities()) do
            if
                entity.Type == enums.entity.ENTITY_EFFECT
                and entity.Variant == enums.effect.HEAVEN_LIGHT_DOOR
            then
                entity:Remove()
            end
        end
    end
    return { build = build, escape = escape, removeExits = removeExits }
end
