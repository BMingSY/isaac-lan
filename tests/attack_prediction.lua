local root = assert(arg[1])
local function module(name)
    return dofile(root .. "/src/bridge/" .. name .. ".lua")
end
local fields = module("sync/fields")
local weapons = { WEAPON_TEARS = 1, WEAPON_BRIMSTONE = 2, WEAPON_KNIFE = 4, WEAPON_TECH_X = 9 }
local policy = module("compat/items/attack_preview")(weapons, {}, fields, {}, {}, {})
local prediction = module("presentation/attack_prediction")(policy)
local pose = module("sync/weapon_pose")
local function snapshot(kind, delay, maximum, charge, chargeLimit)
    return {
        [2] = {
            kind = kind,
            delay = delay,
            maximum = maximum,
            charge = charge,
            chargeLimit = chargeLimit or maximum * (({ [2] = 1, [4] = 4, [9] = 3 })[kind] or 0),
        },
    }
end
local function close(a, b)
    assert(math.abs(a - b) < 0.00001, a .. " ~= " .. b)
end
local shots = 0
local function shot()
    shots = shots + 1
end
local normal = prediction.new(snapshot(1, -1, 10, 0), 0, 0)
normal:step(1, 1 / 60, true, true, shot)
assert(shots == 1, "The first ready shot waited for a host snapshot")
normal:step(2, 1 / 60, false, true, shot)
normal:step(3, 1 / 60, true, true, shot)
assert(shots == 1, "A rapid release/press bypassed the weapon cooldown")
normal:confirm(snapshot(1, 10, 10, 0), 1, 1)
normal:step(4, 1 / 60, true, true, shot)
assert(shots == 1, "Replaying unacknowledged input emitted another shot")
assert(
    not normal:confirm(snapshot(1, -1, 10, 0), 0, 2),
    "Old input acknowledgement rewound the clock"
)
normal:step(5, 0.05, true, false, shot)
assert(shots == 1, "An unsupported tear combination emitted a preview")

-- Number One's native cooldown retains a fractional remainder between shots;
-- an integer maximum can also inherit a fraction after removing that item.
for _, case in ipairs({
    { delay = 5.6946620941162, maximum = 5.6946620941162, ticks = { 6, 13, 20, 26, 33 } },
    { delay = 9.8932418823242, maximum = 10, ticks = { 10, 21, 32, 43, 54 } },
}) do
    local model = prediction.new(snapshot(1, case.delay, case.maximum, 0), 0, 0)
    local times = {}
    for half = 1, case.ticks[#case.ticks] * 2 do
        model:step(half, 1 / 60, true, true, function()
            times[#times + 1] = half / 2
        end)
        -- Keep the history bounded while retaining the observed countdown.
        if half % 2 == 0 then
            model:confirm(model.weapons, half, half / 2)
        end
    end
    assert(#times == #case.ticks)
    for index, tick in ipairs(case.ticks) do
        close(times[index], tick)
    end
end
local unknown = prediction.new(snapshot(1, -1, 10, 0), 0, 0)
unknown:step(1, 1 / 60, true, false)
unknown:step(2, 1 / 60, true, true, function()
    error("Learning an appearance restarted an already running firing cycle")
end)

-- Native measured caps: Brimstone 32, knife 4 * 10, Tech X 3 * 10.
for _, case in ipairs({ { 2, 32, 32 }, { 4, 10, 40 }, { 9, 10, 30 } }) do
    local model = prediction.new(snapshot(case[1], -1, case[2], 0), 0, 0)
    close(model:step(1, 1 / 60, true, false)[2].charge, 0.5)
    close(model:step(2, 1 / 60, true, false)[2].charge, 1)
    model:confirm(snapshot(case[1], -1, case[2], 1), 1, 1)
    close(model:step(3, 1 / 60, true, false)[2].charge, 2)
    model:confirm(snapshot(case[1], -1, case[2], case[3] - 0.5), 3, 2)
    close(model:step(4, 0.05, true, false)[2].charge, case[3])
    close(model:step(5, 1 / 60, false, false)[2].charge, 0)
    -- A delayed packet containing the pre-release charge cannot refill the UI.
    model:confirm(snapshot(case[1], -1, case[2], case[3]), 4, 3)
    close(model.weapons[2].charge, 0)
    close(model:step(6, 1 / 60, true, false)[2].charge, 0.5)
end
local stalled = prediction.new(snapshot(1, -1, 0, 0), 0, 0)
-- Extreme native combinations can expose a negative, read-only charge limit.
-- Preserve authority's charge without inventing a prediction or rejecting it.
for _, limit in ipairs({ -1, -1000, 0 }) do
    local state = snapshot(2, -1, 10, 4, limit)
    assert(not policy.mode(state[2]).charge)
    local model = prediction.new(state, 0, 0)
    close(model:step(1, 1 / 60, true, false)[2].charge, 4)
end
-- Character/item modifiers can change charging independently of fire delay.
local modified = prediction.new(snapshot(2, -1, 10, 35, 40), 0, 0)
close(modified:step(1, 1 / 60, true, false)[2].charge, 35.5)
modified:confirm(snapshot(2, -1, 10, 45, 40), 1, 1)
close(modified:step(2, 1 / 60, true, false)[2].charge, 45)
for sequence = 1, 5 do
    stalled:step(sequence, 0.05, true, true)
end
assert(stalled:step(6, 0.05, true, true) == nil, "A stalled connection kept inventing attacks")

local opaque = "costume and native layer bytes\0\255"
local bytes = string.pack(
    ">BBI4I4fBBI4ffffI4BBB",
    1,
    0,
    9,
    12,
    45,
    0,
    1,
    2,
    -1,
    32,
    4,
    128,
    1,
    0,
    0,
    0
) .. opaque
local decoded = pose.read(bytes)
close(decoded[2].charge, 4)
decoded[2].charge, decoded[2].delay = 7, 123
local displayed = pose.display(bytes, decoded)
close(pose.read(displayed)[2].charge, 7)
close(pose.read(displayed)[2].delay, -1)
assert(displayed:sub(-#opaque) == opaque and #displayed == #bytes)
assert(pose.display(bytes, {}) == bytes)
assert(pose.display(bytes, snapshot(4, 0, 10, 9)) == bytes, "A different weapon changed charge")
print(
    "PASS immediate shooting, cooldown, acknowledgement replay, charge caps/release, stall and pose contract"
)
