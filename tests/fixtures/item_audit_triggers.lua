-- Effect-specific native prerequisites and observations. No production hooks.
return function(report, actor, moveRoom, moveFloor)
    local birthrightTrials = createBirthrightTrials(report, actor, moveRoom, moveFloor)
    local trinketTrials = createTrinketTrials(report, actor, moveRoom, moveFloor)
    local interactions = createInteractionEffects(report, actor, moveRoom, moveFloor)
    local projectileTrials = createProjectileTrials(report, actor)
    local current, moved, rockIndex, crushed, obstacleIndex, attractionPickup
    local initialTearScale
    local pendingSeriesDamage
    local nativeTick = 0
    local generatedIdentity
    local pillTrials = {}
    local seen, spawned, entityCounts = {}, {}, {}
    local effectNames, familiarNames, pickupNames, collectibleNames = {}, {}, {}, {}
    local roomNames, gridNames, playerNames, tearNames = {}, {}, {}, {}
    local stageNames = {}
    for name, id in pairs(LevelStage) do
        if name:match("^STAGE") and not name:find("_GREED", 1, true) then
            stageNames[id] = name
        end
    end
    for name, id in pairs(TearVariant) do
        tearNames[id] = name
    end
    for name, id in pairs(PlayerType) do
        playerNames[id] = name
    end
    -- Legacy XXX aliases share these IDs; pairs() order is not stable.
    playerNames[PlayerType.PLAYER_BLUEBABY] = "PLAYER_BLUEBABY"
    playerNames[PlayerType.PLAYER_BLUEBABY_B] = "PLAYER_BLUEBABY_B"
    for name, id in pairs(RoomType) do
        roomNames[id] = name
    end
    for name, id in pairs(GridEntityType) do
        gridNames[id] = name
    end
    for name, id in pairs(EffectVariant) do
        effectNames[id] = name
    end
    for name, id in pairs(FamiliarVariant) do
        familiarNames[id] = name
    end
    for name, id in pairs(PickupVariant) do
        pickupNames[id] = name
    end
    for name, id in pairs(CollectibleType) do
        if not collectibleNames[id] or name < collectibleNames[id] then
            collectibleNames[id] = name
        end
    end
    local function enabled(case)
        return case and case.trigger_effects
    end
    local function reset(case)
        if current ~= case then
            current, moved, rockIndex, crushed = case, false, nil, false
            obstacleIndex, attractionPickup = nil, nil
            seen, spawned, entityCounts = {}, {}, {}
            initialTearScale = nil
            pendingSeriesDamage = nil
            generatedIdentity = nil
            pillTrials = {}
        end
    end
    local function increment(values, key)
        values[key] = (values[key] or 0) + 1
    end
    local function ownerOf(entity)
        for _ = 1, 4 do
            local player = entity:ToPlayer()
            if player then
                return player
            end
            local familiar = entity:ToFamiliar()
            if familiar then
                return familiar.Player
            end
            entity = entity.SpawnerEntity or entity.Parent
            if not entity or not entity:Exists() then
                return nil
            end
        end
    end
    local function snapshot(case, tick, label)
        local rules = enabled(case)
        if not rules then
            return
        end
        reset(case)
        actor(case.slot, function(p, room)
            local positions = _IsaacLan.rooms_positions()
            local location = positions[tostring(case.slot)]
            local view = positions[tostring(_IsaacLanStatus().slot)]
            local roomVisible = location.index == view.index
                and location.dimension == view.dimension
            -- Remote replica shells contain actors, but no initialized room grid
            -- or descriptor. Only the authority and the visible replica own these.
            local roomObserved = label ~= "replica" or roomVisible
            local effects, familiars, tearFlags, enemyFlags = {}, {}, {}, {}
            local stompingFeet = {}
            local familiarPositions = {}
            local projectiles = {}
            local enemyHp, enemies, familiarCount, returnedPills = 0, 0, 0, 0
            local enemyTypes = {}
            local friendlyCount = 0
            local bosses = {}
            local pedestalOptions = {}
            local tears, targets, pickups, pedestals, pickupTypes, nullEffects =
                {}, {}, {}, {}, {}, {}
            local poopCount, rockCount, coinValue, laserCount = 0, 0, 0, 0
            local runeDrops = 0
            local grids, doors = {}, {}
            local explosives = {}
            local knives = {}
            local lasers = {}
            for slot = 0, (roomObserved and DoorSlot.NUM_DOOR_SLOTS or 0) - 1 do
                local door = room:GetDoor(slot)
                if door then
                    doors[#doors + 1] = {
                        slot = slot,
                        open = door:IsOpen(),
                        locked = door:IsLocked(),
                        type = roomNames[door.TargetRoomType],
                    }
                end
            end
            for i = 0, (roomObserved and room:GetGridSize() or 0) - 1 do
                local grid = room:GetGridEntity(i)
                if grid then
                    increment(grids, gridNames[grid:GetType()] or tostring(grid:GetType()))
                end
                if grid and grid:GetType() == GridEntityType.GRID_POOP then
                    poopCount = poopCount + 1
                end
                if grid and grid:ToRock() and grid.State < 2 then
                    rockCount = rockCount + 1
                end
            end
            for _, e in ipairs(roomObserved and Isaac.GetRoomEntities() or {}) do
                if e:Exists() then
                    if e:IsBoss() then
                        bosses[#bosses + 1] =
                            { type = e.Type, variant = e.Variant, hp = e.HitPoints }
                    end
                    if rules.repel_projectile and e:ToProjectile() then
                        projectiles[#projectiles + 1] = {
                            seed = e.InitSeed,
                            x = e.Position.X,
                            y = e.Position.Y,
                            vx = e.Velocity.X,
                            vy = e.Velocity.Y,
                        }
                    end
                    local identity = e.Type .. "." .. e.Variant .. "." .. e.SubType
                    local key = identity .. ":" .. e.InitSeed
                    if not seen[key] then
                        seen[key] = true
                        if label ~= "before" then
                            increment(spawned, identity)
                        end
                    end
                    if e.Type == EntityType.ENTITY_EFFECT then
                        increment(effects, effectNames[e.Variant] or tostring(e.Variant))
                        if
                            rules.shovel_feet_trial
                            and e.Variant == EffectVariant.MOM_FOOT_STOMP
                        then
                            stompingFeet[#stompingFeet + 1] = {
                                seed = e.InitSeed,
                                age = e.FrameCount,
                                animation = e:GetSprite():GetAnimation(),
                                frame = e:GetSprite():GetFrame(),
                                visible = e.Visible,
                                x = e.Position.X,
                                y = e.Position.Y,
                            }
                        end
                    end
                    if e.Type == EntityType.ENTITY_LASER then
                        laserCount = laserCount + 1
                        local laser = e:ToLaser()
                        lasers[#lasers + 1] = {
                            seed = e.InitSeed,
                            variant = e.Variant,
                            x = e.Position.X,
                            y = e.Position.Y,
                            angle = laser.AngleDegrees,
                            radius = laser.Radius,
                        }
                    end
                    if e.Type == EntityType.ENTITY_BOMB then
                        local bomb = e:ToBomb()
                        explosives[#explosives + 1] = {
                            seed = e.InitSeed,
                            variant = e.Variant,
                            x = e.Position.X,
                            y = e.Position.Y,
                            damage = bomb.ExplosionDamage,
                            radius = bomb.RadiusMultiplier,
                            flags = tostring(bomb.Flags),
                        }
                    end
                    if e.Type == EntityType.ENTITY_KNIFE then
                        knives[#knives + 1] = {
                            seed = e.InitSeed,
                            variant = e.Variant,
                            x = e.Position.X,
                            y = e.Position.Y,
                        }
                    end
                    local familiar = e:ToFamiliar()
                    if
                        e:ToNPC()
                        and (
                            e:GetData().auditTriggerTarget
                            or rules.downgrade_enemies
                            or rules.reroll_enemies
                        )
                    then
                        increment(enemyTypes, tostring(e.Type) .. "." .. e.Variant)
                    end
                    if e:ToNPC() and e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
                        friendlyCount = friendlyCount + 1
                    end
                    local from = ownerOf(e)
                    local owned = from and from.ControllerIndex == p.ControllerIndex
                    if familiar and owned then
                        increment(familiars, familiarNames[e.Variant] or tostring(e.Variant))
                        familiarCount = familiarCount + 1
                        familiarPositions[#familiarPositions + 1] = {
                            variant = familiarNames[e.Variant],
                            subtype = e.SubType,
                            state = familiar.State,
                            x = e.Position.X,
                            y = e.Position.Y,
                            vx = e.Velocity.X,
                            vy = e.Velocity.Y,
                        }
                    end
                    local tear = e:ToTear()
                    if tear and (owned or rules.include_room_tears) then
                        local color = tear:GetSprite().Color
                        local flags = {}
                        if rules.random_tears then
                            for name, value in pairs(TearFlags) do
                                if
                                    name ~= "TEAR_NORMAL"
                                    and type(value) == "userdata"
                                    and tear:HasTearFlags(value)
                                then
                                    flags[#flags + 1] = name
                                end
                            end
                            table.sort(flags)
                        end
                        tears[#tears + 1] = {
                            seed = e.InitSeed,
                            variant_name = tearNames[e.Variant],
                            age = e.FrameCount,
                            x = e.Position.X,
                            y = e.Position.Y,
                            vx = e.Velocity.X,
                            vy = e.Velocity.Y,
                            damage = tear.CollisionDamage,
                            height = tear.Height,
                            scale = tear.Scale,
                            scale_x = tear.SpriteScale.X,
                            scale_y = tear.SpriteScale.Y,
                            knockback = tear.KnockbackMultiplier,
                            flags = flags,
                            color = {
                                color.R,
                                color.G,
                                color.B,
                                color.A,
                                color.RO,
                                color.GO,
                                color.BO,
                            },
                        }
                        entityCounts[key] = true
                        for _, flag in ipairs(rules.tear_flags or {}) do
                            if tear:HasTearFlags(assert(TearFlags[flag], flag)) then
                                increment(tearFlags, flag)
                            end
                        end
                    end
                    if
                        e.Type == EntityType.ENTITY_GAPER
                        or rules.entry_trial and e:IsActiveEnemy(false)
                    then
                        targets[#targets + 1] = {
                            seed = e.InitSeed,
                            hp = e.HitPoints,
                            frame = e.FrameCount,
                            updates = e:GetData().auditTriggerUpdates or 0,
                            aligned = e:GetData().auditAligned or 0,
                            cursor_aligned = e:GetData().auditCursorAligned or 0,
                            x = e.Position.X,
                            y = e.Position.Y,
                        }
                        -- A dying replica may remain for one update with negative HP.
                        -- Corpses have no remaining damage budget.
                        enemies, enemyHp = enemies + 1, enemyHp + math.max(0, e.HitPoints)
                        for _, flag in ipairs(rules.enemy_flags or {}) do
                            if e:HasEntityFlags(assert(EntityFlag[flag], flag)) then
                                increment(enemyFlags, flag)
                            end
                        end
                    end
                    local pickup = e:ToPickup()
                    if pickup then
                        if e.Variant == PickupVariant.PICKUP_TAROTCARD then
                            local card = Isaac.GetItemConfig():GetCard(e.SubType)
                            if card and card.CardType == ItemConfig.CARDTYPE_RUNE then
                                runeDrops = runeDrops + 1
                            end
                        end
                        local value = {
                            seed = e.InitSeed,
                            variant = e.Variant,
                            subtype = e.SubType,
                            price = pickup.Price,
                        }
                        if e.Variant == PickupVariant.PICKUP_COLLECTIBLE then
                            pedestalOptions[tostring(e.InitSeed)] = pickup.OptionsPickupIndex
                            value.enum = collectibleNames[e.SubType]
                            pedestals[#pedestals + 1] = value
                        else
                            pickups[#pickups + 1] = value
                            increment(pickupTypes, pickupNames[e.Variant] or tostring(e.Variant))
                        end
                        if e.Variant == PickupVariant.PICKUP_COIN then
                            coinValue = coinValue + pickup:GetCoinValue()
                        end
                    end
                    if
                        rules.returned_pill
                        and e.Type == EntityType.ENTITY_PICKUP
                        and e.Variant == PickupVariant.PICKUP_PILL
                        and Game():GetItemPool():GetPillEffect(e.SubType, p)
                            == PillEffect[rules.returned_pill]
                    then
                        returnedPills = returnedPills + 1
                    end
                end
            end
            local tearCount = 0
            local redRooms = 0
            if rules.red_rooms then
                local rooms = Game():GetLevel():GetRooms()
                for i = 0, rooms.Size - 1 do
                    if rooms:Get(i).Flags & RoomDescriptor.FLAG_RED_ROOM ~= 0 then
                        redRooms = redRooms + 1
                    end
                end
            end
            local map = {}
            local inventory = {}
            if
                rules.reroll_inventory
                or rules.sacrifice_familiars
                or rules.acquire_generated
                or rules.form_swap_trial
            then
                for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
                    local count = p:GetCollectibleNum(id, true)
                    if count > 0 then
                        inventory[#inventory + 1] = { id = id, count = count }
                    end
                end
            end
            local pillConversions = {}
            local pillMapping = {}
            if rules.pill_conversion then
                for color = 1, PillColor.NUM_PILLS - 1 do
                    pillMapping[#pillMapping + 1] = {
                        color = color,
                        effect = Game():GetItemPool():GetPillEffect(color, p),
                        identified = Game():GetItemPool():IsPillIdentified(color),
                    }
                end
            end
            for _, trial in ipairs(pillTrials) do
                pillConversions[#pillConversions + 1] = {
                    original = trial.original,
                    expected = trial.expected,
                    actual = Game():GetItemPool():GetPillEffect(trial.color, p),
                    identified = Game():GetItemPool():IsPillIdentified(trial.color),
                }
            end
            if rules.map or rules.observe_map then
                local rooms = Game():GetLevel():GetRooms()
                for i = 0, rooms.Size - 1 do
                    local descriptor = rooms:Get(i)
                    if descriptor.Data and descriptor.SafeGridIndex >= 0 then
                        map[#map + 1] = {
                            index = descriptor.SafeGridIndex,
                            type = descriptor.Data.Type,
                            flags = descriptor.DisplayFlags,
                        }
                    end
                end
                table.sort(map, function(a, b)
                    return a.index < b.index
                end)
            end
            for _ in pairs(entityCounts) do
                tearCount = tearCount + 1
            end
            table.sort(pickups, function(a, b)
                return a.seed < b.seed
            end)
            table.sort(explosives, function(a, b)
                return a.seed < b.seed
            end)
            table.sort(pedestals, function(a, b)
                return a.seed < b.seed
            end)
            for _, name in ipairs(rules.null_effects or {}) do
                nullEffects[name] = p:GetEffects():HasNullEffect(assert(NullItemID[name], name))
            end
            local generatedOwned = 0
            if generatedIdentity then
                local id = generatedIdentity >= 0x80000000 and generatedIdentity - 0x100000000
                    or generatedIdentity
                generatedOwned = id < 0 and _IsaacLan.generated_item_count(p:GetSprite(), id)
                    or p:GetCollectibleNum(id, true)
                if p:GetActiveItem() == id then
                    generatedOwned = math.max(1, generatedOwned)
                end
            end
            if rules.camouflage_trial and label == "captured" then
                local players = {}
                for slot, head in pairs(_IsaacLan.rooms_heads()) do
                    local player = Isaac.GetPlayer(head)
                    local color, spriteColor = player.Color, player:GetSprite().Color
                    players[slot] = {
                        no_target = player:HasEntityFlags(EntityFlag.FLAG_NO_TARGET),
                        camo = player:HasCollectible(CollectibleType.COLLECTIBLE_CAMO_UNDIES),
                        faded = player:HasTrinket(TrinketType.TRINKET_FADED_POLAROID),
                        visible = player.Visible,
                        alpha = color.A,
                        sprite_alpha = spriteColor.A,
                        speed = player.MoveSpeed,
                        dead = player:IsDead(),
                        ghost = player:IsCoopGhost(),
                    }
                end
                report("camouflage_actor_state", { tick = tick, players = players })
            end
            report("trigger_probe", {
                tick = tick,
                label = label,
                room = location.index,
                room_visible = roomVisible,
                room_type = roomObserved and roomNames[room:GetType()] or nil,
                stage = Game():GetLevel():GetStage(),
                stage_name = stageNames[Game():GetLevel():GetStage()],
                watch_state = roomObserved
                        and (rules.watch_trial and room:GetBrokenWatchState() or 0)
                    or nil,
                curses = Game():GetLevel():GetCurses(),
                grids = grids,
                doors = doors,
                map = map,
                red_rooms = redRooms,
                x = p.Position.X,
                y = p.Position.Y,
                vx = p.Velocity.X,
                vy = p.Velocity.Y,
                damage = p.Damage,
                delay = p.MaxFireDelay,
                speed = p.MoveSpeed,
                range = p.TearRange,
                shot_speed = p.ShotSpeed,
                luck = p.Luck,
                scale_x = p.SpriteScale.X,
                hearts = p:GetHearts(),
                max_hearts = p:GetMaxHearts(),
                soul = p:GetSoulHearts(),
                coins = p:GetNumCoins(),
                bombs = p:GetNumBombs(),
                keys = p:GetNumKeys(),
                broken = p:GetBrokenHearts(),
                bone = p:GetBoneHearts(),
                rotten = p:GetRottenHearts(),
                eternal = p:GetEternalHearts(),
                extra_lives = p:GetExtraLives(),
                player_type = playerNames[p:GetPlayerType()],
                visible = p.Visible,
                rune_drops = runeDrops,
                charge = p:GetActiveCharge(),
                active_item = collectibleNames[p:GetActiveItem()],
                inventory = inventory,
                enemy_types = enemyTypes,
                trinket_multiplier = rules.trinket_before and p:GetTrinketMultiplier(
                    assert(TrinketType[rules.trinket_before])
                ) or 0,
                trinket_slots = p:GetMaxTrinkets(),
                initial_tear_scale = initialTearScale,
                battery = p:GetBatteryCharge(),
                card = p:GetCard(0),
                pill = p:GetPill(0),
                card_second = p:GetCard(1),
                pill_second = p:GetPill(1),
                pocket_slots = p:GetMaxPocketItems(),
                generated_owned = generatedOwned,
                trinket = p:GetTrinket(0),
                smelted = p:GetTrinket(0) == 0 and p:HasTrinket(TrinketType.TRINKET_CURVED_HORN),
                familiar_count = familiarCount,
                friendly_count = friendlyCount,
                familiars = familiars,
                familiar_positions = familiarPositions,
                pill_conversions = pillConversions,
                pill_mapping = pillMapping,
                effects = effects,
                stomping_feet = stompingFeet,
                tear_flags = tearFlags,
                tear_count = tearCount,
                laser_count = laserCount,
                lasers = lasers,
                explosives = explosives,
                knives = knives,
                tears = tears,
                enemy_flags = enemyFlags,
                enemy_hp = enemyHp,
                enemy_count = enemies,
                spawned = spawned,
                returned_pills = returnedPills,
                rock_crushed = crushed,
                poop_count = poopCount,
                rock_count = rockCount,
                pickups = pickups,
                pedestals = pedestals,
                pickup_count = #pickups,
                pickup_types = pickupTypes,
                coin_value = coinValue,
                breakfast_count = p:GetCollectibleNum(CollectibleType.COLLECTIBLE_BREAKFAST, true),
                dead = p:IsDead(),
                ghost = p:IsCoopGhost(),
                flying = p.CanFly,
                null_effects = nullEffects,
                invincible = p:HasInvincibility(),
                damage_cooldown = p:GetDamageCooldown(),
                can_shoot = p:CanShoot(),
                adult = p:HasPlayerForm(PlayerForm.PLAYERFORM_ADULTHOOD),
                targets = targets,
                bosses = bosses,
                pedestal_options = pedestalOptions,
                projectiles = projectiles,
                attracted_x = attractionPickup
                        and attractionPickup:Exists()
                        and attractionPickup.Position.X
                    or nil,
                obstacle_intact = roomObserved and obstacleIndex ~= nil and room:GetGridCollision(
                    obstacleIndex
                ) == GridCollisionClass.COLLISION_SOLID,
            })
        end)
    end
    return {
        projectileCollision = projectileTrials.collision,
        suppressPlayerTear = function(tear)
            if
                not (enabled(current) and current.trigger_effects.suppress_player_tears)
                or tear.FrameCount == 0
            then
                return
            end
            local source = tear.SpawnerEntity
            if source and source:ToPlayer() then
                for _, name in ipairs(current.trigger_effects.keep_player_tear_variants or {}) do
                    if tear.Variant == TearVariant[name] then
                        return
                    end
                end
                tear:Remove()
            end
        end,
        startingRoom = function(case)
            if
                not (
                    enabled(case)
                    and (case.trigger_effects.secret_doors or case.trigger_effects.secret_adjacent)
                )
            then
                return nil
            end
            local level = Game():GetLevel()
            local rooms = level:GetRooms()
            for i = 0, rooms.Size - 1 do
                local descriptor = rooms:Get(i)
                if descriptor.Data and descriptor.Data.Type == RoomType.ROOM_SECRET then
                    local secret = descriptor.SafeGridIndex
                    for _, offset in ipairs({ -1, 1, -13, 13 }) do
                        local index = secret + offset
                        if
                            index >= 0
                            and index < 169
                            and (
                                math.abs(offset) ~= 1
                                or math.floor(index / 13) == math.floor(secret / 13)
                            )
                        then
                            local neighbor = level:GetRoomByIdx(index, 0)
                            if
                                neighbor.Data
                                and neighbor.Data.Type == RoomType.ROOM_DEFAULT
                                and neighbor.Data.Shape == RoomShape.ROOMSHAPE_1x1
                            then
                                return index
                            end
                        end
                    end
                end
            end
            error("No ordinary room adjacent to a secret room")
        end,
        damage = birthrightTrials.damage,
        pickupInit = birthrightTrials.pickupInit,
        holdTarget = function(npc)
            if npc:GetData().auditTrinketKnockback then
                -- Suppress steering while preserving native collision impulses.
                local data = npc:GetData()
                if data.auditTrinketKnockbackOrigin then
                    npc.Position = Vector(table.unpack(data.auditTrinketKnockbackOrigin))
                    npc.Velocity = Vector.Zero
                    data.auditTrinketKnockbackOrigin = nil
                    data.auditTrinketKnockbackPeak = 0
                end
                data.auditTrinketKnockbackPeak =
                    math.max(data.auditTrinketKnockbackPeak or 0, npc.Velocity:Length())
                return true
            end
            if enabled(current) and npc:GetData().auditTriggerTarget then
                if npc:IsDead() then
                    -- Death updates own native kill rewards and timer extensions.
                    return false
                end
                local rules = current.trigger_effects
                local data = npc:GetData()
                if data.auditTargetWarmupHealth then
                    if npc.FrameCount < 3 then
                        return false
                    end
                    npc.MaxHitPoints, npc.HitPoints =
                        data.auditTargetWarmupHealth, data.auditTargetWarmupHealth
                    data.auditTargetWarmupHealth = nil
                end
                data.auditTriggerUpdates = (data.auditTriggerUpdates or 0) + 1
                npc.Velocity = rules.movement_rate and Vector(2, 0) or Vector.Zero
                if rules.target_velocity then
                    npc.Velocity = Vector(table.unpack(rules.target_velocity))
                end
                if rules.lift_rock and nativeTick >= 75 and rockIndex then
                    npc.Position = Game():GetRoom():GetGridPosition(rockIndex) - Vector(0, 60)
                end
                if rules.cursor_target and nativeTick >= 70 and nativeTick <= 180 then
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        if
                            entity.Type == EntityType.ENTITY_EFFECT
                            and entity.Variant == EffectVariant[rules.cursor_target]
                        then
                            npc.Position = entity.Position
                            data.auditCursorAligned = (data.auditCursorAligned or 0) + 1
                            break
                        end
                    end
                end
                if rules.taurus_trial then
                    local head = _IsaacLan.rooms_heads()[tostring(current.slot)]
                    local p = head and Isaac.GetPlayer(head)
                    if p and p:HasInvincibility() then
                        npc.Position = p.Position
                    end
                end
                if rules.shadow_contact_trial and nativeTick >= 90 and nativeTick <= 300 then
                    local head = _IsaacLan.rooms_heads()[tostring(current.slot)]
                    local p = head and Isaac.GetPlayer(head)
                    if p and p.Velocity:Length() > 1 then
                        npc.Position = p.Position - p.Velocity:Resized(40)
                    end
                end
                if
                    nativeTick >= (rules.align_from or 100)
                    and nativeTick <= (rules.observe_until or 300)
                then
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:Exists() then
                            local matched = rules.target_familiar
                                    and e.Type == EntityType.ENTITY_FAMILIAR
                                    and e.Variant == FamiliarVariant[rules.target_familiar]
                                or rules.target_effect
                                    and e.Type == EntityType.ENTITY_EFFECT
                                    and e.Variant == EffectVariant[rules.target_effect]
                            if
                                rules.target_effect_prefix
                                and e.Type == EntityType.ENTITY_EFFECT
                            then
                                for name, variant in pairs(EffectVariant) do
                                    if
                                        variant == e.Variant
                                        and name:sub(1, #rules.target_effect_prefix)
                                            == rules.target_effect_prefix
                                    then
                                        matched = true
                                    end
                                end
                            end
                            if matched then
                                npc.Position = e.Position
                                data.auditAligned = (data.auditAligned or 0) + 1
                                break
                            elseif rules.target_laser and e:ToLaser() then
                                npc.Position = e.Position
                                    + Vector.FromAngle(e:ToLaser().AngleDegrees) * 80
                                data.auditAligned = (data.auditAligned or 0) + 1
                                break
                            elseif rules.target_bomb and e:ToBomb() then
                                npc.Position = e.Position
                                data.auditAligned = (data.auditAligned or 0) + 1
                                break
                            elseif
                                rules.target_entity
                                and e.Type == EntityType[rules.target_entity]
                            then
                                npc.Position = e.Position
                                data.auditAligned = (data.auditAligned or 0) + 1
                                break
                            end
                        end
                    end
                end
                return true
            end
        end,
        prepare = function(case, tick)
            local rules = enabled(case)
            if not rules then
                return
            end
            reset(case)
            interactions.prepare(case, tick)
            projectileTrials.prepare(case, tick)
            trinketTrials.prepare(case, tick)
            birthrightTrials.prepare(case, tick)
            if rules.camouflage_trial then
                actor(1 - case.slot, function(p)
                    p:SetMinDamageCooldown(2 * case.end_tick + 60)
                end)
            end
            if rules.peer_item then
                actor(1 - case.slot, function(p)
                    local id = assert(CollectibleType[rules.peer_item])
                    p:AddCollectible(id, 0, true)
                    report(
                        "native_peer_prerequisite",
                        { tick = tick, item = id, owned = p:HasCollectible(id) }
                    )
                end)
            end
            actor(case.slot, function(p, room)
                if rules.character_before then
                    assert(
                        p:GetPlayerType() == PlayerType[rules.character_before],
                        "Native starting character differs"
                    )
                end
                if rules.repeat_damage then
                    p:AddMaxHearts(24 - p:GetMaxHearts(), false)
                    p:AddSoulHearts(-p:GetSoulHearts())
                    p:AddHearts(24 - p:GetHearts())
                end
                if rules.full_health_before then
                    p:AddHearts(p:GetMaxHearts() - p:GetHearts())
                end
                if rules.health_before then
                    p:AddHearts(rules.health_before - p:GetHearts())
                end
                if rules.curse_before then
                    Game():GetLevel():AddCurse(assert(LevelCurse[rules.curse_before]), false)
                end
                if rules.inventory_prerequisite then
                    for _, id in ipairs({
                        CollectibleType.COLLECTIBLE_BREAKFAST,
                        CollectibleType.COLLECTIBLE_MINI_MUSH,
                        CollectibleType.COLLECTIBLE_ROID_RAGE,
                    }) do
                        p:AddCollectible(id, 0, false)
                    end
                end
                for _, name in ipairs(rules.prerequisite_items or {}) do
                    p:AddCollectible(
                        assert(CollectibleType[name]),
                        0,
                        rules.prerequisite_first_time == true
                    )
                end
                if rules.trinket_before then
                    p:AddTrinket(assert(TrinketType[rules.trinket_before]), false)
                end
                if rules.blue_flies_before then
                    p:AddBlueFlies(rules.blue_flies_before, p.Position, nil)
                end
                if rules.coins_before then
                    p:AddCoins(rules.coins_before - p:GetNumCoins())
                end
                if rules.keys_before then
                    p:AddKeys(rules.keys_before - p:GetNumKeys())
                end
                if rules.range_before then
                    p.TearRange = rules.range_before
                end
                if rules.larger_tears then
                    local tear = p:FireTear(p.Position, Vector(0, -10), false, true, false)
                    initialTearScale = tear.Scale
                    tear:Remove()
                end
                if rules.hazard_trial then
                    p:AddMaxHearts(24 - p:GetMaxHearts(), false)
                    p:AddHearts(24 - p:GetHearts())
                end
                if rules.wide_lane then
                    p.Position, p.Velocity = room:GetCenterPos() - Vector(180, 0), Vector.Zero
                end
                if rules.drop_resources then
                    p:AddCoins(6 - p:GetNumCoins())
                    p:AddBombs(4 - p:GetNumBombs())
                    p:AddKeys(3 - p:GetNumKeys())
                end
                if rules.priced_pickups then
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        local pickup = e:ToPickup()
                        if pickup then
                            pickup.Price, pickup.AutoUpdatePrice, pickup.ShopItemId = 15, false, 1
                        end
                    end
                    local devil = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        CollectibleType.COLLECTIBLE_LUNCH,
                        room:GetCenterPos() + Vector(100, 100),
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    devil.Price, devil.AutoUpdatePrice, devil.ShopItemId =
                        PickupPrice.PRICE_ONE_HEART, false, 2
                end
                if rules.locked_doors then
                    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                        local door = room:GetDoor(slot)
                        if door then
                            door:Close(true)
                            door:SetLocked(true)
                        end
                    end
                end
                if rules.prior_active then
                    local item = assert(CollectibleType[rules.prior_active])
                    p:AddCollectible(
                        item,
                        Isaac.GetItemConfig():GetCollectible(item).MaxCharges,
                        false
                    )
                end
                if rules.active_before then
                    local item = assert(CollectibleType[rules.active_before])
                    p:AddCollectible(
                        item,
                        rules.charge_before or Isaac.GetItemConfig():GetCollectible(item).MaxCharges,
                        false
                    )
                end
                if rules.pocket_card then
                    p:SetCard(0, assert(Card[rules.pocket_card]))
                end
                if rules.pocket_pill then
                    p:SetPill(
                        0,
                        Game()
                            :GetItemPool()
                            :ForceAddPillEffect(assert(PillEffect[rules.pocket_pill]))
                    )
                end
                for original, converted in pairs(rules.pill_conversion or {}) do
                    pillTrials[#pillTrials + 1] = {
                        original = assert(PillEffect[original]),
                        expected = assert(PillEffect[converted]),
                        color = Game()
                            :GetItemPool()
                            :ForceAddPillEffect(assert(PillEffect[original])),
                    }
                end
                if rules.loose_pickups then
                    for i, variant in ipairs({
                        PickupVariant.PICKUP_COIN,
                        PickupVariant.PICKUP_KEY,
                        PickupVariant.PICKUP_BOMB,
                        PickupVariant.PICKUP_HEART,
                    }) do
                        Isaac.Spawn(
                            EntityType.ENTITY_PICKUP,
                            variant,
                            1,
                            room:GetCenterPos() + Vector(-100 + i * 40, -100),
                            Vector.Zero,
                            nil
                        )
                    end
                end
                if rules.empty_active then
                    p:AddCollectible(
                        CollectibleType[rules.active_item or "COLLECTIBLE_D6"],
                        0,
                        false
                    )
                end
                if rules.smelt then
                    p:AddTrinket(TrinketType.TRINKET_CURVED_HORN, false)
                end
                if rules.prior_pill then
                    local effect = PillEffect.PILLEFFECT_BALLS_OF_STEEL
                    local color = Game():GetItemPool():ForceAddPillEffect(effect)
                    p:UsePill(effect, color, 0)
                end
                if rules.puberty then
                    local color =
                        Game():GetItemPool():ForceAddPillEffect(PillEffect.PILLEFFECT_PUBERTY)
                    p:UsePill(PillEffect.PILLEFFECT_PUBERTY, color, 0)
                    p:UsePill(PillEffect.PILLEFFECT_PUBERTY, color, 0)
                end
                if (rules.enemies or 0) > 0 then
                    if
                        not rules.invulnerable
                        and not rules.damage_trigger
                        and not rules.soul_damage_trigger
                    then
                        p:SetMinDamageCooldown(2 * (case.end_tick or 180) + 60)
                    end
                    room:SetClear(false)
                end
                if rules.bomb_trial then
                    p:SetMinDamageCooldown(2 * (case.end_tick or 180) + 60)
                end
                for i = 1, rules.enemies or rules.kill_before or 0 do
                    local position = p.Position
                        + (rules.aim_target and Vector(25, -100) or Vector((i - 1.5) * 25, -25))
                    if rules.target_offset then
                        position = p.Position
                            + Vector(rules.target_offset[1], rules.target_offset[2])
                    end
                    if rules.spectral_target then
                        position = p.Position - Vector(0, rules.piercing and 100 + i * 40 or 100)
                    elseif rules.piercing then
                        position = p.Position - Vector(0, 30 + i * 40)
                    elseif rules.behind_target then
                        position = p.Position + Vector(0, 65)
                    elseif rules.contact_target then
                        position = p.Position + Vector(100, -60)
                    elseif rules.hit_target then
                        position = p.Position - Vector(0, rules.target_distance or 85)
                    elseif rules.damage_trigger then
                        position = p.Position - Vector(0, 50)
                    elseif rules.distant_bomb_target then
                        position = p.Position - Vector(0, 200)
                    elseif rules.bomb_homing then
                        position = p.Position + Vector(55, -50)
                    elseif rules.kill_before then
                        position = room:GetCenterPos() + Vector(-160 + i * 60, -90)
                    end
                    local e = Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, position, Vector.Zero, nil)
                    e:AddEntityFlags(
                        EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK
                    )
                    e:GetData().auditTriggerTarget = true
                    e.MaxHitPoints, e.HitPoints = rules.target_hp or 500, rules.target_hp or 500
                    if i == 1 and rules.first_enemy_hp then
                        e.MaxHitPoints, e.HitPoints = rules.first_enemy_hp, rules.first_enemy_hp
                    end
                    e:GetData().auditTargetWarmupHealth = e.HitPoints
                end
                if rules.attract_pickup then
                    attractionPickup = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COIN,
                        CoinSubType.COIN_PENNY,
                        p.Position + Vector(70, -65),
                        Vector.Zero,
                        nil
                    )
                end
            end)
            snapshot(case, tick, "before")
        end,
        advance = function(case, tick)
            nativeTick = tick
            local rules = enabled(case)
            if not rules then
                return
            end
            interactions.advance(case, tick)
            projectileTrials.advance(case, tick)
            trinketTrials.advance(case, tick)
            birthrightTrials.advance(case, tick)
            if rules.native_door and tick == 210 then
                actor(case.slot, function(p)
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsActiveEnemy(false) then
                            e:TakeDamage(100000, 0, EntityRef(p), 0)
                        end
                    end
                end)
            end
            if rules.native_door and tick == 240 then
                actor(case.slot, function(p, room)
                    local door = assert(
                        room:GetDoor(DoorSlot.DOWN0),
                        "Native door trial requires lower door"
                    )
                    assert(door:IsOpen(), "Native door trial requires a cleared room")
                    p.Position, p.Velocity = door.Position - Vector(0, 25), Vector.Zero
                    p:SetMinDamageCooldown(case.end_tick + 60)
                    report(
                        "native_door_attempt",
                        { tick = tick, room = room:GetType(), slot = DoorSlot.DOWN0 }
                    )
                end)
            end
            if rules.floor_recharge and tick == 240 then
                moveFloor()
            end
            if rules.floor_visit then
                local visit = rules.floor_visit
                if tick == 90 then
                    if visit.stage then
                        actor(case.slot, function(p)
                            Game()
                                :GetLevel()
                                :SetStage(LevelStage[visit.stage], StageType.STAGETYPE_ORIGINAL)
                            Game():StartStageTransition(true, 0, p)
                        end)
                    else
                        moveFloor()
                    end
                end
                if tick == 420 and visit.room then
                    local rooms = Game():GetLevel():GetRooms()
                    local destination
                    for i = 0, rooms.Size - 1 do
                        local d = rooms:Get(i)
                        if d.Data and d.Data.Type == RoomType[visit.room] then
                            destination = d.SafeGridIndex
                            break
                        end
                    end
                    if not destination and visit.optional then
                        report(
                            "native_room_prerequisite_missing",
                            { tick = tick, room_type = visit.room }
                        )
                        return
                    end
                    assert(destination, "Generated floor lacks required native room")
                    actor(case.slot, function(p)
                        p:SetMinDamageCooldown(600)
                    end)
                    if visit.native_transition then
                        actor(case.slot, function(p)
                            Game():StartRoomTransition(
                                destination,
                                Direction.NO_DIRECTION,
                                RoomTransitionAnim.TELEPORT,
                                p,
                                -1
                            )
                        end)
                    else
                        assert(_IsaacLan.rooms_move(case.slot, destination, 0, -1))
                        if not case.split then
                            assert(_IsaacLan.rooms_move(1 - case.slot, destination, 0, -1))
                        end
                    end
                    report(
                        "floor_room_visit",
                        { tick = tick, target = destination, kind = visit.room }
                    )
                end
                local killTick = visit.kill_tick or 480
                if
                    tick == (visit.kill_boss and killTick or 480)
                    or visit.kill_repeated
                        and tick > killTick
                        and tick <= killTick + 150
                        and (tick - killTick) % 15 == 0
                then
                    actor(case.slot, function(p, room)
                        if visit.kill_boss then
                            local count = 0
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                if e:IsActiveEnemy(false) then
                                    if e:IsBoss() then
                                        count = count + 1
                                    end
                                    if rules.deal_item_trial then
                                        e:Kill()
                                    else
                                        e:TakeDamage(100000, 0, EntityRef(p), 0)
                                    end
                                end
                            end
                            report("native_bosses_defeated", { tick = tick, count = count })
                        elseif visit.moonlight then
                            p.Position = room:GetCenterPos()
                        elseif visit.stairs then
                            local found
                            for i = 0, room:GetGridSize() - 1 do
                                local grid = room:GetGridEntity(i)
                                if
                                    grid
                                    and (
                                        grid:GetType() == GridEntityType.GRID_STAIRS
                                        or grid:GetType() == GridEntityType.GRID_TRAPDOOR
                                    )
                                then
                                    p.Position = grid.Position
                                    found = true
                                    break
                                end
                            end
                            assert(found, "Member Card entrance missing")
                        elseif visit.ladder or visit.portal then
                            local variant = visit.ladder and EffectVariant.TALL_LADDER
                                or EffectVariant.PORTAL_TELEPORT
                            local found
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                if e.Type == EntityType.ENTITY_EFFECT and e.Variant == variant then
                                    p.Position = e.Position
                                    found = true
                                    break
                                end
                            end
                            assert(found, "Floor entrance effect missing")
                        end
                    end)
                end
                if tick == 450 and (visit.kill_boss or visit.choice) then
                    actor(case.slot, function(p, room)
                        p.Position, p.Velocity = room:GetCenterPos() + Vector(0, 100), Vector.Zero
                    end)
                end
                if visit.choice and tick == 600 then
                    actor(case.slot, function(p)
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local pickup = e:ToPickup()
                            if
                                pickup
                                and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
                                and pickup.OptionsPickupIndex ~= 0
                            then
                                pickup.Wait = 0
                                p.Position = pickup.Position
                                report("choose_reward", {
                                    tick = tick,
                                    seed = pickup.InitSeed,
                                    options = pickup.OptionsPickupIndex,
                                })
                                break
                            end
                        end
                    end)
                end
            end
            if rules.fireplace_trial and tick == 180 then
                moveRoom()
            end
            if rules.fireplace_trial and (tick == 90 or tick == 330) then
                for slot = 0, 1 do
                    actor(slot, function(p)
                        p:AddSoulHearts(-p:GetSoulHearts())
                        p:AddHearts(6 - p:GetHearts())
                        p:ResetDamageCooldown()
                        local fire = Isaac.Spawn(
                            EntityType.ENTITY_FIREPLACE,
                            0,
                            0,
                            p.Position,
                            Vector.Zero,
                            nil
                        )
                        fire:GetData().auditFireplace = true
                        report("fireplace_contact", {
                            tick = tick,
                            slot = slot,
                            hearts = p:GetHearts(),
                            seed = fire.InitSeed,
                        })
                    end)
                end
            end
            if rules.fireplace_trial and (tick == 150 or tick == 390) then
                for slot = 0, 1 do
                    actor(slot, function(p)
                        report(
                            "fireplace_result",
                            { tick = tick, slot = slot, hearts = p:GetHearts() }
                        )
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:GetData().auditFireplace then
                                e:Remove()
                            end
                        end
                    end)
                end
            end
            if
                rules.consume_pickup
                and tick >= 90
                and (tick - 90) % 30 == 0
                and (tick - 90) / 30 < (rules.consume_pickup.count or 1)
            then
                actor(case.slot, function(p)
                    if
                        rules.consume_pickup.variant == "PICKUP_HEART"
                        and rules.consume_pickup.subtype <= 2
                    then
                        p:AddHearts(2 - p:GetHearts())
                    end
                end)
                snapshot(case, tick, "before_pickup")
                actor(case.slot, function(p)
                    local pickup = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        assert(PickupVariant[rules.consume_pickup.variant]),
                        rules.consume_pickup.subtype,
                        p.Position,
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    pickup.Wait = 0
                    report("effect_pickup_placed", { tick = tick, seed = pickup.InitSeed })
                end)
            end
            if rules.pocket_conversion and tick == 90 then
                actor(case.slot, function(p)
                    local cards = rules.pocket_conversion == "cards"
                    if cards then
                        p:SetCard(0, Card.CARD_FOOL)
                        p:SetCard(1, Card.CARD_MAGICIAN)
                    else
                        p:SetPill(0, PillColor.PILL_BLUE_BLUE)
                        p:SetPill(1, PillColor.PILL_WHITE_BLUE)
                    end
                    Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        cards and PickupVariant.PICKUP_PILL or PickupVariant.PICKUP_TAROTCARD,
                        cards and PillColor.PILL_BLUE_BLUE or Card.CARD_FOOL,
                        p.Position + Vector(100, 100),
                        Vector.Zero,
                        nil
                    )
                    report("pocket_conversion_spawned", { tick = tick, cards = cards })
                end)
            end
            if rules.generated_pedestals and tick == 90 then
                actor(case.slot, function(p, room)
                    local e = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        0,
                        room:GetCenterPos() + Vector(-100, -100),
                        Vector.Zero,
                        nil
                    )
                    e:GetData().auditGenerated = true
                    generatedIdentity = e.SubType
                    report(
                        "generated_pedestal",
                        { tick = tick, seed = e.InitSeed, subtype = e.SubType }
                    )
                end)
            end
            if rules.acquire_generated and tick == 180 then
                actor(case.slot, function(p)
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:GetData().auditGenerated then
                            e:ToPickup().Wait = 0
                            p.Position = e.Position
                            report(
                                "acquire_generated_attempt",
                                { tick = tick, subtype = e.SubType }
                            )
                        end
                    end
                end)
            end
            if rules.reroll_on_floor and tick == 240 then
                moveFloor()
            end
            if pendingSeriesDamage then
                actor(case.slot, function(p)
                    pendingSeriesDamage.after = p:GetHearts() + p:GetSoulHearts()
                    report("repeated_damage_trial", pendingSeriesDamage)
                end)
                pendingSeriesDamage = nil
            end
            if
                rules.repeat_damage
                and tick >= 90
                and (tick - 90) % 9 == 0
                and (tick - 90) / 9 < rules.repeat_damage
            then
                actor(case.slot, function(p)
                    p:AddHearts(24 - p:GetHearts())
                    p:ResetDamageCooldown()
                    pendingSeriesDamage =
                        { tick = tick, before = p:GetHearts() + p:GetSoulHearts() }
                    p:TakeDamage(1, 0, EntityRef(p), 0)
                end)
            end
            if rules.low_health_after_acquire and tick == 80 then
                actor(case.slot, function(p)
                    p:AddHearts(rules.low_health_after_acquire[1] - p:GetHearts())
                    p:AddSoulHearts(rules.low_health_after_acquire[2] - p:GetSoulHearts())
                end)
            end
            if
                rules.repeat_uses
                and tick >= 57
                and (tick - 57) % (rules.repeat_interval or 30) == 0
                and (tick - 57) / (rules.repeat_interval or 30) < rules.repeat_uses
                and (not rules.repeat_without_recharge or tick == 57)
            then
                actor(case.slot, function(p)
                    p:SetActiveCharge(Isaac.GetItemConfig():GetCollectible(case.id).MaxCharges)
                    report("repeat_use_charge", { tick = tick, charge = p:GetActiveCharge() })
                end)
            end
            if rules.soul_damage_trigger and tick == 90 then
                snapshot(case, tick, "before_hit")
                actor(case.slot, function(p)
                    p:ResetDamageCooldown()
                    p:TakeDamage(1, 0, EntityRef(p), 0)
                end)
            end
            if
                rules.battery_pickups and (tick == 90 or rules.battery_pickups > 1 and tick == 150)
            then
                actor(case.slot, function(p)
                    local pickup = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_LIL_BATTERY,
                        BatterySubType.BATTERY_NORMAL,
                        p.Position,
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    pickup.Wait = 0
                    report("native_battery_pickup", { tick = tick, seed = pickup.InitSeed })
                end)
            end
            if rules.passive_rate and tick == 180 then
                actor(case.slot, function(p)
                    p:RemoveCollectible(case.id)
                end)
            end
            if rules.passive_rate and tick == 210 then
                actor(case.slot, function(_, room)
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:GetData().auditTriggerTarget then
                            e:Remove()
                        end
                    end
                    local e = Isaac.Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        0,
                        room:GetCenterPos() - Vector(150, 60),
                        Vector.Zero,
                        nil
                    )
                    e:GetData().auditTriggerTarget = true
                    e.MaxHitPoints, e.HitPoints = 500, 500
                end)
            end
            if
                rules.floor_bonus
                or rules.floor_oath
                or rules.floor_pickup
                or rules.floor_pickup_any
            then
                if tick == 237 then
                    snapshot(case, tick, "before_floor")
                end
                if tick == 240 then
                    moveFloor()
                end
            end
            if (rules.destroy_fixture_rocks or rules.destroy_fixture_poops) and tick == 90 then
                actor(case.slot, function(_, room)
                    for i = 0, room:GetGridSize() - 1 do
                        local grid = room:GetGridEntity(i)
                        if
                            grid
                            and (
                                (
                                    rules.destroy_fixture_rocks
                                    and grid:GetType() == GridEntityType.GRID_ROCK
                                )
                                or (
                                    rules.destroy_fixture_poops
                                    and grid:GetType() == GridEntityType.GRID_POOP
                                )
                            )
                        then
                            grid:Destroy(false)
                        end
                    end
                end)
            end
            if rules.idle_shield and (tick == 120 or tick == 270) then
                actor(case.slot, function(p)
                    report("idle_shield_attempt", { tick = tick, hearts = p:GetHearts() })
                    p:TakeDamage(1, 0, EntityRef(p), 0)
                end)
            end
            if rules.revive_chance and tick == 85 then
                actor(case.slot, function(p)
                    local rng = p:GetTrinketRNG(case.id)
                    for seed = 1, 1000 do
                        rng:SetSeed(seed, 35)
                        local roll = rng:RandomFloat()
                        if roll < rules.revive_chance then
                            rng:SetSeed(seed, 35)
                            report(
                                "revival_rng_prerequisite",
                                { seed = seed, roll = roll, tick = tick }
                            )
                            break
                        end
                    end
                end)
            end
            if rules.revive and tick == 90 then
                actor(case.slot, function(p)
                    if rules.revive_natural_damage then
                        p:ResetDamageCooldown()
                        p:TakeDamage(1000, 0, EntityRef(p), 0)
                    else
                        p:Kill()
                    end
                end)
            end
            if rules.toenail_trial and tick == 75 then
                actor(case.slot, function(_, room)
                    room:SetClear(false)
                    report("toenail_hostile_prerequisite", {
                        tick = tick,
                        clear = room:IsClear(),
                        enemies = room:GetAliveEnemiesCount(),
                    })
                end)
            end
            if (rules.kill_before and tick == 45) or (rules.kill_after and tick == 100) then
                actor(case.slot, function(p)
                    local killed = 0
                    local killedSeeds = {}
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:GetData().auditTriggerTarget then
                            if rules.kill_limit and killed >= rules.kill_limit then
                                break
                            end
                            killed = killed + 1
                            killedSeeds[#killedSeeds + 1] = e.InitSeed
                            if rules.kill_with_tears then
                                local tear = p:FireTear(
                                    e.Position - Vector(0, 5),
                                    Vector(0, 10),
                                    false,
                                    true,
                                    false
                                )
                                tear.CollisionDamage = 10000
                            else
                                e:TakeDamage(10000, 0, EntityRef(p), 0)
                            end
                        end
                    end
                    if rules.kill_limit then
                        report("fixture_kill_targets", { tick = tick, seeds = killedSeeds })
                    end
                end)
            end
            if rules.repeat_active and tick == (case.use_tick or 60) - 3 then
                snapshot(case, tick, "before_repeat")
            end
            if rules.swap_familiar and tick == (case.use_tick or 60) - 3 then
                snapshot(case, tick, "before_swap")
            end
            if rules.swap_familiar and tick == (case.use_tick or 60) - 10 then
                actor(case.slot, function(p)
                    p:ResetDamageCooldown()
                end)
            end
            if rules.swap_familiar and (tick == (case.use_tick or 60) + 4 or tick == 210) then
                actor(case.slot, function(p)
                    report("swap_damage_trial", { tick = tick, cooldown = p:GetDamageCooldown() })
                    p:TakeDamage(1, 0, EntityRef(p), 0)
                end)
            end
            if rules.random_native_effect and tick == (case.use_tick or 60) - 3 then
                snapshot(case, tick, "before_random")
            end
            if rules.consumed_active and tick == 120 then
                actor(case.slot, function(p)
                    assert(p:GetActiveItem() == 0, "Active item was not consumed")
                    p:AddCollectible(CollectibleType.COLLECTIBLE_D6, 0, false)
                end)
            end
            if rules.shield_trial and (tick == 120 or tick == 420) then
                actor(case.slot, function(p)
                    report("shield_damage_attempt", { tick = tick, hearts = p:GetHearts() })
                    p:TakeDamage(1, 0, EntityRef(p), 0)
                end)
            end
            if
                rules.repel_projectile
                and (
                    tick == 90
                    or rules.reflect_projectiles
                        and tick >= 96
                        and tick <= 156
                        and tick % 6 == 0
                )
            then
                actor(case.slot, function(p)
                    Isaac.Spawn(
                        EntityType.ENTITY_PROJECTILE,
                        0,
                        0,
                        p.Position
                            + (
                                rules.projectile_offset
                                    and Vector(table.unpack(rules.projectile_offset))
                                or Vector(100, -50)
                            ),
                        rules.projectile_velocity
                                and Vector(table.unpack(rules.projectile_velocity))
                            or Vector(-4, 2),
                        nil
                    )
                    report("incoming_projectile", { tick = tick })
                end)
            end
            if rules.revival_card and tick == 240 then
                actor(case.slot, function(p)
                    p:SetCard(0, case.id)
                    p:ResetDamageCooldown()
                    report(
                        "held_card_fatal_damage",
                        { tick = tick, hearts = p:GetHearts(), card = p:GetCard(0) }
                    )
                    p:TakeDamage(10, 0, EntityRef(p), 0)
                end)
            end
            if rules.hazard_trial and tick == 300 then
                -- Prove the initial native damage, then keep the holder alive
                -- long enough to observe the full effect lifetime.
                actor(case.slot, function(p)
                    p:SetMinDamageCooldown(case.end_tick)
                end)
            end
            if rules.rate_lifecycle then
                if tick == 180 then
                    moveRoom()
                elseif tick == 330 then
                    moveFloor()
                elseif tick == 240 or tick == 600 then
                    actor(case.slot, function(p, room)
                        room:SetClear(false)
                        local npc = Isaac.Spawn(
                            EntityType.ENTITY_GAPER,
                            0,
                            0,
                            room:GetCenterPos() - Vector(150, 60),
                            Vector.Zero,
                            nil
                        )
                        npc:GetData().auditTriggerTarget = true
                        npc:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK)
                        npc.MaxHitPoints, npc.HitPoints = 500, 500
                    end)
                end
            end
            if rules.rate_recurrence and (tick == 960 or tick == 1860) then
                actor(case.slot, function(_, room)
                    for _, npc in ipairs(Isaac.GetRoomEntities()) do
                        if npc.Type == EntityType.ENTITY_GAPER then
                            npc:Remove()
                        end
                    end
                    local npc = Isaac.Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        0,
                        room:GetCenterPos() - Vector(150, 60),
                        Vector.Zero,
                        nil
                    )
                    npc:GetData().auditTriggerTarget = true
                    npc:AddEntityFlags(
                        EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK
                    )
                    npc.MaxHitPoints, npc.HitPoints = 500, 500
                    report("rate_target_replaced", { tick = tick, seed = npc.InitSeed })
                end)
            end
            if rules.damage_trigger and tick == 90 then
                snapshot(case, tick, "before_hit")
                actor(case.slot, function(p)
                    p:ResetDamageCooldown()
                    p:TakeDamage(1, 0, EntityRef(p), 0)
                end)
            end
            if rules.prevent_fatal and tick == 90 then
                actor(case.slot, function(p)
                    p:ResetDamageCooldown()
                    p:TakeDamage(1000, 0, EntityRef(p), 0)
                end)
            end
            if rules.vulnerability and (tick == 120 or tick == 1000) then
                actor(case.slot, function(p)
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:GetData().auditTriggerTarget then
                            report("vulnerability_hit", { tick = tick, before = e.HitPoints })
                            e:TakeDamage(10, 0, EntityRef(p), 0)
                        end
                    end
                end)
            end
            if rules.floor_reset and tick == 240 then
                moveFloor()
            end
            if tick == 45 then
                -- Removal in prepare is queued by the game. Wait for native
                -- updates before placing new grid prerequisites in that room.
                actor(case.slot, function(p, room)
                    if rules.luck then
                        p.Luck = rules.luck
                    end
                    if rules.rng_seed then
                        local rng = case.kind == "trinket" and p:GetTrinketRNG(case.id)
                            or p:GetCollectibleRNG(case.id)
                        rng:SetSeed(rules.rng_seed, 35)
                    end
                    if rules.range_before then
                        p.TearRange = rules.range_before
                    end
                    if rules.bounce_wall then
                        p.Position = room:GetClampedPosition(
                            Vector(room:GetBottomRightPos().X - 55, room:GetCenterPos().Y),
                            20
                        )
                        p.Velocity = Vector.Zero
                    end
                    for i = 1, rules.rocks or 0 do
                        local index = room:GetGridIndex(
                            rules.rocks_ahead and p.Position - Vector(0, i * 40)
                                or room:GetCenterPos() + Vector(i * 40, -80)
                        )
                        assert(not room:GetGridEntity(index), "Rock fixture grid occupied")
                        assert(room:SpawnGridEntity(index, GridEntityType.GRID_ROCK, 0, 187 + i, 0))
                    end
                    if rules.spectral_target then
                        obstacleIndex = room:GetGridIndex(p.Position - Vector(0, 55))
                        assert(
                            not room:GetGridEntity(obstacleIndex),
                            "Spectral trial grid occupied"
                        )
                        assert(
                            room:SpawnGridEntity(obstacleIndex, GridEntityType.GRID_ROCK, 0, 187, 0)
                        )
                    end
                    for i = 1, rules.poops or 0 do
                        local index = room:GetGridIndex(room:GetCenterPos() + Vector(i * 40, -80))
                        assert(not room:GetGridEntity(index), "Infestation fixture grid occupied")
                        assert(room:SpawnGridEntity(index, GridEntityType.GRID_POOP, 0, 187 + i, 0))
                    end
                    if rules.crush_rock then
                        room:Update()
                        rockIndex = room:GetGridIndex(room:GetCenterPos() + Vector(80, -80))
                        assert(not room:GetGridEntity(rockIndex), "Giant trial grid occupied")
                        assert(room:SpawnGridEntity(rockIndex, GridEntityType.GRID_ROCK, 0, 187, 0))
                        room:GetGridEntity(rockIndex):Update()
                        room:Update()
                    end
                end)
            end
            if rules.lift_rock and tick == 75 then
                actor(case.slot, function(p, room)
                    p.Position, p.Velocity =
                        room:GetGridPosition(rockIndex) + Vector(0, 40), Vector.Zero
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:GetData().auditTriggerTarget then
                            e.Position = p.Position - Vector(0, 100)
                        end
                    end
                end)
            end
            if rules.lift_rock and (tick == 89 or tick == 105 or tick == 135) then
                actor(case.slot, function(p, room)
                    report("bracelet_native_aim", {
                        tick = tick,
                        direction = p:GetHeadDirection(),
                        x = p.Position.X,
                        y = p.Position.Y,
                        rock_x = room:GetGridPosition(rockIndex).X,
                        rock_y = room:GetGridPosition(rockIndex).Y,
                        collision = room:GetGridCollision(rockIndex),
                    })
                end)
            end
            if rules.crush_rock and not rules.lift_rock and tick == 105 then
                actor(case.slot, function(p, room)
                    p.Position, p.Velocity =
                        room:GetGridPosition(rockIndex)
                            + ((rules.axe or rules.lift_rock) and Vector(0, 40) or Vector.Zero),
                        Vector.Zero
                end)
            end
            if
                rules.crush_rock
                and tick == (rules.lift_rock and 240 or rules.axe and 180 or 120)
            then
                actor(case.slot, function(_, room)
                    crushed = room:GetGridCollision(rockIndex) ~= GridCollisionClass.COLLISION_SOLID
                end)
            end
            if rules.contact_target and tick == (rules.contact_tick or 90) then
                actor(case.slot, function(p)
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:GetData().auditTriggerTarget then
                            p.Position, p.Velocity = e.Position, Vector.Zero
                            break
                        end
                    end
                end)
            end
            if rules.contact_target and tick == 150 then
                actor(case.slot, function(p, room)
                    p.Position, p.Velocity = room:GetCenterPos() - Vector(100, 0), Vector.Zero
                end)
            end
            if
                rules.expire_room
                and not rules.native_door
                and not moved
                and tick >= (rules.room_tick or 180)
            then
                moved = true
                moveRoom()
            end
        end,
        sample = function(case, tick, host)
            if enabled(case) and tick >= 45 and (tick % 3 == 0 or (tick >= 60 and tick <= 69)) then
                snapshot(case, tick, host and "captured" or "replica")
                interactions.sample(case, tick)
                projectileTrials.sample(case, tick)
            end
        end,
        input = function(case, tick)
            local rules = enabled(case)
            local trinketInput = trinketTrials.input(case, tick)
            if trinketInput then
                return trinketInput
            end
            if rules and rules.button_intervals then
                local mask = 0
                for _, interval in ipairs(rules.button_intervals) do
                    if tick >= interval[1] and tick < interval[2] then
                        mask = mask | (1 << assert(ButtonAction[interval[3]]))
                    end
                end
                return mask
            end
            if rules and rules.native_door and tick >= 240 and tick < 270 then
                return (1 << ButtonAction.ACTION_DOWN) | (1 << ButtonAction.ACTION_SHOOTUP)
            end
            if rules and rules.face_target and tick >= 45 and tick < 51 then
                return 1 << ButtonAction.ACTION_UP
            end
            if rules and rules.release_pause and tick >= 210 and tick < 216 then
                return 1 << ButtonAction.ACTION_SHOOTUP
            end
            if rules and rules.idle_shield and tick >= 210 then
                return 1 << ButtonAction.ACTION_SHOOTUP
            end
            if rules and rules.swap_familiar and tick >= 45 and tick < 90 then
                return 1 << ButtonAction.ACTION_SHOOTRIGHT
            end
            if rules and rules.invulnerable and tick >= 75 and tick < case.end_tick - 10 then
                return 1 << ButtonAction.ACTION_SHOOTUP
            end
            if
                rules
                and (rules.paralysis or rules.poop_trail or rules.immobile_shooting)
                and tick >= 75
                and tick < case.end_tick - 10
            then
                return (1 << ButtonAction.ACTION_RIGHT) | (1 << ButtonAction.ACTION_SHOOTUP)
            end
            if
                rules
                and rules.shoot
                and tick >= (rules.shoot_from or 70)
                and tick < (rules.shoot_until or 140)
            then
                if rules.steered_tears and tick >= 100 then
                    return 1 << ButtonAction.ACTION_SHOOTRIGHT
                end
                local mask = 1
                    << (
                        rules.wide_lane and ButtonAction.ACTION_SHOOTRIGHT
                        or ButtonAction.ACTION_SHOOTUP
                    )
                if rules.beam and tick >= 90 and tick < 100 then
                    mask = mask | (1 << ButtonAction.ACTION_RIGHT)
                end
                if rules.diagonal_input then
                    mask = mask | (1 << ButtonAction.ACTION_SHOOTRIGHT)
                end
                return mask
            end
            return 0
        end,
    }
end
