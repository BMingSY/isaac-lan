local root = assert(arg[1])
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local wire = dofile(root .. "/src/bridge/sync/codec.lua")
local reconcile =
    dofile(root .. "/src/bridge/sync/entities.lua")(enums.EntityType, enums.PickupVariant)
local objects, refs, writes = {}, {}, 0
local function entity(kind, index, id)
    local e =
        { Type = kind, Index = index, Variant = 0, SubType = 0, id = id, alive = true, data = {} }
    function e:Exists()
        return self.alive
    end
    function e:GetData()
        return self.data
    end
    function e:GetSprite()
        return self
    end
    return e
end
local native = {
    hornfel_bombs = function(e, a, b)
        if a == nil then
            return e.held[1] and e.held[1].Index or -1, e.held[2] and e.held[2].Index or -1
        end
        assert(e.Type == 906)
        writes = writes + 1
        e.held = { a, b }
        return true
    end,
}
local hornfel = dofile(root .. "/src/bridge/compat/bosses/hornfel.lua")(
    native,
    enums.EntityType,
    function()
        return objects
    end
)
local dogma = dofile(root .. "/src/bridge/compat/bosses/dogma.lua")(function(x, y)
    return { X = x, Y = y }
end, enums.EntityType, enums.EffectVariant)
local visual = dofile(root .. "/src/bridge/compat/bosses/visuals.lua")(dogma, hornfel)
local boss, first, second = entity(906, 10, 101), entity(4, 11, 102), entity(4, 12, 103)
boss.held = { first, second }
objects = { boss, second, first }
local value = wire.decode(wire.encode({ visual.capture(boss, function(e)
    return e.id
end) }))[1]
assert(value == string.pack(">I4I4", 102, 103), "Native indices leaked onto the wire")
objects = {}
local function tuple(id, kind, state)
    local v = { id, kind, 0, 0 }
    for i = 5, 23 do
        v[i] = 0
    end
    v[24] = state
    return v
end
local values = { tuple(101, 906, value), tuple(103, 4, false), tuple(102, 4, false) }
local env = {
    ref = function(id)
        return refs[id]
    end,
    key = function(e)
        return e
    end,
    entities = function()
        return objects
    end,
    discard = function(e)
        e.alive = false
        refs[e.id] = nil
    end,
    reclaim = function() end,
    spawn = function(v)
        local e = entity(v[2], 900 + v[1], v[1])
        objects[#objects + 1] = e
        return e
    end,
    apply = function(e, v)
        refs[v[1]] = e
        visual.apply(e, v[24])
    end,
    link = function(e, v, ref)
        visual.link(e, v[24], ref)
    end,
}
reconcile(values, env)
local replica = refs[101]
assert(
    replica.held[1] == refs[102] and replica.held[2] == refs[103],
    "Bombs must exist before binding"
)
reconcile(values, env)
assert(refs[101] == replica and replica.held[2] == refs[103], "Repeated state recreated the boss")
values[1][24] = string.pack(">I4I4", 0, 103)
table.remove(values, 3)
reconcile(values, env)
assert(
    replica.held[1] == false and replica.held[2] == refs[103] and not refs[102],
    "Released bomb remained linked"
)
local before = writes
for _, invalid in ipairs({ false, "short", string.pack(">I4I4", 999, 0) }) do
    assert(not pcall(visual.link, replica, invalid, env.ref))
end
assert(writes == before, "Invalid state partially updated the native container")
reconcile({}, env)
assert(not refs[101] and not refs[103], "Room departure retained old identities")
objects = {}
values = { tuple(101, 906, string.pack(">I4I4", 0, 0)) }
reconcile(values, env)
assert(
    refs[101] ~= replica and refs[101].held[1] == false and refs[101].held[2] == false,
    "Recreated room/floor must prepare even empty bomb slots"
)
local unrelated = entity(907, 20, 104)
assert(visual.capture(unrelated) == false)
visual.apply(unrelated, false)
visual.link(unrelated, false, env.ref)
local warning = entity(1000, 21, 105)
warning.Variant, warning.SubType, warning.TargetPosition = 172, 1, { X = 20, Y = -40 }
local geometry = visual.capture(warning)
warning.TargetPosition = { X = 0, Y = 0 }
visual.apply(warning, geometry)
assert(
    warning.TargetPosition.X == 20 and warning.TargetPosition.Y == -40,
    "Dogma geometry regressed"
)
print(
    "PASS Hornfel ordered stable links, empty initialization, removal, room/floor recreation and Boss dispatch"
)
