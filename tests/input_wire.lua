-- Compare the shared fixture codec with independently generated native frames.
local neutral, pointer, mixed = assert(arg[1]), assert(arg[2]), assert(arg[3])
local input = dofile(assert(arg[4]))
local function hex(bytes)
    return (
        bytes:gsub(".", function(value)
            return string.format("%02x", string.byte(value))
        end)
    )
end
local function unhex(value)
    return (value:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end
assert(hex(input.neutral) == neutral, "Fixture neutral input differs from native codec")
assert(input.encode() == input.buttons(0))
local sample = input.encode({
    values = { [1] = input.maxValue },
    pointer = { active = true, x = -123.25, y = 876.5 },
})
assert(hex(sample) == pointer, "Lua/native action and pointer field layouts disagree")
local values = {}
for action = 0, input.actionCount - 1 do
    values[action] = (action + 1) * 997
end
local allFields = input.encode({
    values = values,
    triggered = 0xa55a,
    pointer = { active = true, x = -32768, y = 32768 },
})
assert(hex(allFields) == mixed, "Lua/native fields or endianness disagree")
local nativeFrames = { unhex(neutral), unhex(pointer), unhex(mixed), unhex(neutral) }
local batch = table.concat(nativeFrames)
for slot = 0, #nativeFrames - 1 do
    assert(
        input.encode(input.decode(batch, slot)) == nativeFrames[slot + 1],
        "Player slot or decoded fields changed during replay"
    )
end
local decoded = input.decode(batch, 2)
assert(decoded.triggered == 0xa55a and decoded.pointer.active)
assert(decoded.pointer.x == -32768 and decoded.pointer.y == 32768)
for action, value in pairs(values) do
    assert(decoded.values[action] == value)
end
local pressed = input.decode(input.buttons((1 << 1) | (1 << 9), 1 << 9))
assert(pressed.values[1] == input.maxValue and pressed.values[9] == input.maxValue)
assert(pressed.triggered == 1 << 9 and not pressed.pointer.active)
assert(not pcall(input.decode, batch, -1))
assert(not pcall(input.decode, batch, 4))
assert(not pcall(input.decode, batch, 0.5))
assert(not pcall(input.encode, { values = { [input.actionCount] = 1 } }))
for size = 0, #input.neutral - 1 do
    assert(not pcall(input.decode, input.neutral:sub(1, size)), "Truncated fixture input accepted")
end
print("PASS shared Lua/native input codec, defaults, all fields, four slots and malformed frames")
