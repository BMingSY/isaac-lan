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
-- The native loader executes this chunk without retaining its return value.
_IsaacLanPrediction = nil
assert(loadfile(root .. "/src/bridge/presentation/prediction.lua"))()
local prediction =
    assert(_IsaacLanPrediction, "Native prediction bootstrap did not publish its API")
local right, left, stop = Vector(1, 0), Vector(-1, 0), Vector(0, 0)
local origin, speed, dt = Vector(100, 200), 1, 1 / 60
local p = prediction.new(origin)
p:confirm(origin, 0)
local started = p:step(right, 1, speed, dt)
close(started, origin)
assert(p.velocity.X > 0, "Local acceleration waited for a packet")
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
-- Authoritative corrections converge without an immediate positional jump,
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
assert(moving:step(stop, 2, speed, dt).X > expected.X)
local a, b = prediction.new(origin), prediction.new(origin)
a:confirm(Vector(120, 200), 0)
b:confirm(Vector(120, 200), 0)
a:step(right, 1, speed, dt)
b:step(stop, 1, speed, dt)
assert(a.velocity.X > b.velocity.X, "Correction filtered fresh input")
a:step(right, 2, speed, dt)
b:step(stop, 2, speed, dt)
assert(a.display.X > b.display.X, "Correction filtered fresh movement")
for sequence = 2, 60 do
    b:step(stop, sequence, speed, dt)
end
assert(math.abs(b.display.X - 120) < 0.01)
-- Clipped presentation must not build up hidden velocity at a wall;
-- repeated authority confirmations retain the blocked position.
p = prediction.new(origin)
for sequence = 1, 20 do
    p:step(right, sequence, speed, dt)
    p:clip(origin)
    p:confirm(origin, sequence)
    close(p.display, origin)
    assert(p.velocity:LengthSquared() < 40 ^ 2, "Wall clipping accumulated hidden velocity")
end
close(
    p:step(stop, 21, speed, dt, false, function()
        return origin
    end),
    origin
)
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
assert(capped.X - origin.X < 30)
print("PASS local acceleration, inertia, historical correction, walls and resets")

-- A host tick can move under held input without consuming another sample.
-- Repeated ack 10 must not freeze its authority position or retain old inertia.
p = prediction.new(Vector(0, 0))
p:confirm(Vector(0, 0), 10, stop, 100)
p:confirm(Vector(20, 0), 10, stop, 101)
for _ = 1, 60 do
    p:step(stop, 10, speed, dt)
end
assert(math.abs(p.display.X - 20) < 0.001, "Same-ack authority motion was ignored")
p:confirm(Vector(2, 0), 10, stop, 100)
close(p:step(stop, 10, speed, 0), Vector(20, 0))
p = prediction.new(origin)
for sequence = 1, 10 do
    p:step(right, sequence, speed, dt)
end
assert(p.velocity.X > 100)
p:confirm(p.display, 10, stop, 200)
local stopped = p.display
close(p:step(stop, 11, speed, dt), stopped)
close(p.velocity, stop)

-- Replaying pending direction/duration from a stopped authority must match a
-- fresh prediction from that same state, including a turn within one sample.
p = prediction.new(origin)
p:step(right, 1, speed, dt)
p:step(left, 2, speed, dt)
p:step(right, 2, speed, dt)
p:confirm(origin, 1, stop, 1)
p:step(stop, 3, speed, 0)
local fresh = prediction.new(origin)
fresh:step(left, 2, speed, dt)
fresh:step(right, 2, speed, dt)
close(p.velocity, fresh.velocity)
close(p.position, fresh.position)
for sequence = 3, 300 do
    p:step(stop, sequence, speed, dt)
end
assert(#p.pending <= 120, "Missing acknowledgements grew unbounded history")
print("PASS same-ack host ticks, stale ticks, authoritative velocity and bounded input replay")

-- Captured from J460 player updates at 30 Hz: starts, releases, reversals and
-- perpendicular turns at MoveSpeed 0.6, 1, 1.3 and 2. Velocities in the fixture
-- are native units per half tick; the predictor stores units per second.
local samples = assert(io.open(root .. "/tests/fixtures/prediction_motion.csv", "r"))
samples:read("*l")
local previousTick, previousSpeed, checked = nil, nil, 0
for line in samples:lines() do
    local values = {}
    for value in line:gmatch("[^,]+") do
        values[#values + 1] = assert(tonumber(value))
    end
    local tick, x, y, vx, vy, dx, dy, moveSpeed = table.unpack(values)
    if previousTick and tick == previousTick + 1 and moveSpeed == previousSpeed then
        p:step(Vector(dx, dy), tick, moveSpeed, 1 / 30)
        assert(
            (p.position - Vector(x, y)):LengthSquared() < 0.002 ^ 2,
            "Native walking position diverged at speed " .. moveSpeed .. ", tick " .. tick
        )
        assert(
            (p.velocity * (1 / 60) - Vector(vx, vy)):LengthSquared() < 0.00001 ^ 2,
            "Native walking velocity diverged at speed " .. moveSpeed .. ", tick " .. tick
        )
        checked = checked + 1
    else
        p = prediction.new(Vector(x, y))
        p:reset(Vector(x, y), tick, Vector(vx, vy) * 60)
    end
    previousTick, previousSpeed = tick, moveSpeed
end
samples:close()
assert(checked == 160, "Missing native walking samples")
print("PASS native walking traces across speeds, releases, reversals and turns")
