local root = assert(arg[1])
local time, draws = 0, 0
local doors = dofile(root .. "/src/bridge/presentation/doors.lua")({
    doorVariants = { DOOR_LOCKED = 1, DOOR_LOCKED_DOUBLE = 2 },
    gridTypes = { GRID_STAIRS = 18 },
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
doors.render()
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
assert(doors.alpha() == 0 and draws == 2, "Pause/floor/session reset leaked a transition")
doors.begin()
time = 1200
doors.arrive()
time = 1700
assert(doors.alpha() == 1 and doors.movementBlocked(), "Room loading consumed the unseen reveal")
assert(doors.filterInput(input) == filtered, "Loading released the arrival input hold")
doors.render()
time = 1760
assert(math.abs(doors.alpha() - 0.5) < 0.001, "Reveal did not begin on its first actual draw")
time = 1830
assert(doors.alpha() == 0 and not doors.movementBlocked())
doors.reset()
print("PASS local door departure, confirmed arrival, cancellation, rejection and reset")

local function point(x, y)
    return { X = x, Y = y }
end
local door = { Position = point(100, 0), open = false, variant = 1 }
function door:IsOpen()
    return self.open
end
function door:IsLocked()
    return true
end
function door:GetVariant()
    return self.variant
end
local player = { keys = 1, golden = false }
function player:GetNumKeys()
    return self.keys
end
function player:HasGoldenKey()
    return self.golden
end
local stair, hasDoor = nil, true
local room = {
    GetDoor = function(_, slot)
        return hasDoor and slot == 2 and door or nil
    end,
    IsClear = function()
        return true
    end,
    GetGridEntityFromPos = function()
        return stair
    end,
}
time = 2000
assert(doors.preview(room, player, point(60, 0), point(1, 0)) == 2)
assert(
    player.keys == 1 and not door.open and doors.alpha() == 0,
    "Approach preview spent a key, changed the native door or hid a rejected entry"
)
time = 2100
doors.preview(room, player, point(0, 0), point(1, 0), {})
time = 2251
assert(doors.preview(room, player, point(80, 0), point(1, 0)) == nil)
time = 2300
assert(
    doors.preview(room, player, point(80, 0), point(1, 0)) == nil,
    "Held denial restarted preview"
)
doors.preview(room, player, point(60, 0), point(-1, 0))
assert(doors.preview(room, player, point(60, 0), point(1, 0)) == 2)
doors.reset()
player.keys = 0
assert(doors.preview(room, player, point(60, 0), point(1, 0)) == nil)
player.keys, door.variant = 1, 2
assert(doors.preview(room, player, point(60, 0), point(1, 0)) == nil)
player.keys = 2
assert(doors.preview(room, player, point(60, 0), point(1, 0)) == 2)
doors.reset()
player.keys, player.golden = 0, true
assert(doors.preview(room, player, point(60, 0), point(1, 0)) == 2)
door.variant = 5
assert(
    doors.preview(room, player, point(60, 0), point(1, 0)) == nil,
    "Key preview bypassed a different lock"
)
hasDoor = false
stair = {
    Position = point(100, 0),
    GetType = function()
        return 18
    end,
}
doors.preview(room, player, point(76, 0), point(1, 0))
time = 2345
assert(math.abs(doors.alpha() - 0.5) < 0.001, "Crawlspace approach omitted its departure")
doors.preview(room, player, point(106, 0), point(1, 0))
assert(math.abs(doors.alpha() - 0.5) < 0.001, "Crossing the entrance cancelled its preview")
doors.preview(room, player, point(0, 0), point(-1, 0), {})
assert(math.abs(doors.alpha() - 0.5) < 0.001, "A second controlled body cancelled the entrance")
doors.arrive()
assert(doors.movementBlocked())
doors.reset()
doors.preview(room, player, point(76, 0), point(1, 0))
time = 2370
doors.preview(room, player, point(76, 0), point(-1, 0))
assert(not doors.movementBlocked(), "Turning away from stairs acquired an arrival lock")
time = 2600
assert(doors.alpha() == 0)
print("PASS key affordability, bounded denial, retry, stairs and cancellation")
