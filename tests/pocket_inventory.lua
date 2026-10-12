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
print("PASS all four ordered pockets after inventory setters, repeated views and ghost cleanup")
