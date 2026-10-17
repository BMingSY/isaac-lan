local stomachVariants = { [1010] = true, [1020] = true }

return function(game, player, dungeonType)
    local data = game:GetLevel():GetCurrentRoomDesc().Data
    if not data or data.Type ~= dungeonType or not stomachVariants[data.Variant] then
        return
    end
    -- Native ChangeRoom completes the first entrant's pitfall state. An
    -- occupied stomach only runs player entry. Let the native exit animation
    -- finish that state for arriving bodies; stopping the sprite alone leaves
    -- the pitfall update reasserting its control lock.
    for i = 0, game:GetNumPlayers() - 1 do
        local p = player(i)
        if not p:IsExtraAnimationFinished() and p:GetSprite():GetAnimation() == "FallIn" then
            p:AnimatePitfallOut()
        end
    end
end
