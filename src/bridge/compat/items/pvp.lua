-- Item triggers select same-room opponents; every damage slice goes through
-- the shared PvP settlement, defenses and burst budget.
return function(deps)
    local policy, collectibles = deps.policy, deps.enums.collectible
    local records, actors, events, uses = {}, {}, {}, {}
    local beforeUse, bindings, casts, beams = {}, {}, {}, {}
    local POISON_DURATION, POISON_INTERVAL = 60, 15
    local POISON_MULTIPLIER, ITEM_LIMIT = 4, 2
    local ROOM_DAMAGE, ITEM_RATE_SECONDS, BEAN_RADIUS = 40, 2, 100
    local SOURCE_GRACE, SKY_BEAMS, SKY_RADIUS = 40, 5, 24
    local function reset()
        records, actors, events, uses = {}, {}, {}, {}
        beforeUse, bindings, casts, beams = {}, {}, {}, {}
    end
    local function opponents(source, radius)
        local result = {}
        for id, actor in pairs(actors) do
            local dx = actor.player.Position.X - source.player.Position.X
            local dy = actor.player.Position.Y - source.player.Position.Y
            if
                actor.slot ~= source.slot
                and actor.room == source.room
                and deps.alive(actor.player)
                and (not radius or dx * dx + dy * dy <= radius * radius)
            then
                result[id] = true
            end
        end
        return result
    end
    local function enqueue(source, tick, damage, poison, radius, group)
        if not policy.positive(damage) then
            return
        end
        local targets = opponents(source, radius)
        if not next(targets) then
            return
        end
        local slices = poison and POISON_DURATION / POISON_INTERVAL or 1
        events[#events + 1] = {
            owner = source.id,
            room = source.room,
            targets = targets,
            next = poison and tick + POISON_INTERVAL or tick,
            expires = poison and tick + POISON_DURATION or tick + 1,
            interval = poison and POISON_INTERVAL or 1,
            remaining = slices,
            entry = {
                damage = damage / slices,
                scale = policy.scale(damage / ITEM_RATE_SECONDS),
                limit = ITEM_LIMIT,
                group = group or { spent = {}, limit = ITEM_LIMIT },
            },
        }
    end
    local function nearest(source, position)
        local target, distance
        for id in pairs(opponents(source)) do
            local actor = actors[id]
            local dx, dy =
                actor.player.Position.X - position.X, actor.player.Position.Y - position.Y
            local squared = dx * dx + dy * dy
            if not distance or squared < distance then
                target, distance = actor, squared
            end
        end
        return target
    end
    return {
        reset = reset,
        disabled = function()
            records, events, casts, beams = {}, {}, {}, {}
            for id, value in pairs(bindings) do
                if not value.entity:Exists() then
                    bindings[id] = nil
                end
            end
        end,
        retain = function(current)
            actors = {}
            local retained = {}
            for _, actor in ipairs(current) do
                actors[actor.id] = actor
                retained[actor.id] = records[actor.id] or { seen = {} }
            end
            records = retained
            for key, value in pairs(uses) do
                if not actors[value.owner] then
                    uses[key] = nil
                end
            end
            for id in pairs(beforeUse) do
                if not actors[id] then
                    beforeUse[id] = nil
                end
            end
        end,
        beforeUse = function(source, item, tick, entities)
            if item ~= collectibles.COLLECTIBLE_MONSTROS_TOOTH then
                return
            end
            local existing = {}
            for _, entity in ipairs(entities) do
                existing[deps.identity(entity)] = true
            end
            beforeUse[source.id] = { at = tick, existing = existing }
        end,
        nativeSource = function(entity)
            return entity and bindings[deps.identity(entity)]
        end,
        actor = function(id)
            return actors[id]
        end,
        use = function(source, item, tick, entities, enabled)
            local key = source.id
            local use = uses[key]
            if not use or use.at ~= tick then
                use = {
                    owner = source.id,
                    at = tick,
                    items = {},
                    group = { spent = {}, limit = ITEM_LIMIT },
                }
                uses[key] = use
            end
            local repeated = use.items[item]
            use.items[item] = true
            if item == collectibles.COLLECTIBLE_MONSTROS_TOOTH then
                local before = beforeUse[source.id]
                beforeUse[source.id] = nil
                if before and tick - before.at <= 1 then
                    for _, entity in ipairs(entities) do
                        local id = deps.identity(entity)
                        if
                            not before.existing[id]
                            and not bindings[id]
                            and entity.Type == deps.enums.entity.ENTITY_EFFECT
                            and entity.Variant == deps.enums.effect.MONSTROS_TOOTH
                        then
                            bindings[id] = {
                                entity = entity,
                                owner = source.id,
                                room = source.room,
                                slot = source.slot,
                                group = use.group,
                            }
                            local target = enabled and nearest(source, source.player.Position)
                            if target then
                                entity.Target = target.player
                                entity.Position = target.player.Position
                            end
                        end
                    end
                end
            end
            if not enabled or repeated then
                return
            end
            if
                item == collectibles.COLLECTIBLE_NECRONOMICON
                or item == collectibles.COLLECTIBLE_BLOOD_RIGHTS
            then
                enqueue(source, tick, ROOM_DAMAGE, false, nil, use.group)
            elseif item == collectibles.COLLECTIBLE_BEAN then
                enqueue(
                    source,
                    tick,
                    source.player.Damage * POISON_MULTIPLIER,
                    true,
                    BEAN_RADIUS,
                    use.group
                )
            elseif item == collectibles.COLLECTIBLE_CRACK_THE_SKY then
                casts[source.id] = { room = source.room, at = tick, group = use.group }
            end
        end,
        step = function(room, tick, entities)
            for id, source in pairs(actors) do
                if source.room == room then
                    local record = records[id]
                    if record.room ~= room then
                        record.room = room
                        if
                            not record.seen[room]
                            and deps.alive(source.player)
                            and source.player:HasCollectible(collectibles.COLLECTIBLE_TOXIC_SHOCK)
                        then
                            enqueue(source, tick, source.player.Damage * POISON_MULTIPLIER, true)
                        end
                        -- Door hopping cannot repeatedly poison the same room.
                        record.seen[room] = true
                    end
                end
            end
            local active = {}
            for _, entity in ipairs(entities) do
                local id = deps.identity(entity)
                active[id] = true
                if
                    entity.Type == deps.enums.entity.ENTITY_EFFECT
                    and entity.Variant == deps.enums.effect.CRACK_THE_SKY
                    and not beams[id]
                    -- Ignore non-damaging initialization phases.
                    and policy.positive(entity.CollisionDamage)
                then
                    local source = deps.owner(entity)
                    local cast = source and casts[source.id]
                    if cast and cast.room == room and tick - cast.at <= SOURCE_GRACE then
                        beams[id] = { room = room, at = tick }
                        local target = nearest(source, entity.Position)
                        if target then
                            entity.Position = target.player.Position
                            local damage = entity.CollisionDamage
                            if policy.positive(damage) then
                                local entry = {
                                    -- The native sky source only damages enemies.
                                    -- Converted player damage uses its owner.
                                    entity = source.player,
                                    damage = damage,
                                    scale = policy.scale(damage * SKY_BEAMS / ITEM_RATE_SECONDS),
                                    limit = ITEM_LIMIT,
                                    group = cast.group,
                                }
                                for otherId in pairs(opponents(source)) do
                                    local other = actors[otherId]
                                    local dx = other.player.Position.X - entity.Position.X
                                    local dy = other.player.Position.Y - entity.Position.Y
                                    local radius = SKY_RADIUS + other.player.Size
                                    if dx * dx + dy * dy <= radius * radius then
                                        deps.hit(other, entry, tick)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            for id, value in pairs(bindings) do
                if not value.entity:Exists() then
                    bindings[id] = nil
                end
            end
            for id, value in pairs(beams) do
                if value.room == room and not active[id] then
                    beams[id] = nil
                end
            end
            for id, value in pairs(casts) do
                if
                    not actors[id]
                    or actors[id].room ~= value.room
                    or tick - value.at > SOURCE_GRACE
                then
                    casts[id] = nil
                end
            end
            local retained = {}
            for _, event in ipairs(events) do
                local source = actors[event.owner]
                if
                    source
                    and source.room == event.room
                    and deps.alive(source.player)
                    and tick <= event.expires
                then
                    for id in pairs(event.targets) do
                        local target = actors[id]
                        if
                            not target
                            or target.room ~= event.room
                            or not deps.alive(target.player)
                        then
                            event.targets[id] = nil
                        end
                    end
                    if event.room == room and tick >= event.next then
                        event.entry.entity = source.player
                        for id in pairs(event.targets) do
                            deps.hit(actors[id], event.entry, tick)
                        end
                        -- Missed/blocked slices never accumulate into a catch-up hit.
                        event.next = tick + event.interval
                        event.remaining = event.remaining - 1
                    end
                    if
                        next(event.targets)
                        and event.remaining > 0
                        and event.next <= event.expires
                    then
                        retained[#retained + 1] = event
                    end
                end
            end
            events = retained
        end,
    }
end
