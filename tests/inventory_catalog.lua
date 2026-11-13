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

local methodReads, countReads, typeReads = 0, 0, 0
local glitched = dofile(root .. "/src/bridge/compat/items/glitched.lua")({
    generated_item_count = function(player, id)
        return player.items[id] or 0
    end,
})
local bound = dofile(root .. "/tests/fixtures/offline_inventory.lua")(root, nil, nil, function()
    return { -1 }
end, glitched.count, nil, nil, nil, glitched.reader)
function bound.config:GetCollectibles()
    return { Size = 2001 }
end
function bound.config:GetCollectible()
    return setmetatable({}, {
        __index = function(_, name)
            assert(name == "Type")
            typeReads = typeReads + 1
            return 1
        end,
    })
end
local sharedCatalog = {}
for actor = 1, 4 do
    bound.reset()
    local p = bound.player()
    local original = getmetatable(p).__index
    setmetatable(p, {
        __index = function(self, name)
            local value = original(self, name)
            if name == "GetCollectibleNum" then
                methodReads = methodReads + 1
                return function(player, id, onlyTrueItems)
                    assert(onlyTrueItems)
                    countReads = countReads + 1
                    return value(player, id)
                end
            end
            return value
        end,
    })
    p.items[1], p.items[-1] = actor, actor + 1
    local captured = bound.read(sharedCatalog)[1]
    assert(captured[fields.inventory.items][1][2] == actor)
    assert(captured[fields.inventory.items][2][1] == -1)
    assert(captured[fields.inventory.items][2][2] == actor + 1)
end
assert(methodReads == 4 and countReads == 8000, "Count methods were not bound per actor")
assert(typeReads == 0, "Capture read item types needed only during replica repair")
-- Same total count can represent a completely different inventory. Replacing
-- the method between operations and generated-item changes remain visible.
local p = bound.player()
p.GetCollectibleNum = function(_, id)
    return id == 2 and 4 or 0
end
p.items[-1] = 7
local changed = bound.read({})[1][fields.inventory.items]
assert(changed[1][1] == 2 and changed[1][2] == 4 and changed[2][2] == 7)
print("PASS four method resolutions for 8000 live counts, replaced methods and generated counts")

-- Several actors need full repair together after a checkpoint. Share the
-- operation's catalog while preserving each actor's actual counts and slots.
local repair = dofile(root .. "/tests/fixtures/offline_inventory.lua")(root, nil, nil, function()
    return { -1 }
end, glitched.count, nil, nil, nil, glitched.reader)
local snapshots = {}
for actor = 1, 4 do
    repair.reset()
    local p = repair.player()
    p.items[1], p.items[-1], p.actives[1] = actor, actor + 1, { 2, actor }
    snapshots[actor] = repair.read()[1]
end
local repairs = dofile(root .. "/src/bridge/sync/inventory.lua")(fields)({
    config = function()
        return repair.config
    end,
    extraCollectibles = function()
        return { -1 }
    end,
    collectibleReader = glitched.reader,
    activeType = 2,
    curse = 1,
})
local configReads, configLists = 0, 0
local getConfig, getList = repair.config.GetCollectible, repair.config.GetCollectibles
function repair.config:GetCollectible(id)
    configReads = configReads + 1
    return getConfig(self, id)
end
function repair.config:GetCollectibles()
    configLists = configLists + 1
    return getList(self)
end
local repairCatalog, observed = {}, {}
for actor = 1, 4 do
    repair.reset()
    local p = repair.player()
    p.items[1], p.items[5], p.items[-1], p.actives[1] = 9, 3, 1, { 4, 0 }
    repairs.apply(p, snapshots[actor], true, repairCatalog)
    observed[actor] = p
end
assert(configLists == 1 and configReads == 9, "Replica repairs enumerated one catalog per actor")
for actor, p in ipairs(observed) do
    assert(p.items[1] == actor and p.items[5] == 0 and p.items[-1] == actor + 1)
    assert(p.actives[1][1] == 2 and p.actives[1][2] == actor)
end
print("PASS shared repair catalog, independent passive/generated counts and active slots")

-- Reuse values, never cached native counts. Same-size replacements and removals
-- must leave a prior published inventory untouched.
local reuse = dofile(root .. "/tests/fixtures/offline_inventory.lua")(root)
local p = reuse.player()
p.items = { [1] = 2, [5] = 3 }
local original = reuse.read()[1]
local originalBytes = codec.encode(original)
local unchanged = reuse.read({}, original)[1]
assert(unchanged[fields.inventory.items] == original[fields.inventory.items])
p.items[1], p.items[6], p.items[5] = 4, 2, nil
local changed = reuse.read({}, unchanged)[1]
assert(changed[fields.inventory.items] ~= unchanged[fields.inventory.items])
same(changed, reuse.read()[1])
p.items = {}
local empty = reuse.read({}, changed)[1]
assert(#empty[fields.inventory.items] == 0)
assert(codec.encode(original) == originalBytes, "Inventory reuse mutated a prior snapshot")

-- Repeated resources/charges must not call native mutators. A local deviation
-- is still repaired even when the authoritative inventory has not changed.
local setters = 0
for _, name in ipairs({
    "AddCoins",
    "AddBombs",
    "AddKeys",
    "AddSoulCharge",
    "AddBloodCharge",
    "SetActiveCharge",
}) do
    local apply = p[name]
    p[name] = function(self, ...)
        setters = setters + 1
        return apply(self, ...)
    end
end
local state = reuse.read()[1]
reuse.apply(state, false)
reuse.apply(state, true)
assert(setters == 0, "Unchanged inventory called native resource/charge mutators")
p.resources[1], p.resources[4], p.actives[1][2] = 3, 2, 1
reuse.apply(state, false)
assert(setters == 3, "Local resource deviation was not repaired exactly once")
same(reuse.read()[1], state)
-- Battery charge belongs to the same total; it must not spuriously reapply.
p.GetBatteryCharge = function(_, slot)
    return slot == 0 and 2 or 0
end
state = reuse.read()[1]
setters = 0
reuse.apply(state, false)
assert(setters == 0, "Battery charge was ignored in the equality check")
print("PASS immutable inventory reuse, local mutations, resources and battery charges")
