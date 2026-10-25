-- Expand the game's existing floor through Red Key's native generation rules.
return function(deps)
    local rules, enums = deps.rules, deps.enums
    local width, cells = rules.width, rules.width * rules.width
    local corners = { 0, width - 1, cells - width, cells - 1 }
    local function descriptor(level, index)
        local room = level:GetRoomByIdx(index, 0)
        return room and room.Data and room.SafeGridIndex >= 0 and room or nil
    end
    local function doorTarget(room, slot)
        -- MakeRedRoomDoor also creates I AM ERROR entrances for invalid slots
        -- and out-of-map targets. Validate geometry before calling the native API.
        if (room.Data.Doors & (1 << slot)) == 0 then
            return nil
        end
        local shape, shapes = room.Data.Shape, enums.shape
        local large = shape >= shapes.ROOMSHAPE_2x2
        local wide = large or shape == shapes.ROOMSHAPE_2x1 or shape == shapes.ROOMSHAPE_IIH
        local tall = large or shape == shapes.ROOMSHAPE_1x2 or shape == shapes.ROOMSHAPE_IIV
        local left, up, right, down = 0, 1, 2, 3
        local side, second = slot % 4, slot // 4
        local x, y
        if side == left or side == right then
            if second == 1 and not tall then
                return nil
            end
            x, y = side == left and -1 or (wide and 2 or 1), second
            if
                (shape == shapes.ROOMSHAPE_LTL and slot == left)
                or (shape == shapes.ROOMSHAPE_LBL and slot == left + 4)
            then
                x = 0
            elseif
                (shape == shapes.ROOMSHAPE_LTR and slot == right)
                or (shape == shapes.ROOMSHAPE_LBR and slot == right + 4)
            then
                x = 1
            end
        else
            if second == 1 and not wide then
                return nil
            end
            x, y = second, side == up and -1 or (tall and 2 or 1)
            if
                (shape == shapes.ROOMSHAPE_LTL and slot == up)
                or (shape == shapes.ROOMSHAPE_LTR and slot == up + 4)
            then
                y = 0
            elseif
                (shape == shapes.ROOMSHAPE_LBL and slot == down)
                or (shape == shapes.ROOMSHAPE_LBR and slot == down + 4)
            then
                y = 1
            end
        end
        x, y = room.GridIndex % width + x, room.GridIndex // width + y
        if x >= 0 and x < width and y >= 0 and y < width then
            return y * width + x
        end
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
                        local target = doorTarget(room, door)
                        if target and not descriptor(level, target) then
                            level:MakeRedRoomDoor(index, door)
                        end
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
        local layout = {
            boss = boss,
            finalBoss = finalBoss,
            spawns = spawns,
            zones = rules.plan(candidates, deps.random),
        }
        deps.resources(level, layout)
        return layout
    end
    local function openResources(room)
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if
                door
                and (
                    door.TargetRoomType == enums.room.ROOM_TREASURE
                    or door.TargetRoomType == enums.room.ROOM_SHOP
                )
            then
                door:SetLocked(false)
                if room:IsClear() then
                    door:Open()
                end
            end
        end
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
    local function clearSpawn(room)
        -- Remove without death effects, drops or split enemies. Keep pickups,
        -- players and the native room connections intact.
        for _, entity in ipairs(deps.entities()) do
            if
                entity:IsEnemy()
                or entity.Type == enums.entity.ENTITY_PROJECTILE
                or entity.Type == enums.entity.ENTITY_BOMBDROP
                or entity.Type == enums.entity.ENTITY_LASER
            then
                entity:Remove()
            end
        end
        for index = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(index)
            if
                grid
                and grid:GetType() ~= enums.grid.GRID_WALL
                and grid:GetType() ~= enums.grid.GRID_DOOR
            then
                room:RemoveGridEntity(index, 0, false)
            end
        end
        room:SetClear(true)
    end
    local function restrictRoom(room, boss)
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
                (
                    entity.Type == enums.entity.ENTITY_EFFECT
                    and entity.Variant == enums.effect.HEAVEN_LIGHT_DOOR
                )
                or (
                    entity.Type == enums.entity.ENTITY_SLOT
                    and entity.Variant == rules.reviveMachineVariant
                )
            then
                entity:Remove()
            end
        end
    end
    return {
        build = build,
        escape = escape,
        openResources = openResources,
        clearSpawn = clearSpawn,
        restrictRoom = restrictRoom,
    }
end
