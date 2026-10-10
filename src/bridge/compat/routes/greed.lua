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
        authority = function(native, exitType)
            local current = game()
            if not current:IsGreedMode() then
                return
            end
            local level = current:GetLevel()
            local bossWave = current.Difficulty == 3 and 11 or 10
            if level:GetStage() >= 7 or level.GreedModeWave < bossWave then
                return
            end
            local arena = level:GetRoomByIdx(level:GetStartingRoomIndex(), 0)
            if not arena.Clear then
                return
            end
            local visited = {}
            for slot, position in pairs(native.rooms_positions()) do
                local key = position.dimension .. ":" .. position.index
                local descriptor = level:GetRoomByIdx(position.index, position.dimension)
                if
                    not visited[key]
                    and descriptor.Data
                    and descriptor.Data.Type == exitType
                    and not descriptor.Clear
                then
                    visited[key] = true
                    assert(native.rooms_with_player(tonumber(slot), function()
                        local room = current:GetRoom()
                        -- Independent room entry can retain the exit's locked
                        -- clear flag after the arena finishes its Boss waves.
                        -- Restore only an empty Greed exit on a completed floor;
                        -- native grid update still owns opening and collision.
                        if room:GetAliveEnemiesCount() == 0 then
                            room:SetClear(true)
                        end
                    end))
                end
            end
        end,
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
