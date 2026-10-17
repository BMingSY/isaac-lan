-- Native rendering needs the temporary effect as well as the actor's size.
-- Restore its count without replaying item use, damage or the use animation.
return function(collectibles)
    local id = assert(collectibles.COLLECTIBLE_MEGA_MUSH)
    return {
        capture = function(p)
            return p:GetEffects():GetCollectibleEffectNum(id)
        end,
        apply = function(p, count)
            assert(type(count) == "number" and count % 1 == 0 and count >= 0 and count <= 65535)
            local effects = p:GetEffects()
            local delta = count - effects:GetCollectibleEffectNum(id)
            if delta > 0 then
                effects:AddCollectibleEffect(id, true, delta)
            elseif delta < 0 then
                effects:RemoveCollectibleEffect(id, -delta)
            end
        end,
    }
end
