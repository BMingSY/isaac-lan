-- DOGMA_ORB subtype 1 draws its warning beam from Entity.TargetPosition.
-- Its sprite alone is insufficient, and replicas do not run the effect's AI.
return function(vector)
    local function matches(entity)
        return entity.Type == 1000 and entity.Variant == 172 and entity.SubType == 1
    end
    return {
        capture = function(entity)
            if not matches(entity) then
                return false
            end
            local position = entity.TargetPosition
            return string.pack(">ff", position.X, position.Y)
        end,
        apply = function(entity, value)
            if value == false then
                assert(not matches(entity), "Missing Dogma warning geometry")
                return
            end
            assert(matches(entity), "Unexpected Boss visual state")
            assert(type(value) == "string" and #value == 8, "Invalid Dogma warning geometry")
            local x, y = string.unpack(">ff", value)
            assert(
                x == x and y == y and math.abs(x) < math.huge and math.abs(y) < math.huge,
                "Invalid Dogma warning direction"
            )
            entity.TargetPosition = vector(x, y)
        end,
    }
end
