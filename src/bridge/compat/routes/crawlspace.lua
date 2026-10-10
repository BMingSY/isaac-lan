-- Keep the authoritative special-room return origin in the selected room view.
return function(level, vector)
    local function finite(value)
        return value == value and math.abs(value) < math.huge
    end
    return {
        capture = function()
            local current = level()
            local position = current.DungeonReturnPosition
            return string.pack(">ffi4", position.X, position.Y, current.DungeonReturnRoomIndex)
        end,
        apply = function(value)
            assert(type(value) == "string" and #value == 12, "Invalid special-room return context")
            local x, y, index = string.unpack(">ffi4", value)
            assert(
                finite(x) and finite(y) and index >= -20 and index < 169,
                "Invalid special-room return origin"
            )
            local current = level()
            current.DungeonReturnPosition = vector(x, y)
            current.DungeonReturnRoomIndex = index
        end,
    }
end
