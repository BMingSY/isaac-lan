-- The wave counter belongs to the floor, including viewers in side rooms.
-- Replicas display the authority's counter without starting native waves.
return function(game)
    local function wave(value)
        assert(math.type(value) == "integer" and value >= 0 and value <= 12, "Invalid Greed wave")
        return value
    end
    return {
        capture = function()
            local current = game()
            return current:IsGreedMode() and wave(current:GetLevel().GreedModeWave) or false
        end,
        apply = function(value)
            local current = game()
            if current:IsGreedMode() then
                current:GetLevel().GreedModeWave = wave(value)
            else
                assert(value == false, "Greed state outside Greed mode")
            end
        end,
    }
end
