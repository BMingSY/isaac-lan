-- Native room-scoped rosters cannot see a teammate's candle in another room.
return function(level, actors, collectible)
    if level:GetCurses() == 0 then
        return
    end
    for _, actor in ipairs(actors) do
        for _, item in ipairs(actor[4][2]) do
            if item[1] == collectible and item[2] > 0 then
                level:RemoveCurses(level:GetCurses())
                return
            end
        end
    end
end
