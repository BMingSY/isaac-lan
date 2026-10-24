-- Explicit bounded event contract; neither colors nor native pointers cross it.
local header, record = ">I4", ">I4I4I4i4i4I4I4BB"
local recordSize = string.packsize(record)
return function(bytes)
    assert(type(bytes) == "string" and #bytes >= 4, "Invalid combat event header")
    local count, offset = string.unpack(header, bytes)
    assert(count <= 512 and #bytes == 4 + count * recordSize, "Invalid combat event size")
    local result, last = {}, 0
    for _ = 1, count do
        local serial, tick, epoch, dimension, room, source, target, accepted, duration
        serial, tick, epoch, dimension, room, source, target, accepted, duration, offset =
            string.unpack(record, bytes, offset)
        assert(
            serial > last and target > 0 and accepted <= 1 and duration <= 6,
            "Invalid combat event"
        )
        assert(accepted == 1 or duration == 0, "Rejected damage has presentation")
        last = serial
        result[#result + 1] = {
            serial = serial,
            tick = tick,
            epoch = epoch,
            dimension = dimension,
            room = room,
            source = source,
            target = target,
            accepted = accepted == 1,
            duration = duration / 30,
        }
    end
    return result
end
