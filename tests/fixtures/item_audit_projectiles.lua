return function(report, actor)
    local pending
    local heartHit, heartProjectile
    local function ownedFamiliar(p, variant)
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            local f = e:ToFamiliar()
            if
                f
                and f:Exists()
                and not f:IsDead()
                and f.Variant == variant
                and f.Player
                and f.Player.ControllerIndex == p.ControllerIndex
            then
                return f
            end
        end
    end
    return {
        prepare = function()
            pending = nil
            heartHit = nil
            heartProjectile = nil
        end,
        collision = function(projectile, collider)
            local trial = projectile:GetData().auditDefense
            if trial then
                trial.collision = true
                trial.collider = collider.Type
            end
            local heart = projectile:GetData().auditHeartCollision
            if heart then
                heart.collision = true
                heart.collider_type, heart.collider_variant = collider.Type, collider.Variant
            end
        end,
        advance = function(case, tick)
            local rules = case.trigger_effects and case.trigger_effects.projectile_trial
            if not rules then
                return
            end
            actor(case.slot, function(p)
                local heartStart, heartPeriod = 1590, 60
                local heartAttempts = rules.heart_trials or 1
                if
                    rules.heart_hit
                    and tick >= heartStart
                    and tick < heartStart + heartAttempts * heartPeriod
                    and (tick - heartStart) % heartPeriod == 0
                then
                    local f = assert(ownedFamiliar(p, FamiliarVariant.ISAACS_HEART))
                    -- Separate the collision targets before firing: an immune
                    -- body overlapping the heart consumes the test projectile.
                    p.Position, p.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
                    f.Position, f.Velocity = p.Position + Vector(0, 60), Vector.Zero
                    p:ResetDamageCooldown()
                    heartHit = {
                        before = p:GetHearts() + p:GetSoulHearts(),
                        tick = tick,
                        heart_collision = f.EntityCollisionClass,
                    }
                    -- Approach from the exposed side. Starting inside the
                    -- heart can overlap Isaac's immune body, which consumes
                    -- the projectile before it reaches the familiar.
                    local outward = f.Position - p.Position
                    if outward:Length() < 1 then
                        outward = Vector(0, 1)
                    end
                    outward = outward:Normalized()
                    local room, position, distance = Game():GetRoom(), nil, -1
                    for _, angle in ipairs({ 0, 90, -90, 180, 45, -45, 135, -135 }) do
                        local candidate = f.Position + outward:Rotated(angle) * 45
                        if
                            room:IsPositionInRoom(candidate, 20)
                            and room:GetGridCollisionAtPos(candidate) == GridCollisionClass.COLLISION_NONE
                            and candidate:Distance(p.Position) > distance
                        then
                            position, distance = candidate, candidate:Distance(p.Position)
                        end
                    end
                    assert(position, "No unobstructed projectile approach to Isaac's Heart")
                    heartHit.player_position = { p.Position.X, p.Position.Y }
                    heartHit.heart_position = { f.Position.X, f.Position.Y }
                    heartHit.projectile_position = { position.X, position.Y }
                    local q = Isaac.Spawn(
                        EntityType.ENTITY_PROJECTILE,
                        0,
                        0,
                        position,
                        (f.Position - position):Resized(8),
                        nil
                    ):ToProjectile()
                    q.Height, q.FallingAccel, q.FallingSpeed = -10, 0, 0
                    q.CollisionDamage = 1
                    q:GetData().auditHeartCollision = heartHit
                    heartProjectile = q
                elseif heartHit and tick == heartHit.tick + 30 then
                    heartHit.after = p:GetHearts() + p:GetSoulHearts()
                    heartHit.projectile_removed = not heartProjectile:Exists()
                        or heartProjectile:IsDead()
                    report("heart_familiar_damage", heartHit)
                    if heartProjectile:Exists() then
                        heartProjectile:Remove()
                    end
                    heartHit, heartProjectile = nil, nil
                end
                if
                    rules.heart_hit
                    and heartHit
                    and tick > heartHit.tick
                    and tick < heartHit.tick + 30
                    and heartProjectile
                    and heartProjectile:Exists()
                then
                    local f = ownedFamiliar(p, FamiliarVariant.ISAACS_HEART)
                    if f then
                        local approach = f.Position - heartProjectile.Position
                        if approach:Length() > 0 then
                            heartProjectile.Velocity = approach:Resized(8)
                        end
                        heartHit.heart_collision = f.EntityCollisionClass
                        heartHit.closest_distance =
                            math.min(heartHit.closest_distance or math.huge, approach:Length())
                    end
                end
                if tick == 75 and rules.kind == "player" then
                    if case.kind == "trinket" then
                        p:TryRemoveTrinket(case.id)
                    else
                        p:RemoveCollectible(case.id)
                    end
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        local f = e:ToFamiliar()
                        if
                            f
                            and f.Player
                            and f.Player.ControllerIndex == p.ControllerIndex
                            and rules.familiar
                            and f.Variant == FamiliarVariant[rules.familiar]
                        then
                            f:Remove()
                        end
                    end
                    p:AddMaxHearts(24 - p:GetMaxHearts(), false)
                    p:AddSoulHearts(-p:GetSoulHearts())
                elseif tick == 135 and rules.kind == "player" then
                    if case.kind == "trinket" then
                        p:AddTrinket(case.id, false)
                    else
                        p:AddCollectible(case.id, 0, false)
                    end
                end
                if pending then
                    local q = pending.entity
                    if q:Exists() and not q:IsDead() then
                        pending.reflected = pending.reflected
                            or q:HasProjectileFlags(ProjectileFlags.CANT_HIT_PLAYER)
                            or q.Velocity.Y < -0.1
                    end
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:ToTear() and e.Velocity.Y < -0.1 and not rules.shoot then
                            pending.reflected = true
                        end
                    end
                    if tick >= pending.tick + 24 then
                        pending.removed = not q:Exists() or q:IsDead()
                        pending.after = p:GetHearts() + p:GetSoulHearts()
                        pending.entity = nil
                        report("defense_projectile_result", pending)
                        if q:Exists() then
                            q:Remove()
                        end
                        pending = nil
                    end
                end
                if tick == 90 or tick >= 180 and tick <= 1560 and (tick - 180) % 30 == 0 then
                    local control = tick == 90
                    p:AddHearts(24 - p:GetHearts())
                    p:ResetDamageCooldown()
                    local position = control and rules.kind == "familiar" and p.Position
                        or p.Position - Vector(0, 45)
                    if not control and rules.kind == "familiar" then
                        local f = rules.splits and ownedFamiliar(p, FamiliarVariant.TINYTOMA_2)
                            or ownedFamiliar(p, assert(FamiliarVariant[rules.familiar]))
                        if not f and rules.splits then
                            f = ownedFamiliar(p, FamiliarVariant.TINYTOMA_2)
                        end
                        if not f then
                            return
                        end
                        position = f.Position
                    end
                    local q =
                        Isaac.Spawn(EntityType.ENTITY_PROJECTILE, 0, 0, position, Vector(0, 4), nil)
                            :ToProjectile()
                    q.FallingSpeed, q.FallingAccel = 0, 0
                    q.Height = -10
                    pending = {
                        entity = q,
                        tick = tick,
                        control = control,
                        before = p:GetHearts() + p:GetSoulHearts(),
                        collision = false,
                        reflected = false,
                    }
                    q:GetData().auditDefense = pending
                end
                if rules.rearm and tick >= 165 and (tick - 165) % 30 == 0 then
                    local f = ownedFamiliar(p, FamiliarVariant[rules.familiar])
                    if f then
                        p.Position = f.Position
                    end
                end
            end)
        end,
        sample = function(case, tick)
            if not (case.trigger_effects and case.trigger_effects.projectile_trial) then
                return
            end
            actor(case.slot, function(p)
                local small, spiders, flies = 0, 0, 0
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    local f = e:ToFamiliar()
                    if f and f.Player and f.Player.ControllerIndex == p.ControllerIndex then
                        small = small + (f.Variant == FamiliarVariant.TINYTOMA_2 and 1 or 0)
                        spiders = spiders + (f.Variant == FamiliarVariant.BLUE_SPIDER and 1 or 0)
                        flies = flies + (f.Variant == FamiliarVariant.BLUE_FLY and 1 or 0)
                    end
                end
                report("defense_state", {
                    tick = tick,
                    small_tomas = small,
                    spiders = spiders,
                    blue_flies = flies,
                    delay = p.MaxFireDelay,
                })
            end)
        end,
    }
end
