local root = assert(arg[1])
local vector = {}
vector.__index = vector
local allocations = 0
local function Vector(x, y)
    allocations = allocations + 1
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
local motion = dofile(root .. "/src/bridge/presentation/motion.lua")(
    dofile(root .. "/src/bridge/sync/fields.lua")
)({
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
-- Stationary snapshots preserve position without allocating render vectors;
-- starting movement clears the fast path and keeps normal extrapolation.
local still = state.track
assert(still.stationary and motion.sample(still, 7) == still.target)
accept(7, 1, 20, 0)
assert(state.track == still and state.track.stationary)
accept(8, 2, 20, 60)
assert(not state.track.stationary)
close(render(8 + 1 / 60), 21)

-- Preserve diagonal movement and per-tick velocity units without allocating
-- intermediate native Vector values for every moving entity and render.
local position, velocity = Vector(10, 20), Vector(2, -3)
local allocated = allocations
local diagonal = motion.track(nil, position, velocity, 0, 1, 30)
assert(allocations == allocated)
local displayed = motion.sample(diagonal, 1 / 30)
assert(allocations == allocated + 1)
close(displayed.X, 12)
close(displayed.Y, 17)
allocated = allocations
assert(motion.track(diagonal, position, velocity, 1 / 30, 2, 30) == diagonal)
assert(allocations == allocated)
displayed = motion.sample(diagonal, 1 / 30)
close(displayed.X, 12)
close(displayed.Y, 17)

-- Exercise local prediction with the actual item compatibility adapter. A held
-- crafting bag reports an unfinished extra animation throughout PickupWalk.
function vector:LengthSquared()
    return self.X * self.X + self.Y * self.Y
end
local prediction = assert(loadfile(root .. "/src/bridge/presentation/prediction.lua", "t", {
    Vector = Vector,
    setmetatable = setmetatable,
    math = math,
    pairs = pairs,
}))()
local bag = dofile(root .. "/src/bridge/compat/items/crafting_bag.lua")({}, {
    COLLECTIBLE_BAG_OF_CRAFTING = 710,
})
local animation, heldItem, extraFinished, enabled, ghost =
    "PickupWalkRight", 710, false, true, false
local player = { ControlsEnabled = true, MoveSpeed = 1, Size = 10, ControllerIndex = 2 }
function player:ToPlayer()
    return self
end
function player:GetMovementInput()
    return Vector(1, 0)
end
function player:AreControlsEnabled()
    return enabled
end
function player:IsExtraAnimationFinished()
    return extraFinished
end
function player:IsCoopGhost()
    return ghost
end
function player:GetActiveItem(slot)
    return slot == 2 and heldItem or 0
end
function player:GetSprite()
    return {
        GetAnimation = function()
            return animation
        end,
    }
end
local room = {
    IsMirrorWorld = function()
        return false
    end,
    GetDoor = function() end,
    GetClampedPosition = function(_, position)
        return position
    end,
    GetGridCollisionAtPos = function()
        return 0
    end,
}
local actor =
    { 1, 2, { 1 }, {}, { { "body", "LiftItem" } }, false, false, { string.rep("\0", 12), true } }
local localMotion = assert(
    loadfile(
        root .. "/src/bridge/presentation/motion.lua",
        "t",
        setmetatable({ GridCollisionClass = { COLLISION_NONE = 0 } }, { __index = _G })
    )
)()(dofile(root .. "/src/bridge/sync/fields.lua"))({
    rooms_with_player = function(_, fn)
        fn()
        return true
    end,
}, { apply = function() end }, {
    vector = Vector,
    extraAnimationAllowsMovement = function(p, value)
        return bag.allowsMovement(p, value[8], value[5][1] and value[5][1][2])
    end,
    player = function()
        return player
    end,
    clock = function()
        return now * 1000
    end,
    status = function()
        return { pause = 0, slot = 1 }
    end,
    room = function()
        return room
    end,
})
local localState = {
    actor = true,
    controller = 2,
    target = Vector(100, 100),
    display = Vector(100, 100),
    prediction = prediction.new(Vector(100, 100)),
}
local function localRender(sequence)
    now = sequence / 60
    localMotion.present(
        string.pack(">I2I2I2I2", 0, 65535, 0, 0),
        sequence,
        { actor },
        { [1] = localState },
        function()
            return player
        end,
        1
    )
    return player.Position.X
end
local previous = localRender(0)
for sequence = 1, 30 do
    local position = localRender(sequence)
    assert(position > previous, "Held bag froze local motion between snapshots")
    previous = position
end
-- The item-state bit arrives with the same snapshot as the extra-animation
-- flag, while the body can still report Walk for several renders. Exercise
-- repeated raise/lower transitions with continuous movement, not just holding.
for sequence = 31, 90 do
    local phase = (sequence - 31) % 20
    animation = phase < 3 and "WalkRight" or phase < 12 and "PickupWalkRight" or "WalkRight"
    actor[5][1][2] = phase < 8 and "LiftItem" or phase < 18 and "HideItem" or ""
    actor[8][2], extraFinished = phase < 8, phase >= 18
    local position = localRender(sequence)
    assert(position > previous, "Raising/lowering the bag reset movement prediction")
    previous = position
end
-- The exception never enables controls during crafting, pickup, cooldown,
-- ghost conversion, or after removing the bag. Ordinary walking still works.
extraFinished = false
for i, blocked in ipairs({
    "craft",
    "pickup",
    "cooldown",
    "disabled",
    "removed",
    "ghost",
    "unrelated",
    "absent",
    "stale_pose",
}) do
    animation = blocked == "craft" and "UseItem"
        or blocked == "pickup" and "Pickup"
        or (blocked == "unrelated" or blocked == "absent") and "WalkRight"
        or "PickupWalkRight"
    actor[8] = blocked ~= "absent" and { string.rep("\0", 12), blocked ~= "unrelated" }
    actor[5][1][2] = (blocked == "craft" or blocked == "stale_pose") and "UseItem"
        or blocked == "pickup" and "Pickup"
        or "LiftItem"
    enabled, player.ControlsEnabled = blocked ~= "cooldown", blocked ~= "disabled"
    heldItem, ghost = blocked == "removed" and 0 or 710, blocked == "ghost"
    close(localRender(90 + i), localState.target.X, blocked .. " incorrectly predicted movement")
end
extraFinished, enabled, player.ControlsEnabled, ghost = true, true, true, false
animation = "WalkRight"
assert(localRender(100) > localState.target.X, "Ordinary movement did not resume")
print("PASS continuous motion, raising/holding crafting bag, control locks, gaps, pause and reset")

-- Same-controller bodies must query independently. Native character rules can
-- leave a twin stationary, switch the active body, or mirror one local room.
local directions, queried, bodyStates, bodies = {}, {}, {}, {}
local inRoom = false
for id = 1, 2 do
    local body = setmetatable({ Position = Vector(100, id * 100) }, { __index = player })
    bodies[id] = body
    directions[id] = Vector(1, 0)
    body.GetMovementInput = function()
        assert(inRoom, "Movement was queried outside the local room")
        queried[id] = (queried[id] or 0) + 1
        return directions[id]
    end
    bodyStates[id] = {
        actor = true,
        controller = 2,
        target = body.Position,
        display = body.Position,
        prediction = prediction.new(body.Position),
    }
end
local pairedMotion = assert(
    loadfile(
        root .. "/src/bridge/presentation/motion.lua",
        "t",
        setmetatable({ GridCollisionClass = { COLLISION_NONE = 0 } }, { __index = _G })
    )
)()(dofile(root .. "/src/bridge/sync/fields.lua"))({
    rooms_with_player = function(slot, fn)
        assert(slot == 1 and not inRoom)
        inRoom = true
        fn()
        inRoom = false
        return true
    end,
}, {}, {
    vector = Vector,
    clock = function()
        return now * 1000
    end,
    status = function()
        return { pause = 0, slot = 1 }
    end,
    room = function()
        return room
    end,
})
local function pairedRender(sequence)
    now = sequence / 60
    pairedMotion.present(
        string.pack(">I2I2I2I2", 0, 65535, 0, 0),
        sequence,
        {},
        bodyStates,
        function(id)
            return bodies[id]
        end,
        1
    )
end
for sequence = 0, 20 do
    pairedRender(sequence)
end
assert(bodies[1].Position.X > 120 and bodies[2].Position.X > 120)
-- A drop-held twin receives zero despite the other body's continuing input.
directions[2] = Vector(0, 0)
for sequence = 21, 80 do
    pairedRender(sequence)
end
assert(bodyStates[1].prediction.velocity.X > 200)
assert(bodyStates[2].prediction.velocity.X < 0.2)
-- Switching bodies changes the source without retaining the old body's input.
directions[1], directions[2] = Vector(0, 0), Vector(-1, 0)
for sequence = 81, 140 do
    pairedRender(sequence)
end
assert(bodyStates[1].prediction.velocity.X < 0.2)
assert(bodyStates[2].prediction.velocity.X < -200)
assert(queried[1] == 141 and queried[2] == 141)
-- Removing a temporary body and resetting the view never queries the old actor.
bodyStates[2], bodies[2] = nil, nil
pairedMotion.reset()
pairedRender(141)
assert(queried[2] == 141)
print("PASS independent same-controller movement, form switch and companion cleanup")
