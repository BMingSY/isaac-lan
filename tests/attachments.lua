local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local E = fields.entity
local vector = {}
vector.__index = vector
local function Vector(x, y)
    return setmetatable({ X = x, Y = y }, vector)
end
function vector.__add(a, b)
    return Vector(a.X + b.X, a.Y + b.Y)
end
function vector.__sub(a, b)
    return Vector(a.X - b.X, a.Y - b.Y)
end
local types =
    { ENTITY_PLAYER = 1, ENTITY_TEAR = 2, ENTITY_LASER = 7, ENTITY_KNIFE = 8, ENTITY_EFFECT = 1000 }
local effects = { LASER_IMPACT = 50 }
local writes = {}
local attachments = dofile(root .. "/src/bridge/presentation/attachments.lua")(fields)({
    laser_path = function(sprite, bytes, x, y)
        writes[#writes + 1] = { sprite = sprite, bytes = bytes, x = x, y = y }
        return true
    end,
}, Vector, types, effects)
local entities, models = {}, {}
local function add(id, kind, subtype, parent, variant, disabled)
    local entity = {
        Type = kind,
        SubType = subtype or 0,
        Variant = variant or 0,
        DisableFollowParent = disabled,
    }
    function entity:ToLaser()
        return self
    end
    function entity:GetSprite()
        return id
    end
    local value = { [E.parent] = parent or 0 }
    if kind == types.ENTITY_LASER then
        value[E.laserPath], value[E.laserEndPoint] = "path:" .. id, { 400, 210 }
    end
    entities[id] = entity
    models[id] = {
        target = Vector(100, 200),
        display = Vector(105, 207),
        actor = kind == types.ENTITY_PLAYER,
        attachment = attachments.capture(entity, value),
    }
    entity.Position = models[id].display
    return entity, models[id], value
end
local function present()
    attachments.present(models, function(id)
        return entities[id]
    end)
end
local function close(position, x, y, label)
    assert(math.abs(position.X - x) < 0.0001 and math.abs(position.Y - y) < 0.0001, label)
end
local _, body = add(20, types.ENTITY_PLAYER)
body.display = Vector(130, 180)
local _, other = add(30, types.ENTITY_PLAYER)
other.display = Vector(90, 220)
local bone, boneModel = add(1, types.ENTITY_KNIFE, 0, 20, 1)
local knife = add(2, types.ENTITY_KNIFE, 0, 30)
local hitbox = add(3, types.ENTITY_KNIFE, 4, 20, 10)
local projectile = add(4, types.ENTITY_KNIFE, 1, 20)
local tear = add(5, types.ENTITY_TEAR, 0, 20)
local brim, brimModel, brimValue = add(6, types.ENTITY_LASER, 0, 20, 1)
local impact = add(7, types.ENTITY_EFFECT, 1, 6, effects.LASER_IMPACT)
local tech = add(8, types.ENTITY_LASER, 0, 20, 2, true)
local techX = add(9, types.ENTITY_LASER, 2, 20, 2)
local ludo = add(10, types.ENTITY_LASER, 1, 20, 2)
local maw = add(11, types.ENTITY_LASER, 3, 20, 1)
local connection = add(12, types.ENTITY_LASER, 4, 20, 2)
local freeImpact = add(13, types.ENTITY_EFFECT, 5, 9, effects.LASER_IMPACT)
local creep = add(14, types.ENTITY_EFFECT, 0, 20, 70)
local orphan = add(15, types.ENTITY_KNIFE, 0, 99)
local cycleA = add(16, types.ENTITY_KNIFE, 0, 17)
local cycleB = add(17, types.ENTITY_KNIFE, 0, 16)
present()
for _, entity in ipairs({ bone, hitbox, brim, impact, maw }) do
    close(entity.Position, 130, 180, "Attachment detached from its displayed body")
end
close(knife.Position, 90, 220, "A second body inherited the wrong controller's offset")
for _, entity in ipairs({
    projectile,
    tear,
    tech,
    techX,
    ludo,
    connection,
    freeImpact,
    creep,
    orphan,
    cycleA,
    cycleB,
}) do
    close(entity.Position, 105, 207, "Independent or unresolved entity followed a player")
end
close(brim.EndPoint, 430, 190, "Beam endpoint detached from its origin")
close(techX.EndPoint, 405, 217, "Free beam path missed its own display offset")
local count = #writes
present()
assert(#writes == count, "Identical render repeatedly restored native paths")
body.display = Vector(80, 205)
present()
close(bone.Position, 80, 205, "Direction reversal retained stale attachment translation")
close(brim.EndPoint, 380, 215, "Render translation accumulated instead of using authority")
for _, write in ipairs(writes) do
    assert(write.bytes == "path:" .. write.sprite, "Render mutated the authoritative path")
end
-- A repeated authoritative apply restores path bytes before the next render.
brimModel.attachment = attachments.capture(brim, brimValue)
count = #writes
present()
assert(#writes == count + 1, "Repeated snapshots left a restored path untranslated")
-- Parent replacement and disappearance never retain a previous body's offset.
boneModel.attachment = attachments.capture(bone, { [E.parent] = 30 })
present()
close(bone.Position, 90, 220, "Replacement parent did not take ownership")
entities[30] = nil
boneModel.display = Vector(101, 202)
bone.Position = boneModel.display
present()
close(bone.Position, 101, 202, "Removed parent kept moving an orphan")
boneModel.attachment = attachments.capture(bone, { [E.parent] = 0 })
assert(boneModel.attachment == nil, "Detached weapon retained its parent")
models, entities = {}, {}
present()
add(20, types.ENTITY_PLAYER)
local newBone = add(1, types.ENTITY_KNIFE, 0, 20, 1)
present()
close(newBone.Position, 105, 207, "Room reset reused an old attachment offset")
-- Exercise the render pipeline: attachments resolve after actor interpolation,
-- even when the child appears first and its native velocity is zero.
local now = 0
local motion = dofile(root .. "/src/bridge/presentation/motion.lua")(fields)({}, {}, {
    vector = Vector,
    clock = function()
        return now * 1000
    end,
    status = function()
        return { pause = 0, slot = 1 }
    end,
    attachments = attachments,
})
for id, model in pairs(models) do
    model.controller = 1
    model.track = motion.track(nil, model.target, Vector(id == 20 and 120 or 0, 0), 0, 1)
end
now = 0.05
motion.present("", 0, {}, models, function(id)
    return entities[id]
end, 1)
close(newBone.Position, 106, 200, "Render pipeline did not anchor the zero-velocity weapon")
print("Attached weapon, beam path, independent projectile and lifecycle checks passed")

-- A carried actor and its weapon share the holder's prediction, then resume
-- independent trajectories when the authoritative link is released.
local body, bone = models[20], entities[1]
local soul, soulModel = add(80, types.ENTITY_PLAYER)
soulModel.display = Vector(150, 230)
soulModel.held = 20
body.target = Vector(110, 190)
body.display = Vector(115, 195)
present()
close(entities[20].Position, 160, 220, "Carried actor did not follow holder")
close(bone.Position, 150, 230, "Carried weapon did not follow holder")
present()
close(entities[20].Position, 160, 220, "Repeated carry render drifted")
soulModel.held = 0
body.display = Vector(120, 205)
present()
close(bone.Position, 110, 215, "Thrown weapon retained holder offset")
soulModel.held = 20
entities[80] = nil
present()
close(bone.Position, 110, 215, "Removed holder retained a link")
print("PASS carried actor/weapon offsets, repeat, throw and holder removal")
