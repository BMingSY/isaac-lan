-- Resolve speculative walking against the current visible room. Only the
-- speculative offset is constrained; a confirmed native pose is always legal.
return function(Vector, collision, types)
    local cell, halfCell = 40, 20
    local poopRadius, tolerance = 18, 0.01
    local maxStep, maxDistance, contactPasses = 4, 256, 4

    -- Signed distance from a point to the obstacle and its outward normal.
    local function surface(tile, position)
        local x, y = position.X - tile.x, position.Y - tile.y
        if tile.round then
            local length = math.sqrt(x * x + y * y)
            if length == 0 then
                return -poopRadius, 1, 0
            end
            return length - poopRadius, x / length, y / length
        end
        local dx, dy = math.abs(x) - halfCell, math.abs(y) - halfCell
        local sx, sy = x < 0 and -1 or 1, y < 0 and -1 or 1
        if dx > 0 and dy > 0 then
            local length = math.sqrt(dx * dx + dy * dy)
            return length, sx * dx / length, sy * dy / length
        elseif dx > dy then
            return dx, sx, 0
        end
        return dy, 0, sy
    end

    return function(room, radius, flying, corridor, controls, preview)
        -- All tiles, including empty ones, are cached only for this render and
        -- body. Replay sees broken pots, filled pits and changed doors immediately.
        local origin, rows = room:GetGridPosition(0), {}
        local function tileAt(col, row)
            local line = rows[row]
            if not line then
                line = {}
                rows[row] = line
            end
            if line[col] == nil then
                local x, y = origin.X + cell * col, origin.Y + cell * row
                local center = Vector(x, y)
                local class = room:GetGridCollisionAtPos(center)
                local pass = class == collision.COLLISION_NONE
                    or class == collision.COLLISION_WALL_EXCEPT_PLAYER
                    or flying
                        and (class == collision.COLLISION_PIT or class == collision.COLLISION_OBJECT or class == collision.COLLISION_SOLID)
                if pass then
                    line[col] = false
                else
                    local index = room:GetGridIndex(center)
                    local grid = index >= 0 and room:GetGridEntity(index)
                    local kind = grid and grid:GetType()
                    line[col] = {
                        x = x,
                        y = y,
                        round = kind == types.GRID_POOP,
                        doorWall = class == collision.COLLISION_WALL
                            and (not kind or kind == types.GRID_WALL or kind == types.GRID_DOOR),
                    }
                end
            end
            return line[col]
        end

        local function inDoorway(tile, position)
            if not controls or not tile.doorWall then
                return false
            end
            local slot, outward = corridor(room, position, preview)
            if slot then
                local door = room:GetDoor(slot).Position
                local dx, dy = tile.x - door.X, tile.y - door.Y
                return math.abs(dx * outward.Y - dy * outward.X) <= halfCell
                    and dx * outward.X + dy * outward.Y >= -halfCell
            end
        end

        local function contact(from, position)
            local x, y = position.X - origin.X + halfCell, position.Y - origin.Y + halfCell
            local depth, nx, ny = tolerance, 0, 0
            for row = math.floor((y - radius) / cell), math.floor((y + radius) / cell) do
                for col = math.floor((x - radius) / cell), math.floor((x + radius) / cell) do
                    local tile = tileAt(col, row)
                    if tile then
                        local distance, dx, dy = surface(tile, position)
                        if radius - distance > depth and not inDoorway(tile, position) then
                            -- A host-approved contact can sit slightly inside the
                            -- ideal shape. It may slide or leave without moving deeper.
                            local limit = radius
                            if from then
                                local priorDistance = surface(tile, from)
                                limit = math.min(radius, priorDistance)
                            end
                            if limit - distance > depth then
                                depth, nx, ny = limit - distance, dx, dy
                            end
                        end
                    end
                end
            end
            if nx ~= 0 or ny ~= 0 then
                return Vector(nx * depth, ny * depth)
            end
        end

        local function slide(from, wanted)
            local point = wanted
            for _ = 1, contactPasses do
                local push = contact(from, point)
                if not push then
                    return point
                end
                point = point + push
            end
            return contact(from, point) and from or point
        end

        return function(from, wanted, authority)
            if authority and contact(nil, from) and not contact(nil, authority) then
                from = authority
            end
            local clamped = room:GetClampedPosition(wanted, radius)
            if controls and (preview ~= nil or clamped.X ~= wanted.X or clamped.Y ~= wanted.Y) then
                local slot, outward, along = corridor(room, wanted, preview)
                if not slot then
                    wanted = clamped
                elseif slot == preview and not room:GetDoor(slot):IsOpen() and along < 18 then
                    wanted = room:GetDoor(slot).Position - outward * 18
                end
            else
                wanted = clamped
            end
            local delta = wanted - from
            local distance = math.max(math.abs(delta.X), math.abs(delta.Y))
            if distance == 0 then
                return from
            end
            local limited = distance > maxDistance
            if limited then
                delta = delta * (maxDistance / distance)
                wanted = from + delta
                distance = maxDistance
            end
            local steps = math.ceil(distance / maxStep)
            local increment, point = delta * (1 / steps), from
            for _ = 1, steps do
                point = slide(point, point + increment)
            end
            if authority then
                -- If our shape would strand a correction outside a legal native
                -- pose, admit the rejected component only as far as that pose.
                local rejected = wanted - point
                local length = rejected:LengthSquared()
                if length > tolerance * tolerance then
                    local fraction = (authority - point):Dot(rejected) / length
                    if fraction > 0 then
                        point = point + rejected * math.min(fraction, 1)
                    end
                end
            end
            return point, limited
        end
    end
end
