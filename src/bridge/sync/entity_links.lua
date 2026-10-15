-- Native-only EntityPtr links use the same stable IDs as Parent/Child.
local MINECART = 965
return function(native, entities)
    return {
        capture = function(entity, id)
            local index = assert(native.entity_minecart(entity:GetSprite()))
            if index < 0 then
                return 0
            end
            for _, cart in ipairs(entities()) do
                if cart:Exists() and cart.Index == index then
                    assert(cart.Type == MINECART, "Invalid minecart entity")
                    return id(cart)
                end
            end
            -- An EntityPtr can still reference a retired allocation until the
            -- next native cleanup. Such objects are excluded from the view.
            return 0
        end,
        apply = function(entity, identifier, ref)
            assert(math.type(identifier) == "integer" and identifier >= 0, "Invalid minecart ID")
            local target = false
            if identifier ~= 0 then
                local cart = assert(ref(identifier), "Missing minecart")
                assert(cart:Exists() and cart.Type == MINECART, "Invalid minecart entity")
                target = cart:GetSprite()
            end
            assert(native.entity_minecart(entity:GetSprite(), target))
        end,
    }
end
