return function(report, actor, moveRoom, moveFloor)
    local rules, tick
    local firstTargets, secondTargets, moved, floored, removed
    local pending, targets, rockIndex = {}, {}, nil
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
                    assert(not familiar, "Duplicate familiar before attack trial")
                    familiar = f
                end
            end
        end
        assert(familiar, "Missing familiar before attack trial")
        local positions = {}
        if rules.spectral then
            rockIndex = room:GetGridIndex(familiar.Position - Vector(0, 40))
            assert(not room:GetGridEntity(rockIndex))
            assert(room:SpawnGridEntity(rockIndex, GridEntityType.GRID_ROCK, 0, 187, 0))
            positions[1] = Vector(familiar.Position.X, room:GetGridPosition(rockIndex).Y - 35)
        else
            for _, angle in ipairs({ -90, -65, -115, 0, 90, 180 }) do
                positions[#positions + 1] = familiar.Position + Vector.FromAngle(angle) * 95
            end
        end
        for _, position in ipairs(positions) do
            assert(room:IsPositionInRoom(position, 15), "Familiar target outside room")
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
                return true
            end
        end,
        prepare = function(case)
            rules, tick = case.familiar_effects, 0
            firstTargets, secondTargets, moved, floored, removed = false, false, false, false, false
            pending, targets, rockIndex = {}, {}, nil
        end,
        damage = function(entity, amount, source)
            if not rules or not entity:GetData().auditFamiliarTarget then
                return
            end
            local f = familiarSource(source.Entity)
            if f and f.Player and f.Variant == FamiliarVariant[rules.variant] then
                pending[#pending + 1] = {
                    entity = entity,
                    tick = tick,
                    amount = amount,
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
            tick = frame
            actor(case.slot, function(p, room)
                if not firstTargets and tick >= 150 then
                    firstTargets = true
                    spawnTargets(p, room)
                end
                if not secondTargets and tick >= 630 then
                    secondTargets = true
                    spawnTargets(p, room)
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
                and tear.SpawnerEntity:ToPlayer()
            then
                tear:Remove()
            end
        end,
        sample = function(case, frame, host)
            if not enabled(case) or frame < 70 then
                return
            end
            if host then
                local remaining = {}
                for _, hit in ipairs(pending) do
                    if frame > hit.tick + 1 then
                        hit.after = hit.entity.HitPoints
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
                }
                local entities = (host or value.room_visible) and Isaac.GetRoomEntities() or {}
                for _, e in ipairs(entities) do
                    local f = e:ToFamiliar()
                    if f and f.Variant == FamiliarVariant[case.familiar_effects.variant] then
                        value.familiars[#value.familiars + 1] = {
                            controller = f.Player and f.Player.ControllerIndex or -1,
                            x = f.Position.X,
                            y = f.Position.Y,
                        }
                    end
                    local tear, source = e:ToTear(), familiarSource(e)
                    if
                        tear
                        and source
                        and source.Variant == FamiliarVariant[case.familiar_effects.variant]
                    then
                        local data = tear:GetData()
                        value.shots[#value.shots + 1] = {
                            id = data.__isaac_lan_replica or data.__isaac_lan_entity or 0,
                            age = tear.FrameCount,
                            source_age = source.FrameCount,
                            damage = tear.CollisionDamage,
                            controller = source.Player and source.Player.ControllerIndex or -1,
                            spectral = tear:HasTearFlags(TearFlags.TEAR_SPECTRAL),
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
            if frame >= 90 and frame < 100 then
                return 1 << ButtonAction.ACTION_RIGHT
            elseif frame >= 150 and frame < 270 or frame >= 630 and frame < 750 then
                return 1 << ButtonAction.ACTION_SHOOTUP
            end
            return 0
        end,
    }
end
