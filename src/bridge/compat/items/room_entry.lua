-- Called in the arriving room's roster after generic combat-door handling.
return function(game, getPlayer, roomTypes, collectibles, trinkets)
    local room = game:GetRoom()
    local level = game:GetLevel()
    -- Horse-pill flags 24/25 are native LevelStateFlag entries not exported
    -- by the J460 Lua enum. GetStateFlag still accepts these entries.
    local slowEnemiesFloorFlag = 24
    if level:GetStateFlag(slowEnemiesFloorFlag) then
        -- Native horse Drowsy uses the floor flag and an unbounded room timer.
        -- The engine clears the flag on a new floor; ordinary pills never set it.
        local untilRoomEnds = 0x7fffffff
        local watchSlowed = 1
        room:SetBrokenWatchState(watchSlowed)
        room:SetSlowDown(untilRoomEnds)
    end
    for index = 0, game:GetNumPlayers() - 1 do
        local player = getPlayer(index)
        if player:HasTrinket(trinkets.TRINKET_DOOR_STOP) then
            local door = room:GetDoor(level.EnterDoor)
            if level.EnterDoor == -1 then
                -- Native non-door entries use the first nearby door, if any.
                local nearbyDoorDistanceSquared = 100 * 100
                for slot = 0, 7 do
                    local candidate = room:GetDoor(slot)
                    if
                        candidate
                        and candidate.Position:DistanceSquared(player.Position)
                            < nearbyDoorDistanceSquared
                    then
                        door = candidate
                        break
                    end
                end
            end
            if door then
                door:Open()
            end
        end
        if
            room:GetType() == roomTypes.ROOM_DEFAULT
            and player:HasCollectible(collectibles.COLLECTIBLE_MERCURIUS)
        then
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door.TargetRoomType == roomTypes.ROOM_DEFAULT then
                    door:Open()
                end
            end
        end
    end
end
