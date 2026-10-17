return function(report)
    local function curseMask(names)
        local mask = 0
        for _, name in ipairs(names or {}) do
            mask = mask | assert(LevelCurse[name], name)
        end
        return mask
    end
    return {
        prepare = function(case)
            local rules = case.room_effects
            if not rules then
                return
            end
            local level = Game():GetLevel()
            level:RemoveCurses(level:GetCurses())
            local mask = curseMask(rules.preset_curses)
            if mask ~= 0 then
                level:AddCurse(mask, false)
            end
            if rules.identify_pills then
                for color = 1, 3 do
                    Game():GetItemPool():IdentifyPill(color)
                end
            end
            report("floor_effect_precondition", {
                initial_curses = mask,
                remaining_curses = curseMask(rules.remaining_curses),
            })
        end,
        sample = function(case)
            if not case.room_effects then
                return nil
            end
            local level = Game():GetLevel()
            local result = { stage = level:GetStage(), curses = level:GetCurses() }
            if case.room_effects.identify_pills then
                result.identified_pills = {}
                for color = 1, 3 do
                    result.identified_pills[#result.identified_pills + 1] = {
                        color = color,
                        known = Game():GetItemPool():IsPillIdentified(color),
                    }
                end
            end
            if case.room_effects.map then
                local rooms = level:GetRooms()
                result.map = {}
                for i = 0, rooms.Size - 1 do
                    local d = rooms:Get(i)
                    if d.Data and d.SafeGridIndex >= 0 then
                        result.map[#result.map + 1] = {
                            index = d.SafeGridIndex,
                            type = d.Data.Type,
                            flags = d.DisplayFlags,
                        }
                    end
                end
                table.sort(result.map, function(a, b)
                    return a.index < b.index
                end)
            end
            return result
        end,
        curseRoll = function(case, curses)
            if case and case.room_effects then
                report(
                    "floor_curse_roll",
                    { stage = Game():GetLevel():GetStage(), curses = curses }
                )
            end
        end,
    }
end
