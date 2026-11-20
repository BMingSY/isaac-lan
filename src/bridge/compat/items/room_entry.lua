-- Called in the arriving room's roster after generic combat-door handling.
return function(game, getPlayer, roomTypes, collectibles, trinkets, doorStop)
    local room = game:GetRoom()
    local level = game:GetLevel()
    -- Horse-pill flags 24/25 are native LevelStateFlag entries not exported
    -- by the J510 Lua enum. GetStateFlag still accepts these entries.
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
        local heldDoor = doorStop(room, level, player, trinkets.TRINKET_DOOR_STOP)
        if heldDoor then
            heldDoor:Open()
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
        if player:HasCollectible(collectibles.COLLECTIBLE_XRAY_VISION) then
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if
                    door
                    and (
                        door:IsRoomType(roomTypes.ROOM_SECRET)
                        or door:IsRoomType(roomTypes.ROOM_SUPERSECRET)
                    )
                then
                    door:TryBlowOpen(false, player)
                end
            end
        end
    end
end
