-- Movement invariants, independent of the game and packet timing.
local root = arg[1] or "."
local vector = {}
vector.__index = vector
function Vector(x, y)
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
function vector:LengthSquared()
    return self.X * self.X + self.Y * self.Y
end
local function close(a, b)
    assert(math.abs(a.X - b.X) < 0.00001 and math.abs(a.Y - b.Y) < 0.00001)
end
local prediction = assert(loadfile(root .. "/src/bridge/prediction.lua"))()
local right, left, down, stop = Vector(1, 0), Vector(-1, 0), Vector(0, 1), Vector(0, 0)
local origin, speed, dt = Vector(100, 200), 180, 1 / 60
local p = prediction.new(origin)
p:confirm(origin, 0)
close(p:step(right, 1, speed, dt), Vector(103, 200))
-- Starting, reversing, changing axis and releasing all work before the next send.
close(p:step(left, 1, speed, dt), origin)
close(p:step(down, 1, speed, dt), Vector(100, 203))
close(p:step(stop, 1, speed, dt), Vector(100, 203))
-- Acknowledging the last sent sample must retain the unsent preview.
p:confirm(origin, 0)
close(p:step(stop, 1, speed, dt), Vector(100, 203))
-- Consumed input disappears once, and cannot be inserted again by another render.
p:confirm(Vector(100, 203), 1)
close(p:step(right, 1, speed, dt), Vector(100, 203))
close(p:step(right, 2, speed, dt), Vector(103, 203))
-- A correction must affect neutral and moving frames equally: do not filter input.
local moving, neutral = prediction.new(origin), prediction.new(origin)
for _, model in ipairs({ moving, neutral }) do
    model:confirm(Vector(110, 210), 0)
end
close(moving:step(left, 1, speed, dt) - neutral:step(stop, 1, speed, dt), Vector(-3, 0))
-- Replay uses the speed when movement was displayed, not a newer stat value.
p = prediction.new(origin)
p:step(right, 1, speed, dt)
close(p:step(stop, 1, speed * 2, dt), Vector(103, 200))
-- Pending samples may span dropped snapshots; an acknowledgement retires all older ones.
p:step(right, 2, speed, dt)
p:step(right, 3, speed, dt)
p:confirm(Vector(106, 200), 2)
close(p:step(stop, 4, speed, dt), Vector(109, 200))
p:confirm(Vector(109, 200), 3)
close(p:step(stop, 4, speed, dt), Vector(109, 200))
-- Clipped movement stays against a wall and converges after release.
p = prediction.new(origin)
for sequence = 1, 20 do
    p:step(right, sequence, speed, dt)
    p:clip(origin)
    close(p.display, origin)
    p:confirm(origin, sequence)
end
close(p:step(stop, 21, speed, dt), origin)
-- Teleports discard old movement immediately instead of dragging it across the room.
p:step(right, 22, speed, dt)
p:confirm(Vector(600, 200), 21)
close(p:step(stop, 23, speed, dt), Vector(600, 200))
-- A fresh model is also the room/floor/reset boundary.
p = prediction.new(origin)
close(p:step(stop, 0, speed, dt), origin)
-- Clock anomalies and a long stall never produce negative or unbounded movement.
close(p:step(right, 1, speed, -1), origin)
close(p:step(right, 1, speed, 5), Vector(109, 200))
close(p:step(right, 1, speed, 5), Vector(118, 200))
close(p:step(right, 1, speed, 5), Vector(118, 200))
print("PASS immediate preview, acknowledgements, correction, clipping and resets")
