local root = assert(arg[1])
local time, draws = 0, 0
local doors = dofile(root .. "/src/bridge/presentation/doors.lua")({
    clock = function()
        return time
    end,
    vector = function(x, y)
        return { X = x, Y = y }
    end,
    color = function(...)
        return { ... }
    end,
    width = function()
        return 960
    end,
    height = function()
        return 540
    end,
    sprite = function()
        return {
            Load = function() end,
            SetFrame = function() end,
            Render = function(s)
                assert(s.Scale.X == 2 and s.Scale.Y == 2)
                assert(s.Color[4] > 0 and s.Color[4] <= 1)
                draws = draws + 1
            end,
        }
    end,
})
doors.arrive()
assert(doors.alpha() == 0, "Remote-room entry or teleport invented a local door preview")
local codec = dofile(root .. "/tests/support/input.lua")
local values = {}
for action = 0, codec.actionCount - 1 do
    values[action] = codec.maxValue
end
local input = codec.encode({
    values = values,
    triggered = 0xffff,
    pointer = { active = true, x = -123.25, y = 876.5 },
})
assert(not doors.movementBlocked() and doors.filterInput(input) == input)
doors.begin()
time = 45
assert(math.abs(doors.alpha() - 0.5) < 0.001)
assert(not doors.movementBlocked(), "Departure stopped the input needed to cross the door")
doors.render()
doors.begin()
time = 100
assert(doors.alpha() == 1, "Repeated doorway samples restarted departure")
doors.arrive()
assert(doors.movementBlocked(), "Arrival fade allowed invisible local movement")
local filtered = doors.filterInput(input)
assert(#filtered == #input, "Arrival truncated the native input frame")
local decoded = codec.decode(filtered)
for action = 0, 15 do
    assert(decoded.values[action] == (action < 4 and 0 or 65535))
end
assert(decoded.triggered == 0xfff0, "Arrival changed fire or menu edges")
assert(
    decoded.pointer.active and decoded.pointer.x == -123.25 and decoded.pointer.y == 876.5,
    "Arrival changed pointer input"
)
assert(
    doors.filterInput(input .. "extension") == filtered .. "extension",
    "Movement filtering discarded fields it does not own"
)
time = 160
assert(math.abs(doors.alpha() - 0.5) < 0.001)
time = 230
assert(doors.alpha() == 0)
assert(
    not doors.movementBlocked() and doors.filterInput(input) == input,
    "Arrival retained held input"
)
doors.begin()
time = 260
doors.cancel()
assert(not doors.movementBlocked(), "Turning back invented an arrival control lock")
time = 400
assert(doors.alpha() == 0, "Turning back left the view obscured")
doors.begin()
time = 1000
assert(doors.alpha() == 0, "Rejected doorway left the view obscured")
doors.begin()
time = 1100
doors.reset()
assert(doors.alpha() == 0 and draws == 1, "Pause/floor/session reset leaked a transition")
print("PASS local door departure, confirmed arrival, cancellation, rejection and reset")
