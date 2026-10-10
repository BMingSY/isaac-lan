local root = assert(arg[1])
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local stored = string.pack(">ff", 520, -180)
local function vector(x, y)
    return { X = x, Y = y }
end
local dogma = dofile(root .. "/src/bridge/compat/bosses/dogma.lua")(vector)
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
print("PASS Dogma warning geometry, unrelated attack effects and special-room return context")
