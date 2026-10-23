-- Test-only input contract. Keep byte layout here; scenarios use named fields.
-- bridge.input-wire compares this codec with the production C++ codec.
local actionFormat, tailFormat = ">I2", ">I2Bff"
local input = { actionCount = 16, maxValue = 65535 }
local frameSize = input.actionCount * string.packsize(actionFormat) + string.packsize(tailFormat)

function input.encode(frame)
    frame = frame or {}
    local values, pointer = frame.values or {}, frame.pointer or {}
    for action in pairs(values) do
        assert(
            math.type(action) == "integer" and action >= 0 and action < input.actionCount,
            "Unknown test input action"
        )
    end
    local pieces = {}
    for action = 0, input.actionCount - 1 do
        pieces[#pieces + 1] = string.pack(actionFormat, values[action] or 0)
    end
    pieces[#pieces + 1] = string.pack(
        tailFormat,
        frame.triggered or 0,
        pointer.active and 1 or 0,
        pointer.x or 0,
        pointer.y or 0
    )
    return table.concat(pieces)
end

function input.decode(bytes, slot)
    slot = slot or 0
    assert(#bytes % frameSize == 0, "Incomplete test input frame")
    assert(
        math.type(slot) == "integer" and slot >= 0 and (slot + 1) * frameSize <= #bytes,
        "Input player slot is out of range"
    )
    local values, offset = {}, slot * frameSize + 1
    for action = 0, input.actionCount - 1 do
        values[action], offset = string.unpack(actionFormat, bytes, offset)
    end
    local triggered, active, x, y = string.unpack(tailFormat, bytes, offset)
    assert(active == 0 or active == 1, "Invalid test pointer flag")
    return {
        values = values,
        triggered = triggered,
        pointer = { active = active == 1, x = x, y = y },
    }
end

function input.buttons(held, triggered)
    local values = {}
    for action = 0, input.actionCount - 1 do
        values[action] = held & (1 << action) ~= 0 and input.maxValue or 0
    end
    return input.encode({ values = values, triggered = triggered })
end

input.neutral = input.encode()
return input
