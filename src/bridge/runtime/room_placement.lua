-- Safe landing in the already-selected destination room.
return function(deps)
    local offsets = {
        { 0, 0 },
        { -1, -1 },
        { -1, 1 },
        { 1, -1 },
        { 1, 1 },
        { -1, 0 },
        { 1, 0 },
        { 0, -1 },
        { 0, 1 },
    }
    local function clear(room, player, point, flying)
        if not room:IsPositionInRoom(point, player.Size) then
            return false
        end
        local collision = deps.collision
        for _, offset in ipairs(offsets) do
            local value = room:GetGridCollisionAtPos(
                deps.vector(point.X + offset[1] * player.Size, point.Y + offset[2] * player.Size)
            )
            if
                value ~= collision.COLLISION_NONE
                and value ~= collision.COLLISION_WALL_EXCEPT_PLAYER
                and not (
                    flying
                    and (
                        value == collision.COLLISION_PIT
                        or value == collision.COLLISION_OBJECT
                        or value == collision.COLLISION_SOLID
                    )
                )
            then
                return false
            end
        end
        return true
    end
    local function nearest(room, player, target, flying)
        local best, distance = nil, math.huge
        for i = 0, room:GetGridSize() - 1 do
            local point = room:GetGridPosition(i)
            local dx, dy = point.X - target.X, point.Y - target.Y
            local score = dx * dx + dy * dy
            if score < distance and clear(room, player, point, flying) then
                best, distance = point, score
            end
        end
        return best
    end
    local function commit(placements)
        for _, placement in ipairs(placements) do
            placement.player.Position = placement.position
            placement.player.Velocity = deps.vector(0, 0)
        end
    end
    local function near(slot, target)
        local result
        if
            deps.native.api_with_owner(slot, function()
                local game = deps.game()
                local room, placements = game:GetRoom(), {}
                for body = 0, game:GetNumPlayers() - 1 do
                    local player = deps.player(body)
                    local best = nearest(room, player, deps.vector(target.x, target.y), false)
                    if not best then
                        result = false
                        return
                    end
                    placements[#placements + 1] = { player = player, position = best }
                end
                commit(placements)
                result = true
            end)
        then
            return result
        end
    end
    local function arrive(door)
        if door == nil or door >= 0 then
            return true
        end
        local game, placements = deps.game(), {}
        local room = game:GetRoom()
        if deps.canPlace and not deps.canPlace(room) then
            return true
        end
        -- This scope contains only the arriving owner's bodies. A resident may
        -- fly above a rock, so copying their position is not sufficient.
        for body = 0, game:GetNumPlayers() - 1 do
            local player = deps.player(body)
            local flying = player.CanFly or player:IsCoopGhost()
            if not clear(room, player, player.Position, flying) then
                local point = nearest(room, player, player.Position, flying)
                if not point then
                    return false
                end
                placements[#placements + 1] = { player = player, position = point }
            end
        end
        commit(placements)
        return true
    end
    return { near = near, arrive = arrive }
end
