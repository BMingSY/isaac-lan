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
local now, pause = 0, 0
local motion = dofile(root .. "/src/bridge/presentation/motion.lua")({
    rooms_with_player = function(_, fn)
        fn()
        return true
    end,
}, {}, {
    vector = Vector,
    clock = function()
        return now * 1000
    end,
    status = function()
        return { pause = pause, slot = 1 }
    end,
    room = function()
        return {
            IsMirrorWorld = function()
                return false
            end,
        }
    end,
})
local entity, state = {}, {}
local function accept(t, tick, x, speed)
    state.target = Vector(x, 0)
    state.track = motion.track(state.track, Vector(x, 0), Vector(speed, 0), t, tick)
end
local function render(t)
    now = t
    motion.present(string.rep("\0", 8), 0, {}, { [1] = state }, function()
        return entity
    end, 1)
    return entity.Position.X
end
local function close(actual, expected, message)
    assert(
        math.abs(actual - expected) < 0.0001,
        (message or "position") .. ": " .. actual .. " vs " .. expected
    )
end
-- A newly observed projectile is displayed immediately, not one snapshot back.
accept(0, 1, 10, 300)
close(render(0), 10)
close(render(1 / 60), 15)
close(render(1 / 30), 20)
close(render(0.05), 25)
-- The intermediate tick was merged/skipped: the old implementation snapped
-- back to its previous target here despite forward-only authoritative motion.
accept(2 / 30, 3, 30, 300)
close(render(2 / 30), 30, "Skipped snapshot reversed movement")
close(render(2 / 30 + 1 / 60), 35)
-- Dense and sparse updates describe the same constant-velocity path.
for _, gap in ipairs({ 1, 2, 3 }) do
    state = {}
    accept(0, 0, 0, 120)
    for frame = 1, 60 do
        local t = frame / 60
        if frame % (2 * gap) == 0 then
            accept(t, frame / 2, t * 120, 120)
        end
        close(render(t), t * 120, "Cadence changed displayed speed")
    end
end
-- An off-phase packet must preserve the current trajectory at its arrival.
state = {}
accept(0, 1, 0, 300)
local before = render(0.05)
accept(0.05, 2, 10, 300)
close(render(0.05), before, "Late packet introduced a positional jump")
assert(render(0.05 + 1 / 60) > before)
-- Repeated state does not restart the correction clock or extrapolation cap.
local repeated = state.track
accept(0.06, 2, 10, 300)
assert(state.track == repeated)
close(render(1), 40)
close(render(2), 40, "Network stall extrapolated indefinitely")
-- Authoritative stop converges instead of creating lasting drift.
accept(2, 3, 35, 0)
close(render(2), 40)
close(render(3), 35)
-- A real reversal changes direction, while a teleport resets without a sweep.
accept(3, 4, 35, -300)
assert(render(3 + 1 / 60) < 35)
accept(4, 5, 600, 0)
close(render(4), 600)
pause = 1
accept(5, 6, 600, 300)
close(render(5.05), 600, "Pause advanced displayed movement")
pause = 0
close(render(5.08), 600, "Resume released stale paused extrapolation")
-- Room/floor/identity cleanup drops the old trajectory; a spawn has no error.
motion.reset()
state = {}
accept(6, 0, 20, 0)
close(render(6), 20)
print("PASS immediate snapshots, continuous gaps/jitter, cadence, stops, reversal, pause and reset")
