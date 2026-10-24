local root = assert(arg[1])
local make = dofile(root .. "/src/bridge/presentation/event_ledger.lua")
local decode = dofile(root .. "/src/bridge/sync/combat_events.lua")
local contact = dofile(root .. "/src/bridge/core/contacts.lua")
local function event(serial, source, target, accepted, duration)
    return {
        serial = serial,
        source = source,
        target = target,
        accepted = accepted,
        duration = duration or 0.1,
    }
end
local ledger = make()
assert(ledger.predict(12, 21, 1, 0.1))
assert(not ledger.predict(12, 21, 1.01, 0.1))
assert(ledger.sample(1.01)[21])
assert(ledger.confirm(event(3, 12, 21, true), 1.08, 0))
assert(ledger.sample(1.09)[21])
assert(not ledger.sample(1.11)[21], "Confirmation restarted the prediction clock")
assert(not ledger.confirm(event(3, 12, 21, true), 1.2, 0))
assert(not ledger.confirm(event(2, 12, 21, true), 1.2, 0))
assert(ledger.counts.confirmed == 1 and ledger.counts.played == 0)
assert(ledger.predict(13, 22, 2, 0.1))
ledger.confirm(event(4, 13, 22, false, 0), 2.02, 0)
local visible, hidden = ledger.sample(2.03)
assert(not visible[22] and not hidden[13])
assert(ledger.predict(14, 23, 3, 0.1))
visible, hidden = ledger.sample(3.36)
assert(not visible[23] and not hidden[14] and ledger.counts.expired == 1)
ledger.confirm(event(5, 14, 23, true), 3.5, 0)
assert(not ledger.sample(3.5)[23], "Late confirmation replayed a timed-out prediction")
-- Late confirmation of an already completed prediction must not replay.
assert(ledger.predict(15, 24, 4, 0.1))
ledger.confirm(event(6, 15, 24, true), 4.2, 0)
assert(not ledger.sample(4.2)[24])
-- Unpredicted authoritative hits play only their remaining duration.
ledger.confirm(event(7, 100, 25, true), 5, 0.04)
assert(ledger.sample(5.05)[25] and not ledger.sample(5.07)[25])
ledger.confirm(event(8, 100, 25, true), 6, 0.2)
assert(not ledger.sample(6)[25])
-- Accepted native contact is not evidence that the engine played a flash.
ledger.confirm(event(9, 101, 26, true, 0), 6.1, 0)
assert(not ledger.sample(6.1)[26], "Contact without native feedback invented a flash")
assert(ledger.predict(16, 27, 6.2, 0.1))
ledger.confirm(event(10, 16, 27, true, 0), 6.21, 0)
assert(not ledger.sample(6.21)[27], "Zero-duration confirmation retained a predicted flash")
-- Room changes drop visuals but keep the sequence high watermark. Epoch reset
-- can accept a new session's sequence; neither reset leaks a hidden projectile.
ledger.clear(false)
assert(not ledger.confirm(event(7, 100, 25, true), 7, 0))
ledger.observe(20)
assert(
    not ledger.confirm(event(19, 100, 25, true), 7, 0),
    "Reentered room replayed an observed event"
)
ledger.clear(true)
assert(ledger.confirm(event(1, 100, 25, true), 7, 0))
for i = 2, 600 do
    ledger.confirm(event(i, 200 + i, 25, true), 8 + i, 0)
    ledger.sample(8 + i)
end
local record = string.pack(">I4I4I4i4i4I4I4BB", 1, 20, 3, -1, 84, 12, 21, 1, 3)
local wire = string.pack(">I4", 1) .. record
local result = decode(wire)
assert(#result == 1 and result[1].target == 21 and result[1].duration == 0.1)
for _, bad in ipairs({
    "",
    wire:sub(1, -2),
    wire .. "x",
    string.pack(">I4", 513),
    string.pack(">I4", 2) .. record .. record,
}) do
    assert(not pcall(decode, bad))
end
assert(contact(-30, 0, 30, 0, 10) == 1 / 3)
assert(contact(-30, 12, 30, 12, 10) == nil)
assert(contact(0, 0, 0, 0, 10) == 0)
assert(contact(20, 0, 20, 0, 10) == nil)
assert(contact(-40, 0, -20, 0, 10) == nil)
print(
    "PASS hit identity, confirmation, rejection, expiry, scope cleanup, bounded wire and swept contact"
)

local corrected = make()
corrected.predict(1, 10, 0, 0.05)
corrected.confirm(event(1, 1, 10, true, 0.2), 0.08, 0)
assert(not corrected.sample(0.08)[10], "Changed damage duration replayed a completed flash")
corrected.predict(2, 10, 1, 0.1)
corrected.confirm(event(2, 2, 11, true), 1.02, 0)
visible, hidden = corrected.sample(1.03)
assert(
    not visible[10] and visible[11] and not hidden[2],
    "Wrong target prediction was not cancelled"
)

local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local eligibility = dofile(root .. "/src/bridge/sync/combat_state.lua")(
    fields,
    enums.TearVariant,
    enums.TearFlags,
    enums.EntityFlag
)
local E, A, R, L, C = fields.entity, fields.actor, fields.room, fields.location, fields.combat
local function vector(x, y)
    return { X = x, Y = y }
end
local function entity(id, x, isTear)
    local e = {
        Position = vector(x, 0),
        Size = 5,
        Visible = true,
        CollisionDamage = 3.5,
        Variant = enums.TearVariant.BLUE,
        Height = -15,
        WaitFrames = 0,
        TearFlags = enums.TearFlags.TEAR_NORMAL,
        vulnerable = true,
    }
    function e:ToTear()
        return isTear and self
    end
    function e:ToNPC()
        return not isTear and self
    end
    function e:IsVulnerableEnemy()
        return self.vulnerable
    end
    function e:HasEntityFlags(mask)
        assert(mask == 33554432, "NPC flash eligibility used the player invulnerability flag")
        return self.noBlink
    end
    function e:IsDead()
        return false
    end
    function e:Exists()
        return true
    end
    function e:GetSprite()
        return id
    end
    return e
end
local projectile, near, far = entity(2, -30, true), entity(3, 0), entity(4, 20)
assert(eligibility(projectile) == C.projectile)
projectile.TearFlags = enums.TearFlags.TEAR_PIERCING
assert(eligibility(projectile) == C.none, "Per-projectile Mod flags were ignored")
projectile.TearFlags = enums.TearFlags.TEAR_NORMAL
projectile.WaitFrames = 2
assert(eligibility(projectile) == C.none)
projectile.WaitFrames = 0
near.vulnerable = false
assert(eligibility(near) == C.none)
near.vulnerable, near.noBlink = true, true
assert(eligibility(near) == C.none)
near.noBlink = false
assert(eligibility(near) == C.target)
local objects, active, open = { [2] = projectile, [3] = near, [4] = far }, {}, true
local function ref(id)
    return objects[id]
end
local hits = dofile(root .. "/src/bridge/presentation/hits.lua")(fields)({
    ledger = make,
    vector = vector,
    decode = decode,
    contact = contact,
    native = {
        combat_present = function(id)
            if id then
                active[id] = true
            else
                active = {}
            end
            return true
        end,
    },
    metrics = { counter = function() end },
    room = function()
        return {
            CheckLine = function()
                return open
            end,
        }
    end,
})
local value = {
    epoch = 1,
    slot = 1,
    combat = string.pack(">I4", 0),
    locations = { { [L.slot] = 1, [L.dimension] = 0, [L.index] = 84 } },
    actors = { { [A.controller] = 2, [A.entity] = { [E.id] = 1 } } },
    room = {
        [R.entities] = {
            { [E.id] = 2, [E.spawner] = 1, [E.position] = { -30, 0 }, [E.combat] = C.projectile },
            { [E.id] = 4, [E.combat] = C.target },
            { [E.id] = 3, [E.combat] = C.target },
        },
    },
}
hits.confirm(value, 30, 1, ref)
projectile.Position = vector(30, 0)
hits.present(nil, ref, 1.01, nil, nil, { pause = 0 })
assert(active[3] and not active[4] and not projectile.Visible, "Sweep did not choose first target")
hits.suspend(ref)
assert(projectile.Visible and next(active) == nil, "Pause left speculative presentation behind")
projectile.Position = vector(-30, 0)
hits.confirm(value, 31, 2, ref)
projectile.Position, open = vector(30, 0), false
hits.present(nil, ref, 2.01, nil, nil, { pause = 0 })
assert(next(active) == nil and projectile.Visible, "Prediction passed through a blocking grid")
hits.suspend(ref)
open = true
projectile.Position = vector(-30, 0)
hits.confirm(value, 32, 3, ref)
projectile.Position = vector(30, 0)
hits.present(nil, ref, 3.01, nil, nil, { pause = 0 })
assert(not projectile.Visible)
value.locations[1][L.index] = 85
value.room[R.entities] = {}
hits.confirm(value, 33, 3.02, ref)
assert(projectile.Visible and next(active) == nil, "Room change leaked hidden projectiles")
print("PASS actual projectile policy, nearest contact, blocked line, pause and room cleanup")
