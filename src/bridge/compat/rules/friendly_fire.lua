-- Authority-only PvP contacts. Native damage owns defenses and death; emission
-- pricing and scoped cooldowns preserve rapid hits without delayed damage debt.
return function(deps)
    local native, enums, policy = deps.native, deps.enums, deps.policy
    local flag
    for _, option in ipairs(native.net_room_options()) do
        if option.key == "friendlyFire" then
            flag = option.flag
        end
    end
    assert(flag, "Missing friendly fire rule")
    local run, epoch, owners, actors, credits, previous = nil, nil, {}, {}, {}, {}
    local lastTick, pending, settling = nil, {}, nil
    local function identity(entity)
        return tostring(deps.hash(entity)) .. ":" .. tostring(entity.InitSeed)
    end
    local attacks = deps.attacks({ policy = policy, identity = identity })
    local function invoke(player, amount, flags, source)
        local outer = settling
        settling = { player = identity(player), source = identity(source) }
        local ok, result = pcall(player.TakeDamage, player, amount, flags, deps.ref(source), 0)
        settling = outer
        if not ok then
            error(result, 0)
        end
        return result
    end
    local health = deps.health({ policy = policy, damage = invoke })
    local function reset()
        run, epoch, owners, actors, credits, previous = nil, nil, {}, {}, {}, {}
        lastTick, pending, settling = nil, {}, nil
        attacks.reset()
        health.reset()
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
            local room = positions[tostring(slot)]
            if room and (info.connected & (1 << slot)) ~= 0 then
                local actor = {
                    player = player,
                    id = id,
                    slot = slot,
                    room = tostring(room.dimension) .. ":" .. tostring(room.index),
                }
                actors[#actors + 1] = actor
                owners[deps.hash(player)] = actor
                activeCredits[id] = credits[id]
            end
        end
        credits = activeCredits
        attacks.retain(actors)
        health.retain(actors)
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
    local function protected(actor, tick)
        if not alive(actor.player) then
            return true, true
        end
        return health.protected(actor, tick)
    end
    local function damage(entity, amount, flags, source)
        local info = current()
        if not info then
            return
        end
        local victim, attacker = owners[deps.hash(entity)], owner(source.Entity)
        if not victim then
            return
        end
        if
            settling
            and settling.player == victim.id
            and not settling.notified
            and source.Entity
            and settling.source == identity(source.Entity)
        then
            settling.notified = true
            -- Native modifiers run before this callback. Cap their final
            -- amount, then forward without applying Wafer/floor modifiers twice.
            local limit = health.limit(victim)
            if amount > limit then
                invoke(entity, limit, flags | enums.damage.DAMAGE_NO_MODIFIERS, source.Entity)
                return false
            end
            return
        end
        if
            (flags & enums.damage.DAMAGE_EXPLOSION) ~= 0
            and attacker
            and victim.slot ~= attacker.slot
        then
            if not enabled(info) or deps.paused() then
                return false
            end
            local tick = deps.frame()
            if protected(victim, tick) or not policy.positive(amount) then
                return false
            end
            -- Bombs retain native player units, flags, mitigation and immunity.
            -- Their enemy CollisionDamage must never enter the tear conversion.
            local group =
                attacks.source(source.Entity, attacker, victim.room, tick, "explosion").group
            local spent = group.spent[victim.id] or 0
            local count = math.min(math.floor(amount), health.limit(victim) - spent)
            if count > 0 then
                group.spent[victim.id] = spent + count
                health.apply(
                    victim,
                    count,
                    flags | enums.damage.DAMAGE_NO_MODIFIERS,
                    source.Entity,
                    tick
                )
            end
            return false
        end
        -- External hurt or a defense callback takes ownership of native immunity.
        health.external(victim.id)
        credits[victim.id], pending[victim.id] = nil, nil
    end
    local function hit(actor, entry, tick)
        local id = actor.id
        local blocked, discard = protected(actor, tick)
        if blocked then
            if discard then
                credits[id] = nil
            end
            return false
        end
        local value = entry.entity.CollisionDamage
        if not policy.positive(value) then
            return false
        end
        local credit = credits[id]
        if
            not credit
            or credit.room ~= actor.room
            or tick - credit.at > policy.accumulationGap
            or tick < credit.at
        then
            credit = { amount = 0, room = actor.room }
        end
        local group, limit = entry.group, health.limit(actor)
        local spent = group.spent[id] or 0
        value = math.min(value * entry.scale, math.max(0, limit - spent))
        group.spent[id] = spent + value
        credit.amount, credit.at = credit.amount + value, tick
        credits[id] = credit
        pending[id] = { source = entry.entity, limit = limit }
        return true
    end
    local function flush(actor, tick)
        local request, credit = pending[actor.id], credits[actor.id]
        pending[actor.id] = nil
        if not request or not credit then
            return
        end
        local amount = math.floor(credit.amount + policy.roundingEpsilon)
        if amount == 0 then
            return
        end
        local capped = math.min(amount, request.limit)
        if protected(actor, tick) or not health.apply(actor, capped, 0, request.source, tick) then
            credits[actor.id] = nil
        else
            -- Overflow from a burst cap is discarded; accepted fractional
            -- damage survives ordinary hurt and the short PvP burst protection.
            credit.amount = math.max(0, credit.amount - amount)
        end
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
    local function contacts(entry, targets, tick, room, nextPrevious)
        local entity = entry.entity
        local kind = entity.Type
        local tear = kind == enums.entity.ENTITY_TEAR and entity:ToTear()
        local laser = kind == enums.entity.ENTITY_LASER and entity:ToLaser()
        local knife = kind == enums.entity.ENTITY_KNIFE and entity:ToKnife()
        if not (tear or laser or knife) or entity:IsDead() or entity.CollisionDamage <= 0 then
            return
        end
        local attacker = entry.actor
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
            if actor.slot ~= attacker.slot and alive(actor.player) then
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
            if not last or continuous and tick - last >= policy.continuousInterval then
                state.touches[actor.id] = tick
                if tear and tear:HasTearFlags(enums.tear.TEAR_EXPLOSIVE) then
                    if not protected(actor, tick) then
                        -- Let the native explosion deal its native player damage.
                        tear:Die()
                        break
                    end
                elseif
                    hit(actor, entry, tick)
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
            attacks.reset()
            health.reset()
            lastTick, pending = nil, {}
            return
        end
        local tick, rooms, nextPrevious = deps.frame(), {}, {}
        if tick == lastTick then
            return
        elseif lastTick and tick < lastTick then
            reset()
            prepare()
        end
        lastTick = tick
        for _, actor in ipairs(actors) do
            local _, discard = protected(actor, tick)
            if discard or credits[actor.id] and credits[actor.id].room ~= actor.room then
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
                local entries = {}
                for _, entity in ipairs(deps.entities()) do
                    local kind, attacker = entity.Type, owner(entity)
                    local tear = kind == enums.entity.ENTITY_TEAR and entity:ToTear()
                    local laser = kind == enums.entity.ENTITY_LASER and entity:ToLaser()
                    local knife = kind == enums.entity.ENTITY_KNIFE and entity:ToKnife()
                    if
                        attacker
                        and (tear or laser or knife)
                        and not entity:IsDead()
                        and policy.positive(entity.CollisionDamage)
                    then
                        entries[#entries + 1] = {
                            entity = entity,
                            actor = attacker,
                            damage = entity.CollisionDamage,
                            mode = (knife or laser and not laser.OneHit) and "continuous" or "shot",
                        }
                    end
                end
                attacks.observe(entries, key, tick)
                for _, entry in ipairs(entries) do
                    contacts(entry, room.targets, tick, key, nextPrevious)
                end
                for _, actor in ipairs(room.targets) do
                    flush(actor, tick)
                end
            end)
        end
        previous = nextPrevious
    end
    return { prepare = prepare, step = step, damage = damage, reset = reset }
end
