local root = assert(arg[1])
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
function vector.__mul(a, b)
    return Vector(a.X * b, a.Y * b)
end
function vector:Length()
    return math.sqrt(self.X * self.X + self.Y * self.Y)
end
local now = 0
local view = {
    vector = Vector,
    clock = function()
        return now
    end,
    status = function()
        return { pause = 0, slot = 1 }
    end,
    room = function()
        return {
            IsMirrorWorld = function()
                return false
            end,
        }
    end,
}
local native = {
    rooms_with_player = function(_, fn)
        fn()
        return true
    end,
}
local motion = dofile(root .. "/src/bridge/presentation/motion.lua")(native, {}, view)
local replica = { Position = Vector(0, 0) }
local function position(tickGap, milliseconds)
    now = milliseconds
    motion.present(string.rep("\0", 8), 0, {}, {
        [1] = {
            from = Vector(0, 0),
            target = Vector(12, 0),
            velocity = Vector(0, 0),
            at = 0,
            tick = 20,
            previousTick = 20 - tickGap,
            actor = false,
        },
    }, function()
        return replica
    end, 20)
    return replica.Position.X
end
assert(math.abs(position(3, 50) - 6) < 0.0001, "10Hz view jumped to its target after 33ms")
assert(math.abs(position(1, 1000 / 60) - 6) < 0.0001, "30Hz interpolation changed speed")
assert(position(3, 100) == 12, "Variable interval did not reach the target")
print("PASS actual snapshot intervals drive replica interpolation")
