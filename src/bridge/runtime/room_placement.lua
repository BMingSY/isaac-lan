-- Shared safe landing for player-targeted travel and room gathering.
return function(deps)
    return function(slot, target)
        local result
        if
            deps.native.api_with_owner(slot, function()
                local game = deps.game()
                local room, placements = game:GetRoom(), {}
                for body = 0, game:GetNumPlayers() - 1 do
                    local player = deps.player(body)
                    local radius, best, distance = player.Size, nil, math.huge
                    for i = 0, room:GetGridSize() - 1 do
                        local point = room:GetGridPosition(i)
                        local dx, dy = point.X - target.x, point.Y - target.y
                        local score = dx * dx + dy * dy
                        local clear = room:IsPositionInRoom(point, radius)
                        for _, offset in ipairs({
                            { 0, 0 },
                            { -1, -1 },
                            { -1, 1 },
                            { 1, -1 },
                            { 1, 1 },
                        }) do
                            clear = clear
                                and room:GetGridCollisionAtPos(
                                        deps.vector(
                                            point.X + offset[1] * radius,
                                            point.Y + offset[2] * radius
                                        )
                                    )
                                    == deps.collision.COLLISION_NONE
                        end
                        if clear and score < distance then
                            best, distance = point, score
                        end
                    end
                    if not best then
                        result = false
                        return
                    end
                    placements[#placements + 1] = { player = player, position = best }
                end
                for _, placement in ipairs(placements) do
                    placement.player.Position = placement.position
                    placement.player.Velocity = deps.vector(0, 0)
                end
                result = true
            end)
        then
            return result
        end
    end
end
