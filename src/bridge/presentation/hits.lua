-- Presentation for confirmed NPC impacts and locally predicted ordinary tears.
-- Collision tests never call TakeDamage, Kill, Update, or random-number APIs.
return function(fields)
    local A, E, R, L = fields.actor, fields.entity, fields.room, fields.location
    return function(deps)
        local ledger = deps.ledger()
        local shots, targets, scope, epoch, received = {}, {}, nil, nil, nil
        local function restore(ref)
            for id, shot in pairs(shots) do
                local e = ref(id)
                if e and shot.hidden then
                    e.Visible = shot.visible
                    shot.hidden = nil
                end
            end
        end
        local function clear(resetSequence)
            shots, targets, scope, received = {}, {}, nil, nil
            ledger.clear(resetSequence)
            assert(deps.native.combat_present())
        end
        local function confirm(value, tick, now, ref)
            local location
            for _, item in ipairs(value.locations) do
                if item[L.slot] == value.slot then
                    location = item
                    break
                end
            end
            assert(location, "Missing combat view location")
            local nextScope = value.epoch
                .. ":"
                .. location[L.dimension]
                .. ":"
                .. location[L.index]
            if scope ~= nextScope then
                restore(ref)
                clear(epoch ~= value.epoch)
                scope, epoch = nextScope, value.epoch
            end
            received = now
            local owners = {}
            for _, actor in ipairs(value.actors) do
                if actor[A.controller] == value.slot + 1 then
                    owners[actor[A.entity][E.id]] = true
                end
            end
            local nextShots, nextTargets = {}, {}
            for _, v in ipairs(value.room[R.entities]) do
                local id, e = v[E.id], ref(v[E.id])
                if e then
                    if v[E.combat] == fields.combat.target then
                        nextTargets[id] = targets[id] or {}
                    elseif v[E.combat] == fields.combat.projectile and owners[v[E.spawner]] then
                        local shot = shots[id]
                            or { last = deps.vector(table.unpack(v[E.position])) }
                        shot.visible, shot.hidden = e.Visible, nil
                        nextShots[id] = shot
                    end
                end
            end
            shots, targets = nextShots, nextTargets
            for _, event in ipairs(deps.decode(value.combat)) do
                if
                    event.epoch == value.epoch
                    and event.dimension == location[L.dimension]
                    and event.room == location[L.index]
                    and event.tick <= tick
                then
                    -- An exact authority source/target pair confirms the local
                    -- contact; transport repetition never replays its effect.
                    ledger.confirm(event, now, (tick - event.tick) / 30)
                else
                    ledger.observe(event.serial)
                end
            end
            for name, count in pairs(ledger.counts) do
                deps.metrics.counter("hit." .. name, count)
            end
        end
        local function present(_, ref, now, _, _, status)
            assert(deps.native.combat_present())
            restore(ref)
            if not received or now - received > 0.25 or status.pause ~= 0 then
                clear(false)
                return
            end
            local room = deps.room()
            for id, shot in pairs(shots) do
                local e = ref(id)
                if e and not shot.used then
                    local position = e.Position
                    local tear = e:ToTear()
                    if tear and tear.Height < -5 and e.Visible then
                        local hit, first = nil, math.huge
                        for target, history in pairs(targets) do
                            local enemy = ref(target)
                            if enemy and enemy.Visible and not enemy:IsDead() then
                                local old = history.last or enemy.Position
                                local t = deps.contact(
                                    shot.last.X - old.X,
                                    shot.last.Y - old.Y,
                                    position.X - enemy.Position.X,
                                    position.Y - enemy.Position.Y,
                                    e.Size + enemy.Size
                                )
                                if t and t < first then
                                    hit, first = target, t
                                end
                            end
                        end
                        if hit and room:CheckLine(shot.last, position, 0, 0, false, false) then
                            local frames = math.max(
                                1,
                                math.min(
                                    6,
                                    math.floor((math.floor(e.CollisionDamage + 0.5) + 2) / 3)
                                )
                            )
                            ledger.predict(id, hit, now, frames / 30)
                            shot.used = true
                        end
                    end
                    shot.last = deps.vector(position.X, position.Y)
                end
            end
            for id, history in pairs(targets) do
                local e = ref(id)
                if e then
                    history.last = deps.vector(e.Position.X, e.Position.Y)
                end
            end
            local active, hidden = ledger.sample(now)
            for id in pairs(active) do
                local e = ref(id)
                if e and e:Exists() and not e:IsDead() then
                    assert(deps.native.combat_present(e:GetSprite()))
                end
            end
            for id in pairs(hidden) do
                local e, shot = ref(id), shots[id]
                if e and shot then
                    shot.hidden = true
                    e.Visible = false
                end
            end
        end
        return {
            confirm = confirm,
            present = present,
            reset = clear,
            validate = deps.decode,
            suspend = function(ref)
                restore(ref)
                clear(false)
            end,
        }
    end
end
