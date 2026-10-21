-- These native visuals read TemporaryEffects in addition to actor pose/size.
-- Counts retain native ownership and lifetime without replaying item use.
return function(collectibles)
    -- Actor tuple field 9, in this fixed wire order.
    local ids = {
        assert(collectibles.COLLECTIBLE_MEGA_MUSH),
        assert(collectibles.COLLECTIBLE_BOOK_OF_SHADOWS),
        assert(collectibles.COLLECTIBLE_HOLY_MANTLE),
    }
    return {
        capture = function(p)
            local effects, counts = p:GetEffects(), {}
            for i, id in ipairs(ids) do
                counts[i] = effects:GetCollectibleEffectNum(id)
            end
            return counts
        end,
        apply = function(p, counts)
            assert(type(counts) == "table" and #counts == #ids)
            -- Validate the whole tuple before changing any native effect.
            for i = 1, #ids do
                local count = counts[i]
                assert(type(count) == "number" and count % 1 == 0 and count >= 0 and count <= 65535)
            end
            local effects = p:GetEffects()
            for i, id in ipairs(ids) do
                local delta = counts[i] - effects:GetCollectibleEffectNum(id)
                if delta > 0 then
                    effects:AddCollectibleEffect(id, true, delta)
                elseif delta < 0 then
                    effects:RemoveCollectibleEffect(id, -delta)
                end
            end
        end,
    }
end
