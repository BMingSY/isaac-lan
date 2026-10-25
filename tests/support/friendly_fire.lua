-- Stateful native-damage fixture: the production callback and contacts share
-- real cooldown ownership, time, room scopes and ordinary mitigation semantics.
return function(root)
    local world = { tick = 0, entities = {}, events = {}, callbacks = 0 }
    local NO_MODIFIERS = 1 << 25
    local nextId, room, rules = 0, nil, nil
    local function entity(kind, x, damage)
        nextId = nextId + 1
        local e = {
            Type = kind,
            id = nextId,
            InitSeed = nextId,
            FrameCount = 0,
            Size = 3,
            Position = { X = x, Y = 0 },
            Velocity = { X = 0, Y = 0 },
            CollisionDamage = damage,
            flags = 0,
            cooldown = 0,
            hearts = 6,
            maxHearts = 6,
            souls = 0,
            bones = 0,
            eternal = 0,
            room = "0:1",
            Damage = 3.5,
            MaxFireDelay = 10,
            collectibles = {},
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
        function e:HasInvincibility()
            return self.cooldown > 0 or self.shadows or false
        end
        function e:GetDamageCooldown()
            return self.cooldown
        end
        function e:ResetDamageCooldown()
            self.cooldown = 0
        end
        function e:SetMinDamageCooldown(value)
            self.cooldown = math.max(self.cooldown, value)
        end
        function e:GetHearts()
            return self.hearts
        end
        function e:GetMaxHearts()
            return self.maxHearts
        end
        function e:GetSoulHearts()
            return self.souls
        end
        function e:GetBoneHearts()
            return self.bones
        end
        function e:GetEternalHearts()
            return self.eternal
        end
        function e:HasCollectible(item)
            return self.collectibles[item] or false
        end
        function e:GetEffectiveMaxHearts()
            return self.maxHearts + 2 * self.bones
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
        function e:IsFlying()
            return self.flying or false
        end
        function e:HasTearFlags(flag)
            return (self.flags & flag) ~= 0
        end
        function e:Die()
            self.dead = true
        end
        function e:TakeDamage(amount, flags, source)
            assert(world.info.authority == 1 and self.room == room, "damage outside authority room")
            assert(
                (flags & ~(4 | (1 << 24) | NO_MODIFIERS)) == 0,
                "native player defenses were bypassed"
            )
            if (flags & NO_MODIFIERS) == 0 then
                amount = amount * (self.damageMultiplier or 1)
                if self.wafer then
                    amount = math.max(1, math.floor(amount / 2))
                end
            end
            world.callbacks = world.callbacks + 1
            if rules.damage(self, amount, flags, source) == false then
                return false
            end
            if self.throw then
                error("native damage failure")
            end
            if self.veto or self:IsInvincible() or self:HasInvincibility() then
                return false
            end
            if self.mantle then
                self.mantle, self.cooldown = false, 60
                return true
            end
            local before = self.hearts + self.souls
            local soulDamage = math.min(self.souls, amount)
            self.souls = self.souls - soulDamage
            self.hearts = math.max(0, self.hearts - (amount - soulDamage))
            self.cooldown = amount >= 2 and 120 or 60
            world.events[#world.events + 1] = {
                target = self,
                at = world.tick,
                amount = before - self.hearts - self.souls,
                flags = flags,
                source = source.Entity,
            }
            if self.hearts + self.souls == 0 then
                self.dead = true
            end
            return true
        end
        return e
    end
    world.entity = entity
    world.host, world.guest, world.twin, world.third =
        entity(1, 0), entity(1, 100), entity(1, 0), entity(1, 200)
    world.players = { world.host, world.guest, world.twin, world.third }
    world.info = {
        active = 1,
        authority = 1,
        ready = 1,
        runId = "a",
        worldEpoch = 1,
        connected = 7,
        roomOptions = 1,
    }
    local native = {
        api_info = function()
            return world.info
        end,
        net_room_options = function()
            return { { key = "friendlyFire", flag = 1 } }
        end,
        api_actors = function()
            return {
                { index = 0, owner = 1 },
                { index = 1, owner = 2 },
                { index = 2, owner = 1 },
                { index = 3, owner = 3 },
            }
        end,
        rooms_positions = function()
            return {
                ["0"] = { dimension = 0, index = tonumber(world.host.room:match(":(%d+)$")) },
                ["1"] = { dimension = 0, index = world.guest.room == "0:1" and 1 or 2 },
                ["2"] = { dimension = 0, index = 1 },
            }
        end,
        rooms_with_player = function(slot, fn)
            room = slot == 0 and world.host.room
                or slot == 1 and world.guest.room
                or world.third.room
            fn()
            room = nil
            return true
        end,
    }
    rules = dofile(root .. "/src/bridge/compat/rules/friendly_fire.lua")({
        native = native,
        policy = dofile(root .. "/src/bridge/compat/rules/pvp_damage.lua"),
        attacks = dofile(root .. "/src/bridge/compat/rules/pvp_attacks.lua"),
        health = dofile(root .. "/src/bridge/compat/rules/pvp_health.lua"),
        items = dofile(root .. "/src/bridge/compat/items/pvp.lua"),
        player = function(i)
            return world.players[i + 1]
        end,
        hash = function(e)
            return e.id
        end,
        ref = function(e)
            return { Entity = e }
        end,
        frame = function()
            return world.tick
        end,
        paused = function()
            return world.info.paused
        end,
        contact = dofile(root .. "/src/bridge/core/contacts.lua"),
        entities = function()
            local result = {}
            for _, e in ipairs(world.entities) do
                if e.room == room and not e.dead then
                    result[#result + 1] = e
                end
            end
            return result
        end,
        enums = {
            entity = { ENTITY_TEAR = 2, ENTITY_LASER = 7, ENTITY_KNIFE = 8, ENTITY_EFFECT = 1000 },
            damage = { DAMAGE_EXPLOSION = 4, DAMAGE_NO_MODIFIERS = NO_MODIFIERS },
            collectible = {
                COLLECTIBLE_NECRONOMICON = 35,
                COLLECTIBLE_BLOOD_RIGHTS = 186,
                COLLECTIBLE_BEAN = 111,
                COLLECTIBLE_TOXIC_SHOCK = 350,
                COLLECTIBLE_MONSTROS_TOOTH = 86,
                COLLECTIBLE_CRACK_THE_SKY = 160,
            },
            effect = { CRACK_THE_SKY = 19, MONSTROS_TOOTH = 28 },
            tear = { TEAR_PIERCING = 1, TEAR_EXPLOSIVE = 2 },
        },
    })
    world.rules = rules
    function world:use(item, source, spawn)
        source = source or self.host
        room = source.room
        rules.beforeUseItem(item, source)
        local value = spawn and spawn()
        rules.useItem(item, source)
        room = nil
        return value
    end
    function world:step(count)
        for _ = 1, count or 1 do
            if not self.info.paused then
                self.tick = self.tick + 1
                for _, p in ipairs(self.players) do
                    p.cooldown = math.max(0, p.cooldown - 2)
                end
                for _, e in ipairs(self.entities) do
                    e.FrameCount = e.FrameCount + 1
                end
            end
            rules.step()
        end
    end
    function world:shot(damage, source, target, count)
        source, target = source or self.host, target or self.guest
        local last
        for _ = 1, count or 1 do
            last = entity(2, target.Position.X, string.unpack("f", string.pack("f", damage)))
            last.SpawnerEntity, last.room = source, source.room
            self.entities[#self.entities + 1] = last
        end
        return last
    end
    function world:damage(target, amount, flags, source)
        room = target.room
        local result = target:TakeDamage(amount, flags or 0, { Entity = source })
        room = nil
        return result
    end
    function world:laser(damage, source, target)
        source, target = source or self.host, target or self.guest
        local laser = entity(7, source.Position.X, damage)
        laser.SpawnerEntity, laser.Timeout, laser.OneHit = source, 600, false
        function laser:IsCircleLaser()
            return self.circle or false
        end
        function laser:GetSamples()
            return {}
        end
        function laser:GetEndPoint()
            return target.Position
        end
        self.entities[#self.entities + 1] = laser
        return laser
    end
    rules.prepare()
    return world
end
