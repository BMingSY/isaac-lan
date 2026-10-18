local root = assert(arg[1])
local native = assert(_IsaacLanCodec)
local reference = dofile(root .. "/src/bridge/sync/codec.lua")
local codec = { encode = native.state_encode, decode = native.state_decode }
local function compare(value)
    local expected = reference.encode(value)
    assert(codec.encode(value) == expected, "Native encoding differs")
    assert(reference.encode(codec.decode(expected)) == expected, "Native decoding differs")
    assert(codec.encode(reference.decode(expected)) == expected, "Mixed codecs differ")
    return expected
end

-- Execute the shared wire/budget/memo contract against both implementations.
local environment = setmetatable({
    arg = { root },
    loadfile = function(path)
        if path == root .. "/src/bridge/sync/codec.lua" then
            return function()
                return codec
            end
        end
        return loadfile(path)
    end,
}, { __index = _G })
assert(loadfile(root .. "/tests/codec_fragments.lua", "t", environment))()
compare({ math.mininteger, math.maxinteger, 0.0, -0.0, 1.0, -1.0, "\0\255", {} })
assert(math.type(codec.decode(codec.encode(1.0))) == "float")
assert(math.type(codec.decode(codec.encode(1))) == "integer")
assert(1 / codec.decode(codec.encode(-0.0)) == -math.huge)

-- Deterministic randomized nested values, including all finite float32 bit patterns.
math.randomseed(817243)
local function value(depth)
    local kind = math.random(depth < 5 and 6 or 5)
    if kind == 1 then
        return math.random(2) == 1
    elseif kind == 2 then
        return (math.random(0, 0x7fffffff) << 32) | math.random(0, 0x7fffffff)
    elseif kind == 3 then
        return -math.random(0, 0x7fffffff)
    elseif kind == 4 then
        local bits = math.random(0, 0x7fffffff)
        if bits & 0x7f800000 == 0x7f800000 then
            bits = bits & ~0x00800000
        end
        return (string.unpack(">f", string.pack(">I4", bits)))
    elseif kind == 5 then
        return string.rep(string.char(math.random(0, 255)), math.random(0, 32))
    end
    local result = {}
    for i = 1, math.random(0, 8) do
        result[i] = value(depth + 1)
    end
    return result
end
for _ = 1, 1500 do
    compare(value(0))
end

local payload = compare({ { "sprite", { 1, -0.5, 10000000000 } }, true, "hello\0world" })
for length = 0, #payload - 1 do
    assert(not pcall(codec.decode, payload:sub(1, length)), "Truncated payload accepted")
end
for _, invalid in ipairs({
    "\255",
    "\0\0",
    "\5\255\255",
    "\6\255\255",
    "\4" .. string.pack(">f", math.huge),
    "\4" .. string.pack(">f", 0 / 0),
    string.rep("\6\0\1", 12) .. "\0",
    string.rep("\0", 2 * 1024 * 1024 + 1),
}) do
    assert(not pcall(codec.decode, invalid))
end
local cycle = {}
cycle[1] = cycle
for _, invalid in ipairs({ cycle, function() end, coroutine.create(function() end), { 0 / 0 } }) do
    assert(not pcall(codec.encode, invalid))
    compare({ "after failure", 42 })
end
assert(not pcall(codec.encode, nil))
assert(not pcall(codec.decode, {}))

local tuple = { { 0.5, false }, "same-room" }
local luaMemo, nativeMemo = { [tuple] = false }, { [tuple] = false }
for slot = 1, 3 do
    local state = { tuple, slot, { "event", slot } }
    assert(codec.encode(state, nativeMemo) == reference.encode(state, luaMemo))
end
-- Memo fragments can be consumed across codecs, with identical budgets.
assert(codec.encode({ tuple }, luaMemo) == reference.encode({ tuple }, nativeMemo))
collectgarbage("collect")
if native.with_allocation_limit then
    local values = {}
    for i = 1, 1000 do
        values[i] = { i + 0.25, tostring(i) }
    end
    local encoded = compare(values)
    local failures = 0
    for limit = 0, 100 do
        local memo = { [values] = false }
        local ok = native.with_allocation_limit(limit, codec.encode, values, memo)
        failures = failures + (ok and 0 or 1)
        local decoded = native.with_allocation_limit(limit, codec.decode, encoded)
        failures = failures + (decoded and 0 or 1)
        compare({ "after allocation failure", limit })
        collectgarbage("collect")
    end
    assert(failures > 0, "Allocator fault injection did not exercise failures")
end
print("PASS native/Lua differential, numeric types, malformed input and failure recovery")
