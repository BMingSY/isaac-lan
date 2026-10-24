-- Pinking Shears bodies retain the costume sprites captured when the item was used.
-- The current owner's sprite may already be a different costume or head-only pose.
return function(native, types, variants)
    local LAYERS, SPRITES, SPRITE_COUNT = 1, 2, 5
    return {
        matches = function(entity)
            return entity.Type == types.ENTITY_FAMILIAR and entity.Variant == variants.ISAACS_BODY
        end,
        capture = function(entity, _, sprite)
            local layers, bodies = native.familiar_body(entity:GetSprite())
            assert(layers and #bodies == SPRITE_COUNT, "Missing familiar body sprites")
            local values = {}
            for i, body in ipairs(bodies) do
                values[i] = sprite(body)
            end
            return { layers, values }
        end,
        apply = function(entity, value, applySprite)
            assert(
                type(value) == "table"
                    and #value == 2
                    and type(value[LAYERS]) == "string"
                    and #value[LAYERS] == 16
                    and type(value[SPRITES]) == "table"
                    and #value[SPRITES] == SPRITE_COUNT,
                "Invalid familiar body sprites"
            )
            local layers, bodies = native.familiar_body(entity:GetSprite())
            assert(layers and #bodies == SPRITE_COUNT, "Missing familiar body sprites")
            for i, body in ipairs(bodies) do
                applySprite(body, value[SPRITES][i])
            end
            assert(native.familiar_body(entity:GetSprite(), value[LAYERS]))
        end,
    }
end
