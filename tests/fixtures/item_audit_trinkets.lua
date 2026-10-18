return function(report, actor, moveRoom, moveFloor)
    local BLACK_POOP_VARIANT = 5
    local pending, phase, knockTarget, knockPeak
    local gridTrial, gridIndices, gridVictim
    local gridSeeds
    local statusTarget, statusFirst, statusLast
    local championTotal, championCount, championRespawns
    local lockedChest, chestOpeningKeys, shopPurchase
    local pocketTrial, tearTrial
    local effectPeak, attractionTarget, attractionStart, bombTrial
    local seriesSeed, nativeFloorState, myosotisPickup, myosotisCoins, nativeFloorEntities
    local donation, nativeDeal, nativeDealBefore, angelItems, angelCount
    local nativeDealPrices, nativeDealRerolls, nativeDealAcquired
    local doorTrial
    local challengeSeen, challengeStarted, challengeEnemies, challengeBosses
    local championRooms
    local floorChoice
    local doorInputKey, doorInputMask
    local roomIconFlag = 4
    local firstTrialTick, trialPeriod, observationDelay = 90, 15, 9
    local function pickups()
        local result = {}
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            local p = e:ToPickup()
            if p then
                local key = p.Variant .. "." .. p.SubType
                result[key] = (result[key] or 0) + 1
            end
        end
        return result
    end
    local function state(p)
        local familiarCounts, enemyHealth, effects = {}, 0, {}
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            local f = e:ToFamiliar()
            if f and f.Player and f.Player.InitSeed == p.InitSeed then
                local key = tostring(f.Variant)
                familiarCounts[key] = (familiarCounts[key] or 0) + 1
            end
            if e:GetData().auditTrinketVictim then
                enemyHealth = enemyHealth + e.HitPoints
            end
            if e:ToEffect() then
                local key = tostring(e.Variant)
                effects[key] = (effects[key] or 0) + 1
            end
        end
        return {
            hearts = p:GetHearts(),
            soul = p:GetSoulHearts(),
            bone = p:GetBoneHearts(),
            coins = p:GetNumCoins(),
            keys = p:GetNumKeys(),
            bombs = p:GetNumBombs(),
            charge = p:GetActiveCharge(),
            damage = p.Damage,
            luck = p.Luck,
            trinket = p:GetTrinket(0),
            invincible = p:HasInvincibility(),
            cooldown = p:GetDamageCooldown(),
            flies = p:GetNumBlueFlies(),
            spiders = p:GetNumBlueSpiders(),
            room = Game():GetLevel():GetCurrentRoomIndex(),
            pickups = pickups(),
            familiars = familiarCounts,
            enemy_health = enemyHealth,
            effects = effects,
        }
    end
    local function clearPickups()
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:ToPickup() then
                e:Remove()
            end
        end
    end
    return {
        input = function(case, tick)
            local rules = case.trigger_effects and case.trigger_effects.trinket_trial
            if not rules then
                return nil
            end
            local window
            if rules.mode == "curse_door" and tick >= 511 and tick <= 570 then
                window = "curse"
            elseif rules.mode == "door" then
                local control = rules.reward ~= "open" and rules.reward ~= "charge"
                if control and tick >= 511 and tick <= 555 then
                    window = "control"
                elseif tick >= 631 and tick <= 690 then
                    window = "held"
                elseif rules.reward == "blue" and tick >= 841 and tick <= 900 then
                    window = "blue-exit"
                end
            end
            if not window then
                return nil
            end
            local key = case.key .. "/" .. window
            if key ~= doorInputKey then
                local head = _IsaacLan.rooms_heads()[tostring(case.slot)]
                if head == nil then
                    return 0
                end
                local player, room = Isaac.GetPlayer(head), Game():GetRoom()
                local nearest, distance
                for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                    local door = room:GetDoor(slot)
                    if door then
                        local d = door.Position:Distance(player.Position)
                        if not distance or d < distance then
                            nearest, distance = door, d
                        end
                    end
                end
                if not nearest then
                    return 0
                end
                local direction = nearest.Position - room:GetCenterPos()
                local action
                if math.abs(direction.X) > math.abs(direction.Y) then
                    action = direction.X < 0 and ButtonAction.ACTION_LEFT
                        or ButtonAction.ACTION_RIGHT
                else
                    action = direction.Y < 0 and ButtonAction.ACTION_UP or ButtonAction.ACTION_DOWN
                end
                doorInputKey, doorInputMask = key, 1 << action
            end
            return doorInputMask
        end,
        prepare = function(case, tick)
            pending, phase, knockTarget, knockPeak = nil, nil, nil, 0
            gridTrial, gridIndices, gridVictim = nil, {}, nil
            gridSeeds = {}
            statusTarget, statusFirst, statusLast = nil, nil, nil
            championTotal, championCount, championRespawns = 0, 0, 0
            lockedChest, chestOpeningKeys, shopPurchase = nil, nil, nil
            pocketTrial = nil
            effectPeak, attractionTarget, attractionStart, bombTrial = nil, nil, nil, nil
            seriesSeed, nativeFloorState, myosotisPickup, myosotisCoins = nil, nil, nil, nil
            nativeFloorEntities = nil
            donation, nativeDeal, nativeDealBefore, angelItems, angelCount = nil, nil, nil, nil, 0
            nativeDealAcquired = false
            tearTrial = nil
            nativeDealPrices, nativeDealRerolls = {}, 0
            doorTrial = nil
            challengeSeen, challengeStarted, challengeEnemies, challengeBosses = {}, false, {}, {}
            championRooms = {}
            floorChoice = nil
            local rules = case.trigger_effects and case.trigger_effects.trinket_trial
            if rules and rules.mode == "grid" then
                local rng = RNG()
                rng:SetSeed(146883217, 35)
                for i = 1, rules.count do
                    gridSeeds[i] = rng:Next()
                end
            end
            if rules and (rules.mode == "planetarium" or rules.mode == "guppy") then
                actor(case.slot, function(p)
                    report("trinket_condition", {
                        tick = tick,
                        phase = "control",
                        chance = Game():GetLevel():GetPlanetariumChance(),
                        guppy = p:HasPlayerForm(PlayerForm.PLAYERFORM_GUPPY),
                    })
                end)
            end
        end,
        advance = function(case, tick)
            local rules = case.trigger_effects and case.trigger_effects.trinket_trial
            if not rules then
                return
            end
            if rules.mode == "damage" and rules.reward == "umbilical" and tick == 75 then
                moveRoom()
                return
            end
            if
                rules.mode == "damage"
                and rules.reward == "umbilical"
                and tick == 78
                and not case.split
            then
                local destination = _IsaacLan.rooms_positions()[tostring(case.slot)].index
                assert(_IsaacLan.rooms_move(1 - case.slot, destination, 0, -1))
            end
            if rules.mode == "champion_floors" then
                if tick < 90 then
                    return
                end
                local index, offset = math.floor((tick - 90) / 450), (tick - 90) % 450
                if index >= rules.count then
                    return
                end
                if offset == 0 then
                    actor(case.slot, function(p)
                        if index == 0 or index == rules.count / 2 then
                            if case.kind == "trinket" then
                                if index == 0 then
                                    p:TryRemoveTrinket(case.id)
                                else
                                    p:AddTrinket(case.id, false)
                                end
                            else
                                if index == 0 then
                                    p:RemoveCollectible(case.id)
                                else
                                    p:AddCollectible(case.id, 0, false)
                                end
                            end
                            championTotal, championCount, championRespawns = 0, 0, 0
                        end
                        p:SetMinDamageCooldown(case.end_tick * 2)
                        Game():GetSeeds():ForgetStageSeed(LevelStage.STAGE2_2)
                        Game()
                            :GetLevel()
                            :SetStage(LevelStage.STAGE2_2, StageType.STAGETYPE_ORIGINAL)
                        Game():StartStageTransition(true, 0, p)
                    end)
                elseif offset == 270 then
                    championRooms = {}
                    local rooms = Game():GetLevel():GetRooms()
                    for i = 0, rooms.Size - 1 do
                        local d = rooms:Get(i)
                        if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT then
                            local combat = false
                            for j = 0, d.Data.SpawnCount - 1 do
                                local spawn = d.Data.Spawns:Get(j)
                                for k = 0, spawn.EntryCount - 1 do
                                    local kind = spawn.Entries:Get(k).Type
                                    if
                                        kind >= 10
                                        and kind < 1000
                                        and kind ~= EntityType.ENTITY_FIREPLACE
                                        and kind ~= EntityType.ENTITY_SHOPKEEPER
                                        and kind ~= EntityType.ENTITY_MOVABLE_TNT
                                    then
                                        combat = true
                                    end
                                end
                            end
                            if combat and #championRooms < 8 then
                                championRooms[#championRooms + 1] = d.SafeGridIndex
                            end
                        end
                    end
                elseif offset >= 300 and offset <= 405 and (offset - 300) % 15 == 0 then
                    local roomIndex = championRooms[(offset - 300) / 15 + 1]
                    if roomIndex then
                        assert(_IsaacLan.rooms_move(case.slot, roomIndex, 0, -1))
                        if not case.split then
                            assert(_IsaacLan.rooms_move(1 - case.slot, roomIndex, 0, -1))
                        end
                    end
                elseif offset >= 309 and offset <= 414 and (offset - 309) % 15 == 0 then
                    if championRooms[(offset - 309) / 15 + 1] then
                        actor(case.slot, function()
                            local total, champions = 0, 0
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                local npc = e:ToNPC()
                                if npc and npc:IsActiveEnemy(false) then
                                    total = total + 1
                                    champions = champions + (npc:IsChampion() and 1 or 0)
                                end
                            end
                            championTotal, championCount, championRespawns =
                                championTotal + total,
                                championCount + champions,
                                championRespawns + 1
                        end)
                    end
                elseif
                    offset == 430 and (index == rules.count / 2 - 1 or index == rules.count - 1)
                then
                    actor(case.slot, function(p)
                        report("native_champion_rooms", {
                            tick = tick,
                            phase = index == rules.count - 1 and "held" or "control",
                            owned = case.kind == "trinket" and p:HasTrinket(case.id)
                                or case.kind == "collectible" and p:HasCollectible(case.id),
                            total = championTotal,
                            champions = championCount,
                            respawns = championRespawns,
                        })
                    end)
                end
                return
            end
            if rules.mode == "door" then
                if tick == 90 then
                    moveFloor()
                    return
                end
                if tick == 420 then
                    local level = Game():GetLevel()
                    local rooms = level:GetRooms()
                    local target
                    for i = 0, rooms.Size - 1 do
                        local d = rooms:Get(i)
                        if
                            d.Data
                            and d.Data.Type == RoomType[rules.room]
                            and d.Data.Shape == RoomShape.ROOMSHAPE_1x1
                            and d.SafeGridIndex ~= level:GetStartingRoomIndex()
                            and d.Data.SpawnCount > 0
                        then
                            target = d.SafeGridIndex
                            break
                        end
                    end
                    assert(target, "Native door trial has no target room")
                    doorTrial = { target = target, candidates = {} }
                    for _, offset in ipairs({ -1, -13, 1, 13 }) do
                        local index = target + offset
                        if index >= 0 and index < 169 then
                            local d = level:GetRoomByIdx(index, 0)
                            if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT then
                                doorTrial.candidates[#doorTrial.candidates + 1] = index
                            end
                        end
                    end
                end
                if
                    tick >= 420
                    and tick <= 465
                    and (tick - 420) % 15 == 0
                    and not doorTrial.source
                then
                    local index = doorTrial.candidates[(tick - 420) / 15 + 1]
                    if index then
                        assert(_IsaacLan.rooms_move(case.slot, index, 0, -1))
                        if not case.split then
                            assert(_IsaacLan.rooms_move(1 - case.slot, index, 0, -1))
                        end
                    end
                    return
                end
            end
            if rules.mode == "floor_series" and tick >= 90 then
                local index, offset = math.floor((tick - 90) / 450), (tick - 90) % 450
                if index >= rules.count then
                    return
                end
                if offset == 0 then
                    for slot = 0, 1 do
                        actor(slot, function(p)
                            p:SetMinDamageCooldown(case.end_tick * 2)
                        end)
                    end
                    actor(case.slot, function(p)
                        if rules.held_count and index == rules.held_count then
                            p:TryRemoveTrinket(case.id)
                        end
                        local stage = assert(LevelStage[rules.stage])
                        local stageType = StageType[rules.stage_type or "STAGETYPE_ORIGINAL"]
                        local seeds = Game():GetSeeds()
                        if stageType >= StageType.STAGETYPE_REPENTANCE then
                            -- Alternate floors can use a different seed slot.
                            -- Clear the isolated run's stage seeds, and measure
                            -- the actual generated layout rather than a slot.
                            for floor = LevelStage.STAGE1_1, LevelStage.NUM_STAGES - 1 do
                                seeds:ForgetStageSeed(floor)
                            end
                        else
                            seeds:ForgetStageSeed(stage)
                        end
                        Game():GetLevel():SetStage(stage, stageType)
                        Game():StartStageTransition(true, 0, p)
                    end)
                    return
                elseif offset == 300 then
                    local destination
                    actor(case.slot, function()
                        local level = Game():GetLevel()
                        seriesSeed = level:GetDungeonPlacementSeed()
                        local rooms = level:GetRooms()
                        for i = 0, rooms.Size - 1 do
                            local desc = rooms:Get(i)
                            if
                                desc.Data
                                and desc.Data.Type == RoomType[rules.room]
                                and desc.SafeGridIndex ~= level:GetStartingRoomIndex()
                            then
                                destination = desc.SafeGridIndex
                                break
                            end
                        end
                    end)
                    assert(destination, "Native trinket floor lacks its required room")
                    assert(_IsaacLan.rooms_move(case.slot, destination, 0, -1))
                    if not case.split then
                        assert(_IsaacLan.rooms_move(1 - case.slot, destination, 0, -1))
                    end
                    for slot = 0, 1 do
                        if slot == case.slot or not case.split then
                            actor(slot, function(p, room)
                                p.Position = room:GetClampedPosition(
                                    room:GetCenterPos() + Vector(0, 100),
                                    30
                                )
                                p.Velocity = Vector.Zero
                            end)
                        end
                    end
                    return
                end
            elseif rules.mode == "myosotis" then
                if tick == 150 then
                    moveRoom()
                    return
                elseif tick == 240 or tick == 660 then
                    moveFloor()
                    return
                end
            end
            actor(case.slot, function(p, room)
                if rules.mode == "spiked_chests" then
                    local index, offset = math.floor((tick - 90) / 120), (tick - 90) % 120
                    if tick >= 90 and index < 4 then
                        if offset == 0 then
                            clearPickups()
                            if index % 2 == 0 then
                                p:TryRemoveTrinket(case.id)
                            else
                                p:AddTrinket(case.id, false)
                            end
                            p:AddHearts(p:GetMaxHearts() - p:GetHearts())
                            p:ResetDamageCooldown()
                            p.Position = room:GetCenterPos() + Vector(0, 80)
                            local kind = index < 2 and PickupVariant.PICKUP_SPIKEDCHEST
                                or PickupVariant.PICKUP_MIMICCHEST
                            pending = { before = p:GetHearts(), kind = kind }
                            pending.pickup = Isaac.Spawn(
                                EntityType.ENTITY_PICKUP,
                                kind,
                                1,
                                room:GetCenterPos(),
                                Vector.Zero,
                                nil
                            ):ToPickup()
                            pending.pickup.Wait = 0
                        elseif offset == 30 then
                            p.Position = pending.pickup.Position
                        elseif offset == 39 then
                            pending.after = p:GetHearts()
                            p.Position = room:GetCenterPos() + Vector(0, 80)
                        elseif offset == 90 then
                            report("flat_file_native_chest", {
                                tick = tick,
                                kind = pending.kind,
                                owned = p:HasTrinket(case.id),
                                before = pending.before,
                                after = pending.after,
                                opened = not pending.pickup:Exists() or pending.pickup.SubType ~= 1,
                            })
                            pending = nil
                        end
                    end
                    return
                end
                if rules.mode == "curse_door" then
                    if tick == 60 and rules.control then
                        p:TryRemoveTrinket(case.id)
                    elseif tick == 480 then
                        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                            local door = room:GetDoor(slot)
                            if door and door.TargetRoomIndex >= 0 then
                                -- The trial teleports into an unvisited curse room.
                                -- Open its unlocked exit before testing its spikes.
                                local locked = door:IsLocked()
                                if not locked then
                                    door:Open()
                                end
                                report("curse_door_prerequisite", {
                                    tick = tick,
                                    locked = locked,
                                    enemies = room:GetAliveEnemiesCount(),
                                    sprite = door:GetSprite():GetFilename(),
                                    source_type = door.CurrentRoomType,
                                    target_type = door.TargetRoomType,
                                })
                                doorTrial = {
                                    source = Game():GetLevel():GetCurrentRoomIndex(),
                                    destination = door.TargetRoomIndex,
                                    position = door.Position,
                                    direction = (door.Position - room:GetCenterPos()):Normalized(),
                                    before = p:GetHearts(),
                                }
                                break
                            end
                        end
                        p:ResetDamageCooldown()
                    elseif
                        tick >= 510
                        and tick <= 570
                        and doorTrial
                        and Game():GetLevel():GetCurrentRoomIndex() == doorTrial.source
                    then
                        if tick == 510 then
                            p.Position = doorTrial.position - doorTrial.direction * 18
                        end
                    elseif tick == 630 and doorTrial then
                        report("flat_file_native_curse_door", {
                            tick = tick,
                            source = doorTrial.source,
                            destination = doorTrial.destination,
                            room = Game():GetLevel():GetCurrentRoomIndex(),
                            before = doorTrial.before,
                            after = p:GetHearts(),
                            owned = p:HasTrinket(case.id),
                        })
                    end
                    return
                end
                if rules.mode == "angel_door" or rules.mode == "hush_door" then
                    if rules.mode == "hush_door" and tick == 60 then
                        Game().TimeCounter = 31 * 60 * 30
                        if rules.control then
                            p:TryRemoveTrinket(case.id)
                        end
                    elseif tick == 660 then
                        local angel, devil, hush = false, false, false
                        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                            local door = room:GetDoor(slot)
                            if door then
                                angel = angel or door.TargetRoomType == RoomType.ROOM_ANGEL
                                devil = devil or door.TargetRoomType == RoomType.ROOM_DEVIL
                                hush = hush
                                    or door.TargetRoomIndex == GridRooms.ROOM_BLUE_WOOM_IDX
                                        and door:IsOpen()
                            end
                        end
                        report("trinket_native_special_door", {
                            tick = tick,
                            angel = angel,
                            devil = devil,
                            hush = hush,
                            clear = room:IsClear(),
                            stage = Game():GetLevel():GetStage(),
                            time = Game().TimeCounter,
                            owned = p:HasTrinket(case.id),
                        })
                    elseif
                        rules.mode == "hush_door"
                        and tick >= 690
                        and tick <= 714
                        and not rules.control
                    then
                        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                            local door = room:GetDoor(slot)
                            if door and door.TargetRoomIndex == GridRooms.ROOM_BLUE_WOOM_IDX then
                                local direction = (door.Position - room:GetCenterPos()):Normalized()
                                p.Position, p.Velocity =
                                    door.Position - direction * 4, direction * 6
                                break
                            end
                        end
                    elseif rules.mode == "hush_door" and tick == 870 then
                        report(
                            "strange_key_hush_entry",
                            { tick = tick, room = Game():GetLevel():GetCurrentRoomIndex() }
                        )
                    end
                    return
                end
                if rules.mode == "awards" then
                    if tick == 60 then
                        p:TryRemoveTrinket(case.id)
                    elseif tick == 180 then
                        p:AddTrinket(case.id, false)
                    end
                    if tick == 90 or tick == 210 then
                        clearPickups()
                        local drops = {}
                        for _ = 1, rules.count do
                            room:SpawnClearAward()
                            for key, count in pairs(pickups()) do
                                drops[key] = (drops[key] or 0) + count
                            end
                            clearPickups()
                        end
                        report("trinket_native_clear_awards", {
                            tick = tick,
                            owned = p:HasTrinket(case.id),
                            count = rules.count,
                            drops = drops,
                        })
                    end
                    return
                end
                if rules.mode == "challenge" then
                    if room:GetType() ~= RoomType.ROOM_CHALLENGE then
                        return
                    end
                    if tick == 450 then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:ToPickup() then
                                challengeSeen[e.InitSeed] = true
                            end
                        end
                        p:AddKeys(10 - p:GetNumKeys())
                        p:SetMinDamageCooldown(case.end_tick * 2)
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local pickup = e:ToPickup()
                            if pickup then
                                if pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
                                    pickup:TryOpenChest(p)
                                end
                                p.Position = pickup.Position
                                break
                            end
                        end
                    elseif tick >= 480 and tick <= 1350 and tick % 15 == 0 then
                        challengeStarted = challengeStarted or room:IsAmbushActive()
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:IsActiveEnemy(false) then
                                challengeEnemies[e.InitSeed] = true
                                if e:IsBoss() then
                                    challengeBosses[e.InitSeed] = true
                                end
                                if e:IsVulnerableEnemy() then
                                    e:TakeDamage(100000, 0, EntityRef(p), 0)
                                end
                            end
                        end
                    elseif tick == 1380 then
                        local enemies, bosses, rewards = 0, 0, 0
                        rewards = {}
                        for _ in pairs(challengeEnemies) do
                            enemies = enemies + 1
                        end
                        for _ in pairs(challengeBosses) do
                            bosses = bosses + 1
                        end
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:ToPickup() and not challengeSeen[e.InitSeed] then
                                rewards[#rewards + 1] = { variant = e.Variant, subtype = e.SubType }
                            end
                        end
                        report("tattoo_native_challenge", {
                            tick = tick,
                            started = challengeStarted,
                            done = room:IsAmbushDone(),
                            enemies = enemies,
                            bosses = bosses,
                            subtype = Game():GetLevel():GetCurrentRoomDesc().Data.Subtype,
                            rewards = rewards,
                        })
                    end
                    return
                end
                if rules.mode == "door" then
                    local keyControl = rules.reward ~= "open" and rules.reward ~= "charge"
                    if tick == 60 and keyControl then
                        p:TryRemoveTrinket(case.id)
                    elseif
                        tick >= 429
                        and tick <= 474
                        and (tick - 429) % 15 == 0
                        and not doorTrial.source
                    then
                        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                            local door = room:GetDoor(slot)
                            if door and door.TargetRoomIndex == doorTrial.target then
                                doorTrial.source, doorTrial.slot =
                                    Game():GetLevel():GetCurrentRoomIndex(), slot
                                doorTrial.position = door.Position
                                doorTrial.direction = (door.Position - room:GetCenterPos()):Normalized()
                                for _, e in ipairs(Isaac.GetRoomEntities()) do
                                    if e:IsActiveEnemy(false) then
                                        e:Remove()
                                    end
                                end
                                room:SetClear(true)
                                p:AddKeys(-p:GetNumKeys())
                                p:SetMinDamageCooldown(case.end_tick * 2)
                                break
                            end
                        end
                    elseif tick == 510 or tick == 630 then
                        assert(doorTrial.source, "Native target room lacks an adjacent entrance")
                        if tick == 630 or keyControl then
                            p.Position = doorTrial.position - doorTrial.direction * 25
                            doorTrial.charge = p:GetActiveCharge(ActiveSlot.SLOT_PRIMARY)
                        end
                    elseif tick == 570 and keyControl then
                        report("trinket_locked_door_control", {
                            tick = tick,
                            room = Game():GetLevel():GetCurrentRoomIndex(),
                            source = doorTrial.source,
                            keys = p:GetNumKeys(),
                            locked = room:GetDoor(doorTrial.slot):IsLocked(),
                        })
                    elseif tick == 600 and keyControl then
                        p:AddTrinket(case.id, false)
                    elseif tick == 750 then
                        local entryOpen = false
                        local activeConfig = Isaac.GetItemConfig():GetCollectible(p:GetActiveItem())
                        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                            local door = room:GetDoor(slot)
                            if door and door.TargetRoomIndex == doorTrial.source then
                                entryOpen = door:IsOpen()
                            end
                        end
                        report("trinket_native_door_entry", {
                            tick = tick,
                            room = Game():GetLevel():GetCurrentRoomIndex(),
                            target = doorTrial.target,
                            room_type = room:GetType(),
                            keys = p:GetNumKeys(),
                            enemies = room:GetAliveEnemiesCount(),
                            entry_open = entryOpen,
                            charge_before = doorTrial.charge,
                            charge_after = p:GetActiveCharge(ActiveSlot.SLOT_PRIMARY),
                            max_charge = activeConfig and activeConfig.MaxCharges or 0,
                            owned = p:HasTrinket(case.id),
                        })
                    elseif
                        tick >= 780
                        and tick <= 825
                        and tick % 15 == 0
                        and rules.reward == "blue"
                    then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:IsActiveEnemy(false) then
                                e:TakeDamage(100000, 0, EntityRef(p), 0)
                            end
                        end
                    elseif tick == 840 and rules.reward == "blue" then
                        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                            local door = room:GetDoor(slot)
                            if
                                door
                                and door:IsOpen()
                                and door.TargetRoomIndex == doorTrial.target
                            then
                                doorTrial.exitPosition, doorTrial.exitDirection =
                                    door.Position,
                                    (door.Position - room:GetCenterPos()):Normalized()
                                p.Position = doorTrial.exitPosition - doorTrial.exitDirection * 25
                                break
                            end
                        end
                    elseif tick == 990 and rules.reward == "blue" then
                        report("blue_key_native_destination", {
                            tick = tick,
                            room = Game():GetLevel():GetCurrentRoomIndex(),
                            target = doorTrial.target,
                            room_type = room:GetType(),
                            keys = p:GetNumKeys(),
                        })
                    end
                    return
                end
                if rules.mode == "donations" then
                    local index, offset = math.floor((tick - 90) / 90), (tick - 90) % 90
                    if tick >= 90 and index < rules.count then
                        if offset == 0 then
                            clearPickups()
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                if e.Type == EntityType.ENTITY_SLOT then
                                    e:Remove()
                                end
                            end
                            p:AddCoins(20 - p:GetNumCoins())
                            p:AddHearts(1 - p:GetHearts())
                            local coinBeggarVariant = 4
                            donation = {
                                entity = Isaac.Spawn(
                                    EntityType.ENTITY_SLOT,
                                    coinBeggarVariant,
                                    0,
                                    room:GetCenterPos(),
                                    Vector.Zero,
                                    nil
                                ),
                                before = state(p),
                            }
                            p.Position = room:GetCenterPos() + Vector(0, 80)
                        elseif offset == 30 then
                            p.Position = donation.entity.Position
                        elseif offset == 75 then
                            report(
                                "trinket_native_donation",
                                { tick = tick, before = donation.before, after = state(p) }
                            )
                            p.Position = room:GetCenterPos() + Vector(0, 80)
                        end
                    end
                    return
                end
                if rules.mode == "tick" then
                    if tick == 450 then
                        local bosses = {}
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:ToNPC() and e:IsBoss() then
                                bosses[#bosses + 1] = { hp = e.HitPoints, max_hp = e.MaxHitPoints }
                            end
                        end
                        report(
                            "tick_boss_entry",
                            { tick = tick, hearts = p:GetHearts(), bosses = bosses }
                        )
                        p:SetMinDamageCooldown(case.end_tick * 2)
                    elseif tick == 600 then
                        report(
                            "tick_drop_attempt",
                            { tick = tick, retained = p:HasTrinket(case.id) }
                        )
                        nativeDeal = Isaac.Spawn(
                            EntityType.ENTITY_PICKUP,
                            PickupVariant.PICKUP_TRINKET,
                            TrinketType[rules.replacement],
                            p.Position,
                            Vector.Zero,
                            nil
                        ):ToPickup()
                        nativeDeal.Wait = 0
                    elseif tick == 720 then
                        report("tick_native_replacement", {
                            tick = tick,
                            removed = not p:HasTrinket(case.id),
                            replaced = p:HasTrinket(TrinketType[rules.replacement]),
                            consumed = not nativeDeal:Exists(),
                        })
                    end
                    return
                end
                if rules.mode == "angel_boss" then
                    local dealTick = tick - (case.trigger_effects.deal_delay or 0)
                    if dealTick == 720 then
                        angelItems = pickups()
                        local statues = 0
                        for index = 0, room:GetGridSize() - 1 do
                            local grid = room:GetGridEntity(index)
                            if grid and grid:GetType() == GridEntityType.GRID_STATUE then
                                local bomb = p:FireBomb(grid.Position, Vector.Zero, nil)
                                bomb:SetExplosionCountdown(1)
                                statues = statues + 1
                            end
                        end
                        report("filigree_native_statues", { tick = tick, count = statues })
                        p:SetMinDamageCooldown(case.end_tick * 2)
                    elseif dealTick == 900 then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_URIEL
                                or e.Type == EntityType.ENTITY_GABRIEL
                            then
                                angelCount = angelCount + 1
                                e:TakeDamage(100000, 0, EntityRef(p), 0)
                            end
                        end
                    elseif dealTick == 1080 then
                        report("filigree_native_boss_drop", {
                            tick = tick,
                            angels = angelCount,
                            before = angelItems,
                            after = pickups(),
                        })
                    end
                    return
                end
                if rules.mode == "devil_deal" then
                    local dealTick = tick - (case.trigger_effects.deal_delay or 0)
                    local priceTrial = rules.reward == "tongue" or rules.reward == "coins"
                    if rules.reward == "magnet" then
                        if tick == 450 then
                            p:RemoveCollectible(CollectibleType.COLLECTIBLE_GOAT_HEAD)
                            p:TryRemoveTrinket(case.id)
                        elseif tick == 453 or tick == 456 then
                            report("trinket_magnet_deal_chance", {
                                tick = tick,
                                owned = p:HasTrinket(case.id),
                                chance = room:GetDevilRoomChance(),
                            })
                            if tick == 453 then
                                p:AddTrinket(case.id, false)
                            else
                                p:AddCollectible(CollectibleType.COLLECTIBLE_GOAT_HEAD, 0, false)
                            end
                        end
                    end
                    if tick == 60 and priceTrial then
                        p:TryRemoveTrinket(case.id)
                    end
                    if dealTick == 660 then
                        local items, greeds = {}, 0
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e.Type == EntityType.ENTITY_GREED then
                                greeds = greeds + 1
                            end
                            local pickup = e:ToPickup()
                            if
                                pickup
                                and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
                                and pickup.Price ~= 0
                            then
                                items[#items + 1] = { id = pickup.SubType, price = pickup.Price }
                                if
                                    not nativeDeal
                                    or pickup.SubType == CollectibleType.COLLECTIBLE_BRIMSTONE
                                then
                                    nativeDeal = pickup
                                end
                            end
                        end
                        local desc = Game():GetLevel():GetCurrentRoomDesc().Data
                        report("trinket_generated_devil_deals", {
                            tick = tick,
                            items = items,
                            variant = desc.Variant,
                            subtype = desc.Subtype,
                            name = desc.Name,
                        })
                        if priceTrial then
                            report("trinket_native_deal_prices", {
                                tick = tick,
                                owned = p:HasTrinket(case.id),
                                prices = nativeDeal and { nativeDeal.Price } or {},
                            })
                        end
                    elseif dealTick == 690 and priceTrial then
                        p:AddTrinket(case.id, false)
                    elseif priceTrial and dealTick >= 720 and dealTick < 1110 then
                        local offset = dealTick - 720
                        if
                            rules.reward == "coins"
                            and offset % 6 == 0
                            and not (nativeDeal and nativeDeal.Price > 0)
                        then
                            p:UseActiveItem(CollectibleType.COLLECTIBLE_D6, UseFlag.USE_NOANIM)
                            nativeDealRerolls = nativeDealRerolls + 1
                        elseif offset % 6 == 3 then
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                local pickup = e:ToPickup()
                                if
                                    pickup
                                    and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
                                    and pickup.SubType > 0
                                then
                                    nativeDeal = pickup
                                    if rules.reward == "coins" and pickup.Price > 0 then
                                        break
                                    end
                                end
                            end
                            if nativeDeal then
                                nativeDealPrices[#nativeDealPrices + 1] = nativeDeal.Price
                            end
                        end
                    elseif dealTick == 1140 and priceTrial then
                        report("trinket_native_deal_prices", {
                            tick = tick,
                            owned = p:HasTrinket(case.id),
                            prices = nativeDealPrices,
                            rerolls = nativeDealRerolls,
                        })
                    elseif
                        dealTick == (priceTrial and 1170 or 870)
                        and nativeDeal
                        and rules.reward ~= "magnet"
                    then
                        p:AddCoins(99 - p:GetNumCoins())
                        nativeDealBefore = {
                            id = nativeDeal.SubType,
                            owned = p:GetCollectibleNum(nativeDeal.SubType, true),
                            hearts = p:GetMaxHearts() + p:GetSoulHearts(),
                            coins = p:GetNumCoins(),
                            price = nativeDeal.Price,
                        }
                        p.Position = nativeDeal.Position
                    elseif
                        nativeDealBefore
                        and dealTick > (priceTrial and 1170 or 870)
                        and dealTick < (priceTrial and 1290 or 990)
                        and not nativeDealAcquired
                    then
                        nativeDealAcquired = p:GetCollectibleNum(nativeDealBefore.id, true)
                                > nativeDealBefore.owned
                            or p:GetActiveItem() == nativeDealBefore.id
                        if nativeDealAcquired then
                            -- Move off the pedestal before a purchased active
                            -- item can be exchanged back for the old active.
                            p.Position, p.Velocity =
                                room:GetCenterPos() + Vector(0, 100), Vector.Zero
                        end
                    elseif
                        dealTick == (priceTrial and 1290 or 990) and rules.reward ~= "magnet"
                    then
                        report("trinket_native_deal_purchase", {
                            tick = tick,
                            found = nativeDealBefore ~= nil,
                            acquired = nativeDealAcquired,
                            before = nativeDealBefore,
                            after = nativeDealBefore
                                and {
                                    owned = p:GetCollectibleNum(nativeDealBefore.id, true),
                                    hearts = p:GetMaxHearts() + p:GetSoulHearts(),
                                    coins = p:GetNumCoins(),
                                },
                            trinket = p:HasTrinket(case.id),
                        })
                    end
                    return
                end
                if rules.mode == "floor_series" then
                    local offset = (tick - 90) % 450
                    if tick >= 90 and offset == 315 and rules.reward == "replace_resources" then
                        p:TryRemoveTrinket(case.id)
                        nativeFloorState = {}
                    elseif
                        tick >= 90
                        and (offset == 330 or offset == 345)
                        and rules.reward == "replace_resources"
                    then
                        clearPickups()
                        nativeFloorEntities = {}
                        for variantIndex, variant in ipairs({
                            PickupVariant.PICKUP_COIN,
                            PickupVariant.PICKUP_KEY,
                        }) do
                            for i = 1, 128 do
                                local index = (variantIndex - 1) * 128 + i
                                local e = Game():Spawn(
                                    EntityType.ENTITY_PICKUP,
                                    variant,
                                    room:GetCenterPos()
                                        + Vector(
                                            -150 + (index - 1) % 16 * 20,
                                            -170 + math.floor((index - 1) / 16) * 10
                                        ),
                                    Vector.Zero,
                                    nil,
                                    0,
                                    100003 + index * 7919
                                )
                                nativeFloorEntities[#nativeFloorEntities + 1] = e
                            end
                        end
                    elseif
                        tick >= 90
                        and (offset == 333 or offset == 348)
                        and rules.reward == "replace_resources"
                    then
                        local result = { coins = 0, keys = 0, other = 0, removed = 0, types = {} }
                        for _, e in ipairs(nativeFloorEntities) do
                            if e:Exists() then
                                local kind = e.Type .. "." .. e.Variant .. "." .. e.SubType
                                result.types[kind] = (result.types[kind] or 0) + 1
                                local key = e.Type == EntityType.ENTITY_PICKUP
                                        and e.Variant == PickupVariant.PICKUP_COIN
                                        and "coins"
                                    or e.Type == EntityType.ENTITY_PICKUP and e.Variant == PickupVariant.PICKUP_KEY and "keys"
                                    or "other"
                                result[key] = result[key] + 1
                                e:Remove()
                            else
                                result.removed = result.removed + 1
                            end
                        end
                        nativeFloorState[offset == 333 and "control" or "held"] = result
                        if offset == 333 then
                            p:AddTrinket(case.id, false)
                        end
                    elseif tick >= 90 and offset == 390 then
                        local items, greeds = {}, 0
                        floorChoice = nil
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e.Type == EntityType.ENTITY_GREED then
                                greeds = greeds + 1
                            end
                            local pickup = e:ToPickup()
                            if pickup and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
                                items[#items + 1] = {
                                    seed = pickup.InitSeed,
                                    id = pickup.SubType,
                                    options = pickup.OptionsPickupIndex,
                                    blind = pickup:GetSprite():GetAnimation(),
                                    price = pickup.Price,
                                }
                                if not floorChoice and pickup.OptionsPickupIndex > 0 then
                                    floorChoice = {
                                        pickup = pickup,
                                        id = pickup.SubType,
                                        before = p:GetCollectibleNum(pickup.SubType, true),
                                        options = pickup.OptionsPickupIndex,
                                    }
                                end
                            end
                        end
                        report("trinket_native_floor_room", {
                            tick = tick,
                            owned = p:HasTrinket(case.id),
                            seed = seriesSeed,
                            stage = Game():GetLevel():GetStage(),
                            room_type = room:GetType(),
                            items = items,
                            replacements = nativeFloorState,
                            greeds = greeds,
                        })
                        if floorChoice then
                            -- Leave time for the native pickup animation to
                            -- grant the item before checking its inventory.
                            p.Position = floorChoice.pickup.Position
                        end
                    elseif tick >= 90 and offset == 435 and floorChoice then
                        local remaining = 0
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local pickup = e:ToPickup()
                            if
                                pickup
                                and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
                                and pickup.OptionsPickupIndex == floorChoice.options
                            then
                                remaining = remaining + 1
                            end
                        end
                        report("trinket_native_floor_choice", {
                            tick = tick,
                            seed = seriesSeed,
                            acquired = p:GetCollectibleNum(floorChoice.id, true)
                                > floorChoice.before,
                            remaining = remaining,
                            consumed = not floorChoice.pickup:Exists()
                                or floorChoice.pickup.SubType == 0,
                        })
                    end
                    return
                end
                if rules.mode == "floor_room" then
                    if tick == 540 then
                        local machines, prices = 0, {}
                        local restockMachineVariant = 10
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_SLOT
                                and e.Variant == restockMachineVariant
                            then
                                machines = machines + 1
                            end
                            local pickup = e:ToPickup()
                            if pickup and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
                                prices[#prices + 1] = pickup.Price
                            end
                        end
                        report("trinket_native_treasure_room", {
                            tick = tick,
                            machines = machines,
                            prices = prices,
                            room_type = room:GetType(),
                        })
                    end
                    return
                end
                if rules.mode == "pandora" then
                    if tick == 60 then
                        nativeFloorState = pickups()
                    elseif tick == 240 then
                        report("strange_key_pandora", {
                            tick = tick,
                            before = nativeFloorState,
                            after = pickups(),
                            consumed = not p:HasTrinket(case.id),
                        })
                    end
                    return
                end
                if rules.mode == "myosotis" then
                    if tick == 90 then
                        clearPickups()
                        for i = 1, 4 do
                            Isaac.Spawn(
                                EntityType.ENTITY_PICKUP,
                                PickupVariant.PICKUP_COIN,
                                CoinSubType.COIN_DIME,
                                room:GetCenterPos() + Vector(i * 35 - 90, -80),
                                Vector.Zero,
                                nil
                            )
                        end
                        report("myosotis_left_behind", { tick = tick, drops = pickups() })
                    elseif tick == 570 or tick == 990 then
                        report(
                            "myosotis_floor_carry",
                            { tick = tick, drops = pickups(), stage = Game():GetLevel():GetStage() }
                        )
                    elseif tick == 600 then
                        myosotisCoins = p:GetNumCoins()
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_PICKUP
                                and e.Variant == PickupVariant.PICKUP_COIN
                                and e.SubType == CoinSubType.COIN_DIME
                            then
                                myosotisPickup = e
                                p.Position = e.Position
                                break
                            end
                        end
                    elseif tick == 645 then
                        report("myosotis_collected", {
                            tick = tick,
                            consumed = myosotisPickup and not myosotisPickup:Exists(),
                            gain = p:GetNumCoins() - myosotisCoins,
                        })
                    end
                    return
                end
                if rules.mode == "locust" then
                    if tick % 3 == 0 then
                        local flies, flags = {}, {}
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local familiar = e:ToFamiliar()
                            if
                                familiar
                                and familiar.Player
                                and familiar.Player.InitSeed == p.InitSeed
                                and familiar.Variant == FamiliarVariant.BLUE_FLY
                            then
                                flies[#flies + 1] =
                                    { seed = familiar.InitSeed, subtype = familiar.SubType }
                            end
                            if e:ToNPC() then
                                for _, name in ipairs(rules.flags or {}) do
                                    flags[name] = flags[name] or e:HasEntityFlags(EntityFlag[name])
                                end
                            end
                        end
                        report(
                            "trinket_locust_state",
                            { tick = tick, flies = flies, flags = flags }
                        )
                    end
                    return
                end
                if rules.mode == "shiny_rock" then
                    if tick == 60 then
                        gridIndices = {}
                        for i, kind in ipairs({
                            GridEntityType.GRID_ROCKT,
                            GridEntityType.GRID_ROCK,
                        }) do
                            local index =
                                room:GetGridIndex(room:GetCenterPos() + Vector(i * 80 - 120, -60))
                            room:SpawnGridEntity(index, kind, 0, 100003 + i, 0)
                            gridIndices[#gridIndices + 1] = index
                        end
                    elseif tick >= 90 and tick % 3 == 0 then
                        for i, index in ipairs(gridIndices) do
                            local grid = room:GetGridEntity(index)
                            local color = grid:GetSprite().Color
                            report("shiny_rock_color", {
                                tick = tick,
                                kind = i == 1 and "tinted" or "normal",
                                color = { color.R, color.G, color.B, color.RO, color.GO, color.BO },
                            })
                        end
                    end
                    return
                end
                if rules.mode == "tear_probability" then
                    if tick == 60 or tick == 840 then
                        if tick == 60 then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:AddTrinket(case.id, false)
                        end
                        tearTrial = {
                            phase = tick == 60 and "control" or "held",
                            count = 0,
                            teeth = 0,
                            seen = {},
                        }
                    end
                    -- Use normal firing so native per-shot luck adjustments run.
                    -- Shorten only the interval, keeping luck identical in both phases.
                    p.MaxFireDelay = 1
                    if tearTrial then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local tear, source = e:ToTear(), e.SpawnerEntity
                            if
                                tear
                                and source
                                and source.InitSeed == p.InitSeed
                                and not tearTrial.seen[e.InitSeed]
                            then
                                tearTrial.seen[e.InitSeed] = true
                                tearTrial.count = tearTrial.count + 1
                                tearTrial.teeth = tearTrial.teeth
                                    + (tear.Variant == TearVariant.TOOTH and 1 or 0)
                            end
                        end
                        if tick == 780 or tick == 1500 then
                            report("trinket_controlled_spawn", {
                                tick = tick,
                                phase = tearTrial.phase,
                                owned = p:HasTrinket(case.id),
                                luck = p.Luck,
                                count = tearTrial.count,
                                teeth = tearTrial.teeth,
                            })
                        end
                    end
                    return
                end
                if rules.mode == "flies" then
                    if tick == 60 or tick == 180 then
                        if tick == 60 then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:AddTrinket(case.id, false)
                        end
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_FAMILIAR
                                and e.Variant == FamiliarVariant.BLUE_FLY
                            then
                                e:Remove()
                            end
                        end
                    elseif tick == 90 or tick == 210 then
                        local result = {
                            tick = tick,
                            phase = tick == 90 and "control" or "held",
                            owned = p:HasTrinket(case.id),
                            luck = p.Luck,
                        }
                        result.before = p:GetNumBlueFlies()
                        p:AddBlueFlies(1, p.Position, nil)
                        result.after = p:GetNumBlueFlies()
                        report("trinket_controlled_spawn", result)
                    end
                    return
                end
                if rules.mode == "effect_size" then
                    if tick == 60 or tick == 180 then
                        if tick == 60 then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:AddTrinket(case.id, false)
                        end
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_EFFECT
                                and e.Variant == EffectVariant[rules.variant]
                            then
                                e:Remove()
                            end
                        end
                        p:SetActiveCharge(
                            Isaac.GetItemConfig():GetCollectible(p:GetActiveItem()).MaxCharges
                        )
                        effectPeak = { scale = 0, sprite = 0, size = 0, count = 0 }
                    end
                    if effectPeak then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local effect = e:ToEffect()
                            if effect and effect.Variant == EffectVariant[rules.variant] then
                                effectPeak.count = effectPeak.count + 1
                                effectPeak.scale = math.max(effectPeak.scale, effect.Scale)
                                effectPeak.sprite =
                                    math.max(effectPeak.sprite, effect.SpriteScale.X)
                                effectPeak.size = math.max(effectPeak.size, effect.Size)
                            end
                        end
                        if tick == 150 or tick == 270 then
                            effectPeak.tick, effectPeak.phase =
                                tick, tick == 150 and "control" or "held"
                            effectPeak.owned = p:HasTrinket(case.id)
                            report("trinket_effect_size", effectPeak)
                            effectPeak = nil
                        end
                    end
                    return
                end
                if rules.mode == "enemy_attraction" then
                    if tick == 60 or tick == 240 then
                        if tick == 60 then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:AddTrinket(case.id, false)
                        end
                    elseif tick == 75 or tick == 255 then
                        attractionTarget = Isaac.Spawn(
                            EntityType.ENTITY_GAPER,
                            0,
                            0,
                            room:GetClampedPosition(p.Position + Vector(100, 0), 30),
                            Vector.Zero,
                            nil
                        )
                        attractionTarget:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
                        attractionTarget.MaxHitPoints, attractionTarget.HitPoints = 10000, 10000
                        attractionTarget:GetData().auditTriggerTarget = true
                        attractionTarget:GetData().auditTargetWarmupHealth = 10000
                    elseif tick == 90 or tick == 270 then
                        attractionTarget.Position =
                            room:GetClampedPosition(p.Position + Vector(100, 0), 30)
                        attractionTarget.Velocity = Vector.Zero
                        attractionTarget:GetData().auditTrinketKnockback = true
                        attractionStart = attractionTarget.Position:Distance(p.Position)
                        p:SetMinDamageCooldown(240)
                    elseif tick == 210 or tick == 390 then
                        report("trinket_enemy_attraction", {
                            tick = tick,
                            phase = tick == 210 and "control" or "held",
                            owned = p:HasTrinket(case.id),
                            initial = attractionStart,
                            distance = attractionTarget.Position:Distance(p.Position),
                            dead = attractionTarget:IsDead(),
                            health = attractionTarget.HitPoints,
                        })
                        attractionTarget:Remove()
                    end
                    return
                end
                if rules.mode == "bomb_drops" then
                    local index, offset =
                        math.floor((tick - 90) / rules.period), (tick - 90) % rules.period
                    if
                        tick >= 87
                        and (tick - 87) % rules.period == 0
                        and (tick - 87) / rules.period < rules.count
                    then
                        p:AddBombs(2 - p:GetNumBombs())
                        p:SetMinDamageCooldown(case.end_tick * 2)
                        p.Position, p.Velocity = room:GetCenterPos() - Vector(0, 60), Vector.Zero
                    end
                    if tick >= 90 and index < rules.count then
                        if offset == 0 then
                            clearPickups()
                            bombTrial = nil
                        elseif offset == 4 then
                            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                                local bomb = entity:ToBomb()
                                if bomb then
                                    bombTrial = bomb
                                    bomb:SetExplosionCountdown(1)
                                    break
                                end
                            end
                            p.Position, p.Velocity =
                                room:GetCenterPos() + Vector(0, 100), Vector.Zero
                        elseif offset == 15 then
                            report("trinket_bomb_drops", {
                                tick = tick,
                                exploded = bombTrial ~= nil and not bombTrial:Exists(),
                                placed = bombTrial ~= nil,
                                ammo_spent = 2 - p:GetNumBombs(),
                                owned = p:HasTrinket(case.id),
                                drops = pickups(),
                            })
                        end
                    end
                    return
                end
                if rules.mode == "grid_actor" then
                    if tick == 87 then
                        p.Position, p.Velocity = room:GetCenterPos() + Vector(60, -60), Vector.Zero
                    end
                    return
                end
                if rules.mode == "expansion" then
                    if tick >= 87 and (tick - 87) % 90 == 0 and (tick - 87) / 90 < rules.count then
                        p:SetActiveCharge(
                            Isaac.GetItemConfig()
                                :GetCollectible(CollectibleType.COLLECTIBLE_D6).MaxCharges
                        )
                        p:SetMinDamageCooldown(120)
                    end
                    return
                end
                if rules.mode == "endless" then
                    local trialIndex = math.floor((tick - 87) / 45)
                    local offset = (tick - 87) % 45
                    if tick >= 87 and trialIndex < rules.count then
                        if offset == 0 then
                            clearPickups()
                            p.Position, p.Velocity =
                                room:GetCenterPos() - Vector(100, 0), Vector.Zero
                            p:SetCard(0, 0)
                            p:SetPill(0, 0)
                            if trialIndex < 24 then
                                pocketTrial = {
                                    kind = "card",
                                    id = Card.CARD_HIEROPHANT,
                                    variant = PickupVariant.PICKUP_TAROTCARD,
                                }
                                p:SetCard(0, pocketTrial.id)
                            elseif trialIndex < 48 then
                                pocketTrial = {
                                    kind = "pill",
                                    id = Game()
                                        :GetItemPool()
                                        :ForceAddPillEffect(PillEffect.PILLEFFECT_BALLS_OF_STEEL),
                                    variant = PickupVariant.PICKUP_PILL,
                                }
                                p:SetPill(0, pocketTrial.id)
                            else
                                pocketTrial = {
                                    kind = "rune",
                                    id = Card.RUNE_ALGIZ,
                                    variant = PickupVariant.PICKUP_TAROTCARD,
                                }
                                p:SetCard(0, pocketTrial.id)
                            end
                            pocketTrial.origin = p.Position
                        elseif offset == 12 then
                            p.Position, p.Velocity =
                                room:GetClampedPosition(pocketTrial.origin + Vector(100, 0), 30),
                                Vector.Zero
                        elseif offset == 36 then
                            local count = 0
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                if
                                    e.Type == EntityType.ENTITY_PICKUP
                                    and e.Variant == pocketTrial.variant
                                    and e.SubType == pocketTrial.id
                                then
                                    count = count + 1
                                end
                            end
                            report("trinket_consumable_copy", {
                                tick = tick,
                                kind = pocketTrial.kind,
                                id = pocketTrial.id,
                                copies = count,
                                held_card = p:GetCard(0),
                                held_pill = p:GetPill(0),
                            })
                        end
                    end
                    return
                end
                if rules.mode == "troll_bombs" then
                    if tick == 60 or tick == 240 then
                        if tick == 60 then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:AddTrinket(case.id, false)
                        end
                        clearPickups()
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:ToBomb() then
                                e:Remove()
                            end
                        end
                        p.Position = room:GetCenterPos() + Vector(0, 100)
                    elseif tick == 75 or tick == 255 then
                        for i, subtype in ipairs({
                            BombSubType.BOMB_TROLL,
                            BombSubType.BOMB_SUPERTROLL,
                        }) do
                            -- Let the native fuse run: Safety Scissors converts
                            -- a troll bomb immediately before it would explode.
                            Game():Spawn(
                                EntityType.ENTITY_PICKUP,
                                PickupVariant.PICKUP_BOMB,
                                room:GetCenterPos() + Vector(-100 + i * 50, -80),
                                Vector.Zero,
                                nil,
                                subtype,
                                100003 + i * 7919
                            )
                        end
                    elseif tick == 105 or tick == 210 or tick == 390 then
                        local bombs = 0
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:ToBomb() then
                                bombs = bombs + 1
                            end
                        end
                        report("trinket_troll_bombs", {
                            tick = tick,
                            phase = tick == 105 and "control"
                                or tick == 210 and "control_settled"
                                or "held",
                            bombs = bombs,
                            pickups = pickups(),
                            owned = p:HasTrinket(case.id),
                        })
                    end
                    return
                end
                if rules.mode == "shop" then
                    if tick == 480 then
                        local shelf = {}
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local pickup = e:ToPickup()
                            if pickup and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
                                local config = Isaac.GetItemConfig():GetCollectible(pickup.SubType)
                                shelf[#shelf + 1] = {
                                    id = pickup.SubType,
                                    price = pickup.Price,
                                    familiar = config.Type == ItemType.ITEM_FAMILIAR
                                        -- Dead Bird is a conditional familiar
                                        -- with the passive ItemConfig type.
                                        or pickup.SubType
                                            == CollectibleType.COLLECTIBLE_DEAD_BIRD,
                                }
                                if not shopPurchase and not p:HasCollectible(pickup.SubType) then
                                    shopPurchase = {
                                        entity = pickup,
                                        id = pickup.SubType,
                                        initial = p:GetCollectibleNum(pickup.SubType, true),
                                    }
                                end
                            end
                        end
                        report("trinket_native_shop", {
                            tick = tick,
                            shelf = shelf,
                            owned = p:HasTrinket(case.id),
                            room_type = room:GetType(),
                        })
                    elseif rules.reward == "credit" and tick == 540 and shopPurchase then
                        p:AddCoins(-p:GetNumCoins())
                        shopPurchase.coins = p:GetNumCoins()
                        shopPurchase.price = shopPurchase.entity.Price
                        p.Position, p.Velocity = shopPurchase.entity.Position, Vector.Zero
                    elseif rules.reward == "credit" and tick == 660 then
                        report("trinket_shop_purchase", {
                            tick = tick,
                            found = shopPurchase ~= nil,
                            acquired = shopPurchase
                                and p:GetCollectibleNum(shopPurchase.id, true)
                                    > shopPurchase.initial,
                            price = shopPurchase and shopPurchase.price,
                            coins_before = shopPurchase and shopPurchase.coins,
                            coins_after = p:GetNumCoins(),
                            owned = p:HasTrinket(case.id),
                        })
                    end
                    return
                end
                if rules.mode == "locked_chest" then
                    if
                        lockedChest
                        and chestOpeningKeys == nil
                        and (
                            not lockedChest:Exists()
                            or lockedChest.SubType ~= 1
                            or lockedChest.Variant ~= PickupVariant.PICKUP_LOCKEDCHEST
                        )
                    then
                        chestOpeningKeys = p:GetNumKeys()
                        p.Position, p.Velocity = room:GetCenterPos() + Vector(100, 0), Vector.Zero
                    end
                    if tick == 60 or tick == 180 then
                        if tick == 60 then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:AddTrinket(case.id, false)
                        end
                        p:AddKeys(-p:GetNumKeys())
                        clearPickups()
                        lockedChest, chestOpeningKeys = nil, nil
                    elseif tick == 75 or tick == 195 then
                        lockedChest = Isaac.Spawn(
                            EntityType.ENTITY_PICKUP,
                            PickupVariant.PICKUP_LOCKEDCHEST,
                            1,
                            room:GetCenterPos() - Vector(100, 0),
                            Vector.Zero,
                            nil
                        ):ToPickup()
                    elseif tick == 105 or tick == 225 then
                        if rules.explosion then
                            p.Position = room:GetCenterPos() + Vector(100, 0)
                            local bomb = p:FireBomb(lockedChest.Position, Vector.Zero)
                            bomb:SetExplosionCountdown(1)
                        else
                            p.Position = lockedChest.Position
                        end
                        p.Velocity = Vector.Zero
                    elseif tick == 150 or tick == 270 then
                        report("trinket_locked_chest", {
                            tick = tick,
                            phase = tick == 150 and "control" or "held",
                            owned = p:HasTrinket(case.id),
                            keys = chestOpeningKeys or p:GetNumKeys(),
                            opened = not lockedChest:Exists()
                                or lockedChest.SubType ~= 1
                                or lockedChest.Variant ~= PickupVariant.PICKUP_LOCKEDCHEST,
                        })
                    end
                    return
                end
                if rules.mode == "champions" then
                    if tick == 480 or tick == 1110 then
                        if case.kind == "trinket" then
                            if tick == 480 then
                                p:TryRemoveTrinket(case.id)
                            else
                                p:AddTrinket(case.id, false)
                            end
                        else
                            if tick == 480 then
                                p:RemoveCollectible(case.id)
                            else
                                p:AddCollectible(case.id, 0, false)
                            end
                        end
                        championTotal, championCount, championRespawns = 0, 0, 0
                        p:SetMinDamageCooldown(case.end_tick + 60)
                    end
                    local start = tick >= 1110 and 1140 or 510
                    local step = tick - start
                    if step >= 0 and step < rules.count * 9 then
                        if step % 9 == 0 then
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                if e:IsActiveEnemy(false) then
                                    e:Remove()
                                end
                            end
                            room:SetClear(true)
                        elseif step % 9 == 3 then
                            room:RespawnEnemies()
                            championRespawns = championRespawns + 1
                        elseif step % 9 == 6 then
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                local npc = e:ToNPC()
                                if npc and npc:IsActiveEnemy(false) and npc:IsVulnerableEnemy() then
                                    championTotal = championTotal + 1
                                    if npc:IsChampion() then
                                        championCount = championCount + 1
                                    end
                                end
                            end
                            if step == (rules.count - 1) * 9 + 6 then
                                report("native_champion_rooms", {
                                    tick = tick,
                                    phase = start == 510 and "control" or "held",
                                    respawns = championRespawns,
                                    total = championTotal,
                                    champions = championCount,
                                    owned = case.kind == "trinket" and p:HasTrinket(case.id)
                                        or case.kind == "collectible"
                                            and p:HasCollectible(case.id),
                                })
                            end
                        end
                    end
                    return
                end
                if rules.mode == "cooldown" then
                    if tick == 60 then
                        p:TryRemoveTrinket(case.id)
                    elseif tick == 180 then
                        p:AddTrinket(case.id, false)
                    end
                    if tick == 90 or tick == 210 then
                        p:AddHearts(6 - p:GetHearts())
                        p:ResetDamageCooldown()
                        local before = p:GetHearts()
                        local accepted = p:TakeDamage(1, 0, EntityRef(p), 0)
                        report("trinket_cooldown", {
                            tick = tick,
                            phase = tick == 90 and "control" or "held",
                            before = before,
                            after = p:GetHearts(),
                            accepted = accepted,
                            cooldown = p:GetDamageCooldown(),
                            owned = p:HasTrinket(case.id),
                        })
                    end
                    return
                end
                if rules.mode == "poison_duration" then
                    if tick == 60 then
                        p:TryRemoveTrinket(case.id)
                    elseif tick == 600 then
                        p:AddTrinket(case.id, false)
                    end
                    if tick == 75 or tick == 615 then
                        if statusTarget and statusTarget:Exists() then
                            statusTarget:Remove()
                        end
                        statusFirst, statusLast = nil, nil
                        statusTarget = Isaac.Spawn(
                            EntityType.ENTITY_GAPER,
                            0,
                            0,
                            p.Position - Vector(0, 30),
                            Vector.Zero,
                            nil
                        ):ToNPC()
                        statusTarget.MaxHitPoints, statusTarget.HitPoints = 10000, 10000
                        statusTarget:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
                    elseif tick == 90 or tick == 630 then
                        statusTarget.Position = p.Position - Vector(0, 30)
                        statusTarget.Velocity = Vector.Zero
                        statusTarget.MaxHitPoints, statusTarget.HitPoints = 10000, 10000
                        statusTarget:GetData().auditTriggerTarget = true
                        p:FireTear(p.Position - Vector(0, 5), Vector(0, -5), false, true, false)
                    end
                    if
                        statusTarget
                        and statusTarget:Exists()
                        and statusTarget:HasEntityFlags(EntityFlag.FLAG_POISON)
                    then
                        statusFirst = statusFirst or tick
                        statusLast = tick
                    end
                    if tick == 570 or tick == 1170 then
                        report("trinket_poison_duration", {
                            tick = tick,
                            phase = tick == 570 and "control" or "held",
                            first = statusFirst,
                            last = statusLast,
                            expired = not statusTarget:HasEntityFlags(EntityFlag.FLAG_POISON),
                            damage = 10000 - statusTarget.HitPoints,
                        })
                    end
                    return
                end
                if rules.mode == "floor" then
                    if tick == 60 then
                        p:TryRemoveTrinket(case.id)
                    elseif tick == 450 then
                        p:AddTrinket(case.id, false)
                    end
                    if tick == 90 or tick == 480 then
                        Game():GetLevel():SetStage(
                            assert(LevelStage[rules.stage]),
                            assert(StageType[rules.stage_type])
                        )
                        Game():StartStageTransition(true, 0, p)
                    elseif tick == 420 or tick == 810 then
                        local level = Game():GetLevel()
                        local list, counts, icons = level:GetRooms(), {}, 0
                        for i = 0, list.Size - 1 do
                            local d = list:Get(i)
                            if d.Data and d.SafeGridIndex >= 0 then
                                for name in pairs(rules.rooms or {}) do
                                    if d.Data.Type == assert(RoomType[name]) then
                                        counts[name] = (counts[name] or 0) + 1
                                    end
                                end
                                if
                                    d.Data.Type ~= RoomType.ROOM_DEFAULT
                                    and d.DisplayFlags & roomIconFlag ~= 0
                                then
                                    icons = icons + 1
                                end
                            end
                        end
                        report("trinket_floor", {
                            tick = tick,
                            phase = tick == 420 and "control" or "held",
                            stage = level:GetStage(),
                            stage_type = level:GetStageType(),
                            owned = p:HasTrinket(case.id),
                            counts = counts,
                            icons = icons,
                        })
                    end
                    return
                end
                if rules.mode == "rooms" then
                    local step = tick - 450
                    if
                        rules.reward == "watch_charge"
                        and step >= 0
                        and step < rules.count * 120
                        and step % 120 == 30
                    then
                        clearPickups()
                        p:SetActiveCharge(0)
                        p:SetMinDamageCooldown(240)
                    end
                    if
                        step >= 0
                        and step < rules.count * 120
                        and (step % 120 == 30 or step % 120 == 108)
                    then
                        local result = state(p)
                        result.tick, result.phase =
                            tick, step % 120 == 30 and "entered" or "cleared"
                        result.alive, result.clear = room:GetAliveEnemiesCount(), room:IsClear()
                        result.collectible_effects, result.trinket_effects = {}, {}
                        local effects = p:GetEffects()
                        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
                            local count = effects:GetCollectibleEffectNum(id)
                            local virtual = p:GetCollectibleNum(id) - p:GetCollectibleNum(id, true)
                            if count > 0 or virtual > 0 then
                                result.collectible_effects[tostring(id)] = math.max(count, virtual)
                            end
                        end
                        for id = 1, TrinketType.NUM_TRINKETS - 1 do
                            if id ~= case.id then
                                local count = math.max(
                                    effects:GetTrinketEffectNum(id),
                                    p:GetTrinketMultiplier(id)
                                )
                                if count > 0 then
                                    result.trinket_effects[tostring(id)] = count
                                end
                            end
                        end
                        result.pocket = p:GetActiveItem(ActiveSlot.SLOT_POCKET2)
                        result.azazel = p:GetPlayerType() == PlayerType.PLAYER_AZAZEL
                            or p.CanFly and p:HasWeaponType(WeaponType.WEAPON_BRIMSTONE)
                        result.bonies, result.dips, result.red_rooms, result.twins = 0, 0, 0, 0
                        result.dips = result.familiars[tostring(FamiliarVariant.DIP)] or 0
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
                                if e.Type == EntityType.ENTITY_BONY then
                                    result.bonies = result.bonies + 1
                                end
                                if e.Type == EntityType.ENTITY_DIP then
                                    result.dips = result.dips + 1
                                end
                            end
                        end
                        for _, variant in ipairs({
                            FamiliarVariant.BROTHER_BOBBY,
                            FamiliarVariant.SISTER_MAGGY,
                        }) do
                            result.twins = result.twins + (result.familiars[tostring(variant)] or 0)
                        end
                        local rooms = Game():GetLevel():GetRooms()
                        for i = 0, rooms.Size - 1 do
                            if rooms:Get(i).Flags & RoomDescriptor.FLAG_RED_ROOM ~= 0 then
                                result.red_rooms = result.red_rooms + 1
                            end
                        end
                        report("trinket_room_state", result)
                    end
                    return
                end
                if (rules.mode == "planetarium" or rules.mode == "guppy") and tick == 120 then
                    report("trinket_condition", {
                        tick = tick,
                        phase = "held",
                        chance = Game():GetLevel():GetPlanetariumChance(),
                        guppy = p:HasPlayerForm(PlayerForm.PLAYERFORM_GUPPY),
                    })
                end
                if rules.mode == "tear_control" then
                    if tick == 60 then
                        p:TryRemoveTrinket(case.id)
                    elseif tick == 180 then
                        p:AddTrinket(case.id, false)
                    end
                    if rules.effect == "flat" or rules.effect == "knockback" then
                        if tick == 60 or tick == 240 then
                            knockPeak = 0
                            knockTarget = Isaac.Spawn(
                                EntityType.ENTITY_GAPER,
                                0,
                                0,
                                room:GetClampedPosition(p.Position + Vector(150, 0), 30),
                                Vector.Zero,
                                nil
                            ):ToNPC()
                            knockTarget.MaxHitPoints, knockTarget.HitPoints = 10000, 10000
                            knockTarget:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
                            knockTarget:GetData().auditTriggerTarget = true
                            knockTarget:GetData().auditTargetWarmupHealth = 10000
                        elseif tick == 90 or tick == 300 then
                            local position = p.Position - Vector(0, 60)
                            knockTarget:GetData().auditTrinketKnockbackOrigin =
                                { position.X, position.Y }
                            knockTarget.MaxHitPoints, knockTarget.HitPoints = 10000, 10000
                            knockTarget:GetData().auditTrinketKnockback = true
                            knockPeak = 0
                        end
                        if
                            knockTarget
                            and knockTarget:Exists()
                            and knockTarget:GetData().auditTrinketKnockback
                        then
                            knockPeak = math.max(
                                knockPeak,
                                knockTarget.Velocity:Length(),
                                knockTarget:GetData().auditTrinketKnockbackPeak or 0
                            )
                            if tick == 150 or tick == 360 then
                                report("trinket_knockback_result", {
                                    tick = tick,
                                    phase = tick == 150 and "control" or "held",
                                    velocity = knockPeak,
                                    damage = 10000 - knockTarget.HitPoints,
                                    dead = knockTarget:IsDead(),
                                    collision = knockTarget.EntityCollisionClass,
                                    x = knockTarget.Position.X,
                                    y = knockTarget.Position.Y,
                                })
                                knockTarget:Remove()
                                knockTarget = nil
                            end
                        end
                    end
                    return
                end
                if rules.mode == "loot" then
                    if tick == 60 or tick == 180 then
                        if tick == 60 then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:AddTrinket(case.id, false)
                        end
                        clearPickups()
                        p.Position, p.Velocity = room:GetCenterPos() + Vector(0, 100), Vector.Zero
                    end
                    if tick == 75 or tick == 195 then
                        local totals, opened, flies, empty = {}, 0, 0, 0
                        for i = 1, rules.count do
                            local old = {}
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                old[e.InitSeed] = true
                            end
                            local chest = Game():Spawn(
                                EntityType.ENTITY_PICKUP,
                                PickupVariant.PICKUP_CHEST,
                                room:GetCenterPos() - Vector(0, 80),
                                Vector.Zero,
                                nil,
                                1,
                                100003 + i * 7919
                            ):ToPickup()
                            old[chest.InitSeed] = true
                            if chest:TryOpenChest(p) then
                                opened = opened + 1
                            end
                            chest:Remove()
                            local drops = 0
                            for _, e in ipairs(Isaac.GetRoomEntities()) do
                                if not old[e.InitSeed] and e:Exists() then
                                    local pickup = e:ToPickup()
                                    if pickup then
                                        local key = pickup.Variant .. "." .. pickup.SubType
                                        totals[key] = (totals[key] or 0) + 1
                                        drops = drops + 1
                                    end
                                    if e.Type == EntityType.ENTITY_ATTACKFLY then
                                        flies = flies + 1
                                    end
                                    if i ~= rules.count then
                                        e:Remove()
                                    end
                                end
                            end
                            if drops == 0 then
                                empty = empty + 1
                            end
                        end
                        report("trinket_loot", {
                            tick = tick,
                            phase = tick == 75 and "control" or "held",
                            owned = p:HasTrinket(case.id),
                            opened = opened,
                            count = rules.count,
                            drops = totals,
                            flies = flies,
                            empty = empty,
                        })
                    end
                    return
                end
                if rules.mode == "grid" then
                    if tick == 60 or tick == rules.held_tick - 15 then
                        if tick == 60 then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:AddTrinket(case.id, false)
                        end
                        clearPickups()
                        p.Position, p.Velocity = room:GetCenterPos() + Vector(0, 100), Vector.Zero
                        p:SetMinDamageCooldown(case.end_tick + 60)
                        gridTrial = {
                            phase = tick == 60 and "control" or "held",
                            drops = {},
                            destroyed = 0,
                            black_poop = 0,
                            crawl_spaces = 0,
                            rng_samples = {},
                        }
                        if rules.reward == "explosion" then
                            if gridVictim and gridVictim:Exists() then
                                gridVictim:Remove()
                            end
                            gridVictim = Isaac.Spawn(
                                EntityType.ENTITY_GAPER,
                                0,
                                0,
                                room:GetCenterPos() - Vector(0, 60),
                                Vector.Zero,
                                nil
                            )
                            gridVictim.MaxHitPoints, gridVictim.HitPoints = 10000, 10000
                            gridVictim:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
                            gridVictim:GetData().auditTriggerTarget = true
                            gridVictim:GetData().auditTargetWarmupHealth = 10000
                        end
                    end
                    local start = tick >= rules.held_tick - 15 and rules.held_tick or 75
                    local step = tick - start
                    local batch, offset = math.floor(step / 6), step % 6
                    if step >= 0 and batch < rules.count / 8 then
                        if offset == 0 then
                            gridIndices = {}
                            for i = 1, 8 do
                                local index = room:GetGridIndex(
                                    room:GetCenterPos() + Vector(-180 + i * 40, -60)
                                )
                                assert(
                                    not room:GetGridEntity(index),
                                    "Native grid trial location occupied"
                                )
                                if rules.native_poop then
                                    p.Position = room:GetGridPosition(index)
                                    p:UseActiveItem(
                                        CollectibleType.COLLECTIBLE_POOP,
                                        UseFlag.USE_NOANIM | UseFlag.USE_NOCOSTUME
                                    )
                                else
                                    assert(
                                        room:SpawnGridEntity(
                                            index,
                                            assert(GridEntityType[rules.grid]),
                                            0,
                                            gridSeeds[batch * 8 + i],
                                            0
                                        )
                                    )
                                end
                                gridIndices[#gridIndices + 1] = index
                            end
                            p.Position = room:GetCenterPos() + Vector(0, 100)
                        elseif offset == 2 then
                            for _, index in ipairs(gridIndices) do
                                local grid = assert(room:GetGridEntity(index))
                                if #gridTrial.rng_samples < 8 then
                                    gridTrial.rng_samples[#gridTrial.rng_samples + 1] = {
                                        seed = grid:GetRNG():GetSeed(),
                                        state = grid.State,
                                        variant = grid:GetVariant(),
                                    }
                                end
                                if
                                    grid:GetType() == GridEntityType.GRID_POOP
                                    and grid:GetVariant() == BLACK_POOP_VARIANT
                                then
                                    gridTrial.black_poop = gridTrial.black_poop + 1
                                end
                                if rules.grid == "GRID_POOP" then
                                    if grid.HurtWithSource then
                                        grid:HurtWithSource(1000, EntityRef(p))
                                    else
                                        grid:Hurt(1000)
                                    end
                                elseif grid.DestroyWithSource then
                                    grid:DestroyWithSource(false, EntityRef(p))
                                else
                                    grid:Destroy(false)
                                end
                                if
                                    room:GetGridCollision(index)
                                    == GridCollisionClass.COLLISION_NONE
                                then
                                    gridTrial.destroyed = gridTrial.destroyed + 1
                                end
                            end
                        elseif offset == 4 then
                            for key, count in pairs(pickups()) do
                                gridTrial.drops[key] = (gridTrial.drops[key] or 0) + count
                            end
                            for _, index in ipairs(gridIndices) do
                                local grid = room:GetGridEntity(index)
                                if grid and grid:GetType() == GridEntityType.GRID_STAIRS then
                                    gridTrial.crawl_spaces = gridTrial.crawl_spaces + 1
                                end
                                room:RemoveGridEntity(index, 0, false)
                            end
                            if batch == rules.count / 8 - 1 then
                                gridTrial.tick, gridTrial.owned = tick, p:HasTrinket(case.id)
                                gridTrial.enemy_damage = gridVictim and 10000 - gridVictim.HitPoints
                                    or 0
                                report("trinket_grid_loot", gridTrial)
                            else
                                clearPickups()
                            end
                        end
                    end
                    return
                end
                if rules.mode == "generation" then
                    if tick == 60 or tick == 180 then
                        if tick == 60 then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:AddTrinket(case.id, false)
                        end
                        phase = tick == 60 and "control" or "held"
                        clearPickups()
                        p.Position, p.Velocity = room:GetCenterPos() + Vector(0, 100), Vector.Zero
                    end
                    if tick == 75 or tick == 195 then
                        local counts, examples, active = {}, {}, 0
                        for i = 1, rules.count do
                            local seed = 100003 + i * 7919
                            if rules.pool then
                                local id = Game():GetItemPool():GetCollectible(
                                    assert(ItemPoolType[rules.pool]),
                                    false,
                                    seed
                                )
                                local config = Isaac.GetItemConfig():GetCollectible(id)
                                active = active + (config.Type == ItemType.ITEM_ACTIVE and 1 or 0)
                                local key = tostring(id)
                                counts[key] = (counts[key] or 0) + 1
                            else
                                local e = Game():Spawn(
                                    EntityType.ENTITY_PICKUP,
                                    assert(PickupVariant[rules.variant]),
                                    room:GetCenterPos() + Vector(-150 + i % 8 * 40, -80),
                                    Vector.Zero,
                                    nil,
                                    0,
                                    seed
                                ):ToPickup()
                                local key = e.Variant .. "." .. e.SubType
                                counts[key] = (counts[key] or 0) + 1
                                local retain = i <= 8
                                if rules.retain_targets then
                                    retain = false
                                    for _, target in ipairs(rules.target) do
                                        retain = retain or key == target
                                    end
                                    retain = retain and #examples < 8
                                end
                                if retain then
                                    examples[#examples + 1] = {
                                        seed = e.InitSeed,
                                        variant = e.Variant,
                                        subtype = e.SubType,
                                    }
                                else
                                    e:Remove()
                                end
                            end
                        end
                        report("trinket_generation", {
                            tick = tick,
                            phase = phase,
                            owned = p:HasTrinket(case.id),
                            counts = counts,
                            active = active,
                            examples = examples,
                        })
                    end
                    return
                end
                if rules.mode ~= "coins" and rules.mode ~= "damage" and rules.mode ~= "hearts" then
                    return
                end
                if tick == 60 then
                    if rules.reward ~= "dice" then
                        clearPickups()
                    end
                    p:GetTrinketRNG(case.id):SetSeed(rules.seed or 431, 35)
                    if rules.mode == "coins" then
                        p:AddCoins(-p:GetNumCoins())
                        p:AddHearts(1 - p:GetHearts())
                        if rules.reward == "room" then
                            p:SetMinDamageCooldown(case.end_tick * 2)
                        end
                    elseif rules.mode == "hearts" then
                        p:AddHearts(p:GetMaxHearts() - p:GetHearts())
                    elseif rules.mode == "damage" then
                        p:AddMaxHearts((rules.max_hearts or 24) - p:GetMaxHearts(), false)
                        p:AddHearts((rules.max_hearts or 24) - p:GetHearts())
                        p:AddSoulHearts(-p:GetSoulHearts())
                        if rules.reward == "umbilical" then
                            p:AddHearts(1 - p:GetHearts())
                            p:AddSoulHearts(rules.soul or 0)
                            p:SetMinDamageCooldown(case.end_tick * 2)
                        end
                        if rules.enemy then
                            local e = Isaac.Spawn(
                                EntityType.ENTITY_GAPER,
                                0,
                                0,
                                p.Position + Vector(40, 0),
                                Vector.Zero,
                                nil
                            )
                            e.MaxHitPoints, e.HitPoints = 100000, 100000
                            e:GetData().auditTrinketVictim = true
                            e:GetData().auditTriggerTarget = true
                            e:GetData().auditTargetWarmupHealth = 100000
                        end
                    end
                    report("trinket_trial_before", state(p))
                end
                local period = rules.period or trialPeriod
                local trial = (tick - firstTrialTick) / period
                if
                    tick >= firstTrialTick
                    and trial == math.floor(trial)
                    and trial < rules.count
                then
                    if rules.mode == "coins" or rules.mode == "hearts" then
                        p:AddCoins(-p:GetNumCoins())
                        if rules.charge then
                            p:SetActiveCharge(0)
                        end
                        pending = { before = state(p), tick = tick }
                        pending.pickup = Isaac.Spawn(
                            EntityType.ENTITY_PICKUP,
                            rules.mode == "coins" and PickupVariant.PICKUP_COIN
                                or PickupVariant.PICKUP_HEART,
                            rules.mode == "coins" and CoinSubType.COIN_PENNY
                                or HeartSubType.HEART_FULL,
                            p.Position,
                            Vector.Zero,
                            nil
                        ):ToPickup()
                        pending.pickup.Wait = 0
                    elseif rules.mode == "damage" then
                        if rules.passive_items then
                            clearPickups()
                            for _, name in ipairs(rules.passive_items) do
                                local id = assert(CollectibleType[name])
                                if not p:HasCollectible(id) then
                                    p:AddCollectible(id, 0, false)
                                end
                            end
                        end
                        p:AddHearts(
                            (rules.health or (rules.low_health and 2 or 24)) - p:GetHearts()
                        )
                        if rules.soul then
                            p:AddSoulHearts(rules.soul - p:GetSoulHearts())
                        end
                        if rules.resources then
                            p:AddCoins(10 - p:GetNumCoins())
                            p:AddKeys(10 - p:GetNumKeys())
                            p:AddBombs(10 - p:GetNumBombs())
                        end
                        p:ResetDamageCooldown()
                        pending = { before = state(p), tick = tick }
                        local flags = rules.explosion and DamageFlag.DAMAGE_EXPLOSION or 0
                        pending.accepted = p:TakeDamage(1, flags, EntityRef(p), 0)
                        pending.immediate = state(p)
                    end
                end
                if
                    pending
                    and tick == pending.tick + (rules.observation_delay or observationDelay)
                then
                    local result = { tick = tick, before = pending.before, after = state(p) }
                    result.consumed = not pending.pickup or not pending.pickup:Exists()
                    result.accepted, result.immediate = pending.accepted, pending.immediate
                    if rules.passive_items then
                        result.lost_passives = {}
                        for _, name in ipairs(rules.passive_items) do
                            local id = assert(CollectibleType[name])
                            if not p:HasCollectible(id) then
                                result.lost_passives[#result.lost_passives + 1] = id
                            end
                        end
                    end
                    result.tonsils = result.after.familiars[tostring(FamiliarVariant.TONSIL)] or 0
                    result.explosions = result.after.effects[tostring(EffectVariant.BOMB_EXPLOSION)]
                        or 0
                    report("trinket_native_result", result)
                    if pending.pickup and pending.pickup:Exists() then
                        pending.pickup:Remove()
                    end
                    pending = nil
                end
            end)
        end,
    }
end
