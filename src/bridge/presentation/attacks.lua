-- Local aiming, charge clocks and short-lived tear drawings. No entities are spawned.
return function(fields)
    local A, E, R, I = fields.actor, fields.entity, fields.room, fields.inventory
    local staleAfter, handoffTime, projectileLine = 0.25, 0.06, 0
    local maxPreviews, axisTolerance = 32, 0.001
    local simulationRate, birthHistoryTicks = 30, 30
    local inputLookahead, matchDirection = 1, 0.95
    local eyeOffset, playerVelocityRate, maxCorrectionFraction = 4, 60, 0.25
    local minimumLifetime, confirmationMargin, minimumShotSpacing = 0.12, 0.1, 0.5
    local mouthFrame, mouthDuration, handoffCutoff = 2, 0.1, 3
    local groundHeight = -5
    local headNames = { left = "HeadLeft", right = "HeadRight", up = "HeadUp", down = "HeadDown" }
    return function(deps)
        local Vector, native, pose, trajectory =
            deps.vector, deps.native, deps.pose, deps.trajectory
        local states, previews, handoffs, seen = {}, {}, {}, {}
        local lastTick, lastReceived, serial = -1, nil, 0
        local started, confirmed, expired, timedOut, gridStops, landed = 0, 0, 0, 0, 0, 0
        local function measure()
            if deps.metrics then
                deps.metrics.counter("attack.previews", started)
                deps.metrics.counter("attack.confirmed", confirmed)
                deps.metrics.counter("attack.expired", expired)
                deps.metrics.counter("attack.pending", #previews)
                deps.metrics.counter("attack.timed_out", timedOut)
                deps.metrics.counter("attack.grid_stops", gridStops)
                deps.metrics.counter("attack.landed", landed)
            end
        end
        local function clear()
            states, previews, handoffs, seen = {}, {}, {}, {}
            lastTick, lastReceived = -1, nil
            measure()
        end
        local function cancel(id)
            for index = #previews, 1, -1 do
                if previews[index].owner == id then
                    table.remove(previews, index)
                end
            end
        end
        local function position(shot, now)
            return trajectory.sample(shot, now)
        end
        local function confirm(value, tick, ack, now, ref)
            if tick <= lastTick then
                return
            end
            lastTick, lastReceived = tick, now
            local retained = {}
            for _, actor in ipairs(value.actors) do
                if actor[A.controller] == value.slot + 1 and actor[A.pose] then
                    local id = actor[A.entity][E.id]
                    local player = deps.player(actor[A.index])
                    local weapons = pose.read(actor[A.pose])
                    local signature = deps.encode(actor[A.inventory][I.items])
                        .. ":"
                        .. actor[A.inventory][I.type]
                        .. ":"
                        .. player.Damage
                        .. ":"
                        .. player.ShotSpeed
                        .. ":"
                        .. player.MaxFireDelay
                        .. ":"
                        .. player.TearRange
                        .. ":"
                        .. player.TearHeight
                        .. ":"
                        .. player.TearFallingSpeed
                        .. ":"
                        .. player.TearFallingAcceleration
                    for slot = 1, pose.slotCount do
                        local weapon = weapons[slot]
                        signature = signature .. ":" .. (weapon and weapon.kind or 0)
                    end
                    local current = states[id]
                    if not current or current.signature ~= signature then
                        cancel(id)
                        current = {
                            signature = signature,
                            actor = actor,
                            model = deps.prediction.new(weapons, ack, tick),
                            single = true,
                            births = {},
                        }
                        -- The unmodified Isaac shot has a known appearance before
                        -- the first acknowledgement. Other outfits learn a template.
                        if deps.policy.defaultTear(player, actor[A.inventory]) then
                            current.template = {}
                        end
                    else
                        current.model:confirm(weapons, ack, tick)
                        current.actor = actor
                    end
                    retained[id] = current
                end
            end
            for id in pairs(states) do
                if not retained[id] then
                    cancel(id)
                end
            end
            states = retained
            local nextSeen = {}
            for _, entity in ipairs(value.room[R.entities]) do
                local id, owner = entity[E.id], entity[E.spawner]
                nextSeen[id] = true
                local current = states[owner]
                if current and entity[E.type] == deps.tearType and not seen[id] then
                    local birth = tick - entity[E.frame]
                    current.births[birth] = (current.births[birth] or 0) + 1
                    if current.births[birth] > 1 then
                        current.single = false
                        cancel(owner)
                    end
                    for prior in pairs(current.births) do
                        if prior < tick - birthHistoryTicks then
                            current.births[prior] = nil
                        end
                    end
                    local tear = ref(id)
                    if
                        tear
                        and (
                            entity[E.variant] == deps.tearVariants.BLUE
                            or entity[E.variant] == deps.tearVariants.BLOOD
                        )
                    then
                        current.template = {
                            sprite = entity[E.sprite],
                        }
                    end
                    local velocity = Vector(table.unpack(entity[E.velocity]))
                    if velocity:LengthSquared() > 0 then
                        local direction = velocity:Normalized()
                        for index, shot in ipairs(previews) do
                            if
                                shot.owner == owner
                                -- Present labels movement with the upcoming sample;
                                -- a shot can already belong to the sample just sent.
                                and shot.sequence <= ack + inputLookahead
                                and shot.velocity:Normalized():Dot(direction) > matchDirection
                                and now - shot.at <= shot.lifetime
                            then
                                handoffs[id] = {
                                    position = position(shot, now),
                                    velocity = shot.velocity,
                                    at = now,
                                }
                                table.remove(previews, index)
                                confirmed = confirmed + 1
                                break
                            end
                        end
                    end
                end
            end
            seen = nextSeen
        end
        local function aim(player, actor, direction, mouth)
            local name
            if math.abs(direction.X) > math.abs(direction.Y) then
                name = direction.X < 0 and headNames.left or headNames.right
            else
                name = direction.Y < 0 and headNames.up or headNames.down
            end
            local function head(sprite)
                if sprite:GetOverlayAnimation():match("^Head") then
                    sprite:SetOverlayFrame(name, mouth and mouthFrame or 0)
                end
            end
            head(player:GetSprite())
            for index, sprite in ipairs(native.actor_sprites(actor[A.index], player:GetSprite())) do
                if index >= fields.actorSprites.firstCostume then
                    head(sprite)
                end
            end
        end
        local function present(motion, ref, now, dt, sequence, status)
            if not lastReceived or now - lastReceived > staleAfter then
                clear()
                return
            end
            for id, current in pairs(states) do
                local model, player = motion[id], ref(id)
                if model and player then
                    player = player:ToPlayer()
                    local controls = player.ControlsEnabled
                        and player:AreControlsEnabled()
                        and player.ControlsCooldown <= 0
                        and player:IsExtraAnimationFinished()
                        and not player:IsCoopGhost()
                        and player:CanShoot()
                    local direction = Vector(0, 0)
                    if controls then
                        assert(native.rooms_with_player(status.slot, function()
                            direction = player:GetShootingInput()
                        end))
                    end
                    local firing = direction:LengthSquared() > 0
                    if firing then
                        direction = direction:Normalized()
                    end
                    local normal = controls
                        and current.single
                        and current.template ~= nil
                        and deps.policy.normalTear(player)
                        and deps.policy.singleTear(player)
                        and (
                            math.abs(direction.X) < axisTolerance
                            or math.abs(direction.Y) < axisTolerance
                        )
                    if not controls then
                        cancel(id)
                    end
                    local weapons = current.model:step(sequence, dt, firing, normal, function(slot)
                        if slot ~= pose.primarySlot or #previews >= maxPreviews then
                            return
                        end
                        local weapon = current.model.weapons[slot]
                        local interval = (math.max(0, weapon.maximum) + 1) / simulationRate
                        if
                            current.fired
                            and now - current.fired < interval * minimumShotSpacing
                        then
                            return
                        end
                        current.fired = now
                        started = started + 1
                        serial = serial + 1
                        local sprite = deps.sprite()
                        if current.template.sprite then
                            deps.applySprite(sprite, current.template.sprite)
                        else
                            sprite:Load("gfx/002.000_Tear.anm2", true)
                            sprite:SetFrame("RegularTear6", 0)
                        end
                        -- Native inheritance reads an internal simulation cache
                        -- which is not advanced by replica players. Use the local
                        -- walking model, in native half-update velocity units.
                        local movement = model.prediction
                                and model.prediction.velocity * (1 / playerVelocityRate)
                            or player.Velocity
                        local velocity = trajectory.velocity(direction, movement, player.ShotSpeed)
                        local origin = trajectory.origin(
                            player.Position,
                            velocity,
                            serial % 2 == 0 and eyeOffset or -eyeOffset
                        )
                        local height, falling = trajectory.initial(
                            player.TearHeight,
                            player.TearFallingSpeed,
                            player.TearFallingAcceleration
                        )
                        previews[#previews + 1] = {
                            owner = id,
                            sequence = sequence,
                            at = now,
                            sprite = sprite,
                            direction = direction,
                            origin = origin,
                            velocity = velocity,
                            height = height,
                            falling = falling,
                            acceleration = player.TearFallingAcceleration,
                            drawnHeight = height,
                            last = origin,
                            lifetime = math.min(
                                staleAfter,
                                math.max(
                                    minimumLifetime,
                                    (status["ping" .. status.slot] or 0) / 1000 + confirmationMargin
                                )
                            ),
                        }
                    end)
                    if weapons then
                        assert(
                            native.actor_pose(
                                player:GetSprite(),
                                pose.display(current.actor[A.pose], weapons)
                            )
                        )
                        if firing then
                            aim(
                                player,
                                current.actor,
                                direction,
                                current.fired and now - current.fired < mouthDuration
                            )
                        end
                    else
                        cancel(id)
                    end
                end
            end
            for id, handoff in pairs(handoffs) do
                local entity, model = ref(id), motion[id]
                if
                    not entity
                    or not model
                    or now - handoff.at > (handoff.duration or handoffTime) * handoffCutoff
                then
                    handoffs[id] = nil
                else
                    handoff.offset = handoff.offset or (handoff.position - model.display)
                    handoff.duration = handoff.duration
                        or math.max(
                            handoffTime,
                            math.sqrt(handoff.offset:LengthSquared())
                                / math.max(
                                    1,
                                    math.sqrt(handoff.velocity:LengthSquared())
                                        * simulationRate
                                        * maxCorrectionFraction
                                )
                        )
                    entity.Position = model.display
                        + handoff.offset * math.exp(-(now - handoff.at) / handoff.duration)
                end
            end
            for index = #previews, 1, -1 do
                local shot = previews[index]
                local target, height = position(shot, now)
                local timeout = now - shot.at > shot.lifetime
                local ground = height >= groundHeight
                local blocked = not deps.room()
                    :CheckLine(shot.last, target, projectileLine, 0, false, false)
                if timeout or ground or blocked then
                    table.remove(previews, index)
                    expired = expired + 1
                    if ground then
                        landed = landed + 1
                    elseif blocked then
                        gridStops = gridStops + 1
                    else
                        timedOut = timedOut + 1
                    end
                else
                    shot.last, shot.drawnHeight = target, height
                end
            end
            measure()
        end
        return {
            confirm = confirm,
            present = present,
            reset = clear,
            render = function()
                if #previews == 0 then
                    return
                end
                local mirror = deps.room():IsMirrorWorld()
                for _, shot in ipairs(previews) do
                    -- Altitude is in world units too; the room projection is
                    -- scaled independently from the HUD's Sprite coordinates.
                    local screen = deps.screen(shot.last + Vector(0, shot.drawnHeight))
                    if mirror then
                        screen.X = deps.screenWidth() - screen.X
                    end
                    shot.sprite:Render(screen, Vector(0, 0), Vector(0, 0))
                end
            end,
        }
    end
end
