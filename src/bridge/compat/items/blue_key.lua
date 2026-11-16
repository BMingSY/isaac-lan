-- Native Level::ChangeRoom consumes source-door redirects before switching
-- the room pointer. Per-player transfers must keep that source context too.
return function(game, redirectFlag)
    local room, level = game:GetRoom(), game:GetLevel()
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then
            local target = level:GetRoomByIdx(door.TargetRoomIndex)
            if target and target.Data then
                target.Flags = target.Flags & ~redirectFlag
            end
        end
    end
end
