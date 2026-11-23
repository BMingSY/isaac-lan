-- Boss Rush progress belongs to the occupied room, including the quiet ticks
-- between waves. Only the host owns the native queue and starts the next wave.
return function(native, roomType)
    return {
        capture = function(room)
            if room:GetType() ~= roomType then
                return false
            end
            local wave, total = native.room_ambush_wave()
            return { room:IsAmbushActive(), room:IsAmbushDone(), wave, total }
        end,
        apply = function(room, value)
            if room:GetType() ~= roomType then
                assert(value == false, "Boss Rush state outside its room")
                return
            end
            assert(type(value) == "table" and #value == 4, "Missing Boss Rush state")
            local active, done, wave, total = table.unpack(value)
            assert(type(active) == "boolean" and type(done) == "boolean", "Invalid Boss Rush flags")
            assert(native.room_ambush_wave(active and 1 or 0, wave, total))
            if room:IsAmbushDone() ~= done then
                room:SetAmbushDone(done)
            end
        end,
    }
end
