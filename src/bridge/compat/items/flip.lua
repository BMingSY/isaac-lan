-- The alternate pedestal is an embedded native Sprite, independent of the
-- pickup's main appearance. Replicas render it without running pickup AI.
return function(native, types, variants)
    return {
        matches = function(entity)
            return entity.Type == types.ENTITY_PICKUP
                and entity.Variant == variants.PICKUP_COLLECTIBLE
        end,
        capture = function(entity, _, sprite)
            local visible, alternate = native.pickup_flip_visual(entity:GetSprite())
            return visible and sprite(alternate) or false
        end,
        apply = function(entity, value, applySprite)
            assert(value == false or type(value) == "table", "Invalid Flip pedestal visual")
            if value ~= false then
                local _, alternate = native.pickup_flip_visual(entity:GetSprite())
                applySprite(alternate, value)
            end
            assert(native.pickup_flip_visual(entity:GetSprite(), value ~= false))
        end,
    }
end
