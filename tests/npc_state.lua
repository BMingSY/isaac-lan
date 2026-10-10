local root = assert(arg[1])
local codec = dofile(root .. "/src/bridge/state/codec.lua")
local state = dofile(root .. "/src/bridge/state/npc.lua")
function Vector(x, y)
    return { X = x, Y = y }
end
assert(state.capture(nil) == false)
local npc = { V1 = Vector(1.25, -2.5), V2 = Vector(0, 33) }
local function roundTrip()
    local bytes = codec.decode(codec.encode({ state.capture(npc) }))[1]
    local replica = {}
    state.apply(replica, bytes)
    assert(state.capture(replica) == bytes)
    return replica
end
local replica = roundTrip()
assert(replica.V1.X == 1.25 and replica.V2.Y == 33)
-- Native integer -1, viewed through the NPC Vector API, is a quiet NaN.
local sentinel = string.unpack(">f", string.pack(">I4", 0xffffffff))
npc.V2 = Vector(sentinel, math.huge)
replica = roundTrip()
assert(replica.V2.X ~= replica.V2.X and replica.V2.Y == math.huge)
assert(string.pack(">f", replica.V2.X) == string.pack(">I4", 0xffffffff))
for _, bad in ipairs({ "", string.rep("x", 15), string.rep("x", 17), {} }) do
    assert(not pcall(state.apply, {}, bad))
end
-- Ordinary numbers retain their strict validation, including the location.
for _, bad in ipairs({ sentinel, math.huge, -math.huge }) do
    local ok, error = pcall(codec.encode, { { 1, bad } })
    assert(not ok and error:find("Non-finite state value at [1][2]", 1, true))
end
assert(not pcall(codec.decode, "\4" .. string.pack(">f", sentinel)))
print("PASS NPC scratch sentinels, infinities and strict ordinary state numbers")
