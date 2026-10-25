-- Resource placement owns quotas and distribution; the backend only selects
-- compatible native room templates, before any player visits them.
return function(deps)
    local rules, enums = deps.rules, deps.enums
    local width, cells, anyVariant = rules.width, rules.width * rules.width, -1
    local function distance(a, b)
        return math.abs(a % width - b % width) + math.abs(a // width - b // width)
    end
    local function region(index)
        local middle = width // 2
        return (index % width < middle and 0 or 1) + (index // width < middle and 0 or 2) + 1
    end
    return function(level, layout)
        local rooms, connections, protected, resourceTypes = {}, {}, {}, {}
        protected[rules.center], protected[layout.boss], protected[layout.finalBoss] =
            true, true, true
        protected[layout.zones[#rules.zoneSizes]] = true
        for _, index in ipairs(layout.spawns) do
            protected[index] = true
        end
        for _, definition in ipairs(rules.resources) do
            resourceTypes[enums.room[definition.room]] = true
        end
        for index = 0, cells - 1 do
            local room = level:GetRoomByIdx(index, 0)
            if room and room.Data and room.SafeGridIndex == index then
                rooms[index] = room
                connections[index] = assert(deps.native.room_connections(index))
            end
        end
        local function paths(start)
            local distances, parents, queue = { [start] = 0 }, {}, { start }
            local head = 1
            while head <= #queue do
                local index = queue[head]
                head = head + 1
                for _, target in ipairs(connections[index] or {}) do
                    local room = rooms[target]
                    local kind = room and room.Data.Type
                    if
                        distances[target] == nil
                        and (
                            kind == enums.room.ROOM_DEFAULT
                            or kind == enums.room.ROOM_TREASURE
                            or kind == enums.room.ROOM_SHOP
                        )
                    then
                        distances[target], parents[target] = distances[index] + 1, index
                        queue[#queue + 1] = target
                    end
                end
            end
            return distances, parents
        end
        local bounds = rules.bounds(layout.zones, 2)
        local function inFirstZone(index)
            local x, y = index % width, index // width
            return x >= bounds.left and x <= bounds.right and y >= bounds.top and y <= bounds.bottom
        end
        local function count(kind, predicate)
            local total = 0
            for index, room in pairs(rooms) do
                if room.Data.Type == kind and (not predicate or predicate(index)) then
                    total = total + 1
                end
            end
            return total
        end
        for _, definition in ipairs(rules.resources) do
            local kind, rejected = enums.room[definition.room], {}
            local function place(predicate, distances)
                while true do
                    local regional = { 0, 0, 0, 0 }
                    for index, room in pairs(rooms) do
                        if room.Data.Type == kind then
                            regional[region(index)] = regional[region(index)] + 1
                        end
                    end
                    local selected, bestBalance, bestSpacing, ties
                    for index = 0, cells - 1 do
                        local room = rooms[index]
                        if
                            room
                            and not protected[index]
                            and not rejected[index]
                            and room.Data.Type == enums.room.ROOM_DEFAULT
                            and room.Data.Shape == enums.shape.ROOMSHAPE_1x1
                            and room.VisitedCount == 0
                            and (not predicate or predicate(index))
                        then
                            local spacing = width * 2
                            for other, existing in pairs(rooms) do
                                if resourceTypes[existing.Data.Type] then
                                    spacing = math.min(spacing, distance(index, other))
                                end
                            end
                            local balance = distances and distances[index]
                                or regional[region(index)]
                            if
                                not selected
                                or balance < bestBalance
                                or (balance == bestBalance and spacing > bestSpacing)
                            then
                                selected, bestBalance, bestSpacing, ties =
                                    index, balance, spacing, 1
                            elseif balance == bestBalance and spacing == bestSpacing then
                                ties = ties + 1
                                if deps.random(ties) == 1 then
                                    selected = index
                                end
                            end
                        end
                    end
                    if not selected then
                        return nil
                    end
                    if
                        deps.native.room_special_template(
                            selected,
                            kind,
                            anyVariant,
                            deps.random(1, 2147483646)
                        )
                    then
                        return selected
                    end
                    rejected[selected] = true
                end
            end
            if definition.nearSpawns then
                for _, start in ipairs(layout.spawns) do
                    local distances, parents = paths(start)
                    local nearest
                    for index, room in pairs(rooms) do
                        if
                            room.Data.Type == kind
                            and distances[index]
                            and distances[index] <= rules.resourceDistance
                            and (not nearest or distances[index] < distances[nearest])
                        then
                            nearest = index
                        end
                    end
                    nearest = nearest
                        or place(function(index)
                            return distances[index] ~= nil
                                and distances[index] <= rules.resourceDistance
                        end, distances)
                        or place(function(index)
                            return distances[index] ~= nil
                        end, distances)
                    -- Keep the free route to the nearby treasure room usable;
                    -- later library/arcade placement must not add an entry toll.
                    while nearest and parents[nearest] do
                        nearest = parents[nearest]
                        protected[nearest] = true
                    end
                end
            end
            while count(kind, inFirstZone) < definition.firstZone do
                if not place(inFirstZone) then
                    break
                end
            end
            while count(kind) < definition.count do
                if not place() then
                    break
                end
            end
        end
    end
end
