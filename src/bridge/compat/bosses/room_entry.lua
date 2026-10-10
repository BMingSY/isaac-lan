-- Entering an occupied Boss room bypasses its native door transition.
return function(room, trapdoorType)
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        if grid and grid:GetType() == trapdoorType then
            grid.State = 0
            grid:GetSprite():Play("Closed", true)
        end
    end
end
