local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local definitions, extras, size = {}, { -1 }, 9
for id = 1, size - 1 do
    if id ~= 3 then
        definitions[id] = { Type = (id == 2 or id == 4) and 2 or 1 }
    end
end
definitions[-1] = { Type = 1 }
local fixture = dofile(root .. "/tests/fixtures/offline_inventory.lua")(root, nil, nil, function()
    return extras
end, function(player, id)
    return id < 0 and (player.items[id] or 0) or player:GetCollectibleNum(id)
end)
local reads, enumerations = 0, 0
function fixture.config:GetCollectibles()
    enumerations = enumerations + 1
    return { Size = size }
end
function fixture.config:GetCollectible(id)
    reads = reads + 1
    return definitions[id]
end
local function capture(catalog)
    return fixture.read(catalog)[1]
end
local function same(a, b)
    assert(codec.encode(a) == codec.encode(b), "Shared catalog changed inventory bytes")
end
local catalog, saved, savedBytes = {}, {}, {}
local cachedReads, cachedEnumerations = 0, 0
for index = 1, 4 do
    fixture.reset()
    local player = fixture.player()
    player.items = { [1] = index, [5] = 5 - index, [-1] = index + 1 }
    player.actives[1] = { 2, index }
    player.hearts[4], player.resources[1] = index * 2, index * 10
    local reference = capture()
    local beforeReads, beforeEnumerations = reads, enumerations
    local value = capture(catalog)
    cachedReads = cachedReads + reads - beforeReads
    cachedEnumerations = cachedEnumerations + enumerations - beforeEnumerations
    same(value, reference)
    saved[index], savedBytes[index] = value, codec.encode(value)
end
assert(cachedReads == size - 1 + #extras and cachedEnumerations == 1)
assert(saved[1][fields.inventory.items][1][2] == 1)
assert(saved[4][fields.inventory.items][1][2] == 4, "Player counts leaked between inventories")

-- Even within the same catalog, health, charges, resources and item counts
-- remain live. Only the available IDs are shared, never a player's state.
local player = fixture.player()
player.items[1], player.items[-1] = 9, 12
player.hearts[4], player.resources[1], player.actives[1][2] = 6, 42, 7
same(capture(catalog), capture())

-- A new capture generation must observe Mod definitions changing even when
-- the array size is unchanged, and generated IDs appearing/disappearing.
definitions[1], definitions[3] = nil, { Type = 1 }
player.items[3] = 2
definitions[-2], extras = { Type = 2 }, { -1, -2 }
player.actives[2] = { -2, 3 }
same(capture({}), capture())
size, definitions[10], player.items[10] = 11, { Type = 1 }, 4
same(capture({}), capture())
size, definitions[-1], definitions[-2], extras = 5, nil, nil, {}
same(capture({}), capture())
for index, value in ipairs(saved) do
    assert(codec.encode(value) == savedBytes[index], "Later inventory capture mutated old bytes")
end

-- Empty catalogs still have a reusable result. Standalone captures, which
-- have no generation owner, always enumerate fresh definitions.
size, catalog = 1, {}
local beforeEnumerations = enumerations
for _ = 1, 4 do
    assert(#capture(catalog)[fields.inventory.items] == 0)
end
assert(enumerations == beforeEnumerations + 1)
size, definitions[1] = 2, { Type = 1 }
assert(#capture()[fields.inventory.items] == 1)
print(
    "PASS shared catalog, independent live inventory, Mod/generated definitions and immutable bytes"
)
