local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/compat/rules/friendly_fire.lua")
local contact = dofile(root .. "/src/bridge/core/contacts.lua")
local tick, nextId, room, entities = 0, 0, nil, {}
local info = {
    active = 1,
    authority = 1,
    ready = 1,
    runId = "a",
    worldEpoch = 1,
    connected = 3,
    roomOptions = 1,
}
local function entity(kind, x, damage)
    nextId = nextId + 1
    local e = {
        Type = kind,
        id = nextId,
        InitSeed = nextId,
        Size = 3,
        Position = { X = x, Y = 0 },
        Velocity = { X = 0, Y = 0 },
        CollisionDamage = damage,
        flags = 0,
        cooldown = 0,
        hearts = 24,
        room = "0:1",
    }
    function e:Exists()
        return not self.removed
    end
    function e:IsDead()
        return self.dead or false
    end
    function e:IsCoopGhost()
        return self.ghost or false
    end
    function e:IsInvincible()
        return self.invincible or false
    end
    function e:GetDamageCooldown()
        return self.cooldown
    end
    function e:ToFamiliar()
        return self.Type == 3 and self or nil
    end
    function e:ToTear()
        return self.Type == 2 and self or nil
    end
    function e:ToLaser()
        return self.Type == 7 and self or nil
    end
    function e:ToKnife()
        return self.Type == 8 and self or nil
    end
    function e:HasTearFlags(flag)
        return (self.flags & flag) ~= 0
    end
    function e:Die()
        self.dead = true
    end
    function e:TakeDamage(amount, flags, source)
        assert(info.authority == 1 and self.room == room, "damage outside authority room")
        assert(flags == 0 and source.Entity, "native player defenses were bypassed")
        self.lastDamage, self.calls = amount, (self.calls or 0) + 1
        if not self.veto then
            if self.mantle then
                self.mantle = false
            else
                self.hearts = self.hearts - amount
            end
            self.cooldown = 60
        end
    end
    return e
end
local host, guest, twin = entity(1, 0), entity(1, 100), entity(1, 0)
local players = { host, guest, twin }
local native = {
    api_info = function()
        return info
    end,
    net_room_options = function()
        return { { key = "friendlyFire", flag = 1 } }
    end,
    api_actors = function()
        return { { index = 0, owner = 1 }, { index = 1, owner = 2 }, { index = 2, owner = 1 } }
    end,
    rooms_positions = function()
        return {
            ["0"] = { dimension = 0, index = 1 },
            ["1"] = { dimension = 0, index = guest.room == "0:1" and 1 or 2 },
        }
    end,
    rooms_with_player = function(slot, fn)
        room = players[slot + 1].room
        fn()
        room = nil
        return true
    end,
}
local rules = factory({
    native = native,
    player = function(i)
        return players[i + 1]
    end,
    hash = function(e)
        return e.id
    end,
    ref = function(e)
        return { Entity = e }
    end,
    frame = function()
        return tick
    end,
    paused = function()
        return info.paused
    end,
    contact = contact,
    entities = function()
        return entities[room] or {}
    end,
    enums = {
        entity = { ENTITY_TEAR = 2, ENTITY_LASER = 7, ENTITY_KNIFE = 8 },
        damage = { DAMAGE_EXPLOSION = 4 },
        tear = { TEAR_PIERCING = 1, TEAR_EXPLOSIVE = 2 },
    },
})
local function shot(damage, source, target)
    source, target = source or host, target or guest
    local tear = entity(2, target.Position.X, (string.unpack("f", string.pack("f", damage))))
    tear.SpawnerEntity = source
    entities = { [source.room] = { tear } }
    tick = tick + 1
    rules.step()
    return tear
end
assert(shot(3.5).dead and guest.hearts == 23, "starting Isaac must hurt on the first hit")
for _ = 1, 12 do
    shot(100)
end
assert(guest.hearts == 23, "invulnerability was bypassed")
guest.cooldown = 0
shot(0.7)
assert(guest.hearts == 23, "ignored hits accumulated through invulnerability")
for _ = 1, 4 do
    shot(0.7)
end
assert(guest.hearts == 22, "five weak hits must reach half a heart")
guest.cooldown = 0
shot(0.7)
tick = tick + 31
shot(2.8)
assert(guest.hearts == 22, "interrupted accumulation survived")
guest.cooldown = 1
shot(1)
guest.cooldown = 0
shot(15)
assert(guest.hearts == 18 and guest.lastDamage == 4, "15 damage must deal two hearts")
guest.cooldown, guest.mantle = 0, true
shot(100)
assert(guest.hearts == 18 and not guest.mantle, "native shield was bypassed")
guest.cooldown = 0
shot(84)
assert(guest.hearts == -6 and guest.lastDamage == 24, "friendly damage was capped")
guest.hearts, guest.cooldown = 24, 0
shot(3.5, host, twin)
assert(host.hearts == 24 and twin.hearts == 24, "a player's own actors hurt each other")
shot(3.5, guest, host)
assert(host.hearts == 23, "guest-owned attacks were ignored")
guest.room = "0:2"
shot(100)
assert(guest.hearts == 24, "damage crossed a room boundary")
guest.room = "0:1"
info.roomOptions = 0
shot(100)
assert(guest.hearts == 24, "disabled friendly fire dealt damage")
local bomb = entity(4, 0, 100)
bomb.SpawnerEntity = host
assert(rules.damage(guest, 1, 4, { Entity = bomb }) == false, "disabled teammate bomb was allowed")
assert(rules.damage(host, 1, 4, { Entity = bomb }) == nil, "self damage was canceled")
assert(rules.damage(guest, 1, 4, { Entity = nil }) == nil, "environmental explosion was canceled")
info.roomOptions = 1
assert(rules.damage(guest, 2, 4, { Entity = bomb }) == nil, "native bomb damage was replaced")
local explosive = shot(100)
-- Verify explosive tears separately: contact triggers the explosion without a
-- second ordinary hit; the native callback retains player damage units.
guest.hearts, guest.cooldown = 24, 0
explosive = entity(2, 100, 100)
explosive.SpawnerEntity, explosive.flags = host, 2
entities = { ["0:1"] = { explosive } }
tick = tick + 1
rules.step()
assert(explosive.dead and guest.hearts == 24, "explosive tear was converted twice")
local fast = entity(2, 150, 3.5)
fast.SpawnerEntity, fast.Velocity.X = host, 100
entities = { ["0:1"] = { fast } }
tick = tick + 1
rules.step()
assert(guest.hearts == 23, "fast tear tunneled through a teammate")
guest.cooldown, guest.hearts = 0, 24
local laser = entity(7, 0, 0.7)
laser.SpawnerEntity, laser.Timeout, laser.OneHit = host, 20, false
function laser:IsCircleLaser()
    return false
end
function laser:GetSamples()
    return {}
end
function laser:GetEndPoint()
    return { X = 150, Y = 0 }
end
entities = { ["0:1"] = { laser } }
for _ = 1, 9 do
    tick = tick + 1
    rules.step()
end
assert(guest.hearts == 23, "continuous low-damage laser did not accumulate")
guest.cooldown, guest.hearts = 0, 24
info.authority = 0
shot(100)
assert(guest.hearts == 24, "replica executed friendly damage")
info.authority = 1
info.worldEpoch = 2
shot(2.8)
assert(guest.hearts == 24, "previous floor accumulation leaked")
guest.invincible = true
shot(100)
guest.invincible = false
shot(0.7)
assert(guest.hearts == 24, "native invulnerability accumulated debt")
guest.hearts, guest.cooldown, info.paused = 24, 0, true
shot(100)
assert(guest.hearts == 24, "paused simulation dealt damage")
info.paused = false
rules.reset()
local ring = entity(7, 0, 3.5)
ring.SpawnerEntity, ring.Timeout, ring.Radius = host, 30, 100
function ring:IsCircleLaser()
    return true
end
entities = { ["0:1"] = { ring } }
tick = tick + 1
rules.step()
assert(guest.hearts == 23, "laser ring edge did not hit")
guest.cooldown, guest.hearts, ring.Radius = 0, 24, 140
tick = tick + 4
rules.step()
assert(guest.hearts == 24, "the empty center of a ring hurt a teammate")
rules.reset()
local familiar = entity(3, 0)
familiar.Player = host
local child = entity(2, 100, 3.5)
child.Parent = familiar
entities = { ["0:1"] = { child } }
tick = tick + 1
rules.step()
assert(guest.hearts == 23, "familiar-owned projectile lost its player owner")
guest.cooldown, guest.hearts = 0, 24
rules.reset()
shot(2.8)
guest.InitSeed = guest.InitSeed + 1
shot(0.7)
assert(guest.hearts == 24, "reused actor pointer inherited another body's damage credit")
print("friendly fire authority, scaling, defense, room, geometry and ownership checks passed")
