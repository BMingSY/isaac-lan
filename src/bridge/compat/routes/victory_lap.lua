-- The host chooses; replicas enter the same native restart through the epoch barrier.
return {
    id = "routes.victory_lap",
    matches = function(event)
        return event.restart == 2
    end,
    begin = function(native)
        assert(native.victory_lap_begin(), "Native Victory Lap restart failed")
    end,
}
