-- Native rewind owns inventory, RNG and entity restoration.
return {
    id = "items.hourglass",
    matches = function(event)
        return event.rewind and #event.rewind > 0
    end,
    begin = function(native, event)
        assert(native.rewind_begin(event.rewind), "Native hourglass rewind failed")
    end,
}
