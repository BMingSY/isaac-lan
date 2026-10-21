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
function vector:Dot(b)
    return self.X * b.X + self.Y * b.Y
end
function vector:Normalized()
    return self * (1 / math.sqrt(self:Dot(self)))
end
local motion = dofile(root .. "/src/bridge/presentation/tear_motion.lua")(Vector)
local function close(a, b, epsilon)
    assert(math.abs(a - b) <= (epsilon or 0.0005), a .. " ~= " .. b)
end
local input = assert(io.open(root .. "/tests/fixtures/tear_motion.csv"))
local names = {}
for name in input:read("*l"):gmatch("[^,]+") do
    names[#names + 1] = name
end
local count, cases = 0, {}
for line in input:lines() do
    local row, index = {}, 1
    for value in line:gmatch("[^,]+") do
        row[names[index]], index = tonumber(value) or value, index + 1
    end
    local velocity = motion.velocity(Vector(1, 0), Vector(row.body_vx, row.body_vy), row.shot_speed)
    close(velocity.X, row.vx)
    close(velocity.Y, row.vy)
    local position, height = motion.sample({
        at = 0,
        origin = Vector(0, 0),
        velocity = Vector(row.vx, row.vy),
        height = row.height0,
        falling = row.falling0,
        acceleration = row.acceleration,
    }, row.age / 30)
    close(position.X, row.dx)
    close(position.Y, row.dy)
    close(height, row.height)
    local _, falling = motion.altitude(row.height0, row.falling0, row.acceleration, row.age)
    close(falling, row.falling)
    -- Native launch consumes a random value. Its midpoint approximation must
    -- stay within the actual jitter, without consuming a random stream locally.
    local initialHeight, initialFalling =
        motion.initial(row.player_height, row.player_falling, row.player_acceleration)
    close(initialHeight, row.height0, 0.091)
    close(initialFalling, row.falling0, 0.091)
    count, cases[row.case] = count + 1, true
end
input:close()
assert(count > 150 and cases.slow and cases.fast and cases.short and cases.long and cases.cross)
local reverse = motion.velocity(Vector(1, 0), Vector(-5, 2), 0.6)
close(reverse.X, 6)
close(reverse.Y, 1.44)
local slow = motion.origin(Vector(100, 100), Vector(6, 0), 4)
local fast = motion.origin(Vector(100, 100), Vector(16, 0), 4)
close(slow.X, 109)
close(fast.X, 124)
close(slow.Y, fast.Y)
print(
    "PASS "
        .. count
        .. " native tear samples, speed/inertia, range/altitude and muzzle displacement"
)
