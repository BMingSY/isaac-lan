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
local input = string.rep(string.pack(">I2", 65535), 17)
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
for action = 0, 15 do
    assert(string.unpack(">I2", filtered, action * 2 + 1) == (action < 4 and 0 or 65535))
end
assert(string.unpack(">I2", filtered, 33) == 0xfff0, "Arrival changed fire or menu edges")
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
