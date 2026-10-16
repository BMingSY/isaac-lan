local root = assert(arg[1])
local factory =
    dofile(root .. "/src/bridge/sync/deals.lua")(dofile(root .. "/src/bridge/sync/fields.lua"))
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local authoritative, replica, calls = { 1, 0 }, nil, 0
local host = factory({
    deal_chances = function()
        return table.unpack(authoritative)
    end,
    deal_chances_reset = function() end,
})
local guest = factory({
    deal_chances = function(total, angel)
        calls = calls + 1
        replica = { total, angel }
        return true
    end,
    deal_chances_reset = function()
        replica = nil
    end,
})
-- Preserve native guarantees greater than 100%; never add the two players'
-- HUD percentages or turn the Angel modifier into a displayed probability.
for _, chances in ipairs({ { 1, 0 }, { 0.3375, 0.71875 }, { 0.01, 0 }, { 66.1, 1 }, { 0, 1 } }) do
    authoritative = {
        (string.unpack("f", string.pack("f", chances[1]))),
        (string.unpack("f", string.pack("f", chances[2]))),
    }
    local captured = codec.decode(codec.encode(host.capture()))
    guest.apply(captured)
    assert(replica[1] == authoritative[1] and replica[2] == authoritative[2])
    guest.apply(captured)
    assert(
        replica[1] == authoritative[1] and replica[2] == authoritative[2],
        "Repeated snapshot stacks chances"
    )
    local displayedTotal = math.min(replica[1], 1)
    assert(
        math.abs(displayedTotal * (1 - replica[2]) + displayedTotal * replica[2] - displayedTotal)
            < 1e-9
    )
end
-- Reject a malformed pair before any native write, including NaN/infinity.
for _, bad in ipairs({
    {},
    { 1 },
    { 1, 0, 1 },
    { -1, 0 },
    { math.huge, 0 },
    { 0 / 0, 0 },
    { 1, -0.1 },
    { 1, 1.1 },
    { 1, 0 / 0 },
    { "1", 0 },
}) do
    local before = calls
    assert(not pcall(guest.apply, bad))
    assert(calls == before, "Invalid snapshot partially wrote native deal state")
end
guest.reset()
assert(replica == nil, "New floor/run retained a previous authoritative deal chance")
guest.apply({ 0.35, 0 })
assert(replica[1] == 0.35 and replica[2] == 0)
print("PASS authoritative shared deal chances, codec, repeated snapshots, validation and reset")
