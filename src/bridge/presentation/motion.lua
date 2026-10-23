return function(fields)
    local Actor = fields.actor
    local Entity = fields.entity
    local MAX_EXTRAPOLATION = 0.1
    local TELEPORT_DISTANCE = 96
    local CORRECTION_TIME, BRAKING_CORRECTION_TIME = 1 / 30, 1 / 60
    local BRAKING_SPEED_RATIO = 0.85
    local BRAKING_ALIGNMENT = math.cos(math.rad(1))
    local MIN_BRAKING_SPEED = 1
    local walkingExtras = { Pickup = true, UseItem = true, LiftItem = true, HideItem = true }
    local function actionAllowsMovement(player, actor)
        if player:IsCoopGhost() then
            return false
        end
        local body = player:GetSprite():GetAnimation()
        local extra = actor[Actor.visuals][fields.actorSprites.extra]
        local animation = extra and extra[fields.sprite.animation]
        -- These split head/item poses leave native walking enabled, including
        -- the first frames before Walk changes to PickupWalk. Pill reactions
        -- and ordinary damage reactions also animate the body without
        -- consuming movement input. Hit is not a control lock: authority
        -- continues walking and knockback while the hurt sprite is playing.
        return walkingExtras[animation] and (body:match("^Walk") or body:match("^PickupWalk"))
            or (animation == "" and (body == "Happy" or body == "Sad" or body == "Hit"))
    end
    -- Render-only movement and interpolation; authority remains on the host.
    return function(native, actorsPresentation, view)
        local Vector = view.vector
        local lastRender, captured
        local corrections, correctionTotal, correctionMax = 0, 0, 0
        local buckets = { 0, 0, 0, 0, 0 }
        local limits = { 1, 4, 16, 64, math.huge }
        local function travelTime(age, damping)
            local travel = math.min(math.max(0, age), MAX_EXTRAPOLATION)
            return damping > 0 and (1 - math.exp(-damping * travel)) / damping or travel
        end
        local function coordinates(track, now)
            local age = math.max(0, now - track.at)
            local travel = travelTime(age, track.damping)
            local decay =
                math.exp(-math.max(0, now - (track.received or track.at)) / track.correctionTime)
            return track.x + track.vx * travel + track.cx * decay,
                track.y + track.vy * travel + track.cy * decay
        end
        local function sample(track, now)
            if track.stationary then
                return track.target
            end
            return Vector(coordinates(track, now))
        end
        local function track(prior, position, velocity, now, tick, rate, npc)
            if prior and tick <= prior.tick then
                return prior
            end
            local x, y = position.X, position.Y
            local vx, vy = velocity.X * (rate or 1), velocity.Y * (rate or 1)
            local at = captured or now
            local damping, braking = 0, false
            if npc and prior and prior.npc then
                local interval = (tick - prior.tick) / (rate or 1)
                local previousSpeed = math.sqrt(prior.vx * prior.vx + prior.vy * prior.vy)
                local speed = math.sqrt(vx * vx + vy * vy)
                local dx, dy = x - prior.x, y - prior.y
                if interval <= MAX_EXTRAPOLATION and dx * dx + dy * dy < TELEPORT_DISTANCE ^ 2 then
                    braking = speed == 0 and previousSpeed > MIN_BRAKING_SPEED
                    -- Infer only clear, straight-line braking from authority.
                    -- Turns and acceleration retain the latest velocity; guessing
                    -- their future would invent a pursuit target or a curved path.
                    if
                        speed > MIN_BRAKING_SPEED
                        and speed < previousSpeed
                        and (speed / previousSpeed) ^ (1 / (tick - prior.tick)) < BRAKING_SPEED_RATIO
                        and vx * prior.vx + vy * prior.vy
                            >= BRAKING_ALIGNMENT * speed * previousSpeed
                    then
                        damping = -math.log(speed / previousSpeed) / interval
                        braking = true
                    end
                end
            end
            local travel = travelTime(now - at, damping)
            local cx, cy = 0, 0
            if prior then
                local px, py = coordinates(prior, now)
                cx, cy = px - (x + vx * travel), py - (y + vy * travel)
                if cx * cx + cy * cy >= TELEPORT_DISTANCE ^ 2 then
                    cx, cy = 0, 0
                    damping, braking = 0, false
                end
            end
            local result = prior or {}
            result.target, result.at, result.tick, result.received = position, at, tick, now
            result.x, result.y, result.cx, result.cy = x, y, cx, cy
            result.vx, result.vy = vx, vy
            result.npc, result.damping = npc, damping
            result.correctionTime = braking and BRAKING_CORRECTION_TIME or CORRECTION_TIME
            result.stationary = result.vx == 0 and result.vy == 0 and cx == 0 and cy == 0
            return result
        end
        local outwardDirections = { Vector(-1, 0), Vector(0, -1), Vector(1, 0), Vector(0, 1) }
        local function doorCorridor(room, position)
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door:IsOpen() then
                    local outward = outwardDirections[slot % 4 + 1]
                    local delta = door.Position - position
                    local along = delta:Dot(outward)
                    local across = math.abs(delta.X * outward.Y - delta.Y * outward.X)
                    if along < 64 and along > -24 and across < 16 then
                        return slot, outward, along
                    end
                end
            end
        end
        local function clearForPlayer(room, position, aperture, flying)
            local collision = room:GetGridCollisionAtPos(position)
            return collision == GridCollisionClass.COLLISION_NONE
                or collision == GridCollisionClass.COLLISION_WALL_EXCEPT_PLAYER
                or (flying and (collision == GridCollisionClass.COLLISION_PIT or collision == GridCollisionClass.COLLISION_OBJECT or collision == GridCollisionClass.COLLISION_SOLID))
                or (aperture and collision == GridCollisionClass.COLLISION_WALL)
        end
        local footprint = {
            { 1, 0 },
            { -1, 0 },
            { 0, 1 },
            { 0, -1 },
            { 0.7071, 0.7071 },
            { -0.7071, 0.7071 },
            { 0.7071, -0.7071 },
            { -0.7071, -0.7071 },
        }
        local maxSweepStep, maxSweepDistance = 4, 256
        local function sweep(room, from, wanted, radius, flying, controls, authority)
            local function clear(position)
                local aperture = controls and doorCorridor(room, position) ~= nil
                if not clearForPlayer(room, position, aperture, flying) then
                    return false
                end
                for _, offset in ipairs(footprint) do
                    if
                        not clearForPlayer(
                            room,
                            position + Vector(offset[1] * radius, offset[2] * radius),
                            aperture,
                            flying
                        )
                    then
                        return false
                    end
                end
                return true
            end
            -- A native arrival, changed grid or conservative footprint can leave
            -- the old display overlapping a wall. Sweeping every correction from
            -- that invalid origin would reject every subsequent step forever.
            -- Only reconciliation may recover from the host's accepted position;
            -- ordinary prediction still sweeps every local movement segment.
            if authority and not clear(from) then
                from = authority
                if not clear(from) then
                    return authority
                end
            end
            local aperture = controls and doorCorridor(room, wanted) ~= nil
            if not aperture then
                wanted = room:GetClampedPosition(wanted, radius)
            end
            local delta = wanted - from
            local distance = math.max(math.abs(delta.X), math.abs(delta.Y))
            if distance > maxSweepDistance then
                delta = delta * (maxSweepDistance / distance)
                distance = maxSweepDistance
            end
            local steps = math.max(1, math.ceil(distance / maxSweepStep))
            local increment = delta * (1 / steps)
            local position = from
            for _ = 1, steps do
                local nextPosition = position + increment
                if clear(nextPosition) then
                    position = nextPosition
                else
                    local x = Vector(nextPosition.X, position.Y)
                    local y = Vector(position.X, nextPosition.Y)
                    if clear(x) then
                        position = x
                    elseif clear(y) then
                        position = y
                    end
                end
            end
            return position
        end
        local function present(input, sequence, actorVisuals, motion, ref, receivedTick)
            if receivedTick < 0 then
                return
            end
            -- Native room and Mod presentation updates run after receiving a packet.
            -- Reassert authoritative actor poses at the render boundary so local
            -- callbacks cannot replace a body or start an unrelated dance.
            local extraAnimationMovement, actorByID = {}, {}
            for _, actor in ipairs(actorVisuals) do
                local p = view.player(actor[Actor.index])
                if p and p.ControllerIndex == actor[Actor.controller] then
                    actorsPresentation.apply(p, actor)
                    actorByID[actor[Actor.entity][Entity.id]] = actor
                    extraAnimationMovement[actor[Actor.entity][Entity.id]] =
                        actionAllowsMovement(p, actor)
                end
            end
            local now = view.clock() / 1000
            local dt = lastRender and math.max(0, math.min(now - lastRender, 0.05)) or 0
            lastRender = now
            local status = view.status()
            if status.pause ~= 0 then
                if view.doors then
                    view.doors.reset()
                end
                if view.attacks then
                    view.attacks.reset()
                end
                -- Paused snapshots retain native velocities. Do not accumulate
                -- an invisible extrapolation error and release it on resume.
                for _, m in pairs(motion) do
                    m.track.target, m.track.at = m.target, now
                    m.track.x, m.track.y = m.target.X, m.target.Y
                    m.track.vx, m.track.vy, m.track.cx, m.track.cy = 0, 0, 0, 0
                    m.track.stationary = true
                end
                return
            end
            for identifier, m in pairs(motion) do
                local e = ref(identifier)
                if e then
                    local position
                    local predict = m.actor and m.controller == status.slot + 1
                    if predict and view.predictMovement then
                        assert(native.rooms_with_player(status.slot, function()
                            predict = view.predictMovement(e:ToPlayer(), view.room())
                        end))
                    end
                    if predict then
                        local p = e:ToPlayer()
                        local controls = p.ControlsEnabled
                            and p:AreControlsEnabled()
                            and (p:IsExtraAnimationFinished() or extraAnimationMovement[identifier])
                            and not (view.doors and view.doors.movementBlocked())
                        local direction = Vector(0, 0)
                        if controls then
                            assert(native.rooms_with_player(status.slot, function()
                                -- The render scope supplies the same preview input
                                -- to the native query, including drop and mirror rules.
                                direction = p:GetMovementInput()
                            end))
                            if direction:Length() > 1 then
                                direction = direction:Normalized()
                            end
                        end
                        if not controls then
                            if m.doorway and view.doors then
                                view.doors.cancel()
                            end
                            m.doorway = nil
                        end
                        assert(native.rooms_with_player(status.slot, function()
                            local room = view.room()
                            local radius = math.max(5, e.Size)
                            local function resolve(from, wanted, authority)
                                return sweep(
                                    room,
                                    from,
                                    wanted,
                                    radius,
                                    p.CanFly or p:IsCoopGhost(),
                                    controls,
                                    authority
                                )
                            end
                            position = m.prediction:step(
                                controls and direction or Vector(0, 0),
                                sequence,
                                p.MoveSpeed,
                                dt,
                                not controls,
                                resolve,
                                p.Friction
                            )
                            if m.doorway then
                                local door = room:GetDoor(m.doorway.slot)
                                if
                                    not door
                                    or not door:IsOpen()
                                    or direction:Dot(m.doorway.outward) <= 0
                                    or now - m.doorway.at > 0.5
                                then
                                    m.doorway = nil
                                    if view.doors then
                                        view.doors.cancel()
                                    end
                                end
                            end
                            local slot, outward, along = doorCorridor(room, position)
                            local aperture = controls and slot ~= nil
                            if
                                aperture
                                and not m.doorway
                                and direction:Dot(outward) > 0
                                and along < 18
                            then
                                m.doorway = {
                                    slot = slot,
                                    outward = outward,
                                    at = now,
                                    position = position,
                                }
                                if view.doors then
                                    view.doors.begin()
                                end
                            end
                            if m.doorway then
                                -- Await the host's room commit at the doorway. Do not
                                -- extrapolate a source-room walk into the destination.
                                position = m.doorway.position
                                m.prediction.velocity = Vector(0, 0)
                            end
                            position = resolve(
                                m.prediction.teleported and m.prediction.base or m.display,
                                position,
                                m.target
                            )
                            m.prediction.teleported = false
                        end))
                        m.prediction:clip(position)
                        if actorsPresentation.walk and actorByID[identifier] then
                            actorsPresentation.walk(
                                p,
                                actorByID[identifier],
                                m,
                                direction,
                                dt,
                                controls
                            )
                        end
                        if view.metrics and view.metrics.enabled and m.prediction.errorSquared then
                            local error = math.sqrt(m.prediction.errorSquared)
                            corrections = corrections + 1
                            correctionTotal = correctionTotal + error
                            correctionMax = math.max(correctionMax, error)
                            for index, limit in ipairs(limits) do
                                if error <= limit then
                                    buckets[index] = buckets[index] + 1
                                    view.metrics.counter(
                                        "prediction.bucket" .. index,
                                        buckets[index]
                                    )
                                    break
                                end
                            end
                            view.metrics.counter("prediction.corrections", corrections)
                            view.metrics.counter(
                                "prediction.sum_millipixels",
                                math.floor(correctionTotal * 1000)
                            )
                            view.metrics.counter(
                                "prediction.max_millipixels",
                                math.floor(correctionMax * 1000)
                            )
                        end
                    else
                        if m.prediction then
                            -- Drop walking offsets when this body stops accepting
                            -- walking input. Retain the real acknowledgement so a
                            -- later form cannot replay another body's pending path.
                            m.prediction:reset(m.target, m.prediction.acknowledged, m.velocity * 60)
                            m.doorway = nil
                            m.walk = nil
                        end
                        -- Continue from the same display trajectory across packet
                        -- gaps. Only the authority error is smoothed, without a
                        -- compulsory extra snapshot of interpolation delay.
                        position = sample(m.track, now)
                    end
                    m.display = position
                    e.Position = position
                end
            end
            if view.attachments then
                view.attachments.present(motion, ref)
            end
            if view.attacks then
                view.attacks.present(motion, ref, now, dt, sequence, status)
            end
        end
        return {
            track = track,
            sample = sample,
            present = present,
            observe = function(sourceMs, now)
                if view.timeline then
                    local status = view.status()
                    captured = view.timeline.observe(
                        sourceMs,
                        now,
                        status.slot and status["ping" .. status.slot]
                    )
                    if view.metrics and view.metrics.enabled then
                        view.metrics.sample("view.age", math.max(0, now - captured) * 1000)
                    end
                end
            end,
            reset = function(clearMetrics)
                lastRender, captured = nil, nil
                if view.doors then
                    if clearMetrics then
                        view.doors.reset()
                    else
                        view.doors.arrive()
                    end
                end
                if view.attacks then
                    view.attacks.reset()
                end
                if clearMetrics then
                    corrections, correctionTotal, correctionMax = 0, 0, 0
                    buckets = { 0, 0, 0, 0, 0 }
                end
                if view.timeline then
                    view.timeline.reset()
                end
            end,
        }
    end
end
