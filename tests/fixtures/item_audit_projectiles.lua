return function(report, actor)
    local pending
    local heartHit
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
        end,
        collision = function(projectile, collider)
            local trial = projectile:GetData().auditDefense
            if trial then
                trial.collision = true
                trial.collider = collider.Type
            end
        end,
        advance = function(case, tick)
            local rules = case.trigger_effects and case.trigger_effects.projectile_trial
            if not rules then
                return
            end
            actor(case.slot, function(p)
                if rules.heart_hit and tick == 1590 then
                    local f = assert(ownedFamiliar(p, FamiliarVariant.ISAACS_HEART))
                    p:ResetDamageCooldown()
                    heartHit = { before = p:GetHearts() + p:GetSoulHearts(), tick = tick }
                    local q = Isaac.Spawn(
                        EntityType.ENTITY_PROJECTILE,
                        0,
                        0,
                        f.Position,
                        Vector.Zero,
                        nil
                    )
                        :ToProjectile()
                    q.Height, q.FallingAccel, q.FallingSpeed = -10, 0, 0
                elseif rules.heart_hit and tick == 1620 then
                    heartHit.after = p:GetHearts() + p:GetSoulHearts()
                    report("heart_familiar_damage", heartHit)
                end
                if tick == 75 and rules.kind == "player" then
                    p:RemoveCollectible(case.id)
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
                    p:AddCollectible(case.id, 0, false)
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
