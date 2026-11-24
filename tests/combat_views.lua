local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local frame = dofile(root .. "/src/bridge/sync/combat_frame.lua")(fields)
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local schema = dofile(root .. "/src/bridge/sync/world_schema.lua")
local workloads = dofile(root .. "/tests/fixtures/codec_workloads.lua")(root)
local view = schema.unpack(workloads[1].value, 42)
local E, R, A, S = fields.entity, fields.room, fields.actor, fields.sprite
local sample = codec.encode(view.actors[1][A.entity])
for _, count in ipairs({ 0, 63, 64, 100 }) do
    local rows = {}
    for i = 1, count do
        rows[i] = codec.decode(sample)
        rows[i][E.id] = i
    end
    view.room[R.entities] = rows
    local packed = codec.encode(schema.pack(view))
    local bytes = frame.encode(view, schema, codec.encode, {})
    assert((bytes == packed) == (count < 64))
    assert(codec.encode(frame.decode(bytes, schema, codec.decode)) == packed)
    assert(view.room[R.entities] == rows)
    assert(not pcall(frame.decode, bytes:sub(1, -2), schema, codec.decode))
end

local variants = { BLOOD_PARTICLE = 5, BLOOD_EXPLOSION = 2 }
local classes = dofile(root .. "/src/bridge/sync/effect_classes.lua")
local blood = dofile(root .. "/src/bridge/sync/combat_visuals.lua")(fields)(
    { ENTITY_EFFECT = 1000 },
    variants,
    0,
    classes
)
local function particle(id)
    return {
        [E.id] = id,
        [E.type] = 1000,
        [E.variant] = 5,
        [E.subtype] = 99,
        [E.sprite] = { [S.path] = "gfx/1000.005_Blood Particle.anm2", [S.animation] = "Particle" },
    }
end
local object = { EntityCollisionClass = 0, CollisionDamage = 0 }
local example = particle(42)
assert(blood.eligible(object, example))
assert(not blood.eligible({ EntityCollisionClass = 1, CollisionDamage = 0 }, example))
assert(not blood.eligible({ EntityCollisionClass = 0, CollisionDamage = 1 }, example))
for field, value in pairs({ [E.variant] = 51, [E.subtype] = 1, [E.type] = 9 }) do
    local row = particle(42)
    row[field] = value
    assert(not blood.eligible(object, row))
end
example[E.sprite][S.animation] = "Other"
assert(not blood.eligible(object, example))
example[E.sprite] = { [S.path] = "gfx/1000.002_Blood Explosion.anm2", [S.animation] = "Poof" }
example[E.variant], example[E.subtype] = 2, 2
assert(blood.eligible(object, example))
example[E.sprite][S.path] = "mods/custom.anm2"
assert(not blood.eligible(object, example))
local rows, candidates = {}, {}
for i = 1, 84 do
    local row = particle(i)
    rows[#rows + 1], candidates[i] = row, row
end
local function ids(list)
    local result = {}
    for _, row in ipairs(list) do
        result[row[E.id]] = true
    end
    return result
end
local location = { index = 84, dimension = 0 }
local actor = { [A.entity] = { [E.id] = -1, [E.held] = 80 } }
local function project(list, tick, budget, peer, epoch)
    return blood.project(
        list,
        { actor },
        candidates,
        peer or 1,
        epoch or 1,
        location,
        tick,
        budget,
        0
    )
end
local tear, beam, shot, creep =
    { [E.id] = 101, [E.target] = 79 },
    { [E.id] = 102, [E.parent] = 101 },
    { [E.id] = 103, [E.spawner] = 104 },
    { [E.id] = 104 }
for _, row in ipairs({ tear, beam, shot, creep }) do
    rows[#rows + 1] = row
end
rows[79][E.parent], rows[81][E.child] = 81, 79
rows[83][E.spawner] = 104
local first = project(rows, 1, 0)
local admitted = ids(first)
assert(admitted[83], "Blood attached to a gameplay spawner was omitted")
assert(#first < #rows and admitted[79] and admitted[80] and admitted[81])
for _, id in ipairs({ 101, 102, 103, 104 }) do
    assert(admitted[id])
end
local reversed = {}
for i = #rows, 1, -1 do
    reversed[#reversed + 1] = rows[i]
end
local later = ids(project(reversed, 2, 5000))
for i = 1, 84 do
    assert(admitted[i] == later[i], "Particle flickered when priority changed")
end
local hidden = 0
for i = 1, 84 do
    if not admitted[i] then
        hidden = i
        break
    end
end
assert(hidden > 0)
assert(not ids(project({ rows[hidden], tear }, 3, 5000))[hidden])
assert(ids(project({ rows[hidden], tear }, 4, 5000, 2))[hidden])
assert(ids(project({ rows[hidden], tear }, 1, 5000, 1, 2))[hidden])
tear[E.target] = hidden
assert(ids(project(rows, 5, 0))[hidden], "New incoming link did not override an omission")
tear[E.compatibility] = { opaque = true }
assert(project(rows, 6, 0) == rows)
tear[E.compatibility] = nil
actor[A.entity][E.tether] = {}
assert(project(rows, 7, 0) == rows)
actor[A.entity][E.tether] = nil
assert(blood.project(rows, { actor }, nil, 1, 1, location, 8, 0, 0) == rows)
blood.reset()
assert(ids(project({ rows[hidden] }, 9, 0))[hidden])
blood.reset()
local smallCandidates = { [hidden] = rows[hidden] }
blood.project({ rows[hidden] }, { actor }, smallCandidates, 1, 1, location, 1, 0, 0)
assert(ids(project(rows, 2, 0))[hidden], "An already visible particle vanished on entering density")
-- Several independently required effects must not consume the budget for the
-- remaining class. Keep graph dependencies even when they were omitted earlier.
blood.reset()
local styles, byId = {}, {}
for id = 1, 100 do
    local r = particle(id)
    if id <= 40 then
        r[E.subtype] = 0
    end
    styles[id], byId[id] = r, r
end
local required = classes.mask(variants, variants.BLOOD_PARTICLE, 0)
local function draw(slot, tick, mask)
    return ids(blood.project(styles, {}, byId, slot, 1, location, tick, 0, mask))
end
local default = draw(1, 1, 0)
assert(default[1] and not default[40] and not default[100])
styles[40][E.child] = 100
local exact = draw(1, 2, required)
for id = 1, 40 do
    assert(exact[id], "A declared subtype was missing")
end
assert(exact[100], "A newly required effect lost its child")
local fresh = draw(2, 1, required)
assert(fresh[41] and fresh[42] and fresh[43] and fresh[100] and not fresh[44])
local ordinary = draw(3, 1, 0)
assert(ordinary[4] and not ordinary[5] and not ordinary[40] and not ordinary[100])
assert(ids(blood.project(styles, {}, byId, 3, 1, location, 2, 0, classes.all))[100])
print(
    "Dense and small room round trips, optional blood eligibility, graph closure and peer lifecycle passed"
)
