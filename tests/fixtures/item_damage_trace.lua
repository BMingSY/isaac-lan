-- Observe native shield changes without altering damage, inventory or room state.
return function(report, enabled)
    local previous = {}
    return function(phase, player)
        if not enabled() then
            previous = {}
            return
        end
        local function observe(p)
            local count = p:GetEffects()
                :GetCollectibleEffectNum(CollectibleType.COLLECTIBLE_HOLY_MANTLE)
            local stage = Game():GetLevel():GetStage()
            local key = p.InitSeed .. ":" .. p.ControllerIndex
            local value = stage .. ":" .. count
            if previous[key] ~= value then
                previous[key] = value
                report("shield_change", {
                    phase = phase,
                    seed = p.InitSeed,
                    controller = p.ControllerIndex,
                    mantle = count,
                    stage = stage,
                    room = Game():GetLevel():GetCurrentRoomIndex(),
                    room_frame = Game():GetRoom():GetFrameCount(),
                    game_frame = Game():GetFrameCount(),
                })
            end
        end
        if player then
            observe(player)
        else
            for i = 0, Game():GetNumPlayers() - 1 do
                observe(Isaac.GetPlayer(i))
            end
        end
    end
end
