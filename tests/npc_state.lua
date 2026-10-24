local root = assert(arg[1])
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local state = dofile(root .. "/src/bridge/sync/npc.lua")
function Vector(x, y)
    return { X = x, Y = y }
end
local function model()
    return {
        boss = true,
        IsBoss = function(self)
            return self.boss
        end,
        GetSprite = function(self)
            return self
        end,
    }
end
local function apply(npc, bytes)
    state.apply(npc, bytes, function(sprite, boss)
        sprite.boss = boss
        return true
    end)
end
assert(state.capture(nil) == false)
local npc = model()
npc.V1, npc.V2, npc.TargetPosition = Vector(1.25, -2.5), Vector(0, 33), Vector(320, 280)
local function roundTrip()
    local bytes = codec.decode(codec.encode({ state.capture(npc) }))[1]
    local replica = model()
    apply(replica, bytes)
    assert(state.capture(replica) == bytes)
    return replica
end
local replica = roundTrip()
assert(replica.V1.X == 1.25 and replica.V2.Y == 33)
assert(replica.TargetPosition.X == 320 and replica.TargetPosition.Y == 280)
-- A replica spawned away from the anchor must acquire its geometry from the
-- view, including when that same allocation is reused in a different room.
for _, target in ipairs({ Vector(320, 280), Vector(-40, 120), Vector(0, 0) }) do
    npc.TargetPosition = target
    local bytes = state.capture(npc)
    apply(replica, bytes)
    apply(replica, bytes)
    assert(replica.TargetPosition.X == target.X and replica.TargetPosition.Y == target.Y)
end
-- Native integer -1, viewed through the NPC Vector API, is a quiet NaN.
local sentinel = string.unpack(">f", string.pack(">I4", 0xffffffff))
npc.V2 = Vector(sentinel, math.huge)
replica = roundTrip()
assert(replica.V2.X ~= replica.V2.X and replica.V2.Y == math.huge)
assert(string.pack(">f", replica.V2.X) == string.pack(">I4", 0xffffffff))
for _, bad in ipairs({
    "",
    string.rep("x", 16),
    string.rep("x", 23),
    string.rep("x", 24),
    string.rep("x", 26),
    {},
}) do
    assert(not pcall(apply, model(), bad))
end
for _, bad in ipairs({ sentinel, math.huge, -math.huge }) do
    local before = state.capture(replica)
    assert(not pcall(apply, replica, string.pack(">ffffffB", 0, 0, 0, 0, bad, 280, 1)))
    assert(state.capture(replica) == before, "Invalid geometry partially changed NPC state")
end
-- Ordinary numbers retain their strict validation, including the location.
for _, bad in ipairs({ sentinel, math.huge, -math.huge }) do
    local ok, error = pcall(codec.encode, { { 1, bad } })
    assert(not ok and error:find("Non-finite state value at [1][2]", 1, true))
end
assert(not pcall(codec.decode, "\4" .. string.pack(">f", sentinel)))
print("PASS NPC scratch sentinels, infinities and strict ordinary state numbers")

for _, boss in ipairs({ false, true, false }) do
    npc.boss = boss
    local bytes = state.capture(npc)
    apply(replica, bytes)
    apply(replica, bytes)
    assert(replica:IsBoss() == boss, "NPC allocation retained an obsolete Boss classification")
end
local before = state.capture(replica)
assert(not pcall(apply, replica, before:sub(1, -2) .. "\2"))
assert(state.capture(replica) == before, "Invalid classification partially changed NPC state")
print("PASS authority NPC classification, repeat, reuse and malformed state")
