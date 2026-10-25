local root = assert(arg[1])
local new = dofile(root .. "/tests/support/friendly_fire.lua")
local function check(value, message)
    assert(value, message)
end
local function effect(w, variant, damage, source)
    local e = w.entity(1000, 400, damage or 0)
    e.Variant, e.SpawnerEntity = variant, source
    w.entities[#w.entities + 1] = e
    return e
end

local w = new(root)
w.host.collectibles[350] = true
w:step(45)
check(w.guest.hearts == 6, "poison settled before its fractional threshold")
w:step(16)
check(
    w.guest.hearts == 5 and w.host.hearts == 6 and w.twin.hearts == 6,
    "poison target or timing differs"
)
w:step(100)
check(w.guest.hearts == 5, "expired poison kept damaging")
w.host.room, w.twin.room = "0:2", "0:2"
w:step()
w.host.room, w.twin.room = "0:1", "0:1"
w:step(90)
check(w.guest.hearts == 5, "door hopping retriggered room poison")

w = new(root)
w:step()
w.host.collectibles[350] = true
w:step(70)
check(w.guest.hearts == 6, "acquiring Toxic Shock mid-room retriggered entry")
w.host.room, w.twin.room, w.guest.room = "0:2", "0:2", "0:2"
w:step(61)
check(w.guest.hearts == 5, "Toxic Shock failed on actual room entry")

w = new(root)
w.host.Damage, w.host.collectibles[350] = 1000, true
w:step(70)
check(w.guest.hearts == 4, "high-stat room poison bypassed its total cap")

for _, transition in ipairs({
    "source_room",
    "target_room",
    "floor",
    "disconnect",
    "disabled",
    "source_death",
    "target_body",
}) do
    w = new(root)
    w.host.collectibles[350] = true
    w:step(31)
    if transition == "source_room" then
        w.host.room, w.twin.room = "0:2", "0:2"
    elseif transition == "target_room" then
        w.guest.room = "0:2"
    elseif transition == "floor" then
        w.info.worldEpoch, w.host.collectibles[350] = 2, nil
    elseif transition == "disconnect" then
        w.info.connected = 6
    elseif transition == "disabled" then
        w.info.roomOptions = 0
    elseif transition == "source_death" then
        w.host.dead = true
    elseif transition == "target_body" then
        w.guest.InitSeed = w.guest.InitSeed + 1
    end
    w:step(70)
    check(w.guest.hearts == 6, transition .. " retained pending poison")
end

w = new(root)
w.host.collectibles[350], w.guest.shadows = true, true
w:step(61)
w.guest.shadows = false
w:shot(0.1)
w:step()
check(w.guest.hearts == 6, "blocked poison became damage debt")

for _, item in ipairs({ 35, 186 }) do
    w = new(root)
    w:use(item)
    w:use(item)
    w:step(2)
    check(
        w.guest.hearts == 4 and w.host.hearts == 6,
        "room active duplicated, missed or hurt its user"
    )
    w:step(60)
    check(w.guest.hearts == 4, "instant item event replayed")
end

w = new(root)
w:use(35)
w:use(186)
w:step()
check(w.guest.hearts == 4, "nested native item callbacks multiplied one activation's damage")

w = new(root)
w.guest.room = "0:2"
w:use(35)
w:step()
check(w.guest.hearts == 6, "room active crossed rooms")
w = new(root)
w.info.roomOptions = 0
w:use(35)
w:step(70)
check(w.guest.hearts == 6, "disabled item damage was applied")
w = new(root)
w.info.authority = 0
w:use(35)
w:step(70)
check(w.guest.hearts == 6, "replica item callback dealt damage")

w = new(root)
w:use(111)
w:step(61)
check(w.guest.hearts == 5 and w.third.hearts == 6, "Bean poison ignored its radius")

w = new(root)
w:use(160)
local beams = {}
for _ = 1, 5 do
    beams[#beams + 1] = effect(w, 19, 0, w.host)
end
w:step()
check(w.third.hearts == 6, "uninitialized beams damaged an opponent")
for _, beam in ipairs(beams) do
    beam.CollisionDamage = 23.5
end
w:step()
check(
    w.guest.hearts == 6 and w.third.hearts == 4,
    "Sky did not choose the nearest opponent or share its cast cap"
)
check(w.events[1].source == w.host, "converted Sky damage lost its player source")
w:step(35)
check(w.third.hearts == 4, "a lingering beam repeatedly dealt damage")

w = new(root)
local ambient = effect(w, 28)
local tooth = w:use(86, nil, function()
    return effect(w, 28)
end)
check(
    tooth.Target == w.guest and tooth.Position == w.guest.Position,
    "Monstro did not select an opponent"
)
w:damage(w.guest, 2, 1 << 24, tooth)
check(w.guest.hearts == 4 and #w.events == 1, "native tooth damage duplicated or failed")
w = new(root)
w.info.roomOptions = 0
ambient = effect(w, 28)
tooth = w:use(86, nil, function()
    return effect(w, 28)
end)
w:step(70)
w:damage(w.guest, 2, 1 << 24, tooth)
check(w.guest.hearts == 6, "disabled native tooth damage lost its ownership")
w:damage(w.guest, 2, 1 << 24, ambient)
check(w.guest.hearts == 4, "an unrelated environmental stomp was canceled")
w:damage(w.host, 2, 1 << 24, tooth)
check(w.host.hearts == 4, "native item self damage was canceled")
for _, transition in ipairs({ "source_room", "target_room", "disconnect", "source_body" }) do
    w = new(root)
    tooth = w:use(86, nil, function()
        return effect(w, 28)
    end)
    if transition == "source_room" then
        w.host.room, w.twin.room = "0:2", "0:2"
    elseif transition == "target_room" then
        w.guest.room = "0:2"
    elseif transition == "disconnect" then
        w.info.connected = 6
    else
        w.host.InitSeed = w.host.InitSeed + 1
    end
    w:step()
    w:damage(w.guest, 2, 1 << 24, tooth)
    check(w.guest.hearts == 6, transition .. " retained native item damage")
end
print("PvP items: room poison, active damage, targeting, native ownership and cleanup passed")
