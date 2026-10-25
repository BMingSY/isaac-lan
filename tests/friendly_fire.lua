local root = assert(arg[1])
local new = dofile(root .. "/tests/support/friendly_fire.lua")
local function check(value, message)
    assert(value, message)
end
local function shoot(w, damage, count, source, target)
    w:shot(damage, source, target, count)
    w:step()
end
local function duel(interval, damage, count)
    local w = new(root)
    w.host.MaxFireDelay, w.host.Damage = interval - 1, damage
    local first
    for tick = 1, 600 do
        if (tick - 1) % interval == 0 then
            w:shot(damage, nil, nil, count)
            first = first or tick
        end
        w:step()
        if w.guest.dead then
            return (tick - first) / 30, w
        end
    end
    error("duel never finished")
end
local ordinary = duel(11, 3.5)
local built = duel(6, 10)
local strong = duel(3, 10)
check(ordinary >= 4 and ordinary <= 5, "ordinary duel outside 4-5 seconds: " .. ordinary)
check(built >= 2.5 and built <= 3.5, "5 tears/10 damage duel outside target: " .. built)
check(strong >= 2 and strong < built, "strong build lost growth or killed instantly")
local rapid = duel(3, 1)
local heavy = duel(30, 10)
check(math.abs(rapid - heavy) <= 0.6, "equal-DPS rapid/heavy attacks diverged")
local scatter = duel(11, 3.5, 6)
check(scatter < ordinary and scatter >= 2, "multishot lost growth or bypassed diminishing returns")
print(
    string.format(
        "PvP seconds: ordinary=%.3f built=%.3f strong=%.3f rapid=%.3f heavy=%.3f scatter=%.3f",
        ordinary,
        built,
        strong,
        rapid,
        heavy,
        scatter
    )
)

local w = new(root)
shoot(w, 3.5)
check(w.guest.hearts == 6, "fractional damage applied before half-heart threshold")
w:step(10)
shoot(w, 3.5)
check(w.guest.hearts == 6, "fractional damage rounded up")
w:step(10)
shoot(w, 3.5)
check(w.guest.hearts == 5, "three basic hits did not accumulate")
w:step(10)
shoot(w, 3.5)
w:step(10)
shoot(w, 3.5)
check(w.guest.hearts == 4, "accepted remainder was discarded or native hurt swallowed rapid hits")
local eventCount = #w.events
w.rules.step()
w.rules.step()
check(#w.events == eventCount, "duplicate simulation tick dealt damage twice")

w = new(root)
shoot(w, 1000)
check(w.guest.hearts == 3, "burst did not stop at half maximum health")
shoot(w, 1000, nil, w.third)
check(w.guest.hearts == 3, "another attacker bypassed shared burst protection")
w:step(9)
shoot(w, 1000)
check(w.guest.dead, "burst protection prevented a later lethal hit")

w = new(root)
shoot(w, 1000, 10)
check(
    w.guest.hearts == 3 and #w.events == 1,
    "one volley settled multiple hits or bypassed burst cap"
)
w:step(11)
shoot(w, 0.1)
check(w.guest.hearts == 3, "capped damage became delayed debt")

w = new(root)
local parent = w:shot(1000)
w:step(12)
local child = w:shot(1000)
child.SpawnerEntity = parent
w:step()
check(w.guest.hearts == 3, "a derived projectile received a fresh burst budget")
shoot(w, 1000)
check(w.guest.dead, "a new volley inherited an exhausted burst budget")

w = new(root)
w.guest.cooldown = 60
shoot(w, 1000)
check(w.guest.hearts == 6 and w.guest.cooldown == 58, "external immunity was shortened")
w:step(29)
shoot(w, 0.1)
check(w.guest.hearts == 6, "blocked contacts accumulated through native protection")

w = new(root)
w.guest.mantle = true
shoot(w, 1000)
check(w.guest.hearts == 6 and not w.guest.mantle, "native shield was bypassed")
shoot(w, 1000)
check(w.guest.hearts == 6, "mantle protection was mistaken for ordinary PvP cooldown")
w:step(30)
shoot(w, 0.1)
check(w.guest.hearts == 6, "shielded damage left debt")

w = new(root)
shoot(w, 8)
check(w.guest.hearts == 5, "native hit setup failed")
w.guest.shadows = true
w:step(1)
shoot(w, 1000)
check(
    w.guest.hearts == 5 and w.guest.cooldown > 0,
    "item invincibility was bypassed or cooldown lost"
)
w.guest.shadows = false
w:step(30)
shoot(w, 0.1)
check(w.guest.hearts == 5, "item invincibility banked damage")

w = new(root)
w.guest.wafer = true
shoot(w, 1000)
check(w.guest.hearts == 5, "native mitigation was bypassed")

w = new(root)
w.guest.veto = true
shoot(w, 1000)
check(w.guest.hearts == 6, "another damage callback veto was ignored")
w.guest.veto = false
shoot(w, 0.1)
check(w.guest.hearts == 6, "vetoed damage was retained")

w = new(root)
shoot(w, 8)
local cooldown = w.guest.cooldown
w.guest.throw = true
w:shot(8)
local ok = pcall(function()
    w:step()
end)
check(not ok and w.guest.cooldown == cooldown - 2, "native error leaked suspended protection")

for _, transition in ipairs({
    "room",
    "floor",
    "body",
    "disconnect",
    "disabled",
    "backwards",
    "reset",
    "gap",
}) do
    w = new(root)
    shoot(w, 3.5)
    shoot(w, 3.5)
    check(w.guest.hearts == 6, "cleanup setup unexpectedly hurt")
    if transition == "room" then
        w.guest.room = "0:2"
        w:step()
        w.guest.room = "0:1"
    elseif transition == "floor" then
        w.info.worldEpoch = 2
    elseif transition == "body" then
        w.guest.InitSeed = w.guest.InitSeed + 1
    elseif transition == "disconnect" then
        w.info.connected = 5
        w:step()
        w.info.connected = 7
    elseif transition == "disabled" then
        w.info.roomOptions = 0
        w:step()
        w.info.roomOptions = 1
    elseif transition == "backwards" then
        w.tick = -1
    elseif transition == "reset" then
        w.rules.reset()
    elseif transition == "gap" then
        w:step(31)
    end
    shoot(w, 3.5)
    check(w.guest.hearts == 6, transition .. " retained damage credits")
end

w = new(root)
w.info.paused = true
shoot(w, 1000)
check(w.guest.hearts == 6, "paused simulation dealt damage")
w.info.paused, w.info.authority = false, 0
w:step()
check(w.guest.hearts == 6, "replica settled damage")

w = new(root)
shoot(w, 1000, nil, w.host, w.twin)
check(w.host.hearts == 6 and w.twin.hearts == 6, "owned bodies hurt each other")
w.guest.room = "0:2"
shoot(w, 1000)
check(w.guest.hearts == 6, "damage crossed room boundary")
w.guest.room = "0:1"
shoot(w, 1000, nil, w.guest, w.host)
check(w.host.hearts == 3, "guest attack was ignored")

w = new(root)
local fast = w:shot(1000)
fast.Position.X, fast.Velocity.X = 150, 100
w:step()
check(w.guest.hearts == 3, "swept contact missed a fast projectile")

w = new(root)
local piercing = w:shot(3.5)
piercing.flags = 1
w:step(20)
check(w.guest.hearts == 6, "one piercing contact accumulated repeated damage")

w = new(root)
local delayed = w:shot(8)
delayed.Position.X = 150
w:step(60)
delayed.Position.X = 100
w:step()
check(w.guest.hearts == 5, "a delayed hit lost its emission multiplier")

w = new(root)
shoot(w, 1000)
w:step(11)
shoot(w, 8)
shoot(w, 8)
check(w.guest.hearts == 1, "restoring an older PvP cooldown created external immunity")

w = new(root)
w.host.Damage = 0.7
w:laser(0.7)
w:step(15)
check(w.guest.hearts == 6, "continuous contact ticked every simulation update")
w:step(15)
check(w.guest.hearts < 6, "continuous low-damage laser did not accumulate")

w = new(root)
local ring = w:laser(3.5)
ring.circle, ring.Radius = true, 100
w:step(30)
check(w.guest.hearts < 6, "laser ring edge missed")
w = new(root)
ring = w:laser(3.5)
ring.circle, ring.Radius = true, 140
w:step(30)
check(w.guest.hearts == 6, "empty ring center hurt")

w = new(root)
local knife = w.entity(8, 100, 10)
knife.SpawnerEntity = w.host
w.entities = { knife }
w:step(180)
check(w.guest.dead, "persistent knife exhausted its lifetime damage budget")

w = new(root)
knife = w.entity(8, 100, 10)
knife.SpawnerEntity = w.host
w.entities = { knife }
w:step(8)
check(w.guest.hearts == 6, "brief knife contact rounded fractional damage up")
knife.Position.X = 150
w:step(10)
knife.Position.X = 100
w:step(8)
check(w.guest.hearts == 5, "repeated knife contacts lost their fractional damage")

w = new(root)
local familiar = w.entity(3, 0)
familiar.Player = w.host
for _ = 1, 3 do
    shoot(w, 3.5, nil, familiar)
    w:step(29)
end
check(w.guest.hearts < 6, "familiar projectile lost owner")

w = new(root)
w.guest.maxHearts, w.guest.hearts, w.guest.souls = 0, 0, 6
shoot(w, 1000)
check(w.guest.souls == 3, "soul-heart capacity was ignored")
w:step(11)
shoot(w, 1000)
check(w.guest.dead, "soul-heart burst limit shrank with current health")

w = new(root)
local bomb = w.entity(4, 0, 100)
bomb.SpawnerEntity = w.host
w.info.roomOptions = 0
w:damage(w.guest, 2, 4, bomb)
check(w.guest.hearts == 6, "disabled friendly explosion dealt damage")
w:damage(w.host, 2, 4, bomb)
check(w.host.hearts == 4, "self explosion was canceled or scaled")
w:damage(w.guest, 2, 4, nil)
check(w.guest.hearts == 4, "environmental explosion was canceled or scaled")
w = new(root)
bomb = w.entity(4, 0, 100)
bomb.SpawnerEntity = w.host
w:damage(w.guest, 2, 4, bomb)
check(
    w.guest.hearts == 4 and #w.events == 1 and (w.events[1].flags & 4) ~= 0,
    "friendly explosion lost native units or applied twice"
)
w:damage(w.guest, 2, 4, bomb)
check(w.guest.hearts == 4, "chain explosion bypassed burst protection")
w:step(11)
w:damage(w.guest, 2, 4, bomb)
check(w.guest.hearts == 3, "same explosion exceeded its shared volley budget")

w = new(root)
w.guest.wafer, w.host.wafer = true, true
bomb = w.entity(4, 0, 100)
bomb.SpawnerEntity = w.host
w:damage(w.host, 4, 4, bomb)
w:damage(w.guest, 4, 4, bomb)
check(w.guest.hearts == 4 and w.host.hearts == 4, "forwarded explosion applied mitigation twice")

w = new(root)
w.guest.damageMultiplier = 2
shoot(w, 1000)
check(w.guest.hearts == 3, "native floor modifier bypassed the burst cap")

w = new(root)
w.guest.damageMultiplier = 2
bomb = w.entity(4, 0, 100)
bomb.SpawnerEntity = w.host
w:damage(w.guest, 1, 4, bomb)
check(w.guest.hearts == 4, "forwarded explosion applied floor damage twice")

print(
    "friendly fire balance, burst, native defenses, cleanup, rooms, geometry and ownership checks passed"
)
