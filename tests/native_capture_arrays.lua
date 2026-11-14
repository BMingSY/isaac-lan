local native = assert(_IsaacLanCodec)
local capture, encode = native.capture_array, native.state_encode
local memo = {}
local first = capture({ 0, 1 }, memo)
assert(math.type(first[1]) == "float" and math.type(first[2]) == "float")
assert(first == capture({ 0.0, 1.0 }, memo))
assert(first ~= capture({ 0, 1 }))
assert(capture({ 0, 1 }) ~= capture({ 0, 1 }))
local negative = capture({ -0.0, 1 }, memo)
assert(negative ~= first and 1 / negative[1] < 0 and 1 / first[1] > 0)
local color = capture({ 0, 1, 0, 1, 0, 1, 0 }, memo)
assert(color ~= first and #color == 7)
assert(color == capture({ 0, 1, 0, 1, 0, 1, 0 }, memo))
local original = encode({ first, negative, color })
for i = 1, native.capture_array_limit * 3 do
    local values = { i + 0.25, i + 0.5 }
    assert(encode(capture(values, memo)) == encode(capture(values)))
end
assert(#memo == native.capture_array_limit)
assert(first == capture({ 0, 1 }, memo), "Full memo lost an existing entry")
assert(encode({ first, negative, color }) == original, "Capture mutated a prior snapshot")

-- Fail at Lua table/string allocations and recover using the same memo. A
-- partially inserted entry must never bypass the retention bound.
local recovering = {}
local values = { 0.125, 0.25 }
local function insert()
    return capture(values, recovering)
end
for budget = 0, 48 do
    values[1] = budget + 0.125
    native.with_allocation_limit(budget, insert)
    assert(encode(insert()) == encode(capture(values)))
    local numeric, keyed = 0, 0
    for key in pairs(recovering) do
        if type(key) == "number" then
            numeric = numeric + 1
        else
            keyed = keyed + 1
        end
    end
    assert(keyed <= numeric and numeric <= native.capture_array_limit)
end
local weak = setmetatable({ recovering }, { __mode = "v" })
recovering = nil
collectgarbage("collect")
assert(weak[1] == nil, "Capture retained a caller's Lua memo")
print(
    "PASS numeric capture identity, signed zero, capacity, immutable snapshots and allocation recovery"
)
