-- The authority keeps every entity. Only stock, non-colliding blood effects
-- with no incoming gameplay reference may lose their drawing on a busy peer.
return function(fields)
    local E, A, S = fields.entity, fields.actor, fields.sprite
    local denseRoom, minimumBlood, lowBudget, normalBudget = 64, 24, 4, 12
    local particleFile = "gfx/1000.005_Blood Particle.anm2"
    local explosionFile = "gfx/1000.002_Blood Explosion.anm2"
    local bloodAnimations =
        { Particle = true, BloodGib01 = true, BloodGib02 = true, BloodGib03 = true }
    return function(types, variants, noCollision)
        local peers = {}
        local function eligible(entity, row)
            if row[E.type] ~= types.ENTITY_EFFECT then
                return false
            end
            local variant, sub, sprite = row[E.variant], row[E.subtype], row[E.sprite]
            if
                not sprite
                or not (
                    variant == variants.BLOOD_PARTICLE
                        and (sub == 0 or sub == 99)
                        and sprite[S.path] == particleFile
                        and bloodAnimations[sprite[S.animation]]
                    or variant == variants.BLOOD_EXPLOSION
                        and sub == 2
                        and sprite[S.path] == explosionFile
                        and sprite[S.animation] == "Poof"
                )
            then
                return false
            end
            return entity.EntityCollisionClass == noCollision and entity.CollisionDamage == 0
        end
        local function project(rows, actors, candidates, slot, epoch, location, tick, detailBudget)
            if not candidates then
                peers[slot] = nil
                return rows
            end
            local old = peers[slot]
            local prior = old
                    and old.epoch == epoch
                    and old.index == location.index
                    and old.dimension == location.dimension
                    and old.tick <= tick
                    and old.seen
                or {}
            local seen, queue, selected, count = {}, {}, 0, 0
            local function remember()
                peers[slot] = {
                    epoch = epoch,
                    index = location.index,
                    dimension = location.dimension,
                    tick = tick,
                    seen = seen,
                }
            end
            local function complete()
                for id in pairs(candidates) do
                    seen[id] = true
                end
                remember()
                return rows
            end
            if #rows < denseRoom and not next(prior) then
                return complete()
            end
            local function retain(id)
                if candidates[id] and not seen[id] then
                    seen[id] = true
                    queue[#queue + 1] = candidates[id]
                    selected = selected + 1
                end
            end
            local function links(r)
                retain(r[E.parent])
                retain(r[E.spawner])
                retain(r[E.child])
                retain(r[E.target])
                retain(r[E.minecart])
                retain(r[E.held])
            end
            local function opaque(r)
                return r[E.compatibility] or r[E.tether]
            end
            -- Compatibility payloads can contain their own attachment IDs.
            for _, actor in ipairs(actors) do
                local r = actor[A.entity]
                if opaque(r) then
                    return complete()
                end
                links(r)
            end
            for _, r in ipairs(rows) do
                if opaque(r) then
                    return complete()
                end
                local id = r[E.id]
                if not candidates[id] then
                    links(r)
                else
                    count = count + 1
                    local parent, spawner = r[E.parent] or 0, r[E.spawner] or 0
                    if
                        prior[id]
                        or parent ~= 0 and not candidates[parent]
                        or spawner ~= 0 and not candidates[spawner]
                    then
                        retain(id)
                    end
                end
            end
            local dense = #rows >= denseRoom and count >= minimumBlood
            local budget = dense
                    and (detailBudget and detailBudget > 0 and normalBudget or lowBudget)
                or #rows
            local cursor = 1
            local function keepDependencies()
                while cursor <= #queue do
                    links(queue[cursor])
                    cursor = cursor + 1
                end
            end
            keepDependencies()
            local result = {}
            for _, r in ipairs(rows) do
                local id = r[E.id]
                if candidates[id] and seen[id] == nil then
                    if selected < budget and prior[id] ~= false then
                        retain(id)
                        keepDependencies()
                    else
                        seen[id] = false
                    end
                end
            end
            for _, r in ipairs(rows) do
                if seen[r[E.id]] ~= false then
                    result[#result + 1] = r
                end
            end
            remember()
            return #result == #rows and rows or result
        end
        return {
            eligible = eligible,
            project = project,
            reset = function()
                peers = {}
            end,
        }
    end
end
