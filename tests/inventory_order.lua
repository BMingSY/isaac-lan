local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local types = { PLAYER_ISAAC_B = 21 }
local order = dofile(root .. "/src/bridge/compat/characters/isaac.lua")({
    actor_inventory_order = function(player, value)
        if value then
            assert(player.items[1] == 2 and player.items[5] == 1, "Order preceded inventory repair")
            player.selection = value
            return true
        end
        return player.selection
    end,
}, types)
local fixture = dofile(root .. "/tests/fixtures/offline_inventory.lua")(
    root,
    nil,
    nil,
    nil,
    nil,
    nil,
    nil,
    nil,
    nil,
    order
)
local function actor(kind)
    local p = fixture.player()
    p.kind = kind
    p.GetSprite = function(self)
        return self
    end
    return p
end
local p = actor(types.PLAYER_ISAAC_B)
p.items, p.selection = { [1] = 2, [5] = 1 }, string.pack(">iii", 5, 1, 1)
local value = fixture.read()[1]
assert(value[fields.inventory.order] == p.selection)
fixture.reset()
p = actor(types.PLAYER_ISAAC_B)
fixture.apply(value, true)
assert(p.selection == value[fields.inventory.order], "Selected item was not restored")
local mutations = p.itemMutations
for _, selection in ipairs({ { 1, 1, 5 }, { 1, 5, 1 }, { 5, 1, 1 } }) do
    value[fields.inventory.order] = string.pack(">iii", table.unpack(selection))
    fixture.apply(value, false)
    fixture.apply(value, false)
    assert(p.selection == value[fields.inventory.order])
    assert(p.itemMutations == mutations, "Cycling or repeated state changed owned items")
end
fixture.reset()
actor(0)
assert(fixture.read()[1][fields.inventory.order] == false)
assert(not pcall(order, fixture.player(), value[fields.inventory.order]))
print("PASS inventory selection after repair, cycles, repeated state and character isolation")
