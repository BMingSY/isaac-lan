local root = assert(arg[1])
local timeline = dofile(root .. "/src/bridge/presentation/timeline.lua")()
local function close(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, actual .. " vs " .. expected)
end
-- The peers have different monotonic clock origins, with 45 ms one-way delay.
close(timeline.observe(10000, 20.045, 90), 20)
close(timeline.observe(10033, 20.078, 90), 20.033)
-- A late view and inflated RTT do not shift all entity tracks onto receipt time.
close(timeline.observe(10066, 20.266, 400), 20.066)
close(timeline.observe(10099, 20.144, 90), 20.099)
timeline.reset()
close(timeline.observe(0, 30, -1), 30)
close(timeline.observe(1000, 30, -1), 30)
close(timeline.observe(1033, 30.033, 80), 29.993)
-- A restarted authority has a new clock origin.
close(timeline.observe(5, 40, 80), 39.96)
print("authority clock mapping, jitter and reset passed")
