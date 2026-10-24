-- Authority-only contacts. Native player damage owns defenses, hurt animation,
-- invulnerability and death; an ignored contact never becomes delayed damage.
return function(deps)
    local native, enums = deps.native, deps.enums
    local DAMAGE_PER_HALF_HEART = 3.5
    local ACCUMULATION_GAP = 30 -- simulation updates, one second
    local CONTINUOUS_HIT_INTERVAL = 2 -- native laser damage cadence, in simulation updates
    local ROUNDING_EPSILON = 1e-6 -- CollisionDamage is native float32, Lua numbers are doubles.
    local flag
    for _, option in ipairs(native.net_room_options()) do
        if option.key == "friendlyFire" then
            flag = option.flag
        end
    end
    assert(flag, "Missing friendly fire rule")
    local run, epoch, owners, actors, credits, previous = nil, nil, {}, {}, {}, {}
    local function identity(entity)
        return tostring(deps.hash(entity)) .. ":" .. tostring(entity.InitSeed)
    end
    local function reset()
        run, epoch, owners, actors, credits, previous = nil, nil, {}, {}, {}, {}
    end
    local function current()
        local info = native.api_info()
        if info.active ~= 1 or info.authority ~= 1 or info.ready ~= 1 then
            reset()
            return
        end
        if run ~= info.runId or epoch ~= info.worldEpoch then
            reset()
            run, epoch = info.runId, info.worldEpoch
        end
        return info
    end
    local function enabled(info)
        return (info.roomOptions & flag) ~= 0
    end
    local function prepare()
        local info = current()
        if not info then
            return
        end
        owners, actors = {}, {}
        local activeCredits = {}
        local positions = native.rooms_positions()
        for _, actor in ipairs(native.api_actors()) do
            local player = deps.player(actor.index)
            local slot, id = actor.owner - 1, identity(player)
            owners[deps.hash(player)] = slot
            local room = positions[tostring(slot)]
            if room and (info.connected & (1 << slot)) ~= 0 then
                actors[#actors + 1] = {
                    player = player,
                    id = id,
                    slot = slot,
                    room = tostring(room.dimension) .. ":" .. tostring(room.index),
                }
                activeCredits[id] = credits[id]
            end
        end
        credits = activeCredits
        return info
    end
    local function owner(entity, visited)
        if not entity then
            return
        end
        local id = deps.hash(entity)
        if owners[id] ~= nil then
            return owners[id]
        end
        visited = visited or {}
        if visited[id] then
            return
        end
        visited[id] = true
        local familiar = entity:ToFamiliar()
        return owner(familiar and familiar.Player, visited)
            or owner(entity.SpawnerEntity, visited)
            or owner(entity.Parent, visited)
    end
    local function alive(player)
        return player:Exists() and not player:IsDead() and not player:IsCoopGhost()
    end
    local function protected(player)
        return not alive(player) or player:GetDamageCooldown() > 0 or player:IsInvincible()
    end
    local function damage(entity, _, flags, source)
        local info = current()
        if not info or (flags & enums.damage.DAMAGE_EXPLOSION) == 0 then
            return
        end
        local victim, attacker = owners[deps.hash(entity)], owner(source.Entity)
        if victim ~= nil and attacker ~= nil and victim ~= attacker then
            credits[identity(entity)] = nil
            if not enabled(info) then
                return false
            end
            -- Native explosions already use player damage units. Never convert
            -- their enemy damage, and leave self/environmental damage alone.
        end
    end
    local function hit(actor, source, tick)
        local player, id = actor.player, actor.id
        if protected(player) then
            credits[id] = nil
            return false
        end
        local value = source.CollisionDamage
        if not value or value <= 0 or value ~= value or value == math.huge then
            return false
        end
        local credit = credits[id]
        if
            not credit
            or credit.room ~= actor.room
            or tick - credit.at > ACCUMULATION_GAP
            or tick < credit.at
        then
            credit = { amount = 0, room = actor.room }
        end
        credit.amount, credit.at = credit.amount + value, tick
        local amount = math.floor(credit.amount / DAMAGE_PER_HALF_HEART + ROUNDING_EPSILON)
        if amount > 0 then
            credits[id] = nil
            player:TakeDamage(amount, 0, deps.ref(source), 0)
        else
            credits[id] = credit
        end
        return true
    end
    local function segment(a, b, position, radius)
        return deps.contact(
            a.X - position.X,
            a.Y - position.Y,
            b.X - position.X,
            b.Y - position.Y,
            radius
        )
    end
    local function laserContact(laser, player)
        if laser.Timeout <= 0 then
            return nil
        end
        local radius = player.Size + laser.Size
        if laser:IsCircleLaser() then
            local dx, dy =
                laser.Position.X - player.Position.X, laser.Position.Y - player.Position.Y
            return math.abs(math.sqrt(dx * dx + dy * dy) - laser.Radius) <= radius and 0 or nil
        end
        local samples = laser:GetSamples()
        if #samples >= 2 then
            for i = 1, #samples - 1 do
                local contact = segment(samples:Get(i - 1), samples:Get(i), player.Position, radius)
                if contact then
                    return contact
                end
            end
        else
            return segment(laser.Position, laser:GetEndPoint(), player.Position, radius)
        end
    end
    local function contacts(entity, targets, tick, room, nextPrevious)
        local kind = entity.Type
        local tear = kind == enums.entity.ENTITY_TEAR and entity:ToTear()
        local laser = kind == enums.entity.ENTITY_LASER and entity:ToLaser()
        local knife = kind == enums.entity.ENTITY_KNIFE and entity:ToKnife()
        if not (tear or laser or knife) or entity:IsDead() or entity.CollisionDamage <= 0 then
            return
        end
        local attacker = owner(entity)
        if attacker == nil then
            return
        end
        local key = identity(entity)
        local old = previous[key]
        if old and old.room ~= room then
            old = nil
        end
        local position = entity.Position
        local start = old
            or { x = position.X - entity.Velocity.X, y = position.Y - entity.Velocity.Y }
        local state = { x = position.X, y = position.Y, room = room, touches = {} }
        nextPrevious[key] = state
        local candidates = {}
        for _, actor in ipairs(targets) do
            if actor.slot ~= attacker and alive(actor.player) then
                local player = actor.player
                local contact
                if laser then
                    contact = laserContact(laser, player)
                else
                    contact = deps.contact(
                        start.x - player.Position.X + player.Velocity.X,
                        start.y - player.Position.Y + player.Velocity.Y,
                        position.X - player.Position.X,
                        position.Y - player.Position.Y,
                        entity.Size + player.Size
                    )
                end
                if contact then
                    candidates[#candidates + 1] = { actor = actor, distance = contact }
                end
            end
        end
        table.sort(candidates, function(a, b)
            return a.distance < b.distance
        end)
        for _, candidate in ipairs(candidates) do
            local actor = candidate.actor
            local last = old and old.touches[actor.id]
            state.touches[actor.id] = last or tick
            local continuous = knife or laser and not laser.OneHit
            if not last or continuous and tick - last >= CONTINUOUS_HIT_INTERVAL then
                state.touches[actor.id] = tick
                if tear and tear:HasTearFlags(enums.tear.TEAR_EXPLOSIVE) then
                    if not protected(actor.player) then
                        -- Let the native explosion deal its native player damage.
                        tear:Die()
                        break
                    end
                elseif
                    hit(actor, entity, tick)
                    and tear
                    and not tear:HasTearFlags(enums.tear.TEAR_PIERCING)
                then
                    tear:Die()
                    break
                end
            end
        end
    end
    local function step()
        local info = prepare()
        if not info then
            return
        end
        if deps.paused() then
            return
        end
        if not enabled(info) then
            credits, previous = {}, {}
            return
        end
        local tick, rooms, nextPrevious = deps.frame(), {}, {}
        for _, actor in ipairs(actors) do
            if
                protected(actor.player)
                or credits[actor.id] and credits[actor.id].room ~= actor.room
            then
                credits[actor.id] = nil
            end
            local room = rooms[actor.room]
            if not room then
                room = { slot = actor.slot, targets = {} }
                rooms[actor.room] = room
            end
            room.targets[#room.targets + 1] = actor
        end
        for key, room in pairs(rooms) do
            native.rooms_with_player(room.slot, function()
                for _, entity in ipairs(deps.entities()) do
                    contacts(entity, room.targets, tick, key, nextPrevious)
                end
            end)
        end
        previous = nextPrevious
    end
    return { prepare = prepare, step = step, damage = damage, reset = reset }
end
