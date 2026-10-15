return function(dogma, heldBombs)
    local function component(entity)
        return heldBombs.matches(entity) and heldBombs or dogma
    end
    return {
        capture = function(entity, id)
            return component(entity).capture(entity, id)
        end,
        apply = function(entity, value)
            component(entity).apply(entity, value)
        end,
        link = function(entity, value, ref)
            local selected = component(entity)
            if selected.link then
                selected.link(entity, value, ref)
            end
        end,
    }
end
