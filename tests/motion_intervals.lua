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
    timeline = dofile(root .. "/src/bridge/presentation/timeline.lua")(),
    clock = function()
        return now * 1000
    end,
    status = function()
        return { pause = pause, slot = 1, ping1 = 90 }
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

-- Item actions can report unfinished extra animations without blocking walking.
-- Exercise the production presentation path without any item-specific adapter.
function vector:LengthSquared()
    return self.X * self.X + self.Y * self.Y
end
local prediction = assert(loadfile(root .. "/src/bridge/presentation/prediction.lua", "t", {
    Vector = Vector,
    setmetatable = setmetatable,
    math = math,
    pairs = pairs,
    ipairs = ipairs,
    table = table,
}))()
local animation, extraFinished, enabled, ghost = "PickupWalkRight", false, true, false
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
local collision = {
    COLLISION_NONE = 0,
    COLLISION_PIT = 1,
    COLLISION_OBJECT = 2,
    COLLISION_SOLID = 3,
    COLLISION_WALL_EXCEPT_PLAYER = 5,
    COLLISION_WALL = 4,
}
local actor =
    { 1, 2, { 1 }, {}, { { "body", "LiftItem" } }, false, false, { string.rep("\0", 12), true } }
local localMotion = assert(
    loadfile(
        root .. "/src/bridge/presentation/motion.lua",
        "t",
        setmetatable({ GridCollisionClass = collision }, { __index = _G })
    )
)()(dofile(root .. "/src/bridge/sync/fields.lua"))({
    rooms_with_player = function(_, fn)
        fn()
        return true
    end,
}, { apply = function() end }, {
    vector = Vector,
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
close(localRender(1), previous, "Native first half tick integrates the resting velocity")
assert(localState.prediction.velocity.X > 0, "Held bag blocked local acceleration")
for sequence = 2, 30 do
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
-- Every native split item pose keeps walking, independent of inventory and
-- item state. Unknown/full-body poses and explicit control locks stay blocked.
local sequence = 90
actor[8] = false
for _, extra in ipairs({ "Pickup", "UseItem", "LiftItem", "HideItem", "" }) do
    for _, body in ipairs(extra == "" and { "Happy", "Sad" } or { "WalkRight", "PickupWalkRight" }) do
        animation, actor[5][1][2], extraFinished = body, extra, false
        sequence = sequence + 1
        local position = localRender(sequence)
        assert(position > previous, extra .. "/" .. body .. " froze pending movement")
        assert(localState.prediction.acknowledged == -1, "Action fabricated an acknowledgement")
        previous = position
    end
end
local lockedPosition = previous
for _, blocked in ipairs({
    "craft",
    "pickup",
    "death",
    "trapdoor",
    "cooldown",
    "disabled",
    "ghost",
    "absent",
    "unknown",
}) do
    animation = blocked == "craft" and "UseItem"
        or blocked == "pickup" and "Pickup"
        or blocked == "death" and "Death"
        or blocked == "trapdoor" and "Trapdoor"
        or "PickupWalkRight"
    actor[5][1][2] = blocked == "unknown" and "UnknownAction"
        or blocked == "absent" and ""
        or "LiftItem"
    enabled, player.ControlsEnabled, ghost =
        blocked ~= "cooldown", blocked ~= "disabled", blocked == "ghost"
    sequence = sequence + 1
    close(localRender(sequence), lockedPosition, blocked .. " incorrectly predicted movement")
end
extraFinished, enabled, player.ControlsEnabled, ghost = true, true, true, false
animation = "WalkRight"
localRender(sequence + 1)
assert(localState.prediction.velocity.X > 0, "Ordinary acceleration did not resume")
assert(localRender(sequence + 2) > lockedPosition, "Ordinary movement did not resume")
print("PASS pickup/use/raise/lower/pill motion, control locks, gaps, pause and reset")

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

-- A pickup/use animation can arrive while several local inputs are still in
-- flight. The lock must not turn those inputs into host acknowledgements or
-- snap the view back to the older received position.
extraFinished, enabled, player.ControlsEnabled = true, true, true
actor[8] = false
localState.target, localState.display = Vector(100, 100), Vector(100, 100)
localState.prediction = prediction.new(localState.target)
localState.prediction:confirm(localState.target, 0)
localMotion.reset()
for sequence = 0, 8 do
    localRender(sequence)
end
local beforeLock = player.Position.X
assert(beforeLock > 110, "Fixture did not build unacknowledged movement")
extraFinished = false
actor[5][1][2] = "Pickup"
animation = "Pickup"
close(localRender(9), beforeLock, "Pickup snapped to the delayed host position")
assert(localState.prediction.acknowledged == 0, "Animation acknowledged unsent input")
localState.prediction:confirm(Vector(100, 100), 3)
local duringLock = localRender(10)
assert(duringLock < beforeLock and duringLock > 100, "Locked motion ignored or snapped correction")
assert(localState.prediction.acknowledged == 3, "Delayed acknowledgement was discarded")
assert(localState.prediction.velocity:LengthSquared() == 0, "Control lock retained movement")
localState.prediction:confirm(Vector(100, 100), 10)
local previousLocked = duringLock
for sequence = 11, 50 do
    localState.prediction:confirm(Vector(100, 100), 10)
    local position = localRender(sequence)
    assert(
        position <= previousLocked and position >= 100,
        "Repeated locked state restarted correction"
    )
    assert(localState.prediction.acknowledged == 10, "Repeated lock consumed pending input")
    previousLocked = position
end
assert(previousLocked - 100 < 0.001, "Locked position did not settle at the host position")
extraFinished = true
animation = "WalkRight"
localRender(51)
assert(localState.prediction.velocity.X > 0, "Movement waited for another host packet")
print("PASS action locks retain pending inputs, reconcile delayed state and resume locally")

-- Flying crosses pits/rocks but never a solid wall. Check the whole render
-- path, including repeated blocked frames and resuming after the obstacle.
local obstacle = collision.COLLISION_WALL
room.GetGridCollisionAtPos = function(_, p)
    return p.X >= 120 and obstacle or collision.COLLISION_NONE
end
player.CanFly = true
localState.target, localState.display = Vector(100, 100), Vector(100, 100)
localState.prediction = prediction.new(localState.target)
localMotion.reset()
for s = 0, 40 do
    assert(localRender(s) < 120, "Flying prediction crossed a solid wall")
end
for _, kind in ipairs({
    collision.COLLISION_PIT,
    collision.COLLISION_OBJECT,
    collision.COLLISION_SOLID,
}) do
    obstacle = kind
    localState.target, localState.display = Vector(100, 100), Vector(100, 100)
    localState.prediction = prediction.new(localState.target)
    localMotion.reset()
    for s = 0, 40 do
        localRender(s)
    end
    assert(player.Position.X > 120, "Flying prediction stopped at a flyable grid")
end
room.GetGridCollisionAtPos = function()
    return collision.COLLISION_NONE
end

-- Native movement queries return the same input for the tainted skeleton
-- Co-op ghosts retain CanFly=false in J460 but traverse pits and rocks.
local wasGhost = player.IsCoopGhost
player.IsCoopGhost = function()
    return true
end
player.CanFly = false
room.GetGridCollisionAtPos = function(_, p)
    return p.X >= 120 and collision.COLLISION_PIT or collision.COLLISION_NONE
end
localState.target, localState.display = Vector(100, 100), Vector(100, 100)
localState.prediction = prediction.new(localState.target)
localMotion.reset()
for s = 0, 40 do
    localRender(s)
end
assert(player.Position.X > 120, "Ghost was clipped as a grounded living actor")
player.IsCoopGhost = wasGhost
room.GetGridCollisionAtPos = function()
    return collision.COLLISION_NONE
end

-- Native movement queries return the same input for the tainted skeleton
-- and soul, despite only the soul walking. Carrying/throwing still comes
-- from authority. Dungeon gravity/ladders never use top-down walking.
local types = dofile(root .. "/tests/fixtures/game_enums.lua").PlayerType
local forgotten = dofile(root .. "/src/bridge/compat/characters/forgotten.lua")(types)
local dungeonType, roomType, kind = 16, 1, types.PLAYER_ISAAC
local crawlspace = dofile(root .. "/src/bridge/compat/routes/crawlspace.lua")(nil, nil, dungeonType)
player.GetPlayerType = function()
    return kind
end
room.GetType = function()
    return roomType
end
local special = assert(
    loadfile(
        root .. "/src/bridge/presentation/motion.lua",
        "t",
        setmetatable({ GridCollisionClass = collision }, { __index = _G })
    )
)()(dofile(root .. "/src/bridge/sync/fields.lua"))({
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
        return { pause = 0, slot = 1 }
    end,
    room = function()
        return room
    end,
    predictMovement = function(p, r)
        return forgotten.predictMovement(p) and crawlspace.predictMovement(r)
    end,
})
localState.velocity, localState.target = Vector(0, 0), Vector(100, 100)
localState.display = localState.target
localState.prediction = prediction.new(localState.target)
localState.prediction:confirm(localState.target, 0)
localState.track = special.track(nil, localState.target, localState.velocity, 0, 1, 60)
local function specialRender(s)
    now = s / 60
    special.present("", s, {}, { [1] = localState }, function()
        return player
    end, 1)
end
for s = 0, 10 do
    specialRender(s)
end
assert(player.Position.X > 100)
kind = types.PLAYER_THEFORGOTTEN_B
for s = 11, 30 do
    specialRender(s)
    close(player.Position.X, 100, "Tainted skeleton followed its soul's input")
    assert(not next(localState.prediction.pending), "Inactive body kept walking input")
    assert(localState.prediction.acknowledged == 0, "Inactive body fabricated an acknowledgement")
end
-- A thrown skeleton follows its host velocity even while direction is held.
localState.velocity = Vector(-2, 0)
localState.track = special.track(nil, localState.target, localState.velocity, now, 2, 60)
specialRender(31)
close(player.Position.X, 98, "Thrown skeleton lost authoritative movement")
kind, roomType = types.PLAYER_ISAAC, dungeonType
localState.velocity = Vector(0, 0)
localState.track = special.track(nil, localState.target, localState.velocity, now, 3, 60)
for s = 32, 40 do
    specialRender(s)
    close(player.Position.X, 100, "Dungeon used ordinary walking prediction")
end
roomType = 1
specialRender(41)
assert(
    localState.prediction.velocity.X > 0,
    "Walking acceleration did not resume after the dungeon"
)
specialRender(42)
assert(player.Position.X > 100, "Walking did not resume after leaving the dungeon")
kind = types.PLAYER_THESOUL_B
assert(forgotten.predictMovement(player), "Tainted soul lost local walking prediction")
kind = types.PLAYER_THEFORGOTTEN
assert(forgotten.predictMovement(player), "Ordinary Forgotten lost local walking prediction")
print("PASS flying walls, flyable grids, tainted body authority, dungeon and form transitions")

-- A narrow obstacle lies between the start and the high-speed endpoint.
-- Radius-aware swept movement must stop before its near edge and slide.
kind, roomType = types.PLAYER_ISAAC, 1
player.CanFly, player.MoveSpeed = false, 50
room.GetGridCollisionAtPos = function(_, position)
    return position.X >= 120 and position.X < 160 and collision.COLLISION_WALL
        or collision.COLLISION_NONE
end
localState.target, localState.display = Vector(100, 100), Vector(100, 100)
localState.prediction = prediction.new(localState.target)
localMotion.reset()
for s = 0, 10 do
    assert(localRender(s) <= 110, "High-speed prediction crossed a grid or ignored body radius")
end
player.GetMovementInput = function()
    return Vector(0.6, 0.8)
end
for s = 11, 20 do
    localRender(s)
    assert(player.Position.X <= 110, "Diagonal slide entered a blocked grid")
end
assert(player.Position.Y > 110, "Collision prevented sliding along the wall")
localState.prediction:confirm(Vector(200, 100), 20, Vector(0, 0), 300)
localRender(21)
assert(player.Position.X >= 200, "Authoritative teleport was swept through the old obstacle")
print("PASS high-speed swept collision, body radius and diagonal wall sliding")
-- Native arrival can put the old display inside the conservative footprint.
-- The host then walks away in small steps, never producing a teleport-sized
-- authority delta. Corrections must escape instead of clipping back forever.
player.MoveSpeed = 1
player.GetMovementInput = function()
    return Vector(1, 0)
end
localState.target, localState.display = Vector(180, 100), Vector(155, 100)
localState.prediction = prediction.new(localState.display)
localState.prediction:confirm(localState.target, 0, Vector(0, 0), 1)
localMotion.reset()
localRender(1)
assert(player.Position.X >= 170, "Authority correction remained trapped in an invalid origin")
local recovered = player.Position.X
for s = 2, 10 do
    localRender(s)
end
assert(player.Position.X > recovered, "Walking did not resume after recovering from a wall")
print("PASS authority recovery from an overlapping display footprint")
-- Receipt jitter must not restart a remote projectile's simulation clock.
motion.reset(true)
state, pause = {}, 0
motion.observe(1000, 20.045)
accept(20.045, 1, 0, 100)
close(render(20.045), 4.5, "Network travel time omitted from presentation")
motion.observe(1033, 20.095)
accept(20.095, 2, 3.3, 100)
close(render(20.095), 9.5, "Receipt jitter changed the authority timeline")
close(render(20.3), 13.3, "Old views extrapolated past the bounded horizon")
print("PASS shared capture clock and bounded projectile extrapolation")
