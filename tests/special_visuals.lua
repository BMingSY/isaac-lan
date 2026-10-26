local root = assert(arg[1])
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local stored = string.pack(">ff", 520, -180)
local function vector(x, y)
    return { X = x, Y = y }
end
local dogma = dofile(root .. "/src/bridge/compat/bosses/dogma.lua")(
    vector,
    enums.EntityType,
    enums.EffectVariant
)
local function geometry(entity)
    return string.pack(">ff", entity.TargetPosition.X, entity.TargetPosition.Y)
end
local function effect(kind, variant, subtype, geometry)
    return {
        Type = kind,
        Variant = variant,
        SubType = subtype,
        GetSprite = function(self)
            return self
        end,
        TargetPosition = type(geometry) == "string" and #geometry == 8 and vector(
            string.unpack(">ff", geometry)
        ) or vector(0, 0),
    }
end
local warning, replica = effect(1000, 172, 1, stored), effect(1000, 172, 1, "")
local snapshot = codec.decode(codec.encode({ dogma.capture(warning) }))[1]
dogma.apply(replica, snapshot)
assert(geometry(replica) == stored)
stored = string.pack(">ff", -320, 240)
warning.TargetPosition = vector(-320, 240)
dogma.apply(replica, dogma.capture(warning))
assert(geometry(replica) == stored, "Moving warnings must retain both geometry components")
dogma.apply(replica, stored)
assert(geometry(replica) == stored, "Repeated snapshots must retain the same warning direction")
for _, entity in ipairs({
    effect(1000, 172, 0, "orb"),
    effect(1000, 172, 2, "attack"),
    effect(1000, 171, 1, "black-hole"),
    effect(950, 2, 1, "boss"),
}) do
    local previous = entity.TargetPosition
    assert(dogma.capture(entity) == false)
    dogma.apply(entity, false)
    assert(entity.TargetPosition == previous)
    assert(not pcall(dogma.apply, entity, stored), "Unrelated entities must reject Boss geometry")
end
assert(not pcall(dogma.apply, replica, false))
assert(not pcall(dogma.apply, replica, "short"))
assert(not pcall(dogma.apply, replica, string.pack(">ff", math.huge, 1)))
assert(geometry(replica) == stored)
local current = { DungeonReturnPosition = { X = 240, Y = 200 }, DungeonReturnRoomIndex = 86 }
local route = dofile(root .. "/src/bridge/compat/routes/crawlspace.lua")(function()
    return current
end, function(x, y)
    return { X = x, Y = y }
end)
local origin = codec.decode(codec.encode({ route.capture() }))[1]
current.DungeonReturnPosition, current.DungeonReturnRoomIndex = { X = 320, Y = 160 }, 111
route.apply(origin)
local x, y, room = string.unpack(">ffi4", route.capture())
assert(x == 240 and y == 200 and room == 86, "Host viewport must not replace crawlspace origin")
assert(not pcall(route.apply, "short"))
for _, invalid in ipairs({
    string.pack(">ffi4", math.huge, 20, 86),
    string.pack(">ffi4", 10, 20, 169),
    string.pack(">ffi4", 10, 20, -21),
}) do
    assert(not pcall(route.apply, invalid))
    assert(route.capture() == origin, "Invalid return contexts must not partially mutate the level")
end
local diceType = 21
local kind, used, darkens, shakes = diceType, false, 0, 0
local dice = dofile(root .. "/src/bridge/compat/routes/dice_floor.lua")(
    dofile(root .. "/src/bridge/sync/fields.lua")
)(function()
    return {
        GetRoom = function()
            return {
                GetType = function()
                    return kind
                end,
                IsSacrificeDone = function()
                    return used
                end,
            }
        end,
        Darken = function(_, amount, frames)
            assert(amount == 1 and frames == 60)
            darkens = darkens + 1
        end,
        ShakeScreen = function(_, frames)
            assert(frames == 50)
            shakes = shakes + 1
        end,
    }
end, diceType)
local view = { slot = 1, epoch = 1, tick = 10, locations = { { 1, 0, 84 } } }
dice.apply(view)
used, view.tick = true, 11
dice.apply(view)
dice.apply(view)
view.tick = 12
dice.apply(view)
assert(darkens == 1 and shakes == 1, "Dice activation must play once")
view.tick, used = 10, false
dice.apply(view)
view.tick, used = 12, true
dice.apply(view)
assert(darkens == 1, "An older view replayed a dice activation")
view.locations[1][3], view.tick = 85, 13
dice.apply(view)
view.locations[1][3], view.tick = 84, 14
dice.apply(view)
assert(darkens == 1, "Entering a previously used room replayed its activation")
dice.reset()
view.tick = 15
dice.apply(view)
assert(darkens == 1, "Reconnect replayed an old activation")
view.epoch, view.tick, used = 2, 1, false
dice.apply(view)
used, view.tick = true, 2
dice.apply(view)
assert(darkens == 2, "A new floor retained the previous activation")
kind, used, view.tick = 13, false, 3
dice.apply(view)
used, view.tick = true, 4
dice.apply(view)
assert(darkens == 2 and shakes == 2, "Sacrifice rooms received dice presentation")
-- Detached bodies retain their use-time costume when the owner's live appearance changes.
local function body()
    local e = effect(3, 48, 0, "")
    e.layers, e.sprites = string.pack(">i4i4i4i4", 0, 1, -1, -1), {}
    for i = 1, 5 do
        e.sprites[i] = { path = "use-time costume " .. i, frame = i }
    end
    return e
end
local writes = 0
local splitBody = dofile(root .. "/src/bridge/compat/items/split_body.lua")({
    familiar_body = function(e, layers)
        if layers then
            writes, e.layers = writes + 1, layers
            return true
        end
        return e.layers, e.sprites
    end,
}, enums.EntityType, enums.FamiliarVariant)
local visuals = dofile(root .. "/src/bridge/compat/visuals.lua")(dogma, splitBody)
local original, copy = body(), body()
local function captureSprite(s)
    return { s.path, s.frame }
end
local function applySprite(s, value)
    s.path, s.frame = value[1], value[2]
end
local bodyState = codec.decode(codec.encode(visuals.capture(original, nil, captureSprite)))
for _, s in ipairs(copy.sprites) do
    s.path, s.frame = "current head only", 0
end
copy.layers = string.pack(">i4i4i4i4", -1, -1, -1, -1)
visuals.apply(copy, bodyState, applySprite)
visuals.apply(copy, bodyState, applySprite)
assert(copy.layers == original.layers and writes == 2)
for i, s in ipairs(copy.sprites) do
    assert(s.path == original.sprites[i].path and s.frame == i)
end
for _, invalid in ipairs({ false, {}, { "short", bodyState[2] }, { bodyState[1], {} } }) do
    assert(not pcall(visuals.apply, copy, invalid, applySprite))
end
assert(writes == 2, "Invalid body state mutated native layers")
local unrelated = effect(3, 78, 0, "")
assert(visuals.capture(unrelated, nil, captureSprite) == false)
visuals.apply(unrelated, false, applySprite)
assert(not pcall(visuals.apply, unrelated, bodyState, applySprite))
-- Flip changes and clears its alternate independently of the main pedestal.
local flip = dofile(root .. "/src/bridge/compat/items/flip.lua")({
    pickup_flip_visual = function(e, visible)
        if visible ~= nil then
            e.visible = visible
            return true
        end
        return e.visible, e.alternate
    end,
}, enums.EntityType, enums.PickupVariant)
visuals = dofile(root .. "/src/bridge/compat/visuals.lua")(dogma, splitBody, flip)
local pedestal, replicaPedestal = effect(5, 100, 1, ""), effect(5, 100, 1, "")
pedestal.visible, pedestal.alternate = true, { path = "alternate item", frame = 3 }
replicaPedestal.visible, replicaPedestal.alternate = false, { path = "", frame = 0 }
local function copyFlip()
    local value = codec.decode(codec.encode({ visuals.capture(pedestal, nil, captureSprite) }))[1]
    visuals.apply(replicaPedestal, value, applySprite)
end
copyFlip()
copyFlip()
assert(replicaPedestal.visible and replicaPedestal.alternate.path == "alternate item")
pedestal.alternate.path, pedestal.alternate.frame = "flipped item", 7
copyFlip()
assert(replicaPedestal.alternate.path == "flipped item" and replicaPedestal.alternate.frame == 7)
pedestal.SubType = 0 -- The empty pedestal can still hold the alternate item.
copyFlip()
assert(replicaPedestal.visible)
pedestal.visible = false -- Both sides taken, Flip removed, or replica reused after room change.
copyFlip()
copyFlip()
assert(not replicaPedestal.visible)
assert(visuals.capture(effect(5, 20, 1, ""), nil, captureSprite) == false)
assert(not pcall(visuals.apply, replicaPedestal, "invalid", applySprite))
print("PASS special entity geometry, detached costumes, Flip, room return and dice presentation")
