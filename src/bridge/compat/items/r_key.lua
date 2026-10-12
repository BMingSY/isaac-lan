return {
    id = "items.r_key",
    matches = function(event)
        return event.restart == 1
    end,
    begin = function(native)
        assert(native.r_key_begin(), "Native R Key restart failed")
    end,
}
