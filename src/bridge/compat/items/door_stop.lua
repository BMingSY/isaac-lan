-- The native entry slot, or the first nearby door for a non-door arrival.
return function(room, level, player, trinket)
    if not player:HasTrinket(trinket) then
        return
    end
    if level.EnterDoor ~= -1 then
        return room:GetDoor(level.EnterDoor)
    end
    local nearbyDistanceSquared = 100 * 100
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door and door.Position:DistanceSquared(player.Position) < nearbyDistanceSquared then
            return door
        end
    end
end
