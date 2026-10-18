return function(report, actor, moveRoom, moveFloor)
    local feeding, seen, awardChoices = {}, {}, {}
    local awardGroup
    local combatRooms = {}
    local contactTrial, contactEntity, contactSpawner, obstacleIndex
    local secretOrigin, secretIndex, fairyPosition
    local fairyOrigin, fairyRockIndex
    local blanketHit
    local previewChest, flipItems
    local astralHit
    local coinChest, coinChestBefore
    local betrayalActors, betrayalBefore, puppyVictims
    local modemProjectiles
    local dealBoss, devilRoom, sanguineHit
    local pitRooms, pitRoom
    local function collectCombatRooms(case)
        combatRooms = {}
        local rooms = Game():GetLevel():GetRooms()
        local occupied = _IsaacLan.rooms_positions()
        for i = 0, rooms.Size - 1 do
            local d = rooms:Get(i)
            local combat = false
            if
                d.Data
                and d.Data.Type == RoomType.ROOM_DEFAULT
                and d.SafeGridIndex ~= occupied["0"].index
                and d.SafeGridIndex ~= occupied["1"].index
            then
                for j = 0, d.Data.SpawnCount - 1 do
                    local spawn = d.Data.Spawns:Get(j)
                    for k = 0, spawn.EntryCount - 1 do
                        local kind = spawn.Entries:Get(k).Type
                        if
                            kind >= 10
                            and kind < 1000
                            and kind ~= EntityType.ENTITY_FIREPLACE
                            and kind ~= EntityType.ENTITY_MOVABLE_TNT
                            and kind ~= EntityType.ENTITY_SHOPKEEPER
                        then
                            combat = true
                        end
                    end
                end
            end
            if combat then
                combatRooms[#combatRooms + 1] = d.SafeGridIndex
            end
        end
        assert(#combatRooms > 0, "Native floor has no unused combat room")
    end
    local function generation(case, phase, tick)
        local trial = case.trigger_effects and case.trigger_effects.generation_trial
        if not trial then
            return
        end
        actor(case.slot, function(p, room)
            local result = {
                item = case.id,
                tick = tick,
                phase = phase,
                drops = {},
                award_counts = {},
                options = 0,
            }
            if trial.mode == "pool" then
                result.bibles = 0
                for i = 1, 1024 do
                    local id = Game()
                        :GetItemPool()
                        :GetCollectible(ItemPoolType.POOL_BOSS, false, 100003 + i * 7919)
                    if id == CollectibleType.COLLECTIBLE_BIBLE then
                        result.bibles = result.bibles + 1
                    end
                end
            elseif trial.mode == "planetarium" then
                result.chance = Game():GetLevel():GetPlanetariumChance()
            elseif trial.mode == "champions" then
                result.champions = 0
                for i = 1, 512 do
                    local npc = Game():Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        room:GetCenterPos(),
                        Vector.Zero,
                        nil,
                        0,
                        100003 + i * 7919
                    ):ToNPC()
                    result.champions = result.champions + (npc:IsChampion() and 1 or 0)
                    npc:Remove()
                end
            else
                local choiceIteration
                local existing = {}
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    existing[e.InitSeed] = true
                end
                local count = trial.mode == "pickup" and 256 or 32
                if case.id == CollectibleType.COLLECTIBLE_GLYPH_OF_BALANCE then
                    p:AddMaxHearts(6 - p:GetMaxHearts(), false)
                    p:AddSoulHearts(-p:GetSoulHearts())
                    p:AddHearts(1 - p:GetHearts())
                    p:AddKeys(6 - p:GetNumKeys())
                    p:AddBombs(6 - p:GetNumBombs())
                    p:AddCoins(16 - p:GetNumCoins())
                    if p:GetTrinket(0) == 0 then
                        p:AddTrinket(TrinketType.TRINKET_CURVED_HORN)
                    end
                end
                for i = 1, count do
                    if trial.mode == "award" then
                        room:SpawnClearAward()
                    else
                        local drop = Game():Spawn(
                            EntityType.ENTITY_PICKUP,
                            assert(PickupVariant[trial.variant]),
                            room:GetCenterPos(),
                            Vector.Zero,
                            nil,
                            trial.mode == "chest" and 1 or 0,
                            100003 + i * 7919
                        ):ToPickup()
                        if trial.mode == "chest" then
                            assert(drop:TryOpenChest(p), "Native chest did not open")
                            drop:Remove()
                        end
                    end
                    local awarded = 0
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:Exists() and not existing[e.InitSeed] then
                            local pickup = e:ToPickup()
                            if pickup then
                                local key = pickup.Variant .. "." .. pickup.SubType
                                result.drops[key] = (result.drops[key] or 0) + 1
                                result.options = result.options
                                    + (pickup.OptionsPickupIndex ~= 0 and 1 or 0)
                                awarded = awarded + 1
                            end
                            existing[e.InitSeed] = true
                            if
                                case.id == CollectibleType.COLLECTIBLE_OPTIONS
                                and phase == "after"
                                and (choiceIteration == nil or i == choiceIteration)
                                and pickup
                                and pickup.OptionsPickupIndex ~= 0
                            then
                                choiceIteration = i
                                awardChoices[#awardChoices + 1] = pickup
                            else
                                e:Remove()
                            end
                        end
                    end
                    result.award_counts[#result.award_counts + 1] = awarded
                end
            end
            report("native_generation_sample", result)
        end)
    end
    local function pickups()
        local values = {}
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:Exists() and e:ToPickup() then
                values[#values + 1] = { variant = e.Variant, subtype = e.SubType }
            end
        end
        return values
    end
    local function boxSnapshot(case, tick, phase)
        actor(case.slot, function()
            local values = {}
            for _, p in ipairs(pickups()) do
                values[#values + 1] = p.variant .. "." .. p.subtype
            end
            table.sort(values)
            report("box_checkpoint", {
                tick = tick,
                phase = phase,
                room = _IsaacLan.rooms_positions()[tostring(case.slot)].index,
                pickups = values,
            })
        end)
    end
    return {
        prepare = function(case, tick)
            feeding, seen, awardChoices = {}, {}, {}
            awardGroup = nil
            combatRooms = {}
            contactTrial, contactEntity, contactSpawner, obstacleIndex = nil, nil, nil, nil
            secretOrigin, secretIndex, fairyPosition = nil, nil, nil
            fairyOrigin, fairyRockIndex = nil, nil
            blanketHit = nil
            previewChest, flipItems = nil, {}
            astralHit = nil
            coinChest, coinChestBefore = nil, nil
            betrayalActors, betrayalBefore, puppyVictims = nil, nil, {}
            modemProjectiles = {}
            dealBoss, devilRoom, sanguineHit = nil, nil, nil
            pitRooms, pitRoom = {}, nil
            generation(case, "before", tick)
            if case.trigger_effects and case.trigger_effects.hold_poop_trial then
                actor(case.slot, function(p)
                    p:AddPoopMana(10 - p:GetPoopMana())
                end)
            end
            if case.trigger_effects and case.trigger_effects.entry_trial then
                collectCombatRooms(case)
                actor(case.slot, function(p)
                    p:SetMinDamageCooldown(2 * case.end_tick + 60)
                end)
            end
        end,
        advance = function(case, tick)
            local rules = case.trigger_effects
            if not rules then
                return
            end
            if rules.native_pit_trial then
                if tick == 90 then
                    Game()
                        :GetLevel()
                        :SetStage(LevelStage[rules.pit_stage] - 1, StageType.STAGETYPE_ORIGINAL)
                    moveFloor()
                    return
                elseif tick == 420 then
                    local rooms = Game():GetLevel():GetRooms()
                    for i = 0, rooms.Size - 1 do
                        local descriptor = rooms:Get(i)
                        if descriptor.Data and descriptor.Data.Type == RoomType.ROOM_DEFAULT then
                            pitRooms[#pitRooms + 1] = descriptor.SafeGridIndex
                        end
                    end
                elseif not pitRoom and tick >= 450 and tick < rules.collision_delay then
                    local index, offset = math.floor((tick - 450) / 30), (tick - 450) % 30
                    if pitRooms[index + 1] then
                        if offset == 0 then
                            assert(_IsaacLan.rooms_move(case.slot, pitRooms[index + 1], 0, -1))
                            if not case.split then
                                assert(
                                    _IsaacLan.rooms_move(1 - case.slot, pitRooms[index + 1], 0, -1)
                                )
                            end
                            actor(case.slot, function(p)
                                p:SetMinDamageCooldown(case.end_tick * 2)
                            end)
                        elseif offset == 15 then
                            actor(case.slot, function(p, room)
                                local pitCount = 0
                                for gridIndex = 0, room:GetGridSize() - 1 do
                                    local grid = room:GetGridEntity(gridIndex)
                                    local position = room:GetGridPosition(gridIndex)
                                    local valid = grid
                                        and grid:GetType() == GridEntityType.GRID_PIT
                                        and room:GetGridCollision(gridIndex)
                                            == GridCollisionClass.COLLISION_PIT
                                    pitCount = pitCount + (valid and 1 or 0)
                                    for _, dx in ipairs({ -80, -40, 40, 80 }) do
                                        valid = valid
                                            and room:IsPositionInRoom(position + Vector(dx, 0), 30)
                                            and room:GetGridCollisionAtPos(
                                                    position + Vector(dx, 0)
                                                )
                                                == GridCollisionClass.COLLISION_NONE
                                    end
                                    if valid then
                                        obstacleIndex, pitRoom = gridIndex, pitRooms[index + 1]
                                        for _, entity in ipairs(Isaac.GetRoomEntities()) do
                                            if entity:IsEnemy() or entity:ToPickup() then
                                                entity:Remove()
                                            end
                                        end
                                        room:SetClear(true)
                                        p.Position, p.Velocity =
                                            position - Vector(80, 0), Vector.Zero
                                        report("native_floor_pit_found", {
                                            tick = tick,
                                            room = pitRoom,
                                            index = gridIndex,
                                            x = position.X,
                                            y = position.Y,
                                            collision = room:GetGridCollision(gridIndex),
                                            stage = Game():GetLevel():GetStage(),
                                        })
                                        break
                                    end
                                end
                                report("native_floor_pit_search", {
                                    tick = tick,
                                    room = pitRooms[index + 1],
                                    pits = pitCount,
                                    found = pitRoom ~= nil,
                                })
                            end)
                        end
                    end
                end
            end
            if rules.flesh_prices_trial and tick == 450 then
                if not case.split then
                    actor(1 - case.slot, function(p, room)
                        p.Position, p.Velocity =
                            room:GetBottomRightPos() - Vector(40, 40), Vector.Zero
                    end)
                end
                actor(case.slot, function(p, room)
                    p.Position, p.Velocity = room:GetCenterPos() - Vector(0, 60), Vector.Zero
                end)
            end
            if rules.deal_item_trial then
                local dealTick = tick - (rules.deal_delay or 0)
                if dealTick == 570 then
                    actor(case.slot, function()
                        dealBoss = _IsaacLan.rooms_positions()[tostring(case.slot)].index
                        local devil, angel = false, false
                        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                            local door = Game():GetRoom():GetDoor(slot)
                            if door and door.TargetRoomType == RoomType.ROOM_DEVIL then
                                devil = true
                            end
                            if door and door.TargetRoomType == RoomType.ROOM_ANGEL then
                                angel = true
                            end
                            if
                                door
                                and door.TargetRoomType
                                    == RoomType[rules.deal_room or "ROOM_DEVIL"]
                            then
                                devilRoom = door.TargetRoomIndex
                            end
                        end
                        report("native_deal_doors", {
                            tick = tick,
                            devil = devil,
                            angel = angel,
                            stage = Game():GetLevel():GetStage(),
                            clear = Game():GetRoom():IsClear(),
                            chance = Game():GetRoom():GetDevilRoomChance(),
                        })
                    end)
                elseif dealTick >= 600 and dealTick <= 624 then
                    assert(devilRoom, "Native deal door prerequisite missing")
                    actor(case.slot, function(p, room)
                        if _IsaacLan.rooms_positions()[tostring(case.slot)].index ~= dealBoss then
                            return
                        end
                        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                            local door = room:GetDoor(slot)
                            if
                                door
                                and door.TargetRoomType
                                    == RoomType[rules.deal_room or "ROOM_DEVIL"]
                            then
                                -- Touching the native door initializes the special
                                -- room descriptor before requesting its transition.
                                local direction = (door.Position - room:GetCenterPos()):Normalized()
                                p.Position = door.Position - direction * 4
                                p.Velocity = direction * 6
                                if dealTick == 600 then
                                    report("native_deal_entry_requested", {
                                        tick = tick,
                                        destination = door.TargetRoomIndex,
                                        direction = door.Direction,
                                        open = door:IsOpen(),
                                    })
                                end
                                return
                            end
                        end
                        error("Native devil entrance disappeared before use")
                    end)
                elseif dealTick == 630 and not case.split then
                    local location = _IsaacLan.rooms_positions()[tostring(case.slot)]
                    if location.index ~= dealBoss then
                        assert(
                            _IsaacLan.rooms_move(
                                1 - case.slot,
                                location.index,
                                location.dimension,
                                -1
                            )
                        )
                    end
                elseif
                    dealTick == 690
                    and rules.deal_item_trial ~= "sanguine"
                    and not rules.stay_in_deal
                then
                    assert(_IsaacLan.rooms_move(case.slot, dealBoss, 0, -1))
                    if not case.split then
                        assert(_IsaacLan.rooms_move(1 - case.slot, dealBoss, 0, -1))
                    end
                elseif dealTick == 750 and rules.deal_item_trial == "redemption" then
                    moveFloor()
                end
            end
            if tick == 180 then
                generation(case, "after", tick)
            end
            if rules.entry_floor and tick == 90 then
                moveFloor()
            end
            if rules.entry_floor and tick == 420 then
                collectCombatRooms(case)
            end
            local entryStart = rules.entry_floor and 450 or 90
            if
                rules.entry_trial
                and tick >= entryStart
                and (tick - entryStart) % 120 == 0
                and (tick - entryStart) / 120 < rules.entry_trial
            then
                local index = combatRooms[(tick - entryStart) / 120 % #combatRooms + 1]
                assert(_IsaacLan.rooms_move(case.slot, index, 0, -1))
                if not case.split then
                    assert(_IsaacLan.rooms_move(1 - case.slot, index, 0, -1))
                end
                report("native_combat_room_visit", { tick = tick, index = index })
            end
            if
                rules.clear_entries
                and tick >= entryStart + 60
                and (tick - entryStart - 60) % 120 == 0
                and (tick - entryStart - 60) / 120 < (rules.clear_count or rules.entry_trial)
            then
                actor(case.slot, function(p)
                    local killed = 0
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsActiveEnemy(false) and e:IsVulnerableEnemy() then
                            killed = killed + 1
                            e:TakeDamage(10000, 0, EntityRef(p), 0)
                        end
                    end
                    report("native_entry_clear", { tick = tick, killed = killed })
                end)
            end
            if
                rules.confirm_entry_clear
                and tick >= entryStart
                and math.floor((tick - entryStart) / 120) < rules.clear_count
            then
                local offset = (tick - entryStart) % 120
                if offset >= 66 and offset <= 105 and offset % 6 == 0 then
                    actor(case.slot, function(p)
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e:IsActiveEnemy(false)
                                and e:IsVulnerableEnemy()
                                and not e:IsDead()
                            then
                                e:TakeDamage(10000, 0, EntityRef(p), 0)
                            end
                        end
                    end)
                elseif offset == 110 then
                    actor(case.slot, function(_, room)
                        report("native_entry_clear_confirmed", {
                            tick = tick,
                            clear = room:IsClear(),
                            alive = room:GetAliveEnemiesCount(),
                        })
                    end)
                end
            end
            if
                rules.reset_entry_combat
                and tick >= entryStart + 114
                and (tick - entryStart - 114) % 120 == 0
                and (tick - entryStart - 114) / 120 < rules.entry_trial - 1
            then
                actor(case.slot, function(p)
                    p:UseActiveItem(
                        CollectibleType.COLLECTIBLE_D7,
                        UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER,
                        -1
                    )
                end)
            end
            if rules.generation_trial and case.id == CollectibleType.COLLECTIBLE_OPTIONS then
                if tick == 210 then
                    actor(case.slot, function(p)
                        p:AddHearts(1 - p:GetHearts())
                        p:AddCoins(-p:GetNumCoins())
                        p:AddKeys(-p:GetNumKeys())
                        p:AddBombs(-p:GetNumBombs())
                        local selected = assert(awardChoices[1], "Native option awards missing")
                        awardGroup = selected.OptionsPickupIndex
                        selected.Wait = 0
                        p.Position, p.Velocity = selected.Position, Vector.Zero
                        report("native_award_choice", {
                            tick = tick,
                            selected = selected.InitSeed,
                            group = selected.OptionsPickupIndex,
                        })
                    end)
                elseif tick == 270 then
                    local remaining = 0
                    for _, pickup in ipairs(awardChoices) do
                        if
                            pickup:Exists()
                            and not pickup:IsDead()
                            and pickup.OptionsPickupIndex == awardGroup
                        then
                            remaining = remaining + 1
                        end
                    end
                    report("native_award_choice_result", { tick = tick, remaining = remaining })
                end
            end
            if rules.moving_box and tick == 180 then
                moveRoom()
            end
            if rules.fairy_trial then
                if tick == 75 then
                    fairyOrigin = _IsaacLan.rooms_positions()[tostring(case.slot)].index
                    actor(case.slot, function(_, room)
                        -- Native hints use the room's selected tinted-rock
                        -- index; an arbitrary scripted rock is not enough.
                        fairyRockIndex = room:GetTintedRockIdx()
                        assert(fairyRockIndex >= 0 and not room:GetGridEntity(fairyRockIndex))
                        assert(
                            room:SpawnGridEntity(
                                fairyRockIndex,
                                GridEntityType.GRID_ROCKT,
                                0,
                                187,
                                0
                            )
                        )
                        room:GetGridEntity(fairyRockIndex):Update()
                        room:Update()
                        fairyPosition = room:GetGridPosition(fairyRockIndex)
                    end)
                elseif tick == 150 then
                    local rooms, destination = Game():GetLevel():GetRooms(), nil
                    for i = 0, rooms.Size - 1 do
                        local d = rooms:Get(i)
                        if
                            d.Data
                            and d.Data.Type == RoomType.ROOM_DEFAULT
                            and d.SafeGridIndex ~= fairyOrigin
                        then
                            destination = d.SafeGridIndex
                            break
                        end
                    end
                    assert(destination, "Fairy trial needs another native room")
                    for slot = 0, 1 do
                        actor(slot, function(p)
                            p:SetMinDamageCooldown(case.end_tick * 2)
                        end)
                    end
                    -- Retain the owned familiar across the real room visit.
                    -- The generic empty-room helper removes all entities.
                    assert(_IsaacLan.rooms_move(case.slot, destination, 0, -1))
                    if not case.split then
                        assert(_IsaacLan.rooms_move(1 - case.slot, destination, 0, -1))
                    end
                elseif tick == 210 then
                    assert(_IsaacLan.rooms_move(case.slot, fairyOrigin, 0, -1))
                    if not case.split then
                        assert(_IsaacLan.rooms_move(1 - case.slot, fairyOrigin, 0, -1))
                    end
                elseif tick == 240 then
                    actor(case.slot, function(p, room)
                        local position, distance
                        for _, offset in ipairs({
                            Vector(160, 0),
                            Vector(-160, 0),
                            Vector(0, 160),
                            Vector(0, -160),
                        }) do
                            local candidate = room:GetClampedPosition(fairyPosition + offset, 25)
                            if not distance or candidate:Distance(fairyPosition) > distance then
                                position, distance = candidate, candidate:Distance(fairyPosition)
                            end
                        end
                        p.Position, p.Velocity = position, Vector.Zero
                        p:SetMinDamageCooldown(case.end_tick * 2)
                        local rock = assert(room:GetGridEntity(fairyRockIndex))
                        report("fairy_native_tinted_rock", {
                            tick = tick,
                            room = fairyOrigin,
                            index = fairyRockIndex,
                            type = rock:GetType(),
                            owner_distance = distance,
                            source = "fixture_at_native_hint_index",
                        })
                    end)
                end
            end
            if rules.portal_pair_trial and tick == 180 then
                moveRoom()
            end
            if rules.secret_sound_trial and tick == 90 then
                moveFloor()
                return
            end
            local secretTick = tick - (rules.secret_sound_delay or 0)
            if rules.secret_adjacent and secretTick == 150 then
                local level = Game():GetLevel()
                local rooms = level:GetRooms()
                secretOrigin = _IsaacLan.rooms_positions()[tostring(case.slot)].index
                if rules.secret_sound_trial then
                    secretIndex, secretOrigin = nil, nil
                    for i = 0, rooms.Size - 1 do
                        local d = rooms:Get(i)
                        if d.Data and d.Data.Type == RoomType.ROOM_SECRET then
                            for _, delta in ipairs({ -1, 1, -13, 13 }) do
                                local index = d.SafeGridIndex + delta
                                if
                                    index >= 0
                                    and index < 169
                                    and (
                                        math.abs(delta) == 13
                                        or math.floor(index / 13)
                                            == math.floor(d.SafeGridIndex / 13)
                                    )
                                then
                                    local adjacent = level:GetRoomByIdx(index)
                                    if
                                        adjacent.Data
                                        and adjacent.Data.Type == RoomType.ROOM_DEFAULT
                                        and adjacent.VisitedCount == 0
                                    then
                                        secretOrigin, secretIndex = index, d.SafeGridIndex
                                        break
                                    end
                                end
                            end
                        end
                        if secretIndex then
                            break
                        end
                    end
                else
                    for i = 0, rooms.Size - 1 do
                        local d = rooms:Get(i)
                        local delta = d.SafeGridIndex - secretOrigin
                        if
                            d.Data
                            and d.Data.Type == RoomType.ROOM_SECRET
                            and (math.abs(delta) == 1 or math.abs(delta) == 13)
                        then
                            secretIndex = d.SafeGridIndex
                            break
                        end
                    end
                end
                assert(secretIndex and secretOrigin, "Adjacent secret prerequisite missing")
                report("secret_neighbor_trial", {
                    tick = tick,
                    room = secretOrigin,
                    secret = secretIndex,
                    visits = level:GetRoomByIdx(secretOrigin).VisitedCount,
                })
                if not rules.secret_sound_trial then
                    moveRoom()
                end
            elseif rules.secret_adjacent and secretTick == 210 then
                assert(_IsaacLan.rooms_move(case.slot, secretOrigin, 0, -1))
                if rules.secret_sound_trial and not case.split then
                    assert(_IsaacLan.rooms_move(1 - case.slot, secretOrigin, 0, -1))
                end
            end
            actor(case.slot, function(p, room)
                if rules.secret_sound_trial then
                    if tick == 60 then
                        SFXManager():Play(SoundEffect.SOUND_DOG_HOWELL, 0.01, 0, false, 1)
                    elseif tick == 75 then
                        report("secret_sound_control", {
                            tick = tick,
                            playing = SFXManager():IsPlaying(SoundEffect.SOUND_DOG_HOWELL),
                        })
                    elseif tick == 120 then
                        SFXManager():Stop(SoundEffect.SOUND_DOG_HOWELL)
                    end
                end
                if rules.deal_item_trial == "duality" and tick == 750 + (rules.deal_delay or 0) then
                    local angel = false
                    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                        local door = room:GetDoor(slot)
                        angel = angel or door ~= nil and door.TargetRoomType == RoomType.ROOM_ANGEL
                    end
                    report("duality_choice_result", { tick = tick, angel = angel })
                end
                if rules.deal_item_trial == "sanguine" then
                    local dealTick = tick - (rules.deal_delay or 0)
                    if dealTick >= 630 and dealTick <= 1290 and (dealTick - 630) % 60 == 0 then
                        local spikes
                        for i = 0, room:GetGridSize() - 1 do
                            local grid = room:GetGridEntity(i)
                            if grid and grid:GetType() == GridEntityType.GRID_SPIKES then
                                spikes = grid
                                break
                            end
                        end
                        assert(spikes, "Native Sanguine Bond spikes missing")
                        p:AddMaxHearts(6 - p:GetMaxHearts(), false)
                        p:AddHearts(6 - p:GetHearts())
                        p:ResetDamageCooldown()
                        p.Position, p.Velocity = spikes.Position, Vector.Zero
                        sanguineHit = {
                            tick = tick,
                            before = p:GetHearts() + p:GetSoulHearts(),
                            room_type = room:GetType(),
                        }
                    elseif sanguineHit and tick == sanguineHit.tick + 4 then
                        sanguineHit.after = p:GetHearts() + p:GetSoulHearts()
                        report("sanguine_native_spike_hit", sanguineHit)
                        sanguineHit = nil
                        p.Position = p.Position + Vector(70, 0)
                    end
                end
                if rules.modem_projectiles_trial then
                    if tick == 75 then
                        p:RemoveCollectible(case.id)
                    end
                    if tick == 360 then
                        p:AddCollectible(case.id, 0, false)
                    end
                    if tick == 90 or tick == 390 then
                        p.Position, p.Velocity =
                            room:GetCenterPos() + Vector(-150, 100), Vector.Zero
                        modemProjectiles = {}
                        for i = 1, 32 do
                            local projectile = Isaac.Spawn(
                                EntityType.ENTITY_PROJECTILE,
                                0,
                                0,
                                room:GetCenterPos()
                                    + Vector(i % 8 * 10, math.floor(i / 8) * 10 - 50),
                                Vector.Zero,
                                nil
                            ):ToProjectile()
                            projectile.Height, projectile.FallingAccel, projectile.FallingSpeed =
                                -30, -0.1, 0
                            modemProjectiles[#modemProjectiles + 1] = projectile
                        end
                    elseif tick == 330 or tick == 630 then
                        local removed = 0
                        for _, projectile in ipairs(modemProjectiles) do
                            removed = removed
                                + ((not projectile:Exists() or projectile:IsDead()) and 1 or 0)
                            if projectile:Exists() then
                                projectile:Remove()
                            end
                        end
                        report("modem_projectile_result", {
                            tick = tick,
                            control = tick == 330,
                            removed = removed,
                            total = #modemProjectiles,
                        })
                        modemProjectiles = {}
                    end
                end
                if rules.camo_uncloak and tick == 170 then
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsActiveEnemy(false) and e:IsVulnerableEnemy() then
                            p.Position, p.Velocity = e.Position + Vector(0, 35), Vector.Zero
                            report("camo_nearby_target", {
                                tick = tick,
                                seed = e.InitSeed,
                                distance = p.Position:Distance(e.Position),
                            })
                            break
                        end
                    end
                end
                if rules.deaths_list_trial and tick == 120 then
                    report("deaths_list_native_targets", { count = room:GetAliveEnemiesCount() })
                end
                if rules.deaths_list_trial and tick >= 150 and tick <= 570 and tick % 30 == 0 then
                    local mark
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if
                            e.Type == EntityType.ENTITY_EFFECT
                            and e.Variant == EffectVariant.DEATH_SKULL
                        then
                            mark = e
                            break
                        end
                    end
                    if mark then
                        local target, distance
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e:IsActiveEnemy(false)
                                and e:IsVulnerableEnemy()
                                and not e:IsDead()
                            then
                                local d = e.Position:DistanceSquared(mark.Position)
                                if not distance or d < distance then
                                    target, distance = e, d
                                end
                            end
                        end
                        if target then
                            report("marked_enemy_killed", {
                                tick = tick,
                                seed = target.InitSeed,
                                mark_distance = math.sqrt(distance),
                            })
                            target:TakeDamage(10000, 0, EntityRef(p), 0)
                        end
                    end
                end
                if rules.betrayal_trial then
                    if tick == 75 then
                        p:RemoveCollectible(case.id)
                    end
                    if tick == 180 then
                        p:AddCollectible(case.id, 0, false)
                    end
                    if tick == 90 or tick == 210 then
                        local center = room:GetCenterPos()
                        local a = Isaac.Spawn(
                            EntityType.ENTITY_GAPER,
                            0,
                            0,
                            center - Vector(80, 0),
                            Vector.Zero,
                            nil
                        ):ToNPC()
                        local b =
                            Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, center, Vector.Zero, nil)
                                :ToNPC()
                        a:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                        b:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                        a.HitPoints, b.HitPoints = 500, 500
                        betrayalActors, betrayalBefore = { a, b }, b.HitPoints
                        a:FireProjectiles(
                            b.Position - Vector(20, 0),
                            Vector(6, 0),
                            0,
                            ProjectileParams()
                        )
                    elseif tick == 150 or tick == 270 then
                        report("betrayal_projectile_result", {
                            tick = tick,
                            control = tick == 150,
                            before = betrayalBefore,
                            after = betrayalActors[2].HitPoints,
                        })
                        for _, npc in ipairs(betrayalActors) do
                            if npc:Exists() then
                                npc:Remove()
                            end
                        end
                        betrayalActors = nil
                    end
                end
                if rules.puppy_feed_trial then
                    p:SetMinDamageCooldown(120)
                    local puppy
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if
                            e.Type == EntityType.ENTITY_BLOOD_PUPPY
                            or e.Type == EntityType.ENTITY_FAMILIAR
                                and e.Variant == FamiliarVariant.BLOOD_PUPPY
                        then
                            puppy = e
                            break
                        end
                    end
                    if tick >= 120 and tick <= 1440 and (tick - 120) % 30 == 0 then
                        assert(puppy, "Native blood puppy missing")
                        local food = Isaac.Spawn(
                            EntityType.ENTITY_GAPER,
                            0,
                            0,
                            puppy.Position,
                            Vector.Zero,
                            nil
                        ):ToNPC()
                        food.HitPoints, food.MaxHitPoints = 1, 1
                        food:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                        puppyVictims[#puppyVictims + 1] = food
                    end
                    if tick % 30 == 0 then
                        local killed, hearts = 0, 0
                        for _, npc in ipairs(puppyVictims) do
                            killed = killed + ((not npc:Exists() or npc:IsDead()) and 1 or 0)
                        end
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_PICKUP
                                and e.Variant == PickupVariant.PICKUP_HEART
                            then
                                hearts = hearts + 1
                            end
                        end
                        report("puppy_native_feeding", {
                            tick = tick,
                            killed = killed,
                            fed = #puppyVictims,
                            hearts = hearts,
                            variant = puppy and puppy.Variant or -1,
                            subtype = puppy and puppy.SubType or -1,
                            animation = puppy and puppy:GetSprite():GetAnimation() or "missing",
                        })
                    end
                end
                if rules.taurus_trial and p:HasInvincibility() then
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsActiveEnemy(false) and e:IsVulnerableEnemy() then
                            p.Position, p.Velocity = e.Position, Vector.Zero
                            break
                        end
                    end
                end
                if rules.astral_trial then
                    if astralHit and tick == astralHit.tick + 1 then
                        astralHit.after = p:GetHearts() + p:GetSoulHearts()
                        report("astral_shield_result", astralHit)
                        astralHit = nil
                    end
                    if tick == 240 or tick == 270 then
                        astralHit = { tick = tick, before = p:GetHearts() + p:GetSoulHearts() }
                        p:ResetDamageCooldown()
                        p:TakeDamage(1, 0, EntityRef(p), 0)
                    end
                end
                if rules.guppy_preview_trial then
                    if rules.guppy_preview_control and tick == 75 then
                        p:RemoveCollectible(case.id)
                    elseif tick == 90 then
                        if rules.guppy_preview_control then
                            assert(not p:HasCollectible(case.id), "Control still owns Guppy's Eye")
                        end
                        previewChest = Isaac.Spawn(
                            EntityType.ENTITY_PICKUP,
                            PickupVariant.PICKUP_CHEST,
                            1,
                            p.Position - Vector(0, 60),
                            Vector.Zero,
                            nil
                        ):ToPickup()
                        previewChest.Wait = 0
                        report("guppy_preview_chest", { tick = tick, seed = previewChest.InitSeed })
                    elseif tick == 300 then
                        local opened = previewChest
                            and previewChest:Exists()
                            and previewChest:TryOpenChest(p)
                        report("guppy_preview_opened", { tick = tick, opened = opened or false })
                    end
                end
                if rules.flip_pedestal_trial then
                    if tick == 610 or tick == 675 then
                        -- Leave the empty pedestal before Flip restores its
                        -- other side, so the new item is observed before pickup.
                        p.Position, p.Velocity = room:GetCenterPos() - Vector(0, 100), Vector.Zero
                    end
                    if tick == 480 or tick == 600 or tick == 720 then
                        local real, ghosts = {}, 0
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_PICKUP
                                and e.Variant == PickupVariant.PICKUP_COLLECTIBLE
                                and e.SubType > 0
                            then
                                real[#real + 1] = e.SubType
                            end
                            if
                                e.Type == EntityType.ENTITY_EFFECT
                                and e.Variant == EffectVariant.PICKUP_GHOST
                            then
                                ghosts = ghosts + 1
                            end
                        end
                        report(
                            "flip_native_pedestal",
                            { tick = tick, real = real, ghosts = ghosts }
                        )
                    end
                    if tick == 570 or tick == 750 then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            local pickup = e:ToPickup()
                            if
                                pickup
                                and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
                                and pickup.SubType > 0
                            then
                                pickup.Wait = 0
                                p.Position, p.Velocity = pickup.Position, Vector.Zero
                                flipItems[#flipItems + 1] = pickup.SubType
                                break
                            end
                        end
                    end
                    if tick == 630 and p:GetActiveItem() ~= case.id then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_PICKUP
                                and e.Variant == PickupVariant.PICKUP_COLLECTIBLE
                                and e.SubType == case.id
                            then
                                e:ToPickup().Wait = 0
                                p.Position, p.Velocity = e.Position, Vector.Zero
                                break
                            end
                        end
                    end
                    if tick == 675 then
                        p:SetActiveCharge(6)
                    end
                    if tick == 810 then
                        local acquired = {}
                        for _, id in ipairs(flipItems) do
                            acquired[#acquired + 1] = { id = id, held = p:HasCollectible(id) }
                        end
                        report("flip_pedestal_acquired", { tick = tick, items = acquired })
                    end
                end
                if rules.shovel_feet_trial or rules.completed_shovel_trial then
                    p:SetMinDamageCooldown(120)
                end
                if rules.d7_trial and (tick == 120 or tick == 210 or tick == 330) then
                    report("d7_combat_state", {
                        tick = tick,
                        alive = room:GetAliveEnemiesCount(),
                        room = _IsaacLan.rooms_positions()[tostring(case.slot)].index,
                    })
                end
                if rules.shackles_trial and tick == 630 then
                    local heart = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_HEART,
                        HeartSubType.HEART_SOUL,
                        p.Position,
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    heart.Wait = 0
                end
                if rules.strawman_trial and (tick == 90 or tick == 150 or tick == 210) then
                    local body
                    for i = 0, Game():GetNumPlayers() - 1 do
                        local q = Isaac.GetPlayer(i)
                        if
                            q:GetPlayerType() == PlayerType.PLAYER_KEEPER
                            and q.ControllerIndex == p.ControllerIndex
                        then
                            body = q
                        end
                    end
                    if tick == 90 then
                        report(
                            "strawman_body_created",
                            { tick = tick, found = body ~= nil, players = Game():GetNumPlayers() }
                        )
                    end
                    if body then
                        body:ResetDamageCooldown()
                        body:TakeDamage(1000, 0, EntityRef(p), 0)
                    end
                end
                if rules.strawman_trial and tick == 300 then
                    report("strawman_body_death", {
                        tick = tick,
                        owned = p:HasCollectible(case.id),
                        alive = not p:IsDead() and not p:IsCoopGhost(),
                        spiders = p:GetNumBlueSpiders(),
                    })
                end
                if rules.recall_trial then
                    local other = p:GetOtherTwin()
                    if tick == 90 then
                        local holder = other or p
                        local thrown = holder:ThrowHeldEntity(Vector(-12, 0))
                        if thrown then
                            -- The raw throw API leaves the entity inside its
                            -- holder's pickup radius until the next update.
                            thrown.Position = holder.Position - Vector(60, 0)
                        end
                        report("recall_native_throw", {
                            tick = tick,
                            found = thrown ~= nil,
                            type = thrown and thrown.Type,
                        })
                    end
                    if tick == 150 or tick == 300 then
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
                        report("recall_body_distance", {
                            tick = tick,
                            found = other ~= nil,
                            distance = other and p.Position:Distance(other.Position) or -1,
                            player_type = p:GetPlayerType(),
                            other_type = other and other:GetPlayerType(),
                            same_entity = other and GetPtrHash(p) == GetPtrHash(other),
                            bodies = bodies,
                        })
                    end
                end
                if rules.blanket_trial then
                    if blanketHit and tick == blanketHit.tick + 1 then
                        blanketHit.after = p:GetHearts() + p:GetSoulHearts()
                        report("blanket_damage_trial", blanketHit)
                        blanketHit = nil
                        p:SetMinDamageCooldown(300)
                    end
                    if tick == 480 or tick == 660 then
                        blanketHit = {
                            tick = tick,
                            before = p:GetHearts() + p:GetSoulHearts(),
                            room_type = room:GetType(),
                        }
                        p:ResetDamageCooldown()
                        p:TakeDamage(1, 0, EntityRef(p), 0)
                    end
                end
                if rules.mercurius_trial and tick == 330 then
                    local open, total = 0, 0
                    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                        local door = room:GetDoor(slot)
                        if door and door.TargetRoomType == RoomType.ROOM_DEFAULT then
                            total = total + 1
                            open = open + (door:IsOpen() and 1 or 0)
                        end
                    end
                    report("mercurius_doors", {
                        tick = tick,
                        enemies = room:GetAliveEnemiesCount(),
                        open = open,
                        total = total,
                    })
                end
                if rules.portal_pair_trial and tick == 90 then
                    report("native_portal_origin", {
                        tick = tick,
                        room = _IsaacLan.rooms_positions()[tostring(case.slot)].index,
                    })
                end
                if
                    rules.portal_pair_trial and tick == 300
                    or rules.portal_feed_trial and tick == 690
                then
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if
                            e.Type == EntityType.ENTITY_EFFECT
                            and (
                                e.Variant == EffectVariant.WOMB_TELEPORT
                                or e.Variant == EffectVariant.PORTAL_TELEPORT
                                    and e.SubType >= 900
                            )
                        then
                            p.Position, p.Velocity = e.Position, Vector.Zero
                            report("native_portal_entry", {
                                tick = tick,
                                room = _IsaacLan.rooms_positions()[tostring(case.slot)].index,
                                subtype = e.SubType,
                            })
                            break
                        end
                    end
                end
                if
                    rules.portal_pair_trial and tick == 420
                    or rules.portal_feed_trial and tick == 780
                then
                    report("native_portal_destination", {
                        tick = tick,
                        room = _IsaacLan.rooms_positions()[tostring(case.slot)].index,
                    })
                end
                if
                    rules.portal_feed_trial
                    and tick >= 90
                    and tick <= 450
                    and (tick - 90) % 120 == 0
                then
                    for i = 1, 4 do
                        local food = Isaac.Spawn(
                            EntityType.ENTITY_PICKUP,
                            PickupVariant.PICKUP_COIN,
                            CoinSubType.COIN_PENNY,
                            p.Position - Vector(0, 25 + i * 20),
                            Vector.Zero,
                            nil
                        ):ToPickup()
                        food.Wait = 0
                    end
                end
                if rules.coin_chest_trial then
                    if tick == 90 then
                        coinChest = Isaac.Spawn(
                            EntityType.ENTITY_PICKUP,
                            PickupVariant.PICKUP_LOCKEDCHEST,
                            1,
                            p.Position + Vector(0, -60),
                            Vector.Zero,
                            nil
                        ):ToPickup()
                        coinChest.Wait = 0
                    elseif tick == 150 then
                        coinChestBefore = p:GetNumCoins()
                        p.Position, p.Velocity = coinChest.Position, Vector.Zero
                    elseif tick == 180 then
                        local sprite = coinChest:GetSprite()
                        report("coin_chest_result", {
                            tick = tick,
                            opened = coinChest.SubType == 0
                                or sprite:IsPlaying("Open")
                                or sprite:IsPlaying("Opened")
                                or sprite:IsFinished("Open"),
                            animation = sprite:GetAnimation(),
                            subtype = coinChest.SubType,
                            before_coins = coinChestBefore,
                            coins = p:GetNumCoins(),
                            keys = p:GetNumKeys(),
                        })
                        p.Position = p.Position + Vector(80, 0)
                    end
                end
                if rules.paid_stats_trial and tick == 180 then
                    local pickup = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        CollectibleType.COLLECTIBLE_POOP,
                        p.Position,
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    pickup.Price, pickup.AutoUpdatePrice, pickup.ShopItemId, pickup.Wait =
                        15, false, 1, 0
                    report("shop_stat_purchase", {
                        tick = tick,
                        coins = p:GetNumCoins(),
                        speed = p.MoveSpeed,
                        range = p.TearRange,
                        damage = p.Damage,
                    })
                end
                local collision = rules.world_collision_trial
                local collisionTick = tick - (rules.collision_delay or 0)
                if rules.native_pit_trial and not pitRoom then
                    collision = nil
                end
                if collision == "spike_and_creep" then
                    collision = tick < 450 and "spike_contact" or "creep_contact"
                    collisionTick = tick % 450
                end
                if collision then
                    if collisionTick == 60 then
                        if case.kind == "trinket" then
                            p:TryRemoveTrinket(case.id)
                        else
                            p:RemoveCollectible(case.id)
                        end
                    elseif collisionTick == 240 then
                        if case.kind == "trinket" then
                            p:AddTrinket(case.id, false)
                        else
                            p:AddCollectible(case.id, 0, false)
                        end
                    end
                    if collisionTick == 75 or collisionTick == 255 then
                        p:AddMaxHearts(24 - p:GetMaxHearts(), false)
                        p:AddSoulHearts(-p:GetSoulHearts())
                        p:AddHearts(24 - p:GetHearts())
                        if collision == "pit_crossing" or collision == "spike_contact" then
                            -- Flush earlier room cleanup before reusing its grid cells.
                            room:Update()
                            if not obstacleIndex then
                                obstacleIndex = room:GetGridIndex(room:GetCenterPos())
                                assert(
                                    room:SpawnGridEntity(
                                        obstacleIndex,
                                        collision == "pit_crossing" and GridEntityType.GRID_PIT
                                            or GridEntityType.GRID_SPIKES,
                                        0,
                                        1,
                                        0
                                    ),
                                    "Native collision obstacle failed to spawn"
                                )
                                room:GetGridEntity(obstacleIndex):Update()
                                room:Update()
                            end
                            p.Position = room:GetGridPosition(obstacleIndex) - Vector(80, 0)
                        end
                        p.Velocity = Vector.Zero
                    end
                    if collisionTick == 90 or collisionTick == 270 then
                        p:ResetDamageCooldown()
                        contactTrial = {
                            tick = tick,
                            mode = collision,
                            control = collisionTick == 90,
                            before_health = p:GetHearts() + p:GetSoulHearts(),
                            start_x = p.Position.X,
                            start_room = Game():GetLevel():GetCurrentRoomIndex(),
                            start_grid_collision = obstacleIndex
                                and room:GetGridCollision(obstacleIndex),
                        }
                        if obstacleIndex then
                            local grid = room:GetGridEntity(obstacleIndex)
                            report("world_collision_obstacle", {
                                tick = tick,
                                owned = p:GetCollectibleNum(case.id),
                                x = p.Position.X,
                                y = p.Position.Y,
                                grid_type = grid and grid:GetType(),
                                grid_collision = grid and grid.CollisionClass,
                            })
                        end
                        if collision == "fly_contact" or collision == "spider_contact" then
                            contactEntity = Isaac.Spawn(
                                collision == "fly_contact" and EntityType.ENTITY_ATTACKFLY
                                    or EntityType.ENTITY_SPIDER,
                                0,
                                0,
                                p.Position,
                                Vector.Zero,
                                nil
                            )
                        elseif collision == "creep_contact" then
                            contactSpawner = Isaac.Spawn(
                                EntityType.ENTITY_GLOBIN,
                                0,
                                0,
                                p.Position + Vector(180, 0),
                                Vector.Zero,
                                nil
                            )
                            contactSpawner:GetData().auditTriggerTarget = true
                            contactEntity = Isaac.Spawn(
                                EntityType.ENTITY_EFFECT,
                                EffectVariant.CREEP_RED,
                                0,
                                p.Position,
                                Vector.Zero,
                                contactSpawner
                            )
                            contactEntity.CollisionDamage = 1
                            contactEntity:ToEffect():SetDamageSource(EntityType.ENTITY_GLOBIN)
                            contactEntity:Update()
                            contactEntity:ToEffect():SetTimeout(120)
                        elseif collision == "spike_contact" then
                            p.Position = room:GetGridPosition(obstacleIndex)
                        elseif collision == "unused_falling_projectile" then
                            contactEntity = Isaac.Spawn(
                                EntityType.ENTITY_PROJECTILE,
                                0,
                                0,
                                p.Position,
                                Vector.Zero,
                                nil
                            ):ToProjectile()
                            contactEntity.Height, contactEntity.FallingSpeed, contactEntity.FallingAccel =
                                -40, 2, 0.5
                        end
                    end
                    if
                        contactEntity
                        and contactEntity:Exists()
                        and not contactEntity:IsDead()
                        and collision ~= "falling_projectile"
                    then
                        contactEntity.Position, contactEntity.Velocity = p.Position, Vector.Zero
                    end
                    if
                        collision == "explosion" and (collisionTick == 90 or collisionTick == 270)
                    then
                        p:ResetDamageCooldown()
                        local bomb = p:FireBomb(p.Position, Vector.Zero)
                        bomb:SetExplosionCountdown(1)
                        report("native_immunity_bomb", { tick = tick, seed = bomb.InitSeed })
                    end
                    if collisionTick == 150 or collisionTick == 390 then
                        contactTrial.health = p:GetHearts() + p:GetSoulHearts()
                        contactTrial.flying = p.CanFly
                        contactTrial.player_collision = p.GridCollisionClass
                        local obstacle = obstacleIndex and room:GetGridEntity(obstacleIndex)
                        contactTrial.grid_type = obstacle and obstacle:GetType()
                        contactTrial.grid_collision = obstacle and obstacle.CollisionClass
                        contactTrial.y = p.Position.Y
                        contactTrial.x = p.Position.X
                        contactTrial.end_room = Game():GetLevel():GetCurrentRoomIndex()
                        if collision == "creep_contact" then
                            contactTrial.creep_exists = contactEntity and contactEntity:Exists()
                            if contactTrial.creep_exists then
                                contactTrial.creep_size = contactEntity.Size
                                contactTrial.creep_scale = contactEntity:ToEffect().Scale
                                contactTrial.creep_timeout = contactEntity:ToEffect().Timeout
                                contactTrial.creep_source = contactEntity:ToEffect().DamageSource
                                contactTrial.creep_damage = contactEntity.CollisionDamage
                            end
                        end
                        contactTrial.obstacle_x = obstacleIndex
                                and room:GetGridPosition(obstacleIndex).X
                            or nil
                        report("world_collision_result", contactTrial)
                        if contactEntity and contactEntity:Exists() then
                            contactEntity:Remove()
                        end
                        if contactSpawner and contactSpawner:Exists() then
                            contactSpawner:Remove()
                        end
                        contactTrial, contactEntity, contactSpawner = nil, nil, nil
                        if obstacleIndex then
                            p.Position = room:GetGridPosition(obstacleIndex) - Vector(80, 0)
                        end
                    end
                end
                if rules.paschal_trial and tick == 750 then
                    p:ResetDamageCooldown()
                    p:TakeDamage(1, 0, EntityRef(p), 0)
                end
                if rules.shard_trial and tick == 780 then
                    p:AddHearts(24 - p:GetHearts())
                end
                if rules.purgatory_trial and tick >= 120 and tick % 30 == 0 then
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if
                            e.Type == EntityType.ENTITY_EFFECT
                            and e.Variant == EffectVariant.PURGATORY
                            and e.SubType == 0
                        then
                            p.Position, p.Velocity = e.Position, Vector.Zero
                            report("purgatory_crack_crossed", { tick = tick, seed = e.InitSeed })
                            break
                        end
                    end
                end
                if rules.placenta_trial and tick == 75 then
                    p:AddHearts(1 - p:GetHearts())
                end
                if
                    rules.crafting_trial
                    and tick >= 90
                    and tick <= 510
                    and (tick - 90) % 60 == 0
                then
                    local drop = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COIN,
                        CoinSubType.COIN_PENNY,
                        p.Position - Vector(0, 35),
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    drop.Wait = 0
                    report("crafting_material_placed", { tick = tick, seed = drop.InitSeed })
                end
                local requested = rules.fire_through_familiar
                    or rules.player_in_aura
                    or rules.kick_familiar
                if requested and tick >= 60 and tick <= 300 then
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        local f = e:ToFamiliar()
                        if
                            f
                            and f:Exists()
                            and f.Variant == FamiliarVariant[requested]
                            and f.Player
                            and f.Player.ControllerIndex == p.ControllerIndex
                        then
                            if rules.fire_through_familiar and tick % 60 == 0 then
                                local tear =
                                    p:FireTear(f.Position, Vector(0, -8), false, true, false)
                                report(
                                    "familiar_tear_trial",
                                    { tick = tick, seed = tear.InitSeed, variant = f.Variant }
                                )
                            elseif rules.player_in_aura then
                                p.Position, p.Velocity = f.Position, Vector.Zero
                            elseif rules.kick_familiar and tick == 60 then
                                p.Position, p.Velocity = f.Position + Vector(0, 35), Vector.Zero
                            end
                            break
                        end
                    end
                end
                local feed = rules.feed_familiar
                if
                    feed
                    and tick >= 90
                    and tick < 90 + feed.count * 60
                    and (tick - 90) % 60 == 0
                then
                    local familiar
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        local f = e:ToFamiliar()
                        if
                            f
                            and f.Variant == FamiliarVariant[feed.variant]
                            and f.Player
                            and f.Player.ControllerIndex == p.ControllerIndex
                        then
                            familiar = f
                            break
                        end
                    end
                    assert(familiar, "Feeding target familiar missing")
                    local foodPosition = familiar.Position
                    local away = room:GetClampedPosition(foodPosition + Vector(150, 0), 30)
                    if away:Distance(foodPosition) < 80 then
                        away = room:GetClampedPosition(foodPosition - Vector(150, 0), 30)
                    end
                    for i = 0, Game():GetNumPlayers() - 1 do
                        local localPlayer = Isaac.GetPlayer(i)
                        if localPlayer.Position:Distance(foodPosition) < 60 then
                            localPlayer.Position, localPlayer.Velocity = away, Vector.Zero
                        end
                    end
                    local food = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant[feed.pickup],
                        1,
                        foodPosition,
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    food.Wait = 0
                    food:GetData().auditFood = true
                    feeding[#feeding + 1] = {
                        entity = food,
                        tick = tick,
                        seed = food.InitSeed,
                        resource_before = feed.pickup == "PICKUP_COIN" and p:GetNumCoins()
                            or feed.pickup == "PICKUP_KEY" and p:GetNumKeys()
                            or 0,
                    }
                end
                local unresolved = {}
                for _, trial in ipairs(feeding) do
                    if tick >= trial.tick + 57 then
                        report("familiar_feed_result", {
                            tick = tick,
                            seed = trial.seed,
                            consumed = not trial.entity:Exists()
                                or trial.entity:IsDead()
                                or trial.entity:GetSprite():IsPlaying("Collect"),
                            resource_before = trial.resource_before,
                            resource_after = feed.pickup == "PICKUP_COIN" and p:GetNumCoins()
                                or feed.pickup == "PICKUP_KEY" and p:GetNumKeys()
                                or 0,
                        })
                        if trial.entity:Exists() then
                            trial.entity:Remove()
                        end
                    else
                        unresolved[#unresolved + 1] = trial
                    end
                end
                feeding = unresolved
                if rules.jar_hearts and tick >= 90 and tick <= 225 and (tick - 90) % 45 == 0 then
                    local heart = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_HEART,
                        HeartSubType.HEART_FULL,
                        p.Position,
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    heart.Wait = 0
                end
                if rules.echo_cards then
                    if tick == 90 then
                        p:AddCoins(1 - p:GetNumCoins())
                        p:AddBombs(1 - p:GetNumBombs())
                    elseif tick == 117 then
                        p:SetCard(0, Card.CARD_CLUBS_2)
                    elseif tick == 177 or tick == 237 then
                        p:SetCard(0, Card.CARD_DIAMONDS_2)
                    elseif tick == 150 or tick == 210 or tick == 270 then
                        report(
                            "echo_result",
                            { tick = tick, coins = p:GetNumCoins(), bombs = p:GetNumBombs() }
                        )
                    end
                end
                if rules.switch_actives and tick == 90 then
                    p:AddSoulHearts(-p:GetSoulHearts())
                    p:AddCollectible(
                        CollectibleType.COLLECTIBLE_D6,
                        6,
                        false,
                        ActiveSlot.SLOT_PRIMARY
                    )
                    p:AddCollectible(
                        CollectibleType.COLLECTIBLE_SATANIC_BIBLE,
                        6,
                        false,
                        ActiveSlot.SLOT_SECONDARY
                    )
                end
                if rules.jar_charges then
                    if tick >= 87 and tick <= 987 and (tick - 87) % 90 == 0 then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:ToPickup() then
                                e:Remove()
                            end
                        end
                        for i = 0, room:GetGridSize() - 1 do
                            local grid = room:GetGridEntity(i)
                            if grid and grid:GetType() == GridEntityType.GRID_POOP then
                                room:RemoveGridEntity(i, 0, false)
                            end
                        end
                        p:SetActiveCharge(1 + (tick - 87) / 90)
                    elseif tick >= 120 and tick <= 1020 and (tick - 120) % 90 == 0 then
                        local poops = 0
                        for i = 0, room:GetGridSize() - 1 do
                            local grid = room:GetGridEntity(i)
                            if grid and grid:GetType() == GridEntityType.GRID_POOP then
                                poops = poops + 1
                            end
                        end
                        report("jar_charge_result", {
                            tick = tick,
                            charge = 1 + (tick - 120) / 90,
                            pickups = pickups(),
                            poops = poops,
                        })
                    end
                end
                if rules.moving_box and tick == 60 then
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
                            room:GetCenterPos() + Vector(i * 30 - 90, -90),
                            Vector.Zero,
                            nil
                        )
                    end
                elseif rules.moving_box and tick == 327 then
                    p:SetActiveCharge(4)
                end
            end)
            if rules.moving_box then
                if tick == 87 then
                    boxSnapshot(case, tick, "before")
                elseif tick == 150 then
                    boxSnapshot(case, tick, "stored")
                elseif tick == 390 then
                    boxSnapshot(case, tick, "released")
                end
            end
        end,
        sample = function(case, tick)
            local rules = case.trigger_effects
            if
                not rules
                or not (
                    rules.feed_familiar
                    or rules.jar_hearts
                    or rules.switch_actives
                    or rules.crafting_trial
                    or rules.hold_poop_trial
                    or rules.zodiac_trial
                    or rules.secret_sound_trial
                    or rules.fairy_trial
                )
            then
                return
            end
            actor(case.slot, function(p)
                if rules.secret_sound_trial then
                    report(
                        "secret_sound_probe",
                        { tick = tick, howl = SFXManager():IsPlaying(SoundEffect.SOUND_DOG_HOWELL) }
                    )
                end
                if rules.fairy_trial and fairyPosition then
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        local f = e:ToFamiliar()
                        if
                            f
                            and f.Variant == FamiliarVariant.YO_LISTEN
                            and f.Player
                            and f.Player.ControllerIndex == p.ControllerIndex
                        then
                            report("fairy_target_probe", {
                                tick = tick,
                                distance = f.Position:Distance(fairyPosition),
                                owner_distance = p.Position:Distance(fairyPosition),
                                state = f.State,
                                animation = f:GetSprite():GetAnimation(),
                                target_distance = f.TargetPosition:Distance(fairyPosition),
                                rock_index = fairyRockIndex,
                            })
                        end
                    end
                end
                if rules.zodiac_trial then
                    local effects = {}
                    local id = p:GetZodiacEffect()
                    if id > 0 then
                        effects[tostring(id)] = 1
                    end
                    report("zodiac_effects", { tick = tick, effects = effects })
                end
                if rules.crafting_trial then
                    local bytes = assert(_IsaacLan.actor_crafting_bag(p:GetSprite()))
                    local contents, count = {}, 0
                    for i = 1, 8 do
                        contents[i] = bytes:byte(i)
                        count = count + (contents[i] ~= 0 and 1 or 0)
                    end
                    report("crafting_trial_probe", {
                        tick = tick,
                        materials = contents,
                        count = count,
                        collectibles = p:GetCollectibleCount(),
                    })
                end
                if rules.hold_poop_trial then
                    local queue = {}
                    for i = 0, 5 do
                        queue[#queue + 1] = p:GetPoopSpell(i)
                    end
                    report(
                        "hold_poop_probe",
                        { tick = tick, mana = p:GetPoopMana(), queue = queue }
                    )
                end
                local hearts, bumboLevel, bumboCoins = 0, 0, 0
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:Exists() then
                        if e:ToPickup() and e.Variant == PickupVariant.PICKUP_HEART then
                            hearts = hearts + 1
                        end
                        local f = e:ToFamiliar()
                        if f and f.Variant == FamiliarVariant.BUMBO then
                            bumboLevel, bumboCoins = f.SubType, f.Coins
                        end
                        if rules.feed_familiar and e:ToPickup() and not seen[e.InitSeed] then
                            seen[e.InitSeed] = true
                            if tick >= 90 and not e:GetData().auditFood then
                                report("fed_familiar_reward", {
                                    tick = tick,
                                    seed = e.InitSeed,
                                    variant = e.Variant,
                                    subtype = e.SubType,
                                })
                            end
                        end
                    end
                end
                report("interaction_probe", {
                    tick = tick,
                    jar_hearts = rules.jar_hearts and p:GetJarHearts() or 0,
                    heart_pickups = hearts,
                    bumbo_level = bumboLevel,
                    bumbo_coins = bumboCoins,
                    active = p:GetActiveItem(ActiveSlot.SLOT_PRIMARY),
                    secondary = p:GetActiveItem(ActiveSlot.SLOT_SECONDARY),
                    charge = p:GetActiveCharge(),
                    soul = p:GetSoulHearts(),
                })
            end)
        end,
    }
end
