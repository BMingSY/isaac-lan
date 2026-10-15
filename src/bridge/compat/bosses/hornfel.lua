-- Hornfel renders held bombs through two native EntityPtr slots, initialized
-- by its AI on the host. Carry stable IDs and bind only after reconciliation.
return function(native, types, entities)
    local function decode(value)
        assert(type(value) == "string" and #value == 8, "Invalid Hornfel bomb links")
        return string.unpack(">I4I4", value)
    end
    return {
        matches = function(entity)
            return entity.Type == types.ENTITY_HORNFEL
        end,
        capture = function(entity, id)
            local first, second = native.hornfel_bombs(entity:GetSprite())
            assert(
                type(first) == "number" and type(second) == "number",
                "Cannot read Hornfel bombs"
            )
            local links = { 0, 0 }
            for _, bomb in ipairs(entities()) do
                if bomb:Exists() and bomb.Type == types.ENTITY_BOMB then
                    if bomb.Index == first then
                        links[1] = id(bomb)
                    end
                    if bomb.Index == second then
                        links[2] = id(bomb)
                    end
                end
            end
            return string.pack(">I4I4", table.unpack(links))
        end,
        apply = function(_, value)
            decode(value)
        end,
        link = function(entity, value, ref)
            local first, second = decode(value)
            local function resolve(identifier)
                if identifier == 0 then
                    return false
                end
                local bomb = assert(ref(identifier), "Missing Hornfel bomb")
                assert(bomb:Exists() and bomb.Type == types.ENTITY_BOMB, "Invalid Hornfel bomb")
                return bomb:GetSprite()
            end
            local a, b = resolve(first), resolve(second)
            assert(native.hornfel_bombs(entity:GetSprite(), a, b))
        end,
    }
end
