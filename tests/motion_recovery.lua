local root = assert(arg[1])
local function Vector(x, y)
    return { X = x, Y = y }
end
local motion = dofile(root .. "/src/bridge/presentation/motion.lua")(
    dofile(root .. "/src/bridge/sync/fields.lua")
)({}, {}, {
    vector = Vector,
    timeline = dofile(root .. "/src/bridge/presentation/timeline.lua")(),
    status = function()
        return { slot = 1, ping1 = 90 }
    end,
})
local function close(a, b)
    assert(math.abs(a - b) < 0.0001, a .. " vs " .. b)
end
local function accept(track, source, received, tick, x, velocity)
    motion.observe(source * 1000, received)
    return motion.track(track, Vector(x, 0), Vector(velocity, 0), received, tick)
end

-- Clean delivery adds no buffering to a constant-velocity trajectory.
local track = accept(nil, 1, 1.045, 30, 0, 120)
for frame = 3, 60 do
    local now = 1 + frame / 60
    if frame % 2 == 0 then
        local source = now - 0.045
        track = accept(track, source, now, 30 + frame / 2, (source - 1) * 120, 120)
    end
    close(motion.sample(track, now).X, (now - 1) * 120)
end

-- A 250 ms delivery gap used to release 11.2 units on the first 60 Hz
-- render, despite normal motion advancing only 2. Keep every recovery step
-- bounded, including when new snapshots arrive during the correction.
motion.reset()
track = accept(nil, 1, 1.045, 30, 0, 120)
close(motion.sample(track, 1.25).X, 12)
local shown = motion.sample(track, 1.295).X
track = accept(track, 1.25, 1.295, 38, 30, 120)
close(motion.sample(track, 1.295).X, shown)
local maximum = 0
for frame = 1, 30 do
    local now = 1.295 + frame / 60
    if frame % 2 == 0 then
        track = accept(track, now - 0.045, now, 38 + frame / 2, (now - 1.045) * 120, 120)
    end
    local x = motion.sample(track, now).X
    maximum = math.max(maximum, x - shown)
    assert(x >= shown - 0.0001 and x - shown <= 5.001, "Recovery jumped or reversed")
    shown = x
end
assert(math.abs(shown - (1.795 - 1) * 120) < 0.1, "Recovery retained a permanent display delay")
-- Repeated/old state cannot replenish recovery or start a new extrapolation.
assert(accept(track, 1.75, 1.85, 53, 90, 120) == track)
local stopped = motion.sample(track, 3).X
close(motion.sample(track, 4).X, stopped)
track = accept(track, 4, 4.045, 120, stopped - 10, 0)
close(motion.sample(track, 5).X, stopped - 10)
track = accept(track, 6, 6.045, 180, 600, 0)
close(motion.sample(track, 6.045).X, 600)
motion.reset()
track = accept(nil, 7, 7.045, 0, 10, 0)
close(motion.sample(track, 7.045).X, 10)
print(string.format("PASS bounded gap recovery: maximum step %.3f; normal step 2", maximum))
