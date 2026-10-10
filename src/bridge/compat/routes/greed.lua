-- The wave counter belongs to the floor, including viewers in side rooms.
-- Replicas display the authority's counter without starting native waves.
return function(game)
    local authoritative
    local function wave(value)
        assert(math.type(value) == "integer" and value >= 0 and value <= 12, "Invalid Greed wave")
        return value
    end
    local function apply(value)
        local current = game()
        if current:IsGreedMode() then
            current:GetLevel().GreedModeWave = wave(value)
        else
            assert(value == false, "Greed state outside Greed mode")
        end
    end
    return {
        capture = function()
            local current = game()
            return current:IsGreedMode() and wave(current:GetLevel().GreedModeWave) or false
        end,
        apply = function(value)
            apply(value)
            authoritative = value
        end,
        present = function()
            -- Native room presentation runs after snapshot application and can
            -- advance this counter locally. Restore it before HUD rendering.
            if authoritative ~= nil then
                apply(authoritative)
            end
        end,
        reset = function()
            authoritative = nil
        end,
    }
end
