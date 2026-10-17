local root = assert(arg[1])
local factory = dofile(root .. "/tests/fixtures/offline_inventory.lua")
local pool = { 5, 2, 1 }
local players = { factory(root, pool), factory(root, pool) }
players[2].reset(true)
local a, b = players[1].read()[1], players[2].read()[1]
assert(a[5][1] == 5 and b[5][1] == 5)
a[5], b[5] = { 12, 4, 3, 2, 0, false, false }, { 12, 4, 3, 0, 0, false, false }
players[1].apply(a, true)
assert(players[2].read()[1][5][1] == 12)
local first = players[1].read()
players[2].apply(b, true)
assert(players[1].read()[2] == first[2] and players[1].read()[3] == first[3])
assert(players[1].read()[1][5][4] == 2)
assert(players[2].read()[1][5][4] == 0)
-- Spending in another room or restoring an absolute snapshot must update
-- one pool once, including the hidden inventory of a co-op ghost.
b[5] = { 0, 3, 2, 0, 0, false, false }
players[2].apply(b, true)
assert(players[1].read()[1][5][1] == 0 and players[1].read()[1][5][2] == 3)
local before = players[2].read()
assert(players[2].apply(b, true)[3] == before[3])
assert(players[1].read()[1][5][4] == 2)
print("PASS shared resource snapshots, ghosts and private charges")

local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local Inventory, Resource = fields.inventory, fields.resources
assert(Resource.goldenBomb and Resource.goldenKey, "Golden resources missing from schema")
local desired = players[1].read()[1]
local resources = desired[Inventory.resources]
resources[Resource.goldenBomb], resources[Resource.goldenKey] = true, false
players[1].apply(desired, false)
assert(
    players[2].read()[1][Inventory.resources][Resource.goldenBomb],
    "Ghost lost shared gold bomb"
)
local captured = players[1].read()
assert(players[1].apply(desired, false)[3] == captured[3], "Repeated golden flags mutate resources")
-- Bombs Are Key swaps the shared flags; a ghost can receive the same view.
desired[Inventory.ghost] = true
resources[Resource.goldenBomb], resources[Resource.goldenKey] = false, true
players[2].apply(desired, false)
local actual = players[1].read()[1][Inventory.resources]
assert(not actual[Resource.goldenBomb] and actual[Resource.goldenKey])
-- A later floor or a rewind can clear both flags without rebuilding items.
resources[Resource.goldenKey] = false
players[2].apply(desired, false)
actual = players[1].read()[1][Inventory.resources]
assert(not actual[Resource.goldenBomb] and not actual[Resource.goldenKey])
print("PASS shared golden bomb/key flags, swaps, repeated views and removal")
