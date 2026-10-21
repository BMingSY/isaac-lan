-- Dice floors reuse the native sacrifice-complete flag. Gameplay stays on the
-- authority; a newly accepted activation starts only the local screen effects.
return function(fields)
    local Location = fields.location
    local darkness, darkenFrames, shakeFrames = 1, 60, 50
    return function(game, diceRoomType)
        local previousRoom, previousUsed, previousTick
        return {
            apply = function(view)
                local current = game()
                local room = current:GetRoom()
                local key
                for _, location in ipairs(view.locations) do
                    if location[Location.slot] == view.slot then
                        key = view.epoch
                            .. ":"
                            .. location[Location.dimension]
                            .. ":"
                            .. location[Location.index]
                        break
                    end
                end
                if key == previousRoom and previousTick and view.tick <= previousTick then
                    return
                end
                local used = room:GetType() == diceRoomType and room:IsSacrificeDone()
                if
                    key == previousRoom
                    and previousTick
                    and view.tick > previousTick
                    and used
                    and not previousUsed
                then
                    current:Darken(darkness, darkenFrames)
                    current:ShakeScreen(shakeFrames)
                end
                previousRoom, previousUsed, previousTick = key, used, view.tick
            end,
            reset = function()
                previousRoom, previousUsed, previousTick = nil, nil, nil
            end,
        }
    end
end
