local root = assert(arg[1])
local create = dofile(root .. "/src/bridge/presentation/hit_candidates.lua")
local contact = dofile(root .. "/src/bridge/core/contacts.lua")
local function first(targets, shot, query)
    local id, time, order = nil, math.huge, math.huge
    local seen, visits = {}, 0
    local function visit(target)
        assert(not seen[target.id], "A multi-cell target was tested twice")
        seen[target.id], visits = true, visits + 1
        local t = contact(
            shot.oldX - target.oldX,
            shot.oldY - target.oldY,
            shot.x - target.x,
            shot.y - target.y,
            shot.radius + target.radius
        )
        if t and (t < time or (t == time and target.order < order)) then
            id, time, order = target.id, t, target.order
        end
    end
    if query then
        query(shot.x, shot.y, shot.oldX, shot.oldY, shot.radius, visit)
    else
        for _, target in ipairs(targets) do
            visit(target)
        end
    end
    return id, time, visits
end
local function compare(targets, shot)
    local expected, when = first(targets, shot)
    local query, second, direct = create(targets, 100), create(targets, 100), create(targets, 1)
    for _ = 1, 3 do
        local actual, at = first(targets, shot, query)
        assert(
            actual == expected and at == when,
            "Candidate filter changed the first swept contact"
        )
        actual, at = first(targets, shot, second)
        assert(actual == expected and at == when, "Queries shared deduplication state")
        actual, at = first(targets, shot, direct)
        assert(actual == expected and at == when, "Small-workload fallback changed contact")
    end
end
math.randomseed(460)
for _ = 1, 1000 do
    local targets = {}
    for id = 1, 50 do
        targets[id] = {
            id = id,
            order = id,
            x = math.random(-500, 500),
            y = math.random(-500, 500),
            oldX = math.random(-500, 500),
            oldY = math.random(-500, 500),
            radius = math.random(1, 100),
        }
    end
    compare(targets, {
        x = math.random(-500, 500),
        y = math.random(-500, 500),
        oldX = math.random(-500, 500),
        oldY = math.random(-500, 500),
        radius = math.random(1, 30),
    })
end
-- A moving enemy crosses a stationary tear; equal-time contacts retain order.
compare({
    { id = 1, order = 1, oldX = -5000, oldY = 0, x = 5000, y = 0, radius = 10 },
    { id = 2, order = 2, oldX = -5000, oldY = 0, x = 5000, y = 0, radius = 10 },
}, { x = 0, y = 0, oldX = 0, oldY = 0, radius = 5 })
compare(
    { { id = 1, order = 1, oldX = 0, oldY = 0, x = 0, y = 0, radius = 5000 } },
    { x = 10000, y = 0, oldX = -10000, oldY = 0, radius = 5 }
)
local far = {}
for id = 1, 50 do
    far[id] =
        { id = id, order = id, x = id * 10, y = 1000, oldX = id * 10, oldY = 1000, radius = 5 }
end
local query, visits = create(far, 200), 0
for id = 1, 200 do
    local _, _, count = first(far, { oldX = id, oldY = 0, x = id + 1, y = 0, radius = 5 }, query)
    visits = visits + count
end
assert(visits == 0, "Separated tears still test every target")
print(
    "PASS candidate equivalence, moving targets, ties, large sweeps, deduplication and 10000 rejected pairs"
)
