local root = assert(arg[1])
local factory = dofile(root .. "/tests/fixtures/offline_inventory.lua")
local raw, writes = string.pack(">I4I4I4I4I4I4I4I4", 3, 2, 14, 1, 4, 2, 2050, 0), 0
local player = factory(root, nil, function(p, value)
    if value then
        assert(
            p:GetCard(0) == 0 and p:GetPill(0) == 0,
            "Pocket order restored before the slot setters"
        )
        raw, writes = value, writes + 1
        return true
    end
    return raw
end)
local desired = player.read()[1]
assert(desired[11] == raw, "Inventory dropped the active/card/horse-pill pocket order")
raw = string.rep(string.pack(">I4I4", 0, 1), 4)
player.apply(desired, true)
assert(raw == desired[11] and writes == 1)
player.apply(desired, false)
assert(raw == desired[11] and writes == 2)
player.reset(true)
desired[9] = true
player.apply(desired, false)
assert(writes == 2, "Ghost pocket inventory must remain owned by native ghost conversion")
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
player.reset()
local expected = {
    23,
    { { 1, 3 }, { 2, 1 }, { 4, 1 }, { 6, 2 } },
    { { 2, 5 }, { 0, 0 }, { 4, 7 }, { 0, 0 } },
    { 1, 12, 2, 8, 1, 1, 1, 6, 5 },
    { 21, 8, 3, 4, 5, true, false },
    { 13, 14 },
    { 22, 0 },
    { 0, 9 },
    false,
    2,
    raw,
}
-- Setter order is checked above; this round trip fixes every nested tuple position.
local plain = factory(root)
expected[11] = false
plain.apply(expected, true)
assert(codec.encode(plain.read()[1]) == codec.encode(expected), "Schema-22 inventory bytes changed")
plain.apply(expected, false)
assert(codec.encode(plain.read()[1]) == codec.encode(expected), "Repeated inventory drifted")
print("PASS all four ordered pockets after inventory setters, repeated views and ghost cleanup")

local glitched = dofile(root .. "/src/bridge/compat/items/glitched.lua")({
    generated_item_count = function(p, id)
        local count = p.items[id] or 0
        for _, entry in ipairs(p.actives) do
            if entry[1] == id then
                count = count + 1
            end
        end
        return count
    end,
})
local first = factory(root, nil, nil, glitched.extraCollectibles, glitched.count)
local second = factory(root, nil, nil, glitched.extraCollectibles, glitched.count)
local value = first.read()[1]
value[2] = { { 1, 1 }, { -1, 2 }, { -3, 1 } }
value[3][1] = { -2, 4 }
first.apply(value, true)
local captured = first.read()[1]
local counts = {}
for _, entry in ipairs(captured[2]) do
    counts[entry[1]] = entry[2]
end
assert(counts[-1] == 2 and counts[-2] == 1 and counts[-3] == 1 and captured[3][1][1] == -2)
assert(#second.read()[1][2] == 0, "Glitched effects leaked into another holder")
local mutations = first.read()[2]
first.apply(captured, true)
assert(first.read()[2] == mutations, "Repeated views reapplied glitched effects")
value[2], value[3][1] = {}, { 0, 0 }
first.apply(value, true)
assert(#first.read()[1][2] == 0, "Removed glitched items survived inventory reconciliation")
print("PASS generated passive/active inventory, repeated views, removal and per-picker ownership")
