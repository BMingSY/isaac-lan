local root = assert(arg[1])
local function Vector(x, y)
    return { X = x, Y = y }
end
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local motion = dofile(root .. "/src/bridge/presentation/motion.lua")(fields)({}, {}, {
    vector = Vector,
    status = function()
        return {}
    end,
    timeline = {
        observe = function(source)
            return source / 1000
        end,
        reset = function() end,
    },
})
local cases = {}
local input = assert(io.open(root .. "/tests/fixtures/npc_motion.csv"))
input:read("*l")
for line in input:lines() do
    local name, tick, x, y, vx, vy = line:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
    cases[name] = cases[name] or {}
    local rows = cases[name]
    rows[#rows + 1] = {
        t = tonumber(tick),
        p = Vector(tonumber(x), tonumber(y)),
        v = Vector(tonumber(vx), tonumber(vy)),
    }
end
input:close()

local function distance(a, b)
    return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
end
local function replay(rows, npc, gap)
    motion.reset()
    local track, last, error, brakingError, brakingUntil = nil, -1, 0, 0, 0
    for frame = 0, (#rows - 2) * 2 do
        local now = frame / 60
        local index = math.floor((now - 0.04) * 30 + 0.000001)
        index = index - index % gap
        if index >= 0 then
            if index ~= last then
                local row = rows[index + 1]
                motion.observe(index * 1000 / 30, now)
                track = motion.track(track, row.p, row.v, now, row.t, 30, npc)
                last = index
            end
            local actual = motion.sample(track, now)
            local index = math.floor(frame / 2) + 1
            local a, b = rows[index], rows[index + 1]
            local blend = frame % 2 / 2
            local truth = Vector(a.p.X + (b.p.X - a.p.X) * blend, a.p.Y + (b.p.Y - a.p.Y) * blend)
            local e = distance(actual, truth)
            error = error + e
            if distance(b.v, Vector(0, 0)) < distance(a.v, Vector(0, 0)) * 0.85 then
                brakingUntil = frame + 6
            end
            if frame <= brakingUntil then
                brakingError = brakingError + e
            end
        end
    end
    return error, brakingError
end
-- Two native J460 runs: burst/brake spider, charger and turning attack fly.
-- Replay identical observations at 80 ms RTT, also merging alternate packets.
for name, rows in pairs(cases) do
    assert(#rows >= 200)
    for _, gap in ipairs({ 1, 2 }) do
        local linear, linearBrake = replay(rows, false, gap)
        local adaptive, adaptiveBrake = replay(rows, true, gap)
        if name:match("^spider") then
            -- This policy can only improve observed braking. Unseen burst starts
            -- and direction changes still contribute to the whole-path error.
            assert(adaptive < linear * 0.95, "Spider display still overran its native braking path")
            assert(adaptiveBrake < linearBrake * 0.85, "Braking correction retained excess travel")
        else
            assert(adaptive < linear * 1.02, "Steering/charging acquired extra display lag")
        end
        print(
            string.format(
                "%s gap=%d error %.2f -> %.2f brake %.2f -> %.2f",
                name,
                gap,
                linear,
                adaptive,
                linearBrake,
                adaptiveBrake
            )
        )
    end
end

motion.reset()
local track = motion.track(nil, Vector(0, 0), Vector(9, 0), 0, 0, 30, true)
track = motion.track(track, Vector(3.6, 0), Vector(5.4, 0), 1 / 30, 1, 30, true)
local before = motion.sample(track, 0.06)
assert(motion.track(track, Vector(3.6, 0), Vector(5.4, 0), 0.06, 1, 30, true) == track)
assert(distance(before, motion.sample(track, 0.06)) == 0, "Repeated packet restarted braking")
assert(
    distance(motion.sample(track, 1), motion.sample(track, 10)) < 0.001,
    "Stalled NPC drifted indefinitely"
)
track = motion.track(track, Vector(10, 0), Vector(-9, 0), 1, 2, 30, true)
assert(motion.sample(track, 1.05).X < motion.sample(track, 1).X, "Reversal retained old braking")
track = motion.track(track, Vector(600, 400), Vector(0, 0), 2, 3, 30, true)
assert(
    distance(motion.sample(track, 2), Vector(600, 400)) < 0.001,
    "Teleport swept an old trajectory"
)
motion.reset()
track = motion.track(nil, Vector(20, 30), Vector(3, 0), 3, 0, 30, true)
assert(
    distance(motion.sample(track, 3.05), Vector(24.5, 30)) < 0.001,
    "New identity inherited braking"
)
print("PASS native NPC braking, skipped/repeated states, stalls, reversals and view reset")
