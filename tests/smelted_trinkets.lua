local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local factory = dofile(root .. "/tests/fixtures/offline_inventory.lua")
local empty = string.pack(">I2", 0)
local swallowed = string.pack(">I2I2I2I2I2I2I2", 2, 39, 2, 1, 83, 0, 1)
local writes = 0
local function smelted(p, value)
    if value == nil then
        return rawget(p, "smelted") or empty
    end
    -- The native restore reports changes without replaying the item effect.
    local changed = (rawget(p, "smelted") or empty) ~= value
    p.smelted = value
    writes = writes + 1
    return changed and 1 or 0
end
local fixture = factory(root, nil, nil, nil, nil, nil, nil, nil, nil, nil, smelted)
local p = fixture.player()
p.smelted, p.trinkets = swallowed, { 13, 14 }
local expected = fixture.read()[1]
assert(expected[fields.inventory.smeltedTrinkets] == swallowed)
fixture.reset()
p = fixture.player()
fixture.apply(expected, true)
assert(p.smelted == swallowed and p:GetTrinket(0) == 13 and p:GetTrinket(1) == 14)
assert(p.cacheEvaluations == 1, "Swallowed effects did not invalidate native attribute caches")
fixture.apply(expected, false)
assert(p.cacheEvaluations == 1, "Repeated state reevaluated unchanged swallowed effects")
local other = factory(root, nil, nil, nil, nil, nil, nil, nil, nil, nil, smelted)
assert(other.read()[1][fields.inventory.smeltedTrinkets] == empty, "Another holder gained effects")
-- Restore an older checkpoint, including loss of all swallowed effects.
expected[fields.inventory.smeltedTrinkets] = empty
fixture.apply(expected, false)
assert(p.smelted == empty and p.cacheEvaluations == 2)
expected[fields.inventory.smeltedTrinkets] = swallowed
fixture.apply(expected, false)
assert(p.smelted == swallowed and p.cacheEvaluations == 3)
local before = writes
fixture.reset(true)
expected[fields.inventory.ghost] = true
fixture.apply(expected, false)
assert(writes == before, "Replica changed the ghost's native hidden inventory")
expected[fields.inventory.ghost] = false
fixture.reset()
fixture.apply(expected, true)
assert(fixture.player().smelted == swallowed, "Replacement actor lost swallowed effects")
print("PASS swallowed inventory, held slots, repeated views, rollback, ghosts and replacement")
