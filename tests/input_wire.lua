-- Check the fixture's Lua input encoding against the production native codec.
local neutral, pointer = assert(arg[1]), assert(arg[2])
local function hex(bytes)
    return (
        bytes:gsub(".", function(value)
            return string.format("%02x", string.byte(value))
        end)
    )
end
assert(neutral == hex(string.rep("\0", 43)), "Fixture neutral-input size differs from native codec")
local values = {}
for action = 0, 15 do
    values[#values + 1] = string.pack(">I2", action == 1 and 65535 or 0)
end
local bytes = table.concat(values) .. string.pack(">I2Bff", 0, 1, -123.25, 876.5)
assert(hex(bytes) == pointer, "Lua/native action and pointer field layouts disagree")
assert(string.unpack(">B", bytes, 35) == 1)
print("PASS Lua/native input field layout, endianness and neutral frame")
