local root = assert(arg[1])
local received, count
local module = dofile(root .. "/src/bridge/state/poop.lua")({
    actor_poop = function(sprite, value)
        assert(sprite == "sprite")
        received, count = value, (count or 0) + 1
        return true
    end,
})
local kind, ghost = 0, false
local player = {
    GetPlayerType = function()
        return kind
    end,
    IsCoopGhost = function()
        return ghost
    end,
    GetSprite = function()
        return "sprite"
    end,
    GetPoopMana = function()
        assert(kind == 25)
        return 12
    end,
    GetPoopSpell = function(_, index)
        assert(index >= 0 and index < 6)
        return ({ 1, 11, 7, 0, 5, 9 })[index + 1]
    end,
}
assert(module.capture(player) == false)
module.apply(player, false)
assert(not count)
kind = 25
local value = module.capture(player)
assert(#value == 10)
assert(value == string.pack(">I4BBBBBB", 12, 1, 11, 7, 0, 5, 9))
module.apply(player, value)
module.apply(player, value)
assert(received == value and count == 2)
ghost = true
assert(module.capture(player) == false)
print("PASS private Tainted Blue Baby mana and queue without casting or consumption")
