local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local factory = dofile(root .. "/tests/fixtures/offline_inventory.lua")
local function subplayer(player)
    return rawget(player, "subplayer")
end
local authority = factory(root, nil, nil, nil, nil, subplayer)
local replica = factory(root, nil, nil, nil, nil, subplayer)
local soul = factory(root).player()
local copiedSoul = factory(root).player()
authority.player().kind, replica.player().kind = 16, 16
soul.kind, copiedSoul.kind = 17, 17
authority.player().subplayer, replica.player().subplayer = soul, copiedSoul
for _, hearts in ipairs({ { 5, 2 }, { 1, 0 }, { 6, 7 } }) do
    soul.souls, soul.black = hearts[1], hearts[2]
    local value = authority.read()[1]
    replica.apply(value, true)
    assert(copiedSoul.souls == soul.souls and copiedSoul.black == soul.black)
    replica.apply(value, false)
    assert(copiedSoul.souls == soul.souls and copiedSoul.black == soul.black)
    assert(copiedSoul.itemMutations == 0, "Hidden form health rebuilt its inventory")
end
-- The same contract carries the skeleton's red/bone health while the soul is active.
authority.player().kind, replica.player().kind = 17, 17
soul.kind, copiedSoul.kind = 16, 16
soul.hearts[fields.hearts.bone], soul.hearts[fields.hearts.red] = 3, 5
replica.apply(authority.read()[1], true)
assert(copiedSoul.hearts[fields.hearts.bone] == 3 and copiedSoul.hearts[fields.hearts.red] == 5)
authority.player().subplayer = nil
assert(authority.read()[1][fields.inventory.subplayer] == false)
print("PASS hidden form soul/black/red/bone health, repeat snapshots and form switching")
