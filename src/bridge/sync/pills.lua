-- ItemPool identification and color/effect assignments are shared run state.
return function(native)
    local function validate(value)
        assert(type(value) == "string" and #value == 75, "Invalid pill state")
        local cursor = 1
        for _ = 1, 15 do
            local effect, known
            effect, known, cursor = string.unpack(">i4B", value, cursor)
            assert(effect >= -1 and effect < 4096 and known <= 1, "Invalid pill state")
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
