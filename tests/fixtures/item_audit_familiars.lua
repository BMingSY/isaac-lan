return function(report, actor, moveRoom, moveFloor)
    local rules, tick, nativeTick
    local firstTargets, secondTargets, moved, floored, removed
    local pending, targets, rockIndex = {}, {}, nil
    local contactFamiliar, projectiles = nil, {}
    local seenPickups = {}
    local function familiarSource(entity)
        if not entity then
            return nil
        end
        local f = entity:ToFamiliar()
        if f then
            return f
        end
        local parent = entity.SpawnerEntity
        return parent and parent:ToFamiliar()
    end
    local function clearTargets()
        for _, target in ipairs(targets) do
            if target:Exists() then
                target:Remove()
            end
        end
        targets = {}
        if rockIndex then
            Game():GetRoom():RemoveGridEntity(rockIndex, 0, false)
            rockIndex = nil
        end
    end
    local function spawnTargets(p, room)
        clearTargets()
        local familiar
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if
                e.Type == EntityType.ENTITY_FAMILIAR
                and e.Variant == FamiliarVariant[rules.variant]
            then
                local f = e:ToFamiliar()
                if f.Player and f.Player.ControllerIndex == p.ControllerIndex then
                    assert(not familiar or rules.count, "Duplicate familiar before attack trial")
                    familiar = familiar or f
                end
            end
        end
        assert(familiar, "Missing familiar before attack trial")
        contactFamiliar = familiar
        if rules.provider then
            return
        end
        p:SetMinDamageCooldown(150)
        local positions = {}
        if rules.contact then
            positions[1] = room:GetClampedPosition(familiar.Position, 20)
        elseif rules.aims_at_player then
            positions[1] = familiar.Position + (p.Position - familiar.Position):Resized(85)
        elseif rules.spectral then
            rockIndex = room:GetGridIndex(familiar.Position - Vector(0, 40))
            assert(not room:GetGridEntity(rockIndex))
            assert(room:SpawnGridEntity(rockIndex, GridEntityType.GRID_ROCK, 0, 187, 0))
            positions[1] = Vector(familiar.Position.X, room:GetGridPosition(rockIndex).Y - 35)
        elseif rules.pattern == "split" then
            -- Harlequin's native velocities are (+/-2, -10). Put both
            -- stationary targets in those lanes, without a central blocker.
            positions[1] = familiar.Position + Vector(-19, -95)
            positions[2] = familiar.Position + Vector(19, -95)
        else
            for _, angle in ipairs({ -90, -65, -115, 0, 90, 180 }) do
                positions[#positions + 1] = familiar.Position + Vector.FromAngle(angle) * 95
            end
        end
        for _, position in ipairs(positions) do
            position = room:GetClampedPosition(position, 25)
            local e = Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, position, Vector.Zero, nil)
            e:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK)
            e.MaxHitPoints, e.HitPoints = 1000, 1000
            e:GetData().auditFamiliarTarget = true
            targets[#targets + 1] = e
        end
        report("familiar_targets", { tick = tick, count = #targets, rock = rockIndex })
    end
    local function enabled(case)
        return case and case.familiar_effects
    end
    return {
        holdTarget = function(npc)
            if rules and npc:GetData().auditFamiliarTarget then
                -- Keep the native damage target stationary throughout the
                -- trial. A temporary freeze expires and permits contact hits,
                -- which interrupt the holder's normal shooting cadence.
                npc.Velocity = Vector.Zero
                if rules.contact and contactFamiliar and contactFamiliar:Exists() then
                    npc.Position = Game():GetRoom():GetClampedPosition(contactFamiliar.Position, 20)
                end
                return true
            end
        end,
        prepare = function(case)
            rules, tick = case.familiar_effects, 0
            firstTargets, secondTargets, moved, floored, removed = false, false, false, false, false
            pending, targets, rockIndex = {}, {}, nil
            contactFamiliar, projectiles = nil, {}
            seenPickups = {}
            if rules and rules.prerequisite then
                actor(case.slot, function(p)
                    p:AddCollectible(assert(CollectibleType[rules.prerequisite]), 0, false)
                end)
            end
        end,
        clearAward = function()
            if rules and rules.provider then
                report("familiar_clear", { tick = nativeTick })
            end
        end,
        projectileCollision = function(projectile, collider)
            if rules and rules.blocks and projectile:GetData().auditBlockTrial then
                local f = collider:ToFamiliar()
                if f and f.Variant == FamiliarVariant[rules.variant] then
                    projectile:GetData().auditBlockTrial.collision = true
                end
            end
        end,
        damage = function(entity, amount, source)
            if not rules or not entity:GetData().auditFamiliarTarget then
                return
            end
            local f = familiarSource(source.Entity)
            if f and f.Player and f.Variant == FamiliarVariant[rules.variant] then
                for _, hit in ipairs(pending) do
                    if hit.seed == entity.InitSeed and hit.tick == tick then
                        hit.amount = hit.amount + amount
                        hit.hits = hit.hits + 1
                        return
                    end
                end
                pending[#pending + 1] = {
                    entity = entity,
                    seed = entity.InitSeed,
                    tick = tick,
                    amount = amount,
                    hits = 1,
                    before = entity.HitPoints,
                    controller = f.Player.ControllerIndex,
                    variant = f.Variant,
                    rock_intact = rockIndex ~= nil
                        and Game():GetRoom():GetGridEntity(rockIndex) ~= nil
                        and Game():GetRoom():GetGridCollision(rockIndex)
                            == GridCollisionClass.COLLISION_SOLID,
                }
            end
        end,
        advance = function(case, frame)
            if not enabled(case) then
                return
            end
            nativeTick = frame
            local scale = rules.timeline_scale or 1
            if frame % scale ~= 0 then
                return
            end
            -- Native room-clear rewards wait for the room to remain empty.
            -- Providers therefore leave 27 updates between a kill and the
            -- next spawned enemy; quick combat trials keep their own cadence.
            tick = frame / scale
            actor(case.slot, function(p, room)
                if not firstTargets and tick >= 150 then
                    firstTargets = true
                    spawnTargets(p, room)
                end
                if not secondTargets and tick >= 630 then
                    secondTargets = true
                    spawnTargets(p, room)
                end
                if
                    rules.provider
                    and ((tick >= 150 and tick < 270) or (tick >= 630 and tick < 750))
                then
                    if tick % 12 == 6 then
                        clearTargets()
                        room:SetClear(false)
                        local npc = Isaac.Spawn(
                            EntityType.ENTITY_GAPER,
                            0,
                            0,
                            room:GetCenterPos() + Vector(100, 0),
                            Vector.Zero,
                            nil
                        )
                        npc:GetData().auditFamiliarTarget = true
                        targets[1] = npc
                    elseif tick % 12 == 9 then
                        for _, npc in ipairs(targets) do
                            if npc:Exists() then
                                npc:Kill()
                            end
                        end
                    end
                end
                if
                    rules.blocks
                    and ((tick >= 180 and tick <= 240) or (tick >= 660 and tick <= 720))
                    and tick % 15 == 0
                then
                    if contactFamiliar and contactFamiliar:Exists() then
                        local projectile = Isaac.Spawn(
                            EntityType.ENTITY_PROJECTILE,
                            0,
                            0,
                            contactFamiliar.Position,
                            Vector(0, 1),
                            nil
                        ):ToProjectile()
                        local trial = { entity = projectile, tick = tick, collision = false }
                        projectile:GetData().auditBlockTrial = trial
                        projectiles[#projectiles + 1] = trial
                    end
                end
                if not removed and tick >= 780 then
                    removed = true
                    clearTargets()
                    p:RemoveCollectible(case.id)
                end
            end)
            if not moved and tick >= 300 then
                moved = true
                actor(case.slot, clearTargets)
                moveRoom()
            end
            if not floored and tick >= 390 then
                floored = true
                moveFloor()
            end
        end,
        suppressPlayerTear = function(tear)
            -- Incubus initially creates a player tear, then assigns itself as
            -- the source before the next update. Wait for that native setup.
            if
                rules
                and tear.FrameCount > 0
                and tear.SpawnerEntity
                and (
                    tear.SpawnerEntity:ToPlayer()
                    or (
                        rules.prerequisite
                        and tear.SpawnerEntity:ToFamiliar()
                        and tear.SpawnerEntity.Variant ~= FamiliarVariant[rules.variant]
                    )
                )
            then
                tear:Remove()
            end
        end,
        sample = function(case, frame, host)
            if not enabled(case) or frame < 70 then
                return
            end
            if host then
                local unresolved = {}
                for _, trial in ipairs(projectiles) do
                    if frame >= trial.tick + 5 then
                        report("familiar_block", {
                            tick = trial.tick,
                            removed = not trial.entity:Exists() or trial.entity:IsDead(),
                            familiar_collision = trial.collision,
                        })
                    else
                        unresolved[#unresolved + 1] = trial
                    end
                end
                projectiles = unresolved
                local remaining = {}
                for _, hit in ipairs(pending) do
                    if frame > hit.tick + 1 then
                        hit.after = hit.entity.HitPoints
                        hit.bleeding = rules.damage_over_time
                                and hit.entity:HasEntityFlags(EntityFlag.FLAG_BLEED_OUT)
                            or false
                        hit.fear = rules.fear and hit.entity:HasEntityFlags(EntityFlag.FLAG_FEAR)
                            or false
                        hit.after_tick = frame
                        hit.entity = nil
                        report("familiar_hit", hit)
                    else
                        remaining[#remaining + 1] = hit
                    end
                end
                pending = remaining
            end
            local teammateOwned
            actor(1 - case.slot, function(p)
                teammateOwned = p:GetCollectibleNum(case.id, true)
            end)
            actor(case.slot, function(p, room)
                local positions = _IsaacLan.rooms_positions()
                local view = positions[tostring(_IsaacLanStatus().slot)]
                local location = positions[tostring(case.slot)]
                local value = {
                    tick = frame,
                    room = location.index,
                    stage = Game():GetLevel():GetStage(),
                    room_visible = view.index == location.index
                        and view.dimension == location.dimension,
                    x = p.Position.X,
                    y = p.Position.Y,
                    owned = p:GetCollectibleNum(case.id, true),
                    teammate_owned = teammateOwned,
                    familiars = {},
                    shots = {},
                    retired_familiars = 0,
                }
                local entities = (host or value.room_visible) and Isaac.GetRoomEntities() or {}
                for _, e in ipairs(entities) do
                    local f = e:ToFamiliar()
                    if
                        f
                        and f.Variant == FamiliarVariant[case.familiar_effects.variant]
                        and not f:Exists()
                    then
                        value.retired_familiars = value.retired_familiars + 1
                    elseif f and f.Variant == FamiliarVariant[case.familiar_effects.variant] then
                        value.familiars[#value.familiars + 1] = {
                            controller = f.Player and f.Player.ControllerIndex or -1,
                            x = f.Position.X,
                            y = f.Position.Y,
                        }
                    end
                    local tear, source = e:ToTear(), familiarSource(e)
                    if
                        case.familiar_effects.provider
                        and e:Exists()
                        and e:ToPickup()
                        and source
                        and source.Variant == FamiliarVariant[case.familiar_effects.variant]
                        and not seenPickups[e.InitSeed]
                    then
                        seenPickups[e.InitSeed] = true
                        report("familiar_drop", {
                            tick = frame,
                            seed = e.InitSeed,
                            variant = e.Variant,
                            subtype = e.SubType,
                            controller = source.Player and source.Player.ControllerIndex or -1,
                        })
                    end
                    if
                        tear
                        and tear:Exists()
                        and source
                        and source.Variant == FamiliarVariant[case.familiar_effects.variant]
                    then
                        local data = tear:GetData()
                        local flags = {}
                        for _, flag in
                            ipairs(
                                case.familiar_effects.observe_flags
                                    or case.familiar_effects.flags
                                    or {}
                            )
                        do
                            flags[flag] = tear:HasTearFlags(assert(TearFlags[flag]))
                        end
                        value.shots[#value.shots + 1] = {
                            id = data.__isaac_lan_replica or data.__isaac_lan_entity or 0,
                            seed = tear.InitSeed,
                            variant = tear.Variant,
                            age = tear.FrameCount,
                            source_age = source.FrameCount,
                            damage = tear.CollisionDamage,
                            controller = source.Player and source.Player.ControllerIndex or -1,
                            spectral = tear:HasTearFlags(TearFlags.TEAR_SPECTRAL),
                            flags = flags,
                            vx = tear.Velocity.X,
                            vy = tear.Velocity.Y,
                        }
                    end
                end
                report("familiar_probe", value)
            end)
        end,
        input = function(case, frame)
            if not enabled(case) then
                return 0
            end
            frame = frame / (case.familiar_effects.timeline_scale or 1)
            if frame >= 90 and frame < 100 then
                return 1 << ButtonAction.ACTION_RIGHT
            elseif case.familiar_effects.controlled and frame >= 100 and frame < 140 then
                return 1 << ButtonAction.ACTION_SHOOTUP
            elseif frame >= 150 and frame < 270 or frame >= 630 and frame < 750 then
                if
                    case.familiar_effects.automatic
                    or case.familiar_effects.provider
                    or (case.familiar_effects.contact and not case.familiar_effects.contact_shoot)
                then
                    return 0
                end
                return 1 << ButtonAction.ACTION_SHOOTUP
            end
            return 0
        end,
    }
end
