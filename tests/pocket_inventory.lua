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
    false,
    false,
    false,
}
-- Setter order is checked above; this round trip fixes every nested tuple position.
local plain = factory(root)
expected[11] = false
plain.apply(expected, true)
assert(codec.encode(plain.read()[1]) == codec.encode(expected), "Inventory tuple bytes changed")
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

local data, activeWrites = { 1 << 16, 12, 9 << 16, 0 }, 0
local active = factory(root, nil, nil, nil, nil, nil, nil, function(p, value)
    if value then
        for slot = 0, 3 do
            local id, state = string.unpack(">i4i4", value, slot * 8 + 1)
            assert(id == p:GetActiveItem(slot), "Active data restored before slot identity")
            data[slot + 1] = state
        end
        activeWrites = activeWrites + 1
        return true
    end
    local bytes = {}
    for slot = 0, 3 do
        bytes[#bytes + 1] = string.pack(">i4i4", p:GetActiveItem(slot), data[slot + 1])
    end
    return table.concat(bytes)
end)
local wanted = active.read()[1]
wanted[3] = { { 2, 6 }, { 4, 12 }, { 2, 2 }, { 0, 0 } }
wanted[13] = string.pack(">i4i4i4i4i4i4i4i4", 2, 4 << 16, 4, 12, 2, 7 << 16, 0, 0)
data = { 0, 0, 0, 0 }
local p = active.player()
local setCharge = p.SetActiveCharge
p.SetActiveCharge = function(self, charge, slot)
    assert(data[1] == 4 << 16 and data[3] == 7 << 16, "Charge restored before active mode data")
    setCharge(self, charge, slot)
end
active.apply(wanted, true)
assert(active.read()[1][13] == wanted[13])
local mutations = active.read()[2]
active.apply(wanted, false)
assert(active.read()[1][13] == wanted[13] and active.read()[2] == mutations and activeWrites == 2)
active.reset(true)
wanted[9] = true
active.apply(wanted, false)
assert(activeWrites == 2, "Ghost active data was overwritten")
print("PASS four active states after identity and before charges, repeated views and ghosts")
