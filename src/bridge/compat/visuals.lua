return function(...)
    local components = { ... }
    local function component(entity)
        for _, candidate in ipairs(components) do
            if candidate.matches(entity) then
                return candidate
            end
        end
    end
    return {
        capture = function(entity, id, sprite)
            local selected = component(entity)
            return selected and selected.capture(entity, id, sprite) or false
        end,
        apply = function(entity, value, applySprite)
            local selected = component(entity)
            if selected then
                selected.apply(entity, value, applySprite)
            else
                assert(value == false, "Unexpected entity visual state")
            end
        end,
        link = function(entity, value, ref)
            local selected = component(entity)
            if selected and selected.link then
                selected.link(entity, value, ref)
            end
        end,
    }
end
