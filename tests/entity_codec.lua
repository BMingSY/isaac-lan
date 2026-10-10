local root = assert(arg[1])
local schemas = dofile(root .. "/src/bridge/sync/entity_schema.lua")
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
local geometry = string.pack(">ff", 520, -180)
local dogma = dofile(root .. "/src/bridge/compat/bosses/dogma.lua")(env.Vector)
local component = assert(loadfile(root .. "/src/bridge/sync/entity_codec.lua", "t", env))()(
    {
        entity_prepare = function()
            return true
        end,
        entity_shadow = function()
            return ""
        end,
        sprite_state = function(_, bytes)
            return bytes and {} or ""
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
    dogma
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
assert(state[1] == 1 and state[10] == false and state[20] == "native laser path")
assert(laserReads == 1 and #state[9] == 11, "SampleLaser userdata must stay outside scalar fields")
component.apply(target, state)
assert(target.flags == 1 and target.DepthOffset == -9990, "Replica must not bake floor/wall flags")
assert(target.Position.X == 12 and target.Velocity.Y == 3 and target.EndPoint.X == 51)
assert(target.EntityCollisionClass == 0 and target.GridCollisionClass == 0 and laserWrites == 1)
component.apply(target, state)
assert(target.DepthOffset == -9990, "Repeated snapshots must not accumulate the floor offset")
local actor, replica = entity(1, 1), entity(1, 128)
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
local value = wire.decode(wire.encode(component.capture(warning)))
assert(value[24] == geometry)
component.apply(beam, value)
assert(
    beam.Variant == 172
        and beam.SubType == 1
        and string.pack(">ff", beam.TargetPosition.X, beam.TargetPosition.Y) == geometry
)
source.MaxDistance = {}
assert(not pcall(component.capture, source, false), "Unsupported userdata scalar must be rejected")
source.MaxDistance = math.huge
assert(not pcall(component.capture, source, false), "Non-finite scalar must be rejected")
print("PASS portable entity fields, native laser state and replica lifecycle flag ownership")
