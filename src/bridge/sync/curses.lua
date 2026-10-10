-- A floor owns one shared mask; players never carry separate level curses.
local function mask(value)
    assert(
        math.type(value) == "integer" and value >= 0 and value <= 0xffffffff,
        "Invalid level curse mask"
    )
    return value
end
return {
    capture = function(level)
        return mask(level:GetCurses())
    end,
    apply = function(level, value)
        value = mask(value)
        local current = mask(level:GetCurses())
        local removed, added = current & ~value, value & ~current
        if removed ~= 0 then
            level:RemoveCurses(removed)
        end
        if added ~= 0 then
            level:AddCurse(added, false)
        end
        return removed ~= 0 or added ~= 0
    end,
}
