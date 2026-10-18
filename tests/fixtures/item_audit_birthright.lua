return function(report, actor, moveRoom, moveFloor)
    local SAMSON_BERSERK_MAX_CHARGE = 100000
    local twinBefore, choice, pending, poolBefore, protected
    local activeCase, target, clots, initialCoins, spawnedInventory, rangeTargets
    local inventoryBefore, salvageSpawned, coinTargets, coinEmissions, stagedCoins
    local inventoryItems = {
        "COLLECTIBLE_BREAKFAST",
        "COLLECTIBLE_STEVEN",
        "COLLECTIBLE_SAD_ONION",
        "COLLECTIBLE_WIRE_COAT_HANGER",
        "COLLECTIBLE_BLOOD_MARTYR",
        "COLLECTIBLE_ROID_RAGE",
        "COLLECTIBLE_MINI_MUSH",
        "COLLECTIBLE_MEAT",
        "COLLECTIBLE_SCREW",
        "COLLECTIBLE_SPEED_BALL",
        "COLLECTIBLE_SAFETY_PIN",
        "COLLECTIBLE_MAGIC_SCAB",
        "COLLECTIBLE_GLASS_EYE",
    }
    local copiedItems = { "COLLECTIBLE_STEVEN", "COLLECTIBLE_MINI_MUSH", "COLLECTIBLE_SAD_ONION" }
    local function owner(case, callback)
        actor(case.slot, function(p, room)
            if case.trigger_effects.birthright_twin then
                p = assert(p:GetOtherTwin(), "Birthright requires the native Esau twin")
            end
            callback(p, room)
        end)
    end
    local function clearPickups()
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:ToPickup() then
                e:Remove()
            end
        end
    end
    local function inventoryCount(p, names)
        local count = 0
        for _, name in ipairs(names) do
            if p:HasCollectible(CollectibleType[name]) then
                count = count + 1
            end
        end
        return count
    end
    local function passiveInventory(p)
        local items, count = {}, 0
        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
            local config = Isaac.GetItemConfig():GetCollectible(id)
            if
                config
                and config.Type ~= ItemType.ITEM_ACTIVE
                and id ~= CollectibleType.COLLECTIBLE_BIRTHRIGHT
            then
                local owned = p:GetCollectibleNum(id, true)
                if owned > 0 then
                    items[tostring(id)] = owned
                    count = count + owned
                end
            end
        end
        return items, count
    end
    local function charge(p, slot)
        local id = p:GetActiveItem(slot)
        if id > 0 then
            p:SetActiveCharge(Isaac.GetItemConfig():GetCollectible(id).MaxCharges, slot)
        end
    end
    local function createTarget(p, offset)
        local npc =
            Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, p.Position + offset, Vector.Zero, nil)
                :ToNPC()
        npc:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        npc:GetData().auditTriggerTarget = true
        npc:GetData().auditTargetWarmupHealth = 10000
        npc.MaxHitPoints, npc.HitPoints = 10000, 10000
        return npc
    end
    local function forgottenBody(p)
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            local f = e:ToFamiliar()
            if
                f
                and f.Variant == FamiliarVariant.FORGOTTEN_BODY
                and f.Player
                and f.Player.ControllerIndex == p.ControllerIndex
            then
                return f
            end
        end
    end
    local function sample(p, room, tick, phase)
        local birds, slots, esaus, chains, wisps = 0, 0, 0, 0, {}
        local chainEndpoints, esauStates = {}, {}
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            local f = e:ToFamiliar()
            if f and f.Player and f.Player.InitSeed == p.InitSeed then
                if f.Variant == FamiliarVariant.DEAD_BIRD and f.Visible then
                    birds = birds + 1
                end
                if f.Variant == FamiliarVariant.ITEM_WISP then
                    local config = Isaac.GetItemConfig():GetCollectible(f.SubType)
                    wisps[#wisps + 1] = {
                        quality = config and config.Quality or -1,
                        health = f.HitPoints,
                        id = f.SubType,
                    }
                end
            end
            slots = slots + (e.Type == EntityType.ENTITY_SLOT and 1 or 0)
            esaus = esaus + (e.Type == EntityType.ENTITY_DARK_ESAU and e.Variant == 0 and 1 or 0)
            if e.Type == EntityType.ENTITY_DARK_ESAU then
                esauStates[#esauStates + 1] = {
                    seed = e.InitSeed,
                    animation = e:GetSprite():GetAnimation(),
                    state = e:ToNPC().State,
                }
            end
            if e.Type == EntityType.ENTITY_EFFECT and e.Variant == EffectVariant.ANIMA_CHAIN then
                chainEndpoints[#chainEndpoints + 1] = {
                    parent = e.Parent and e.Parent.Type,
                    target = e.Target and e.Target.Type,
                    child = e.Child and e.Child.Type,
                }
                if
                    e.Parent and e.Parent.Type == EntityType.ENTITY_DARK_ESAU
                    or e.Target and e.Target.Type == EntityType.ENTITY_DARK_ESAU
                    or e.Child and e.Child.Type == EntityType.ENTITY_DARK_ESAU
                then
                    chains = chains + 1
                end
            end
        end
        report("birthright_state", {
            tick = tick,
            phase = phase,
            owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
            limit = p:GetHeartLimit(),
            max_hearts = p:GetMaxHearts(),
            hearts = p:GetHearts(),
            soul = p:GetSoulHearts(),
            dead = p:IsDead(),
            damage = p.Damage,
            belial = p:HasCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL),
            passive_belial = p:HasCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL_PASSIVE),
            active = p:GetActiveItem(),
            room_type = room:GetType(),
            slots = slots,
            babylon = p:GetEffects()
                :GetCollectibleEffectNum(CollectibleType.COLLECTIBLE_WHORE_OF_BABYLON),
            birds = birds,
            poop = p:GetPoopMana(),
            wisps = wisps,
            esaus = esaus,
            chained_esaus = chains,
            anima_endpoints = chainEndpoints,
            esau_states = esauStates,
        })
    end
    local function lostPool(p, tick)
        local useless = {
            [CollectibleType.COLLECTIBLE_BREAKFAST] = true,
            [CollectibleType.COLLECTIBLE_LUNCH] = true,
            [CollectibleType.COLLECTIBLE_DINNER] = true,
            [CollectibleType.COLLECTIBLE_DESSERT] = true,
            [CollectibleType.COLLECTIBLE_ROTTEN_MEAT] = true,
            [CollectibleType.COLLECTIBLE_HEART] = true,
            [CollectibleType.COLLECTIBLE_RAW_LIVER] = true,
        }
        local count = 0
        for i = 1, 1024 do
            local id = Game()
                :GetItemPool()
                :GetCollectible(ItemPoolType.POOL_BOSS, false, 100003 + i * 7919)
            count = count + (useless[id] and 1 or 0)
        end
        report("birthright_lost_pool", {
            tick = tick,
            owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
            useless = count,
        })
    end
    return {
        pickupInit = function(pickup)
            if salvageSpawned and pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
                salvageSpawned[tostring(pickup.InitSeed)] = {
                    variant = pickup.Variant,
                    subtype = pickup.SubType,
                }
            end
            if coinEmissions and pickup.Variant == PickupVariant.PICKUP_COIN then
                coinEmissions[tostring(pickup.InitSeed)] = true
            end
        end,
        damage = function(entity, amount, source)
            local rules = activeCase
                and activeCase.trigger_effects
                and activeCase.trigger_effects.birthright_trial
            local from = source and source.Entity
            if not rules or not entity:ToNPC() or not from then
                return
            end
            if rules.mode == "gello" then
                local head = _IsaacLan.rooms_heads()[tostring(activeCase.slot)]
                local p = head and Isaac.GetPlayer(head)
                if p and entity:GetData().auditTriggerTarget then
                    report("birthright_gello_damage", {
                        tick = _IsaacLanStatus().verified,
                        amount = amount,
                        owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                        player_damage = p.Damage,
                        source_type = from.Type,
                        source_variant = from.Variant,
                        parent_type = from.Parent and from.Parent.Type,
                        spawner_type = from.SpawnerEntity and from.SpawnerEntity.Type,
                    })
                end
            elseif rules.mode == "lazarus_ghost" then
                local player = from:ToPlayer()
                    or from.SpawnerEntity and from.SpawnerEntity:ToPlayer()
                if player then
                    local head = _IsaacLan.rooms_heads()[tostring(activeCase.slot)]
                    local main = head and Isaac.GetPlayer(head)
                    if main then
                        report("birthright_lazarus_damage", {
                            tick = _IsaacLanStatus().verified,
                            amount = amount,
                            player_type = player:GetPlayerType(),
                            ghost = GetPtrHash(player) ~= GetPtrHash(main),
                        })
                    end
                end
            end
        end,
        prepare = function(case, tick)
            twinBefore, choice, pending, poolBefore, protected = nil, nil, nil, nil, nil
            activeCase, target, clots, initialCoins, spawnedInventory = case, nil, 0, nil, nil
            rangeTargets = {}
            inventoryBefore = nil
            salvageSpawned = nil
            coinTargets, coinEmissions, stagedCoins = {}, nil, 0
            local rules = case.trigger_effects and case.trigger_effects.birthright_trial
            if not rules then
                return
            end
            owner(case, function(p, room)
                if rules.mode == "twin_items" then
                    local twin = assert(p:GetOtherTwin())
                    for _, name in ipairs(copiedItems) do
                        twin:AddCollectible(CollectibleType[name], 0, true)
                    end
                    twinBefore = inventoryCount(p, copiedItems)
                elseif rules.mode == "eden_choice" then
                    clearPickups()
                elseif rules.mode == "soul_upgrade" then
                    p:AddSoulHearts(4 - p:GetSoulHearts())
                elseif rules.mode == "protected_items" then
                    for _, name in ipairs(copiedItems) do
                        p:AddCollectible(CollectibleType[name], 0, true)
                    end
                    protected = {}
                    for _, name in ipairs(copiedItems) do
                        protected[name] = p:GetCollectibleNum(CollectibleType[name], true)
                    end
                elseif rules.mode == "bloodlust" then
                    p:AddMaxHearts(24 - p:GetMaxHearts(), false)
                    p:AddHearts(24 - p:GetHearts())
                elseif rules.mode == "lost_pool" then
                    lostPool(p, tick)
                elseif rules.mode == "inventory_slots" then
                    for i = 1, 8 do
                        local id = CollectibleType[inventoryItems[i]]
                        if not p:HasCollectible(id) then
                            p:AddCollectible(id, 0, true)
                        end
                    end
                elseif rules.mode == "clot_hearts" then
                    p:AddMaxHearts(24 - p:GetMaxHearts(), false)
                    p:AddHearts(24 - p:GetHearts())
                end
                sample(p, room, tick, "before")
            end)
        end,
        advance = function(case, tick)
            local rules = case.trigger_effects and case.trigger_effects.birthright_trial
            if not rules then
                return
            end
            if rules.mode == "lazarus_ghost" then
                if tick == 300 then
                    moveRoom()
                    return
                end
                if tick == 450 then
                    moveFloor()
                    return
                end
            end
            owner(case, function(p, room)
                if rules.mode == "void" then
                    if tick == 60 then
                        clearPickups()
                        for i = 1, 6 do
                            Isaac.Spawn(
                                EntityType.ENTITY_PICKUP,
                                PickupVariant.PICKUP_COLLECTIBLE,
                                CollectibleType[inventoryItems[i]],
                                room:GetCenterPos() + Vector(i * 30 - 105, -70),
                                Vector.Zero,
                                nil
                            )
                        end
                    elseif tick == 150 then
                        report("birthright_void_absorbed", {
                            tick = tick,
                            pickups = Isaac.CountEntities(
                                nil,
                                EntityType.ENTITY_PICKUP,
                                PickupVariant.PICKUP_COLLECTIBLE,
                                -1
                            ),
                            damage = p.Damage,
                            speed = p.MoveSpeed,
                            delay = p.MaxFireDelay,
                        })
                    elseif
                        tick >= 207
                        and tick < 207 + rules.attempts * 60
                        and (tick - 207) % 60 == 0
                    then
                        clearPickups()
                        charge(p, ActiveSlot.SLOT_PRIMARY)
                    elseif
                        tick >= 240
                        and tick < 240 + rules.attempts * 60
                        and (tick - 240) % 60 == 0
                    then
                        local items = {}
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_PICKUP
                                and e.Variant == PickupVariant.PICKUP_COLLECTIBLE
                            then
                                items[#items + 1] = e.SubType
                            end
                        end
                        report("birthright_void_returned", {
                            tick = tick,
                            items = items,
                            damage = p.Damage,
                            speed = p.MoveSpeed,
                            delay = p.MaxFireDelay,
                        })
                    end
                elseif rules.mode == "chain" then
                    if tick == 60 then
                        p:RemoveCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
                    elseif tick == 240 then
                        p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, true)
                    end
                    if tick == 105 or tick == 240 then
                        p.Position, p.Velocity =
                            room:GetCenterPos() + Vector(-150, 100), Vector.Zero
                        local body = assert(forgottenBody(p), "Native Forgotten body missing")
                        body.Position, body.Velocity = p.Position, Vector.Zero
                    end
                    if tick == 210 or tick == 360 then
                        local other = forgottenBody(p)
                        report("birthright_soul_chain", {
                            tick = tick,
                            owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                            found = other ~= nil,
                            distance = other and p.Position:Distance(other.Position) or -1,
                        })
                    end
                elseif rules.mode == "inventory_slots" then
                    local index, offset = math.floor((tick - 90) / 180) + 9, (tick - 90) % 180
                    if tick >= 90 and index <= 13 then
                        if offset == 0 then
                            clearPickups()
                            inventoryBefore = passiveInventory(p)
                            spawnedInventory = Isaac.Spawn(
                                EntityType.ENTITY_PICKUP,
                                PickupVariant.PICKUP_COLLECTIBLE,
                                CollectibleType[inventoryItems[index]],
                                p.Position - Vector(0, 70),
                                Vector.Zero,
                                nil
                            )
                        elseif offset == 30 then
                            -- Capacity is the subject here; keep the selected
                            -- pedestal passive while the native actor picks it up.
                            spawnedInventory:ToPickup():Morph(
                                EntityType.ENTITY_PICKUP,
                                PickupVariant.PICKUP_COLLECTIBLE,
                                CollectibleType[inventoryItems[index]],
                                true,
                                true,
                                false
                            )
                            spawnedInventory:ToPickup().Wait = 0
                            p.Position = spawnedInventory.Position
                        elseif offset > 30 and offset < 150 then
                            local inventory = passiveInventory(p)
                            for id, owned in pairs(inventory) do
                                if owned > (inventoryBefore[id] or 0) then
                                    p.Position, p.Velocity =
                                        room:GetCenterPos() + Vector(0, 120), Vector.Zero
                                    break
                                end
                            end
                        elseif offset == 150 then
                            local inventory, count = passiveInventory(p)
                            local acquired, replaced = false, false
                            for id, owned in pairs(inventory) do
                                if owned > (inventoryBefore[id] or 0) then
                                    acquired = true
                                end
                            end
                            for id, owned in pairs(inventoryBefore) do
                                if (inventory[id] or 0) < owned then
                                    replaced = true
                                end
                            end
                            report("birthright_inventory_capacity", {
                                tick = tick,
                                index = index,
                                owned = count,
                                inventory = inventory,
                                new_item = acquired,
                                consumed = not spawnedInventory:Exists()
                                    or spawnedInventory.SubType == 0,
                                replaced = replaced,
                            })
                        end
                    end
                elseif rules.mode == "dark_arts_range" or rules.mode == "sneeze_range" then
                    if tick == 60 or tick == 300 then
                        if target and target:Exists() then
                            target:Remove()
                        end
                        if tick == 60 then
                            p:RemoveCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
                        else
                            p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, true)
                        end
                        for _, entry in ipairs(rangeTargets) do
                            if entry.entity:Exists() then
                                entry.entity:Remove()
                            end
                        end
                        rangeTargets = {}
                        if rules.mode == "sneeze_range" then
                            for _, distance in ipairs({ 75, 110, 150, 190, 230 }) do
                                rangeTargets[#rangeTargets + 1] = {
                                    distance = distance,
                                    entity = createTarget(p, Vector(0, -distance)),
                                }
                            end
                        else
                            target = createTarget(p, Vector(35, 0))
                        end
                        p:SetMinDamageCooldown(600)
                        charge(p, ActiveSlot.SLOT_POCKET)
                    elseif tick == 210 or tick == 450 then
                        local samples = {}
                        for _, entry in ipairs(rangeTargets) do
                            samples[#samples + 1] = {
                                distance = entry.distance,
                                damage = 10000 - entry.entity.HitPoints,
                                marked = entry.entity:HasEntityFlags(
                                    EntityFlag.FLAG_BRIMSTONE_MARKED
                                ),
                            }
                        end
                        report("birthright_native_ability_range", {
                            tick = tick,
                            owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                            damage = target and 10000 - target.HitPoints or 0,
                            marked = target
                                    and target:HasEntityFlags(EntityFlag.FLAG_BRIMSTONE_MARKED)
                                or false,
                            targets = samples,
                        })
                    end
                elseif rules.mode == "clot_hearts" then
                    if tick == 300 then
                        clearPickups()
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local f = e:ToFamiliar()
                            if
                                f
                                and f.Variant == FamiliarVariant.BLOOD_BABY
                                and f.Player
                                and f.Player.InitSeed == p.InitSeed
                            then
                                clots = clots + 1
                                f:TakeDamage(1000, 0, EntityRef(nil), 0)
                            end
                        end
                    elseif tick == 330 or tick == 405 then
                        local hearts = {}
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local pickup = e:ToPickup()
                            if pickup and pickup.Variant == PickupVariant.PICKUP_HEART then
                                hearts[#hearts + 1] =
                                    { subtype = pickup.SubType, timeout = pickup.Timeout }
                            end
                        end
                        report(
                            "birthright_clot_hearts",
                            { tick = tick, clots = clots, hearts = hearts }
                        )
                    end
                elseif rules.mode == "berserk_duration" then
                    if tick == 60 or tick == 630 then
                        if tick == 60 then
                            p:RemoveCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
                        else
                            p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, true)
                        end
                        target = createTarget(p, Vector(0, -45))
                        p.SamsonBerserkCharge = 0
                    elseif tick == 90 or tick == 660 then
                        p.SamsonBerserkCharge = SAMSON_BERSERK_MAX_CHARGE
                    elseif tick == 210 or tick == 780 then
                        report("birthright_berserk_kill_prerequisite", {
                            tick = tick,
                            active = p:HasWeaponType(WeaponType.WEAPON_BONE),
                        })
                        target.MaxHitPoints, target.HitPoints = 1, 1
                    elseif tick == 300 or tick == 870 then
                        report(
                            "birthright_berserk_kill",
                            { tick = tick, killed = not target:Exists() or target:IsDead() }
                        )
                    end
                    if tick % 3 == 0 then
                        report("birthright_berserk_timer", {
                            tick = tick,
                            owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                            active = p:HasWeaponType(WeaponType.WEAPON_BONE),
                            damage = p.Damage,
                        })
                    end
                elseif rules.mode == "lazarus_ghost" then
                    if tick == 165 then
                        charge(p, ActiveSlot.SLOT_POCKET)
                    end
                    if tick == 120 or tick == 240 or tick == 390 or tick == 810 then
                        local other = p:GetOtherTwin()
                        local before, after
                        if other then
                            before = other:GetHearts() + other:GetSoulHearts()
                            other:ResetDamageCooldown()
                            other:TakeDamage(1, 0, EntityRef(p), 0)
                            after = other:GetHearts() + other:GetSoulHearts()
                        end
                        report("birthright_lazarus_pair", {
                            tick = tick,
                            found = other ~= nil,
                            player_type = p:GetPlayerType(),
                            other_type = other and other:GetPlayerType(),
                            other_owned = other
                                and other:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                            other_visible = other and other.Visible,
                            before = before,
                            after = after,
                            room = Game():GetLevel():GetCurrentRoomIndex(),
                            stage = Game():GetLevel():GetStage(),
                        })
                    end
                elseif rules.mode == "gello" then
                    if tick == 60 then
                        p:RemoveCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
                    elseif tick == 210 then
                        p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, true)
                    end
                    if tick == 135 or tick == 285 then
                        local gello, follower
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local f = e:ToFamiliar()
                            if f and f.Player and f.Player.InitSeed == p.InitSeed then
                                if f.Variant == FamiliarVariant.UMBILICAL_BABY then
                                    gello = f
                                end
                                if f.Variant == FamiliarVariant.BROTHER_BOBBY then
                                    follower = f
                                end
                            end
                        end
                        report("birthright_gello_follower", {
                            tick = tick,
                            owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                            found = gello ~= nil and follower ~= nil,
                            player_distance = follower and follower.Position:Distance(p.Position),
                            gello_distance = gello
                                and follower
                                and follower.Position:Distance(gello.Position),
                        })
                    end
                elseif rules.mode == "enemy_coins" then
                    p:SetMinDamageCooldown(case.end_tick * 2)
                    local staging = tick >= 120 and tick <= 135 or tick >= 300 and tick <= 315
                    if staging and coinEmissions then
                        stagedCoins = 0
                        for _, entity in ipairs(Isaac.GetRoomEntities()) do
                            if entity:ToPickup() and coinEmissions[tostring(entity.InitSeed)] then
                                entity.Position, entity.Velocity =
                                    p.Position + Vector(60, 0), Vector.Zero
                                stagedCoins = stagedCoins + 1
                            end
                        end
                        initialCoins = p:GetNumCoins()
                    end
                    if tick == 60 or tick == 240 then
                        stagedCoins = 0
                        p.Position, p.Velocity = room:GetCenterPos() - Vector(140, 0), Vector.Zero
                        for i = 0, Game():GetNumPlayers() - 1 do
                            local teammate = Isaac.GetPlayer(i)
                            if teammate.InitSeed ~= p.InitSeed then
                                teammate.Position, teammate.Velocity =
                                    room:GetCenterPos() - Vector(0, 140), Vector.Zero
                                teammate:SetMinDamageCooldown(case.end_tick * 2)
                            end
                        end
                        clearPickups()
                        if tick == 60 then
                            p:RemoveCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
                        else
                            p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, true)
                        end
                        coinTargets, coinEmissions = {}, {}
                        for _ = 1, 16 do
                            local enemy = createTarget(p, Vector(60, 0))
                            enemy.EntityCollisionClass = EntityCollisionClass.ENTCOLL_PLAYERONLY
                            coinTargets[#coinTargets + 1] = enemy
                        end
                        initialCoins = p:GetNumCoins()
                    elseif tick == 120 or tick == 300 then
                        for _, enemy in ipairs(coinTargets) do
                            enemy:GetData().auditTriggerTarget = nil
                            enemy:TakeDamage(100000, 0, EntityRef(p), 0)
                        end
                    elseif tick == 210 or tick == 390 then
                        local killed, emitted = 0, 0
                        for _, enemy in ipairs(coinTargets) do
                            killed = killed + ((not enemy:Exists() or enemy:IsDead()) and 1 or 0)
                        end
                        for _ in pairs(coinEmissions) do
                            emitted = emitted + 1
                        end
                        report("birthright_keeper_coins", {
                            tick = tick,
                            owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                            killed = killed == 16,
                            emitted = emitted,
                            staged = stagedCoins,
                            gained = p:GetNumCoins() - initialCoins,
                        })
                        coinEmissions = nil
                    end
                elseif rules.mode == "abyss_attack" then
                    if tick == 60 then
                        clearPickups()
                        Isaac.Spawn(
                            EntityType.ENTITY_PICKUP,
                            PickupVariant.PICKUP_COLLECTIBLE,
                            CollectibleType.COLLECTIBLE_SAD_ONION,
                            room:GetCenterPos(),
                            Vector.Zero,
                            nil
                        )
                    elseif tick == 150 then
                        p:RemoveCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
                        target = createTarget(p, Vector(0, -100))
                    elseif tick == 390 then
                        p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, true)
                    end
                    if tick >= 180 and tick % 3 == 0 and target then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local f = e:ToFamiliar()
                            if
                                f
                                and f.Variant == FamiliarVariant.ABYSS_LOCUST
                                and f.Player
                                and f.Player.InitSeed == p.InitSeed
                            then
                                report("birthright_locust_target", {
                                    tick = tick,
                                    owned = p:HasCollectible(
                                        CollectibleType.COLLECTIBLE_BIRTHRIGHT
                                    ),
                                    seed = f.InitSeed,
                                    distance = f.Position:Distance(target.Position),
                                    damage = 10000 - target.HitPoints,
                                })
                            end
                        end
                    end
                elseif rules.mode == "recall" and tick == 150 then
                    local holder = p:GetOtherTwin() or p
                    local thrown = holder:ThrowHeldEntity(Vector(-12, 0))
                    if thrown then
                        thrown.Position = holder.Position - Vector(60, 0)
                    end
                    report("birthright_native_throw", {
                        tick = tick,
                        found = thrown ~= nil,
                        type = thrown and thrown.Type,
                    })
                elseif rules.mode == "recall" and (tick == 210 or tick == 360) then
                    local other = p:GetOtherTwin()
                    local bodies = {}
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if
                            e.Type == EntityType.ENTITY_FAMILIAR
                            and e.Variant == FamiliarVariant.FORGOTTEN_BODY
                        then
                            bodies[#bodies + 1] = {
                                x = e.Position.X,
                                y = e.Position.Y,
                                distance = p.Position:Distance(e.Position),
                            }
                        end
                    end
                    report("birthright_native_recall", {
                        tick = tick,
                        found = other ~= nil,
                        distance = other and p.Position:Distance(other.Position) or -1,
                        player_type = p:GetPlayerType(),
                        other_type = other and other:GetPlayerType(),
                        same_entity = other and GetPtrHash(p) == GetPtrHash(other),
                        bodies = bodies,
                        primary_pocket = p:GetActiveItem(ActiveSlot.SLOT_POCKET),
                        other_pocket = other and other:GetActiveItem(ActiveSlot.SLOT_POCKET),
                    })
                end
                if rules.mode == "heart_limit" and tick == 90 then
                    p:AddMaxHearts(40, false)
                    p:AddHearts(40)
                elseif rules.mode == "soul_upgrade" and tick == 90 then
                    local before = p:GetSoulHearts()
                    p:AddCollectible(CollectibleType.COLLECTIBLE_LUNCH, 0, true)
                    report(
                        "birthright_health_upgrade",
                        { tick = tick, before = before, after = p:GetSoulHearts() }
                    )
                elseif
                    rules.mode == "bloodlust"
                    and tick >= 90
                    and tick <= 270
                    and (tick - 90) % 20 == 0
                then
                    p:AddHearts(24 - p:GetHearts())
                    p:ResetDamageCooldown()
                    local before = p:GetHearts()
                    p:TakeDamage(1, 0, EntityRef(p), 0)
                    report(
                        "birthright_bloodlust_hit",
                        { tick = tick, before = before, after = p:GetHearts(), damage = p.Damage }
                    )
                elseif rules.mode == "beam" then
                    if tick == 60 then
                        p:RemoveCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
                    elseif tick == 210 then
                        p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, true)
                    end
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:ToLaser() then
                            report("birthright_beam", {
                                tick = tick,
                                owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                                size = e.Size,
                            })
                        end
                    end
                elseif rules.mode == "eden_choice" then
                    if tick == 90 then
                        choice = { options = {}, owned = {} }
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local pickup = e:ToPickup()
                            if
                                pickup
                                and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
                                and pickup.OptionsPickupIndex > 0
                            then
                                choice.options[#choice.options + 1] = pickup
                                choice.owned[pickup.SubType] =
                                    p:GetCollectibleNum(pickup.SubType, true)
                            end
                        end
                        if choice.options[1] then
                            p.Position = choice.options[1].Position
                        end
                    elseif tick == 210 then
                        local acquired, remaining = false, 0
                        for _, pickup in ipairs(choice.options) do
                            remaining = remaining
                                + (pickup:Exists() and pickup.SubType > 0 and 1 or 0)
                        end
                        for id, count in pairs(choice.owned) do
                            acquired = acquired or p:GetCollectibleNum(id, true) > count
                        end
                        report("birthright_eden_choice", {
                            tick = tick,
                            options = #choice.options,
                            acquired = acquired,
                            remaining = remaining,
                        })
                    end
                elseif rules.mode == "lost_pool" and tick == 90 then
                    lostPool(p, tick)
                elseif rules.mode == "front_familiars" and (tick == 135 or tick == 225) then
                    local count, front = 0, 0
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        local f = e:ToFamiliar()
                        if
                            f
                            and f.Player
                            and f.Player.InitSeed == p.InitSeed
                            and (
                                f.Variant == FamiliarVariant.INCUBUS
                                or f.Variant == FamiliarVariant.BROTHER_BOBBY
                            )
                        then
                            count = count + 1
                            if
                                tick == 135 and f.Position.Y < p.Position.Y - 5
                                or tick == 225 and f.Position.X > p.Position.X + 5
                            then
                                front = front + 1
                            end
                        end
                    end
                    report("birthright_front_familiars", {
                        tick = tick,
                        direction = tick == 135 and "up" or "right",
                        count = count,
                        front = front,
                    })
                elseif rules.mode == "twin_items" and tick == 90 then
                    report(
                        "birthright_copied_items",
                        { tick = tick, before = twinBefore, after = inventoryCount(p, copiedItems) }
                    )
                elseif rules.mode == "poop_capacity" and tick == 90 then
                    p:AddPoopMana(50)
                elseif rules.mode == "soul_charges" then
                    if tick >= 87 and (tick - 87) % 45 == 0 and (tick - 87) / 45 < rules.count then
                        p:AddSoulCharge(200 - p:GetSoulCharge())
                        p:SetActiveCharge(0)
                        p:GetEffects()
                            :RemoveCollectibleEffect(
                                CollectibleType.COLLECTIBLE_BOOK_OF_SHADOWS,
                                -1
                            )
                        pending = p:GetSoulCharge()
                    elseif pending and tick >= 105 and (tick - 105) % 45 == 0 then
                        report("birthright_soul_charge_use", {
                            tick = tick,
                            used = p:HasInvincibility(),
                            spent = pending - p:GetSoulCharge(),
                        })
                        pending = nil
                    end
                elseif rules.mode == "protected_items" then
                    if tick == 60 then
                        p:AddCollectible(CollectibleType.COLLECTIBLE_ROID_RAGE, 0, true)
                    elseif tick >= 90 and tick <= 450 and (tick - 90) % 60 == 0 then
                        p:AddSoulHearts(12 - p:GetSoulHearts())
                        p:ResetDamageCooldown()
                        -- Self-inflicted damage does not reroll Tainted Eden.
                        local projectile = Isaac.Spawn(
                            EntityType.ENTITY_PROJECTILE,
                            ProjectileVariant.PROJECTILE_NORMAL,
                            0,
                            p.Position,
                            Vector.Zero,
                            nil
                        ):ToProjectile()
                        projectile.CollisionDamage = 1
                        projectile.Height, projectile.FallingSpeed, projectile.FallingAccel =
                            -10, 0, 0
                    elseif tick >= 105 and tick <= 465 and (tick - 105) % 60 == 0 then
                        local preserved = true
                        local counts = {}
                        for name, count in pairs(protected) do
                            counts[name] = p:GetCollectibleNum(CollectibleType[name], true)
                            -- A newly rerolled item may become another copy of a
                            -- protected item; its original copies must remain.
                            preserved = preserved and counts[name] >= count
                        end
                        report("birthright_protected_inventory", {
                            tick = tick,
                            preserved = preserved,
                            expected = protected,
                            actual = counts,
                            rerolled = not p:HasCollectible(CollectibleType.COLLECTIBLE_ROID_RAGE),
                        })
                    end
                elseif rules.mode == "salvage" then
                    if tick == 60 or tick == 210 then
                        if tick == 60 then
                            p:RemoveCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
                        else
                            p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, true)
                        end
                        clearPickups()
                        p.Position = room:GetCenterPos() + Vector(0, 100)
                    elseif tick == 75 or tick == 225 then
                        salvageSpawned = {}
                        pending = Game():Spawn(
                            EntityType.ENTITY_PICKUP,
                            PickupVariant.PICKUP_COLLECTIBLE,
                            room:GetCenterPos(),
                            Vector.Zero,
                            nil,
                            CollectibleType.COLLECTIBLE_SAD_ONION,
                            431
                        ):ToPickup()
                    elseif tick == 105 or tick == 255 then
                        p:GetDropRNG():SetSeed(431, 35)
                        pending:GetDropRNG():SetSeed(431, 35)
                        p.Position = pending.Position
                    elseif (tick > 105 and tick < 150) or (tick > 255 and tick < 300) then
                        if pending and not pending:Exists() then
                            -- Count native salvage before the holder can collect it.
                            p.Position, p.Velocity =
                                room:GetCenterPos() + Vector(0, 100), Vector.Zero
                        end
                    elseif tick == 150 or tick == 300 then
                        local drops, emitted = 0, 0
                        for _ in pairs(salvageSpawned) do
                            emitted = emitted + 1
                        end
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:ToPickup() and e.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
                                drops = drops + 1
                            end
                        end
                        report("birthright_salvage", {
                            tick = tick,
                            owned = p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                            consumed = not pending:Exists(),
                            drops = emitted,
                            remaining = drops,
                            spawned = salvageSpawned,
                        })
                        salvageSpawned = nil
                        pending = nil
                    end
                end
                if rules.mode == "double_esau" and tick >= 240 and tick < 360 then
                    -- Keep the native binding prerequisite alive until the
                    -- scheduled Anima use; do not let contact transform Jacob.
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e.Type == EntityType.ENTITY_DARK_ESAU and e.Variant == 0 then
                            e.Position, e.Velocity =
                                room:GetClampedPosition(p.Position + Vector(180, -100), 20),
                                Vector.Zero
                        end
                    end
                end
                if tick >= 60 and tick % 15 == 0 then
                    sample(
                        p,
                        room,
                        tick,
                        p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT) and "held"
                            or "control"
                    )
                end
            end)
        end,
    }
end
