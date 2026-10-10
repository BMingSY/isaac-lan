local root = assert(arg[1])
local factory = dofile(root .. "/tests/fixtures/offline_inventory.lua")
local pool = { 5, 2, 1 }
local players = { factory(root, pool), factory(root, pool) }
players[2].reset(true)
local a, b = players[1].read()[1], players[2].read()[1]
assert(a[5][1] == 5 and b[5][1] == 5)
a[5], b[5] = { 12, 4, 3, 2, 0 }, { 12, 4, 3, 0, 0 }
players[1].apply(a, true)
assert(players[2].read()[1][5][1] == 12)
local first = players[1].read()
players[2].apply(b, true)
assert(players[1].read()[2] == first[2] and players[1].read()[3] == first[3])
assert(players[1].read()[1][5][4] == 2)
assert(players[2].read()[1][5][4] == 0)
-- Spending in another room or restoring an absolute snapshot must update
-- one pool once, including the hidden inventory of a co-op ghost.
b[5] = { 0, 3, 2, 0, 0 }
players[2].apply(b, true)
assert(players[1].read()[1][5][1] == 0 and players[1].read()[1][5][2] == 3)
local before = players[2].read()
assert(players[2].apply(b, true)[3] == before[3])
assert(players[1].read()[1][5][4] == 2)
print("PASS shared resource snapshots, ghosts and private charges")
