return {
    id = "items.r_key",
    matches = function(event)
        return event.rKey
    end,
    begin = function(native)
        assert(native.r_key_begin(), "Native R Key restart failed")
    end,
}
