local root = assert(arg[1])
local V = {}
V.__index = V
local function Vector(x, y)
    return setmetatable({ X = x, Y = y }, V)
end
function V.__sub(a, b)
    return Vector(a.X - b.X, a.Y - b.Y)
end
function V.__add(a, b)
    return Vector(a.X + b.X, a.Y + b.Y)
end
function V.__mul(a, b)
    return Vector(a.X * b, a.Y * b)
end
local data, rendered = {}, {}
local owner = {
    Position = Vector(20, 10),
    Exists = function()
        return true
    end,
}
local entity = {
    Type = 3,
    Visible = true,
    Position = Vector(60, 10),
    GetData = function()
        return data
    end,
    GetSprite = function()
        return "body"
    end,
}
local bytes = string.pack(">I2fffffffff", 3, 20, 10, -8, 40, 12, -12, 60, 10, -6)
local module = dofile(root .. "/src/bridge/presentation/tethers.lua")(
    {
        familiar_tether_render = function(body, sprite, value)
            assert(body == "body" and sprite.path == "native cord")
            rendered[#rendered + 1] = value
            return true
        end,
    },
    Vector,
    function()
        return {}
    end,
    { ENTITY_FAMILIAR = 3 },
    function()
        return { entity }
    end
)
local value = { bytes, { path = "native cord" }, 7, { 20, 10 }, { 60, 10 } }
module.apply(entity, value, function(sprite, pose)
    sprite.path = pose.path
end)
module.link(entity, value, function(id)
    assert(id == 7)
    return owner
end)
owner.Position = Vector(23, 12)
entity.Position = Vector(65, 8)
module.render()
local n, x, y, z, mx, my, mz, tx, ty, tz = string.unpack(">I2fffffffff", rendered[1])
assert(n == 3 and x == 23 and y == 12 and tx == 65 and ty == 8 and mx == 44 and my == 12)
assert(z == -8 and mz == -12 and tz == -6, "Tether interpolation changed its altitude")
module.render()
assert(rendered[2] == rendered[1] and value[1] == bytes, "Repeated drawing accumulated prediction")
module.apply(entity, false)
module.render()
assert(#rendered == 2, "Removed tether survived the next snapshot")
print("PASS independent tether endpoints, native altitude, repeated render and removal")
