return function(...)
    local components = { ... }
    local lastType, lastVariant, lastSubtype, selected
    local identity = {}
    -- Match only the captured identity tuple. This bounded cache retains no
    -- entity; native fields and each component's validation remain live.
    local function component(entity, kind, variant, subtype)
        if kind == nil then
            kind, variant, subtype = entity.Type, entity.Variant, entity.SubType
        end
        if kind == lastType and variant == lastVariant and subtype == lastSubtype then
            return selected
        end
        lastType, lastVariant, lastSubtype, selected = kind, variant, subtype, nil
        identity.Type, identity.Variant, identity.SubType = kind, variant, subtype
        for _, candidate in ipairs(components) do
            if candidate.matches(identity) then
                selected = candidate
                break
            end
        end
        return selected
    end
    return {
        capture = function(entity, id, sprite, kind, variant, subtype)
            local selected = component(entity, kind, variant, subtype)
            return selected and selected.capture(entity, id, sprite) or false
        end,
        apply = function(entity, value, applySprite, kind, variant, subtype)
            local selected = component(entity, kind, variant, subtype)
            if selected then
                selected.apply(entity, value, applySprite)
            else
                assert(value == false, "Unexpected entity visual state")
            end
        end,
        link = function(entity, value, ref, kind, variant, subtype)
            local selected = component(entity, kind, variant, subtype)
            if selected and selected.link then
                selected.link(entity, value, ref)
            end
        end,
    }
end
