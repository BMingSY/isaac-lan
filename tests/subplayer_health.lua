local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local factory = dofile(root .. "/tests/fixtures/offline_inventory.lua")
local function subplayer(player)
    return rawget(player, "subplayer")
end
local swaps = 0
local types = { PLAYER_THEFORGOTTEN = 16, PLAYER_THESOUL = 17 }
local forms = dofile(root .. "/src/bridge/compat/characters/forgotten.lua")(types, {
    actor_forgotten_form = function(player, desired)
        local hidden = assert(player.subplayer)
        assert(player.kind ~= desired and hidden.kind == desired)
        for _, name in ipairs({ "kind", "hearts", "souls", "black" }) do
            player[name], hidden[name] = hidden[name], player[name]
        end
        swaps = swaps + 1
        return true
    end,
})
local authority = factory(root, nil, nil, nil, nil, subplayer)
local replica = factory(root, nil, nil, nil, nil, subplayer, forms.restoreForm)
local replicaPlayer = replica.player()
function replicaPlayer:GetSprite()
    return self
end
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
authority.player().kind = 17
soul.kind = 16
soul.hearts[fields.hearts.bone], soul.hearts[fields.hearts.red] = 3, 5
replica.apply(authority.read()[1], true)
assert(swaps == 1 and replica.player().kind == 17 and copiedSoul.kind == 16)
assert(copiedSoul.hearts[fields.hearts.bone] == 3 and copiedSoul.hearts[fields.hearts.red] == 5)
replica.apply(authority.read()[1], false)
assert(swaps == 1, "Duplicate state toggled the form again")
authority.player().kind, soul.kind = 16, 17
authority.player().hearts[fields.hearts.bone] = 2
soul.souls, soul.black = 4, 1
replica.apply(authority.read()[1], true)
assert(swaps == 2 and replica.player().kind == 16 and copiedSoul.kind == 17)
assert(replica.player().hearts[fields.hearts.bone] == 2)
assert(copiedSoul.souls == 4 and copiedSoul.black == 1)
assert(copiedSoul.itemMutations == 0, "Native form restore rebuilt the hidden inventory")
authority.player().ghost = true
authority.player().kind, soul.kind = 17, 16
replica.apply(authority.read()[1], false)
assert(swaps == 2, "Ghost state switched its hidden form")
authority.player().ghost = false
authority.player().kind = 0
authority.player().subplayer = nil
assert(authority.read()[1][fields.inventory.subplayer] == false)
replica.apply(authority.read()[1], true)
assert(replica.player().kind == 0 and swaps == 2, "Ordinary type change lost its fallback")
print("PASS hidden form soul/black/red/bone health, repeat snapshots and form switching")
