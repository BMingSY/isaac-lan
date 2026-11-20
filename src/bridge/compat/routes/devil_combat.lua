-- Deal rooms can gain enemies after their entrance has already opened.
return function(native, doorStop)
    local closed = {}
    local function update()
        local game = Game()
        local room = game:GetRoom()
        if room:GetType() ~= RoomType.ROOM_DEVIL then
            return
        end
        local info = native.api_info()
        if info.authority ~= 1 or info.ready ~= 1 then
            return
        end
        local seed = room:GetDecorationSeed()
        if room:IsClear() then
            local mask = closed[seed]
            if mask then
                for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                    local door = room:GetDoor(slot)
                    if
                        (mask & (1 << slot)) ~= 0
                        and door
                        and not door:IsLocked()
                        and not door:IsOpen()
                    then
                        door:Open()
                    end
                end
                closed[seed] = nil
            end
        elseif not closed[seed] and room:GetAliveEnemiesCount() > 0 then
            local mask, held = 0, 0
            for i = 0, game:GetNumPlayers() - 1 do
                local door = doorStop(
                    room,
                    game:GetLevel(),
                    Isaac.GetPlayer(i),
                    TrinketType.TRINKET_DOOR_STOP
                )
                if door then
                    held = held | (1 << door.Slot)
                end
            end
            for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                local door = room:GetDoor(slot)
                if door and door:IsOpen() and not door.Busted and (held & (1 << slot)) == 0 then
                    door:Close(true)
                    mask = mask | (1 << slot)
                end
            end
            closed[seed] = mask
        end
    end
    return {
        update = update,
        reset = function()
            closed = {}
        end,
    }
end
