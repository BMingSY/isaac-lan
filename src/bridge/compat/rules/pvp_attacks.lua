-- Observe emissions, including misses, so accuracy never changes the damage
-- multiplier. Related projectiles share a volley and its per-victim burst cap.
return function(deps)
    local policy = deps.policy
    local sources, groups, streams = {}, {}, {}
    local FAMILIAR_INITIAL_INTERVAL = 30
    local STREAM_IDLE_INTERVALS = 2
    local function reset()
        sources, groups, streams = {}, {}, {}
    end
    local function source(entity, actor, room, tick, mode)
        local id = deps.identity(entity)
        local value = sources[id]
        if value and value.room == room and value.owner == actor.id then
            value.at = tick
            return value
        end
        local parent, spawner = entity.Parent, entity.SpawnerEntity
        local inherited = parent and sources[deps.identity(parent)]
            or spawner and sources[deps.identity(spawner)]
        if inherited and inherited.room == room and inherited.owner == actor.id then
            value = { room = room, owner = actor.id, group = inherited.group }
        else
            local emitter = entity.SpawnerEntity or entity.Parent or actor.player
            local familiar = emitter:ToFamiliar()
            local emitterId = familiar and deps.identity(emitter) or actor.id
            local continuous = mode == "continuous"
            local interval = continuous and policy.continuousInterval
                or familiar and FAMILIAR_INITIAL_INTERVAL
                or math.max(1, actor.player.MaxFireDelay + 1)
            local birth = tick - entity.FrameCount
            local streamId = actor.id .. ":" .. emitterId .. ":" .. mode
            local key = streamId .. ":" .. room .. ":" .. (continuous and "contact" or birth)
            local group = groups[key]
            if not group then
                local stream = streams[streamId]
                if familiar and stream and birth > stream.birth then
                    interval = math.min(stream.interval, birth - stream.birth)
                end
                group = {
                    key = key,
                    streamId = streamId,
                    owner = actor.id,
                    room = room,
                    birth = birth,
                    interval = interval,
                    continuous = continuous,
                    power = 0,
                    spent = {},
                }
                groups[key] = group
            end
            value = { room = room, owner = actor.id, group = group }
        end
        sources[id] = value
        value.at = tick
        return value
    end
    return {
        reset = reset,
        retain = function(actors)
            local active = {}
            for _, actor in ipairs(actors) do
                active[actor.id] = actor.room
            end
            for id, value in pairs(sources) do
                if active[value.owner] ~= value.room then
                    sources[id] = nil
                end
            end
            for id, value in pairs(streams) do
                if active[value.owner] ~= value.room then
                    streams[id] = nil
                end
            end
        end,
        source = source,
        observe = function(entries, room, tick)
            local active, power, rates = {}, {}, {}
            for _, entry in ipairs(entries) do
                local value = source(entry.entity, entry.actor, room, tick, entry.mode)
                local group = value.group
                entry.group = group
                active[deps.identity(entry.entity)] = value
                local damage = entry.damage
                local spawner = entry.entity.SpawnerEntity
                if not group.continuous and not (spawner and spawner:ToFamiliar()) then
                    -- Charged/critical hits retain their multiplier. The normal
                    -- firing stream is priced using the owner's damage stat.
                    damage = math.min(damage, entry.actor.player.Damage)
                end
                power[group] = (power[group] or 0) + damage
                if group.continuous then
                    rates[group] = (rates[group] or 0)
                        + damage * policy.updatesPerSecond / entry.interval
                end
            end
            for group, damage in pairs(power) do
                if group.continuous or group.power == 0 then
                    group.power = damage
                end
                local stream = streams[group.streamId]
                if group.continuous or not stream or group.birth >= stream.birth then
                    streams[group.streamId] = {
                        owner = group.owner,
                        room = room,
                        birth = group.continuous and tick or group.birth,
                        interval = group.interval,
                        dps = rates[group]
                            or group.power * policy.updatesPerSecond / group.interval,
                    }
                end
                if
                    group.continuous and (not group.at or tick - group.at >= policy.burstProtection)
                then
                    group.spent, group.at = {}, tick
                end
            end
            local totals = {}
            for key, stream in pairs(streams) do
                if
                    tick < stream.birth
                    or tick - stream.birth
                        > math.max(policy.accumulationGap, stream.interval * STREAM_IDLE_INTERVALS)
                then
                    streams[key] = nil
                elseif stream.room == room then
                    totals[stream.owner] = (totals[stream.owner] or 0) + stream.dps
                end
            end
            for _, entry in ipairs(entries) do
                local group = entry.group
                if group.continuous or not group.scale then
                    group.scale = policy.scale(
                        totals[entry.actor.id]
                            or group.power * policy.updatesPerSecond / group.interval
                    )
                end
                entry.scale = group.scale
            end
            for id, value in pairs(sources) do
                if
                    value.room == room
                    and not active[id]
                    and tick - value.at > policy.accumulationGap
                then
                    sources[id] = nil
                end
            end
            local retained = {}
            for _, value in pairs(sources) do
                retained[value.group.key] = value.group
            end
            groups = retained
        end,
    }
end
