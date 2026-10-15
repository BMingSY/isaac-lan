-- Native renderers require two slots for Hornfel and three for Horny Boys.
-- Carry stable IDs and bind only after all snapshot entities exist.
return function(native, types, entities)
    local function count(entity)
        return entity.Type == types.ENTITY_HORNY_BOYS and 3 or 2
    end
    local function format(entity)
        return ">" .. string.rep("I4", count(entity))
    end
    local function decode(entity, value)
        local size = count(entity)
        assert(type(value) == "string" and #value == size * 4, "Invalid Boss held bomb links")
        local links = { string.unpack(format(entity), value) }
        links[size + 1] = nil
        return links
    end
    return {
        matches = function(entity)
            return entity.Type == types.ENTITY_HORNFEL or entity.Type == types.ENTITY_HORNY_BOYS
        end,
        capture = function(entity, id)
            local indices = { native.boss_held_bombs(entity:GetSprite()) }
            assert(#indices == count(entity), "Cannot read Boss held bombs")
            local links = {}
            for i = 1, count(entity) do
                assert(type(indices[i]) == "number", "Invalid held bomb index")
                links[i] = 0
            end
            for _, bomb in ipairs(entities()) do
                if bomb:Exists() and bomb.Type == types.ENTITY_BOMB then
                    for i, index in ipairs(indices) do
                        if bomb.Index == index then
                            links[i] = id(bomb)
                        end
                    end
                end
            end
            return string.pack(format(entity), table.unpack(links))
        end,
        apply = function(entity, value)
            decode(entity, value)
        end,
        link = function(entity, value, ref)
            local links = decode(entity, value)
            for i, identifier in ipairs(links) do
                if identifier == 0 then
                    links[i] = false
                else
                    local bomb = assert(ref(identifier), "Missing Boss held bomb")
                    assert(
                        bomb:Exists() and bomb.Type == types.ENTITY_BOMB,
                        "Invalid Boss held bomb"
                    )
                    links[i] = bomb:GetSprite()
                end
            end
            assert(native.boss_held_bombs(entity:GetSprite(), table.unpack(links)))
        end,
    }
end
