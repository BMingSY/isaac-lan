-- Numeric observations only: no game calls, randomness or world mutations.
local nav = {}
function nav.distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
function nav.cell(map, x, y)
    local col = math.floor((x - map.x) / map.step + 0.5)
    local row = math.floor((y - map.y) / map.step + 0.5)
    if col < 0 or row < 0 or col >= map.width or row >= map.height then
        return nil
    end
    return row * map.width + col + 1
end
function nav.position(map, cell)
    return {
        x = map.x + ((cell - 1) % map.width) * map.step,
        y = map.y + math.floor((cell - 1) / map.width) * map.step,
    }
end
local function corridor(door, x, y, radius)
    if not door then
        return false
    end
    local dx, dy = x - door.x, y - door.y
    local along = dx * door.dx + dy * door.dy
    local across = math.abs(dx * door.dy - dy * door.dx)
    return along > -48 and along < 48 and across + radius <= 22
end
function nav.zonesAllow(map, x, y, radius, time, from, ignoreTimed)
    for _, zone in ipairs(map.zones or {}) do
        if (not zone.exit or zone.id ~= map.allowedExit) and not (ignoreTimed and zone.timed) then
            local blocked = not zone.timed or (time or 0) >= (zone.safeFor or 0)
            local distance = nav.distance({ x = x, y = y }, zone)
            if blocked and distance < radius + zone.radius then
                -- A resumed bot may already overlap a hazard/exit. Permit only
                -- outward movement, including its first still-overlapping step.
                if
                    not from
                    or distance <= nav.distance(from, zone)
                    or (x - from.x) * (from.x - zone.x) + (y - from.y) * (from.y - zone.y) < 0
                then
                    return false
                end
            end
        end
    end
    return true
end
function nav.passable(map, x, y, radius, door, time, from, ignoreTimed)
    if not nav.zonesAllow(map, x, y, radius, time, from, ignoreTimed) then
        return false
    end
    if corridor(door, x, y, radius) then
        return true
    end
    local a, b = nav.cell(map, x - radius, y - radius), nav.cell(map, x + radius, y - radius)
    local c, d = nav.cell(map, x - radius, y + radius), nav.cell(map, x + radius, y + radius)
    if
        not a
        or not b
        or not c
        or not d
        or not (map.walk[a] or map.exitCells and map.exitCells[a])
        or not (map.walk[b] or map.exitCells and map.exitCells[b])
        or not (map.walk[c] or map.exitCells and map.exitCells[c])
        or not (map.walk[d] or map.exitCells and map.exitCells[d])
    then
        return false
    end
    return true
end
function nav.line(map, from, to, radius, door, t0, t1, ignoreTimed)
    t0 = t0 or 0
    t1 = t1 or t0 + nav.distance(from, to) / (map.speed or 200) + 0.15
    local steps = math.max(1, math.ceil(nav.distance(from, to) / 8))
    for i = 1, steps do
        local t = i / steps
        if
            not nav.passable(
                map,
                from.x + (to.x - from.x) * t,
                from.y + (to.y - from.y) * t,
                radius,
                door,
                t0 + (t1 - t0) * t,
                from,
                ignoreTimed
            )
        then
            return false
        end
    end
    return true
end
function nav.approachTimed(map, from, path, radius, door)
    local previous, safe = from, from
    local braking = (map.speed or 200) * 0.13 + 4
    for _, point in ipairs(path) do
        local count = math.max(1, math.ceil(nav.distance(previous, point) / 8))
        for i = 1, count do
            local nextPoint = {
                x = previous.x + (point.x - previous.x) * i / count,
                y = previous.y + (point.y - previous.y) * i / count,
            }
            for _, zone in ipairs(map.zones or {}) do
                if
                    zone.timed
                    and nav.distance(nextPoint, zone) < radius + zone.radius + braking
                then
                    return nav.distance(from, safe) > 8 and safe or nil
                end
            end
            if not nav.line(map, safe, nextPoint, radius, door) then
                return nav.distance(from, safe) > 8 and safe or nil
            end
            safe = nextPoint
        end
        previous = point
    end
    return nil
end
local function push(heap, item)
    local i = #heap + 1
    while i > 1 do
        local parent = math.floor(i / 2)
        if heap[parent].score <= item.score then
            break
        end
        heap[i], i = heap[parent], parent
    end
    heap[i] = item
end
local function pop(heap)
    local first, last = heap[1], table.remove(heap)
    if #heap > 0 then
        local i = 1
        while i * 2 <= #heap do
            local child = i * 2
            if child < #heap and heap[child + 1].score < heap[child].score then
                child = child + 1
            end
            if last.score <= heap[child].score then
                break
            end
            heap[i], i = heap[child], child
        end
        heap[i] = last
    end
    return first
end
function nav.path(map, from, to, radius, limit, door, ignoreTimed)
    if not nav.passable(map, to.x, to.y, radius, door, 0, nil, ignoreTimed) then
        return nil
    end
    if nav.line(map, from, to, radius, door, nil, nil, ignoreTimed) then
        return { to }
    end
    local start, target = nav.cell(map, from.x, from.y), nav.cell(map, to.x, to.y)
    if not start or not target then
        return nil
    end
    local heap, cost, prior, closed = {}, { [start] = 0 }, {}, {}
    push(heap, { cell = start, score = 0 })
    for _ = 1, limit or 640 do
        if #heap == 0 then
            return nil
        end
        local cell = pop(heap).cell
        if cell == target then
            local path = { to }
            while cell ~= start do
                table.insert(path, 1, nav.position(map, cell))
                cell = prior[cell]
            end
            return path
        end
        if not closed[cell] then
            closed[cell] = true
            local p = nav.position(map, cell)
            for _, delta in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
                local x, y = p.x + delta[1] * map.step, p.y + delta[2] * map.step
                local nextCell = nav.cell(map, x, y)
                if
                    nextCell
                    and not closed[nextCell]
                    and nav.line(
                        map,
                        cell == start and from or p,
                        { x = x, y = y },
                        radius,
                        door,
                        cost[cell] / (map.speed or 200),
                        (cost[cell] + map.step) / (map.speed or 200) + 0.15,
                        ignoreTimed
                    )
                then
                    local nextCost = cost[cell] + map.step
                    if not cost[nextCell] or nextCost < cost[nextCell] then
                        prior[nextCell], cost[nextCell] = cell, nextCost
                        push(heap, {
                            cell = nextCell,
                            score = nextCost + math.abs(x - to.x) + math.abs(y - to.y),
                        })
                    end
                end
            end
        end
    end
    return nil
end
function nav.segmentDistance(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local t = math.max(
        0,
        math.min(1, ((x - ax) * dx + (y - ay) * dy) / math.max(0.001, dx * dx + dy * dy))
    )
    return math.sqrt((x - ax - t * dx) ^ 2 + (y - ay - t * dy) ^ 2)
end
return nav
