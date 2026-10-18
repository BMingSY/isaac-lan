-- Called in the arriving room's roster after generic combat-door handling.
return function(game, getPlayer, roomTypes, collectibles)
    local room = game:GetRoom()
    -- Horse-pill flags 24/25 are native LevelStateFlag entries not exported
    -- by the J460 Lua enum. GetStateFlag still accepts these entries.
    local slowEnemiesFloorFlag = 24
    if game:GetLevel():GetStateFlag(slowEnemiesFloorFlag) then
        -- Native horse Drowsy uses the floor flag and an unbounded room timer.
        -- The engine clears the flag on a new floor; ordinary pills never set it.
        local untilRoomEnds = 0x7fffffff
        local watchSlowed = 1
        room:SetBrokenWatchState(watchSlowed)
        room:SetSlowDown(untilRoomEnds)
    end
    if room:GetType() ~= roomTypes.ROOM_DEFAULT then
        return
    end
    for index = 0, game:GetNumPlayers() - 1 do
        if getPlayer(index):HasCollectible(collectibles.COLLECTIBLE_MERCURIUS) then
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door.TargetRoomType == roomTypes.ROOM_DEFAULT then
                    door:Open()
                end
            end
            return
        end
    end
end
