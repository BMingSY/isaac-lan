return function(room, bossType, closeBossExit, trapdoorType)
    if room:IsClear() then
        return
    end
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then
            door:Close(true)
        end
    end
    if room:GetType() == bossType then
        closeBossExit(room, trapdoorType)
    end
end
