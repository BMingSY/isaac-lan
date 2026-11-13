local root = assert(arg[1])
local function module(name)
    return dofile(root .. "/src/bridge/" .. name .. ".lua")
end
local fields = module("sync/fields")
local A, E, R, I = fields.actor, fields.entity, fields.room, fields.inventory
local vector = {}
vector.__index = vector
local function Vector(x, y)
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
function vector:Dot(b)
    return self.X * b.X + self.Y * b.Y
end
function vector:LengthSquared()
    return self:Dot(self)
end
function vector:Normalized()
    return self * (1 / math.sqrt(self:LengthSquared()))
end
local draws, made, counters, poses = {}, 0, {}, {}
local function sprite()
    made = made + 1
    return {
        Load = function() end,
        SetFrame = function() end,
        Render = function(_, position)
            draws[#draws + 1] = position
        end,
    }
end
local head = { animation = "HeadDown" }
function head:GetOverlayAnimation()
    return self.animation
end
function head:SetOverlayFrame(name, frame)
    self.animation, self.frame = name, frame
end
local direction, enabled, passable, mirror, roomAvailable = Vector(1, 0), true, true, false, true
local player = {
    Damage = 3.5,
    ShotSpeed = 1,
    MaxFireDelay = 10,
    TearHeight = -23,
    TearRange = 260,
    TearFallingSpeed = 0,
    TearFallingAcceleration = 0,
    ControlsEnabled = true,
    ControlsCooldown = 0,
    Position = Vector(100, 100),
    Velocity = Vector(0, 0),
}
function player:ToPlayer()
    return self
end
function player:GetSprite()
    return head
end
function player:AreControlsEnabled()
    return enabled
end
function player:IsExtraAnimationFinished()
    return true
end
function player:IsCoopGhost()
    return false
end
function player:CanShoot()
    return true
end
function player:GetShootingInput()
    return direction
end
function player:GetTearMovementInheritance()
    error("Replica simulation caches cannot supply local launch inertia")
end
local native = {
    actor_pose = function(_, bytes)
        poses[#poses + 1] = bytes
        return true
    end,
    actor_sprites = function()
        return {}
    end,
    rooms_with_player = function(_, fn)
        fn()
        return true
    end,
}
local tearCount = 1
local policy = {
    mode = function(weapon)
        return { tears = weapon.kind == 1, charge = weapon.kind == 2 and 32 or nil }
    end,
    defaultTear = function()
        return true
    end,
    normalTear = function()
        return true
    end,
    tearCount = function()
        return tearCount
    end,
}
local attacks = module("presentation/attacks")(fields)({
    native = native,
    vector = Vector,
    sprite = sprite,
    screen = function(v)
        return v * 0.5 + Vector(20, 30)
    end,
    screenWidth = function()
        return 640
    end,
    player = function()
        return player
    end,
    encode = module("sync/codec").encode,
    applySprite = function() end,
    pose = module("sync/weapon_pose"),
    policy = policy,
    timeline = module("presentation/timeline")(),
    latency = function()
        return 0.04
    end,
    matching = module("presentation/attack_matching")(module("presentation/tear_motion")(Vector)),
    volley = module("presentation/attack_volley")(
        Vector,
        module("presentation/tear_motion")(Vector)
    ),
    prediction = module("presentation/attack_prediction")(policy),
    trajectory = module("presentation/tear_motion")(Vector),
    tearType = 2,
    tearVariants = { BLUE = 0, BLOOD = 1 },
    room = function()
        assert(roomAvailable, "An empty/retired view queried the native room")
        return {
            IsMirrorWorld = function()
                return mirror
            end,
            CheckLine = function()
                return passable
            end,
        }
    end,
    metrics = {
        counter = function(name, value)
            counters[name] = value
        end,
    },
})
local function weapon(kind, charge, maximum, delay)
    return string.pack(
        ">BBI4I4fBBI4ffffI4BBB",
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        kind or 1,
        delay or -1,
        maximum or 10,
        charge or 0,
        kind == 2 and 10 or 0,
        0,
        0,
        0,
        0
    )
end
local actor = {
    [A.index] = 0,
    [A.controller] = 2,
    [A.entity] = { [E.id] = 10 },
    [A.inventory] = { [I.items] = {}, [I.type] = 0 },
    [A.pose] = weapon(),
}
local entities = { [10] = player }
local motion = { [10] = { display = player.Position } }
local function ref(id)
    return entities[id]
end
local value = { slot = 1, actors = { actor }, room = { [R.entities] = {} } }
local status = { slot = 1, ping1 = 80 }
local function confirm(tick, ack, now)
    attacks.confirm(value, tick, ack, now, ref)
end
local function present(now, sequence)
    attacks.present(motion, ref, now, 1 / 60, sequence, status)
    draws = {}
    attacks.render()
end
confirm(0, 0, 0)
present(0, 1)
assert(#draws == 1 and head.animation == "HeadRight" and head.frame == 2)
assert(math.abs(draws[1].Y - 66.595) < 0.00001, "Tear altitude bypassed the room projection scale")
assert(counters["attack.pending"] == 1 and made == 1)
assert(next(entities, 10) == nil, "Drawing a shot allocated a game entity")
local tear = { Height = -23, Position = Vector(115, 100) }
function tear:ToTear()
    return self
end
entities[20], motion[20] = tear, { display = tear.Position }
value.room[R.entities] = {
    {
        [E.id] = 20,
        [E.type] = 2,
        [E.variant] = 0,
        [E.spawner] = 10,
        [E.frame] = 0,
        [E.velocity] = { 10, 0 },
        [E.sprite] = {},
    },
}
confirm(2, 1, 0.08)
present(0.08, 2)
assert(#draws == 0 and counters["attack.confirmed"] == 1)
assert(tear.Position.X > 130, "Confirmation snapped to the delayed spawn position")
local handedOff = tear.Position.X
confirm(2, 1, 0.08)
confirm(3, 2, 0.1)
motion[20].display = Vector(121, 100)
present(0.1, 3)
assert(counters["attack.confirmed"] == 1, "Repeated snapshots confirmed a shot twice")
assert(tear.Position.X - handedOff >= 4.5, "Handoff braked the tear below its launch speed budget")

local function fresh(kind, maximum)
    attacks.reset()
    actor[A.pose], value.room[R.entities] = weapon(kind, nil, maximum), {}
    confirm(0, 0, 0)
end
fresh()
present(0, 1)
enabled = false
present(0.02, 2)
assert(#draws == 0, "Disabling control left a speculative shot")
enabled = true
fresh()
present(0, 1)
player.Position = Vector(400, 100)
actor[A.pose] = weapon(nil, nil, 10, 10)
confirm(1, 1, 0.02)
present(0.02, 2)
assert(#draws == 0, "A same-room teleport retained a departure preview")
player.Position = Vector(100, 100)
fresh()
present(0, 1)
actor[A.pose] = weapon(2)
confirm(1, 0, 0.02)
present(0.02, 2)
assert(#draws == 0, "A weapon change retained an old tear")
direction = Vector(0, 0)
present(0.04, 3)
assert(module("sync/weapon_pose").read(poses[#poses])[2].charge == 0)
direction = Vector(1, 0)
fresh()
passable = false
present(0, 1)
assert(#draws == 0, "A preview crossed a solid grid")
passable = true
fresh()
present(0, 1)
present(0.2, 2)
assert(#draws == 0, "Unconfirmed preview outlived the RTT budget")
present(0.3, 3)
assert(counters["attack.pending"] == 0, "Stale authority retained predictions")
fresh()
present(0, 1)
local plainX = draws[1].X
mirror = true
draws = {}
attacks.render()
assert(draws[1].X == 640 - plainX, "Mirror preview was drawn across the room")
mirror = false
-- Walking across the aim direction bends the actual shot. Confirmation must
-- compare the full launch velocity, not reject it against the raw shoot key.
fresh()
player.Velocity = Vector(0, 5)
local beforeConfirmed = counters["attack.confirmed"]
present(0, 1)
value.room[R.entities] = {
    {
        [E.id] = 20,
        [E.type] = 2,
        [E.variant] = 0,
        [E.spawner] = 10,
        [E.frame] = 0,
        [E.velocity] = { 10, 6 },
        [E.sprite] = {},
    },
}
confirm(2, 1, 0.08)
present(0.08, 2)
assert(
    #draws == 0 and counters["attack.confirmed"] == beforeConfirmed + 1,
    "A moving player's inherited tear was abandoned in midair"
)
player.Velocity = Vector(0, 0)
-- The first shot was never observed (e.g. it hit between two delivered views).
-- The newer authority must consume the closest launch, not the first list entry.
fresh(nil, 1)
for frame = 0, 3 do
    present(frame / 60, frame + 1)
end
assert(counters["attack.pending"] == 2)
tear.Position, tear.Height = Vector(115, 104), -23
motion[20].display = tear.Position
value.room[R.entities] = {
    {
        [E.id] = 20,
        [E.type] = 2,
        [E.variant] = 0,
        [E.spawner] = 10,
        [E.frame] = 0,
        [E.position] = { 115, 104 },
        [E.velocity] = { 10, 0 },
        [E.sprite] = {},
    },
}
actor[A.pose] = weapon(nil, nil, 1, 1)
confirm(3, 4, 0.13)
present(0.13, 5)
assert(
    math.abs(tear.Position.X - 139) < 0.001 and tear.Position.Y == 104,
    "A newer authority tear consumed an older unmatched launch"
)
assert(#draws == 1 and math.abs((draws[1].X - 20) * 2 - 154) < 0.001)
-- Unrelated launches are not bridged across the room, even with matching aim.
fresh()
present(0, 1)
local matched = counters["attack.confirmed"]
value.room[R.entities] = {
    {
        [E.id] = 20,
        [E.type] = 2,
        [E.variant] = 0,
        [E.spawner] = 10,
        [E.frame] = 0,
        [E.position] = { 320, 220 },
        [E.velocity] = { 10, 0 },
        [E.sprite] = {},
    },
}
confirm(2, 1, 0.08)
present(0.08, 2)
assert(counters["attack.confirmed"] == matched, "Distant launch acquired a false handoff")
-- Learn a double volley before predicting it. Each authority consumes one preview.
tearCount = 2
fresh()
local other = { Height = -23, Position = Vector(115, 104), ToTear = tear.ToTear }
entities[21], motion[21] = other, { display = other.Position }
tear.Position, tear.Height = Vector(115, 96), -23
motion[20].display = tear.Position
value.room[R.entities] = {}
for index, y in ipairs({ 96, 104 }) do
    value.room[R.entities][index] = {
        [E.id] = 19 + index,
        [E.type] = 2,
        [E.variant] = 0,
        [E.spawner] = 10,
        [E.frame] = 0,
        [E.position] = { 115, y },
        [E.velocity] = { 10, 0 },
        [E.sprite] = {},
    }
end
confirm(1, 0, 0)
present(0, 1)
assert(#draws == 2, "A learned double volley did not emit two previews")
value.room[R.entities] = {}
for index, y in ipairs({ 96, 104 }) do
    local id = 29 + index
    entities[id] = { Height = -23, Position = Vector(115, y), ToTear = tear.ToTear }
    motion[id] = { display = entities[id].Position }
    value.room[R.entities][index] = {
        [E.id] = id,
        [E.type] = 2,
        [E.variant] = 0,
        [E.spawner] = 10,
        [E.frame] = 0,
        [E.position] = { 115, y },
        [E.velocity] = { 10, 0 },
        [E.sprite] = {},
    }
end
matched = counters["attack.confirmed"]
actor[A.pose] = weapon(nil, nil, 10, 10)
confirm(3, 1, 0.08)
present(0.08, 2)
assert(
    #draws == 0 and counters["attack.confirmed"] == matched + 2,
    "A double volley retained a ghost or consumed a launch twice"
)
-- A moving double volley learns from its authority birth pose, then rotates
-- the original aim rather than baking walking inertia into the learned spread.
fresh()
player.Velocity = Vector(0, 2)
confirm(1, 0, 0)
local volley =
    module("presentation/attack_volley")(Vector, module("presentation/tear_motion")(Vector))
local travel = Vector(10, 2.4)
local perpendicular = Vector(-2.4, 10):Normalized()
local movingShots = {}
value.room[R.entities] = {}
for index, eye in ipairs({ -4, 4 }) do
    local at = Vector(115, 103.6) + perpendicular * eye
    movingShots[index] = { position = at, velocity = travel, age = 0 }
    value.room[R.entities][index] = {
        [E.id] = 49 + index,
        [E.type] = 2,
        [E.variant] = 0,
        [E.spawner] = 10,
        [E.frame] = 0,
        [E.position] = { at.X, at.Y },
        [E.velocity] = { 10, 2.4 },
        [E.sprite] = {},
    }
end
assert(
    volley(movingShots, 2, player.Position, player.Velocity, 1) == nil,
    "A moving volley guessed its unobserved birth pose"
)
local learned = volley(
    movingShots,
    2,
    player.Position,
    player.Velocity,
    1,
    { position = Vector(100, 100), velocity = Vector(0, 2) }
)
assert(
    learned
        and math.abs(learned[1].along - 1) < 0.00001
        and math.abs(learned[1].across) < 0.00001
        and math.abs(learned[1].eye + 4) < 0.00001
        and math.abs(learned[2].eye - 4) < 0.00001,
    "Moving inertia changed the learned volley geometry"
)
confirm(2, 0, 0.03)
present(0.03, 1)
assert(#draws == 2, "Continuous walking prevented double-shot prediction")
player.Velocity = Vector(0, 0)
tearCount = 1
-- Missing early shots and jitter must not shift high-rate launches by one shot.
local trajectory = module("presentation/tear_motion")(Vector)
local match = module("presentation/attack_matching")(trajectory)
for _, rtt in ipairs({ 0, 80, 150 }) do
    for _, jitter in ipairs({ 0, 0.015, 0.03 }) do
        local timeline = module("presentation/timeline")()
        local oneWay = rtt / 2000
        timeline.observe(1000, 1 + oneWay, rtt)
        local born, age = 1.04, 1
        local captured = born + oneWay + age / 30
        local now = captured + oneWay + jitter
        local mapped = timeline.observe(captured * 1000, now, rtt)
        local shots = {}
        for index = 1, 3 do
            local at = 1 + (index - 1) * 0.04
            if at <= now then
                shots[#shots + 1] = {
                    owner = 10,
                    sequence = index,
                    at = at,
                    lifetime = 0.25,
                    origin = Vector(115, 100),
                    velocity = Vector(10, 0),
                    height = -23,
                    falling = 0,
                    acceleration = 0,
                }
            end
        end
        local index = match(shots, 10, Vector(125, 100), Vector(10, 0), age, 2, now, mapped, oneWay)
        assert(index == 2, "Latency/jitter matched a missing shot instead of the observed launch")
    end
end
attacks.reset()
draws = {}
roomAvailable = false
attacks.render()
assert(#draws == 0, "View reset left a tear in another room")
print(
    "PASS local aiming/drawing, unique confirmation, smooth handoff, controls, weapon change, collision, timeout and view reset"
)

-- Native Analog Stick aim may be diagonal; ordinary cardinal weapons retain
-- their restriction. These are drawing-only previews and disappear on reset.
roomAvailable = true
direction = Vector(1, 1)
fresh()
present(0, 1)
assert(#draws == 0, "Ordinary weapon guessed a diagonal tear")
policy.freeAim = function()
    return true
end
fresh()
present(0, 1)
assert(#draws == 1, "Known free-aim weapon did not preview its diagonal shot")
policy.freeAim = nil
direction = Vector(1, 0)
status.sync1, status.ping1 = 300, 40
fresh()
present(0, 1)
present(0.28, 2)
assert(#draws > 0, "Preview expired at the short RTT despite delayed authoritative views")
present(0.51, 3)
assert(counters["attack.pending"] == 0, "Delayed preview outlived its hard deadline")
status.sync1 = nil
print("PASS diagonal free-aim presentation and sync-delay budget")
