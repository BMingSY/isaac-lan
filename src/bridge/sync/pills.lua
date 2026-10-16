-- ItemPool identification and color/effect assignments are shared run state.
local PILL_COLOR_COUNT, EFFECT_ID_LIMIT = 15, 4096
local FORMAT = ">i4B"
local BYTE_COUNT = PILL_COLOR_COUNT * string.packsize(FORMAT)
return function(native)
    local function validate(value)
        assert(type(value) == "string" and #value == BYTE_COUNT, "Invalid pill state")
        local cursor = 1
        for _ = 1, PILL_COLOR_COUNT do
            local effect, known
            effect, known, cursor = string.unpack(FORMAT, value, cursor)
            assert(effect >= -1 and effect < EFFECT_ID_LIMIT and known <= 1, "Invalid pill state")
        end
        return value
    end
    return {
        capture = function()
            return validate(native.pill_state())
        end,
        apply = function(value)
            assert(native.pill_state(validate(value)), "Cannot restore pill state")
        end,
    }
end
