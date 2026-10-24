local root = assert(arg[1])
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local schemas = dofile(root .. "/src/bridge/sync/entity_schema.lua")(enums.EntityType)
local env = setmetatable({
    Vector = function(x, y)
        return { X = x, Y = y }
    end,
    Color = function(...)
        return { table.unpack({ ... }) }
    end,
    EntityFlag = { FLAG_RENDER_FLOOR = 2, FLAG_RENDER_WALL = 4, FLAG_NO_DAMAGE_BLINK = 1 },
    EntityCollisionClass = { ENTCOLL_NONE = 0 },
    EntityGridCollisionClass = { GRIDCOLL_NONE = 0 },
}, { __index = _G })
local laserReads, laserWrites = 0, 0
local spriteChanges = true
local geometry = string.pack(">ff", 520, -180)
local dogma = dofile(root .. "/src/bridge/compat/bosses/dogma.lua")(
    env.Vector,
    enums.EntityType,
    enums.EffectVariant
)
local component = assert(loadfile(root .. "/src/bridge/sync/entity_codec.lua", "t", env))()(
    dofile(root .. "/src/bridge/sync/fields.lua")
)(
    {
        presentation_local_effect = function(kind, variant, subtype)
            return kind == 1000 and variant == 99 and subtype == 1
        end,
        entity_prepare = function()
            return true
        end,
        entity_shadow = function()
            return ""
        end,
        sprite_state = function(_, bytes)
            return bytes and spriteChanges or ""
        end,
        laser_path = function(_, bytes)
            if bytes then
                assert(bytes == "native laser path")
                laserWrites = laserWrites + 1
                return true
            end
            laserReads = laserReads + 1
            return "native laser path"
        end,
    },
    schemas,
    {
        capture = function()
            return false
        end,
    },
    dogma,
    {
        capture = function()
            return 0
        end,
        captureHeld = function()
            return 0
        end,
        applyHeld = function() end,
        apply = function() end,
    }
)
local function entity(kind, flags)
    local e = {
        Type = kind,
        Variant = 0,
        SubType = 0,
        InitSeed = 123,
        FrameCount = 40,
        Position = { X = 12, Y = 13 },
        Velocity = { X = 2, Y = 3 },
        SpriteOffset = { X = 0, Y = 0 },
        SpriteScale = { X = 1, Y = 1 },
        Color = { R = 1, G = 1, B = 1, A = 1, RO = 0, GO = 0, BO = 0 },
        EndPoint = { X = 51, Y = 52 },
        SampleLaser = {},
        flags = flags,
        data = {},
        sprite = {},
    }
    for _, name in ipairs(schemas.common) do
        e[name] = 0
    end
    for _, name in ipairs(schemas.byType[kind]) do
        e[name] = 0
    end
    e.Visible, e.DepthOffset = true, 10
    function e:Exists()
        return true
    end
    function e:GetData()
        return self.data
    end
    function e:ToLaser()
        return self
    end
    function e:ToTear()
        return self
    end
    function e:ToPlayer()
        return self
    end
    function e:ToNPC()
        return nil
    end
    function e:ToEffect()
        return self
    end
    function e:GetSprite()
        return self.sprite
    end
    function e:GetEntityFlags()
        return self.flags
    end
    function e:ClearEntityFlags(mask)
        self.flags = self.flags & ~mask
    end
    function e:AddEntityFlags(mask)
        self.flags = self.flags | mask
    end
    return e
end
local source, target = entity(7, 7), entity(7, 255)
local state = component.capture(source, false)
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local common, typed = {}, {}
for _, name in ipairs(schemas.common) do
    common[#common + 1] = source[name]
end
for _, name in ipairs(schemas.byType[7]) do
    typed[#typed + 1] = source[name]
end
local expected = {
    1,
    7,
    0,
    0,
    123,
    { 12, 13 },
    { 2, 3 },
    common,
    typed,
    false,
    0,
    0,
    0,
    0,
    { 0, 0 },
    { 1, 1 },
    { 1, 1, 1, 1, 0, 0, 0 },
    false, -- Unused entity-local frame counter is not transmitted.
    7,
    "native laser path",
    { 51, 52 },
    false,
    false,
    false,
    0,
    false,
    0,
    false,
    0, -- contact eligibility
}
assert(codec.encode(state) == codec.encode(expected), "Compact entity contract changed")
assert(state[1] == 1 and state[10] == false and state[20] == "native laser path")
assert(laserReads == 1 and #state[9] == 11, "SampleLaser userdata must stay outside scalar fields")
component.apply(target, state)
assert(target.flags == 1 and target.DepthOffset == -9990, "Replica must not bake floor/wall flags")
assert(target.Position.X == 12 and target.Velocity.Y == 3 and target.EndPoint.X == 51)
assert(target.EntityCollisionClass == 0 and target.GridCollisionClass == 0 and laserWrites == 1)
component.apply(target, state)
assert(target.DepthOffset == -9990, "Repeated snapshots must not accumulate the floor offset")
local actor, replica = entity(1, 1), entity(1, 128)
-- Replica Player::Update does not count down the native arrival/input lock.
-- An authoritative zero must release it, while a live cooldown remains locked.
actor.ControlsEnabled, replica.ControlsEnabled = true, true
for _, cooldown in ipairs({ 45, 12, 0, 0, 60, 0 }) do
    actor.ControlsCooldown, replica.ControlsCooldown = cooldown, 90
    component.apply(replica, component.capture(actor, false))
    assert(replica.ControlsCooldown == cooldown, "Replica retained an obsolete control lock")
end
component.apply(replica, component.capture(actor, false))
assert(replica.flags == 129, "Replica actor must retain its native lifecycle flags")
local warning, beam = entity(1000, 1), entity(1000, 0)
warning.Variant, warning.SubType, warning.TargetPosition = 172, 1, env.Vector(520, -180)
for _, e in ipairs({ warning, beam }) do
    local s = e.sprite
    s.Scale, s.Offset, s.Color = e.SpriteScale, e.SpriteOffset, e.Color
    s.FlipX, s.FlipY, s.Rotation = false, false, 0
    for _, name in ipairs({ "GetFilename", "GetAnimation", "GetOverlayAnimation" }) do
        s[name] = function()
            return ""
        end
    end
    for _, name in ipairs({ "GetFrame", "GetOverlayFrame" }) do
        s[name] = function()
            return 0
        end
    end
    function s:RemoveOverlay() end
end
local wire = dofile(root .. "/src/bridge/sync/codec.lua")
assert(component.capture(warning)[18] == false, "Unused entity frame counter reached the wire")
assert(component.capture(entity(2, 0), false)[18] == 40, "Tear prediction lost its birth age")
local sourceSprite = {
    GetFilename = function()
        return "test.anm2"
    end,
    GetAnimation = function()
        return "Walk"
    end,
    GetFrame = function()
        return 17
    end,
    GetOverlayAnimation = function()
        return "Glow"
    end,
    GetOverlayFrame = function()
        return 11
    end,
    FlipX = true,
    FlipY = false,
    Rotation = 45,
    Scale = env.Vector(2, 3),
    Offset = env.Vector(4, 5),
    Color = { R = 0.1, G = 0.2, B = 0.3, A = 0.4, RO = 0.5, GO = 0.6, BO = 0.7 },
}
local expectedSprite = {
    "test.anm2",
    "Walk",
    17,
    "Glow",
    11,
    true,
    false,
    45,
    { 2, 3 },
    { 4, 5 },
    false, -- Native Sprite blob already contains the complete color.
    "",
}
assert(
    wire.encode(component.sprite(sourceSprite)) == wire.encode(expectedSprite),
    "Compact sprite contract changed"
)
local animation, overlay = "Walk", "Glow"
local animationChanges, overlayChanges = 0, 0
function sourceSprite:GetAnimation()
    return animation
end
function sourceSprite:GetOverlayAnimation()
    return overlay
end
function sourceSprite:SetFrame(name)
    animation, animationChanges = name, animationChanges + 1
end
function sourceSprite:SetOverlayFrame(name)
    overlay, overlayChanges = name, overlayChanges + 1
end
function sourceSprite:RemoveOverlay()
    overlay = ""
end
component.applySprite(sourceSprite, expectedSprite)
assert(animationChanges == 0 and overlayChanges == 0, "Unchanged animations restarted")
local switched = wire.decode(wire.encode(expectedSprite))
switched[2], switched[4] = "Idle", "Flash"
component.applySprite(sourceSprite, switched)
component.applySprite(sourceSprite, switched)
assert(animationChanges == 1 and overlayChanges == 1, "Animation switch did not occur once")
local value = wire.decode(wire.encode(component.capture(warning)))
assert(value[24] == geometry)
component.apply(beam, value)
assert(
    beam.Variant == 172
        and beam.SubType == 1
        and string.pack(">ff", beam.TargetPosition.X, beam.TargetPosition.Y) == geometry
)
local replaced, loaded = {}, 0
function beam.sprite:ReplaceSpritesheet(layer, path)
    replaced[#replaced + 1] = { layer, path }
end
function beam.sprite:LoadGraphics()
    loaded = loaded + 1
end
spriteChanges = { { 2, "changed.png" }, { 0, "base.png" } }
component.apply(beam, value)
assert(wire.encode(replaced) == wire.encode(spriteChanges) and loaded == 1)
spriteChanges = true
component.apply(beam, value)
assert(#replaced == 2 and loaded == 1, "Unchanged sprite reloaded graphics")
source.MaxDistance = {}
assert(not pcall(component.capture, source, false), "Unsupported userdata scalar must be rejected")
source.MaxDistance = math.huge
assert(not pcall(component.capture, source, false), "Non-finite scalar must be rejected")
local spray = entity(1000, 0)
spray.Variant, spray.SubType = 99, 1
assert(component.localEffect(spray) and not component.localEffect(warning))
actor.Parent, actor.SpawnerEntity, actor.Child, actor.Target = spray, spray, spray, spray
local linked = component.capture(actor, false)
for index = 11, 14 do
    assert(linked[index] == 0, "Local particle leaked an unresolved authority ID")
end
assert(spray:GetData().__isaac_lan_entity == nil)

-- Exercise the production packing branch. Opaque fields must survive the outer
-- codec and reach their own plan, while identity/motion remain available to Lua.
local unpacked = component.capture(warning, false)
local packedFields =
    codec.encode({ unpacked[8], unpacked[9], unpacked[15], unpacked[16], unpacked[17] })
local applied = {}
local packedNative = {
    entity_fields_plan = function(kind, template)
        return kind == 1000 and template or false
    end,
    entity_fields_capture = function(_, template)
        assert(#template == 29)
        local value = {}
        for i, field in ipairs(template) do
            value[i] = field ~= false and unpacked[i] or false
        end
        return value
    end,
    entity_fields_encode = function(_, template)
        assert(template[1] == schemas.common and template[2] == schemas.byType[1000])
        assert(
            template[3] == "SpriteOffset"
                and template[4] == "SpriteScale"
                and template[5] == "Color"
        )
        return packedFields
    end,
    entity_fields_apply = function(_, template, value)
        if #template == 29 then
            assert(value[2] == 1000 and value[6][1] == unpacked[6][1])
            applied[#applied + 1] = "outer"
        else
            assert(#template == 5 and value == packedFields)
            applied[#applied + 1] = "packed"
        end
        return true
    end,
    presentation_local_effect = function()
        return false
    end,
}
local packedComponent = assert(loadfile(root .. "/src/bridge/sync/entity_codec.lua", "t", env))()(
    dofile(root .. "/src/bridge/sync/fields.lua")
)(
    packedNative,
    schemas,
    {
        capture = function()
            return false
        end,
    },
    nil,
    {
        capture = function()
            return 0
        end,
        captureHeld = function()
            return 0
        end,
        applyHeld = function() end,
        apply = function() end,
    }
)
local packedState = codec.decode(codec.encode(packedComponent.capture(warning, false)))
for _, field in ipairs({ 8, 9, 15, 16, 17 }) do
    assert(packedState[field] == false, "Packed fields were also expanded into Lua arrays")
end
assert(packedState[26] == packedFields)
packedComponent.apply(beam, packedState)
assert(table.concat(applied, ",") == "outer,packed", "Packed plan was not restored")
packedState[26] = false
assert(not pcall(packedComponent.apply, beam, packedState), "Missing packed fields accepted")
print("PASS portable entity fields, native laser state and replica lifecycle flag ownership")
