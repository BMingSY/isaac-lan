local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local E, S = fields.entity, fields.sprite
local reads, writes = 0, 0
local sprite = { name = "Idle", frame = 2, PlaybackSpeed = 1 }
function sprite:GetAnimation()
    return self.name
end
function sprite:SetFrame(name, frame)
    assert(name == self.name)
    self.frame, writes = frame, writes + 1
end
function sprite:Update()
    error("Display extrapolation ran native animation updates")
end
local entity =
    { Height = -23, FallingSpeed = 0.5, FallingAcceleration = 0, TearFlags = 0, WaitFrames = 0 }
function entity:GetSprite()
    return sprite
end
function entity:ToTear()
    return self
end
function entity:Update()
    error("Display extrapolation ran gameplay")
end
local presentation = dofile(root .. "/src/bridge/presentation/entity_visuals.lua")(fields)(
    {
        sprite_animation_length = function()
            reads = reads + 1
            return 8
        end,
    },
    dofile(root .. "/src/bridge/presentation/tear_motion.lua")(function() end),
    2,
    { BLUE = 0, BLOOD = 1 },
    0
)
local value = {
    [E.type] = 2,
    [E.variant] = 0,
    [E.sprite] = { [S.path] = "tear.anm2", [S.animation] = "Idle", [S.frame] = 2 },
}
local visual = presentation.observe(nil, entity, value, 1.05, 1)
presentation.present(visual, entity, 1.05)
assert(sprite.frame == 3 and entity.Height > -23)
presentation.present(visual, entity, 1.06)
local displayed = entity.Height
-- Restore authority before observing the next snapshot; no cumulative height drift.
entity.Height = -22.8
visual = presentation.observe(visual, entity, value, 1.06, 1.03)
presentation.present(visual, entity, 1.06)
assert(math.abs(entity.Height - displayed) < 0.02)
assert(reads == 1, "Unchanged animation re-read native length")
presentation.present(visual, entity, 2)
local stopped = entity.Height
presentation.present(visual, entity, 3)
assert(
    math.abs(entity.Height - stopped) < 0.001 and sprite.frame == 5,
    "A packet outage advanced animation or altitude indefinitely"
)
value[E.sprite][S.frame] = 7
visual = presentation.observe(nil, entity, value, 3, 3)
presentation.present(visual, entity, 3.1)
assert(sprite.frame == 7, "Display crossed an unconfirmed animation boundary")
sprite.name, value[E.sprite][S.animation] = "Attack", "Attack"
local before = writes
entity.TearFlags = 1
visual = presentation.observe(nil, entity, value, 4, 4)
local height = entity.Height
presentation.present(visual, entity, 4.1)
assert(
    writes == before and height == entity.Height,
    "An attack animation or special trajectory was extrapolated"
)
sprite.name, value[E.sprite][S.animation] = "Idle", "Idle"
value[E.sprite][S.path] = "replacement.anm2"
local beforeReads = reads
presentation.observe(visual, entity, value, 5, 5)
assert(reads == beforeReads + 1, "Entity/animation replacement reused a stale length")
print("PASS bounded animation/altitude, authority handoff, replacement and gameplay isolation")
