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
local prediction = assert(loadfile(root .. "/src/bridge/presentation/prediction.lua"))()
local right, left, stop = Vector(1, 0), Vector(-1, 0), Vector(0, 0)
local origin, speed, dt = Vector(100, 200), 264.705882, 1 / 60
local p = prediction.new(origin)
p:confirm(origin, 0)
local started = p:step(right, 1, speed, dt)
assert(started.X > origin.X, "Local start waited for a packet")
local initialVelocity = p.velocity.X
p:step(left, 1, speed, dt)
assert(p.velocity.X < initialVelocity, "Local turn waited for the next sample")
-- Release applies friction locally, preserving native inertia rather than
-- stopping instantly and being dragged onward by late authority positions.
for sequence = 2, 30 do
    p:step(right, sequence, speed, dt)
end
local beforeRelease = p.display.X
local movingVelocity = p.velocity.X
p:step(stop, 31, speed, dt)
assert(p.display.X > beforeRelease and p.velocity.X < movingVelocity)
for sequence = 32, 100 do
    p:step(stop, sequence, speed, dt)
end
assert(p.velocity.X < 0.1, "Released movement did not settle")
-- Acknowledgement compares historical movement, retaining the unsent preview.
p = prediction.new(origin)
p:step(right, 1, speed, dt)
local acknowledgedPosition = p.display
p:step(right, 2, speed, dt)
local preview = p.display
p:confirm(acknowledgedPosition, 1)
close(p.display, preview)
p:step(stop, 3, speed, 0)
close(p.display, preview)
-- Repeated confirmations cannot consume or move the same preview twice.
p:confirm(acknowledgedPosition, 1)
p:step(stop, 3, speed, 0)
close(p.display, preview)
-- Small moving errors leave the path alone. Meaningful errors converge,
-- while fresh input retains exactly the same contribution during correction.
local moving, neutral = prediction.new(origin), prediction.new(origin)
for _, model in ipairs({ moving, neutral }) do
    model:confirm(Vector(101, 200), 0)
end
moving:step(right, 1, speed, dt)
neutral:step(right, 1, speed, dt)
local expected = moving.display
moving:confirm(Vector(102, 200), 1)
close(moving.display, expected)
close(moving:step(stop, 2, speed, dt), neutral:step(stop, 2, speed, dt))
local a, b = prediction.new(origin), prediction.new(origin)
a:confirm(Vector(120, 200), 0)
b:confirm(Vector(120, 200), 0)
a:step(right, 1, speed, dt)
b:step(stop, 1, speed, dt)
assert(a.display.X > b.display.X, "Correction filtered fresh input")
for sequence = 2, 60 do
    b:step(stop, sequence, speed, dt)
end
assert(math.abs(b.display.X - 120) < 0.01)
-- Clipping edits the recorded displacement too: blocked motion must never
-- become a later correction or build up hidden velocity at a wall.
p = prediction.new(origin)
for sequence = 1, 20 do
    p:step(right, sequence, speed, dt)
    p:clip(origin)
    p:confirm(origin, sequence)
    close(p.display, origin)
    close(p.velocity, stop)
end
close(p:step(stop, 21, speed, dt), origin)
-- Teleports and room resets discard history, inertia and corrections.
p:step(right, 22, speed, dt)
p:confirm(Vector(600, 200), 22)
close(p:step(stop, 23, speed, dt), Vector(600, 200))
p:reset(origin, 23)
close(p:step(stop, 24, speed, dt), origin)
-- Clock anomalies and an unacknowledged stall stay bounded.
p = prediction.new(origin)
close(p:step(right, 1, speed, -1), origin)
p:step(right, 1, speed, 5)
p:step(right, 1, speed, 5)
local capped = p.display
close(p:step(right, 1, speed, 5), capped)
assert(capped.X - origin.X < speed * 0.1)
print("PASS local acceleration, inertia, historical correction, walls and resets")
