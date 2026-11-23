-- Render the same actors, enemies and pickup in the challenge and the following ordinary run.
local native, config = _IsaacLan, _IsaacLanTest
local frame, phases = _IsaacLanFrame, native.net_phases()
local renders, joined, chosen, started = 0, false, false, false
local ordinary, placed, observed, complete = false, false, false, false
local goal, goalRoom, goalTick
local waterSeen, sawBoss = false, false
local function report(text)
    Isaac.DebugString(
        "LAN_NETWORK SIDE chasing-shadows " .. text .. " ms=" .. native.api_info().nowMs
    )
end
local function scene()
    local center = Game():GetRoom():GetCenterPos()
    for slot = 0, 1 do
        local player = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
        player.Position = center + Vector(slot == 0 and -140 or 140, 65)
        player.Velocity = Vector.Zero
    end
    Isaac.Spawn(EntityType.ENTITY_HORF, 0, 0, center + Vector(-75, -45), Vector.Zero, nil)
    local boss =
        Isaac.Spawn(EntityType.ENTITY_MONSTRO, 0, 0, center + Vector(75, -45), Vector.Zero, nil)
    boss:AddEntityFlags(EntityFlag.FLAG_FREEZE)
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, 1, center, Vector.Zero, nil)
end
local function checkScene(label)
    local seeds = Game():GetSeeds()
    assert(seeds:HasSeedEffect(SeedEffect.SEED_INVISIBLE_ISAAC) == not ordinary)
    assert(seeds:HasSeedEffect(SeedEffect.SEED_INVISIBLE_ENEMIES) == not ordinary)
    local types = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        types[entity.Type] = true
    end
    assert(types[EntityType.ENTITY_HORF] and types[EntityType.ENTITY_MONSTRO])
    assert(types[EntityType.ENTITY_PICKUP] and Game():GetNumPlayers() == 2)
    report(label)
end
local function enterBoss(level, kind)
    local rooms = level:GetRooms()
    for index = 0, rooms.Size - 1 do
        local desc = rooms:Get(index)
        if desc.Data and desc.Data.Type == RoomType.ROOM_BOSS then
            for i = 0, desc.Data.SpawnCount - 1 do
                local spawn = desc.Data.Spawns:Get(i)
                for j = 0, spawn.EntryCount - 1 do
                    if spawn.Entries:Get(j).Type == kind then
                        for slot = 0, 1 do
                            assert(native.rooms_move(slot, desc.SafeGridIndex, 0, -1))
                        end
                        return desc.SafeGridIndex
                    end
                end
            end
        end
    end
    error("Missing boss room for " .. kind)
end
local battles = {
    mom = { boss = EntityType.ENTITY_MOM, departure = "womb" },
    heart = { boss = EntityType.ENTITY_MOMS_HEART, departure = "sheol" },
    satan = { boss = EntityType.ENTITY_SATAN, reward = PickupVariant.PICKUP_BIGCHEST },
    lamb = { boss = EntityType.ENTITY_THE_LAMB, reward = PickupVariant.PICKUP_TROPHY },
}
local function finishAtLamb(tick)
    local game, level = Game(), Game():GetLevel()
    assert(
        not goalTick or tick - goalTick < 1200 or goal == "trophy",
        "Stalled at " .. tostring(goal)
    )
    if not goal then
        goal, goalTick = "downpour", tick
        level:SetStage(LevelStage.STAGE1_2, StageType.STAGETYPE_REPENTANCE)
        game:StartStageTransition(true, 0, Isaac.GetPlayer(0))
    elseif
        goal == "downpour"
        and tick > goalTick + 60
        and level:GetStage() == LevelStage.STAGE1_2
    then
        assert(game:GetRoom():HasWater())
        scene()
        goal, goalTick = "water", tick
    elseif goal == "water" and waterSeen and tick > goalTick + 120 then
        goal, goalTick = "depths", tick
        level:SetStage(LevelStage.STAGE3_2, StageType.STAGETYPE_ORIGINAL)
        game:StartStageTransition(true, 0, Isaac.GetPlayer(0))
    elseif
        goal == "depths"
        and level:GetStage() == LevelStage.STAGE3_2
        and tick > goalTick + 60
    then
        goalRoom = enterBoss(level, battles.mom.boss)
        goal, goalTick = "mom", tick
    elseif goal == "womb" and level:GetStage() == LevelStage.STAGE4_1 and tick > goalTick + 90 then
        goal, goalTick = "womb two", tick
        level:SetStage(LevelStage.STAGE4_2, StageType.STAGETYPE_ORIGINAL)
        game:StartStageTransition(true, 0, Isaac.GetPlayer(0))
    elseif
        goal == "womb two"
        and level:GetStage() == LevelStage.STAGE4_2
        and tick > goalTick + 60
    then
        goalRoom = enterBoss(level, battles.heart.boss)
        goal, goalTick, sawBoss = "heart", tick, false
    elseif goal == "sheol" and tick > goalTick + 60 and level:GetStage() == LevelStage.STAGE5 then
        goalRoom = enterBoss(level, battles.satan.boss)
        goal, goalTick, sawBoss = "satan", tick, false
    elseif
        goal == "dark room"
        and level:GetStage() == LevelStage.STAGE6
        and tick > goalTick + 90
    then
        assert(level:GetStageType() == StageType.STAGETYPE_ORIGINAL)
        goalRoom = enterBoss(level, battles.lamb.boss)
        goal, goalTick, sawBoss = "lamb", tick, false
        report("DARK_ROOM")
    elseif battles[goal] and level:GetCurrentRoomIndex() == goalRoom then
        local player = Isaac.GetPlayer(0)
        if not game:GetRoom():IsClear() then
            player:SetMinDamageCooldown(100)
        end
        local battle = battles[goal]
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity.Type == battle.boss then
                sawBoss = true
            end
            if entity:IsActiveEnemy(false) and tick > goalTick + 120 and tick % 15 == 0 then
                entity:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(player), 0)
            elseif
                entity.Type == EntityType.ENTITY_PICKUP
                and entity.Variant == battle.reward
                and entity.FrameCount >= 90
                and entity:ToPickup().Wait <= 0
                and game:GetRoom():IsClear()
            then
                assert(sawBoss and game:GetVictoryLap() == 0)
                player.Position, player.Velocity = entity.Position, Vector.Zero
                if goal == "satan" then
                    assert(native.rooms_chest_ending() == 0, "Satan chest would end the run")
                    goal = "dark room"
                    report("SATAN_CHEST")
                else
                    goal = "trophy"
                    report("LAMB_TROPHY")
                end
                goalTick = tick
                break
            end
        end
        if battle.departure and sawBoss and game:GetRoom():IsClear() and tick > goalTick + 160 then
            local room = game:GetRoom()
            for index = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(index)
                if
                    grid
                    and grid:GetType() == GridEntityType.GRID_TRAPDOOR
                    and grid.VarData == 0
                then
                    if grid.State == 1 then
                        player.Position, player.Velocity = grid.Position, Vector.Zero
                        report(goal == "mom" and "MOM_EXIT" or "HEART_EXIT")
                        goal, goalTick = battle.departure, tick
                    else
                        -- A closed trapdoor opens once all nearby players have stepped away.
                        for slot = 0, 1 do
                            local actor =
                                Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
                            if actor.Position:Distance(grid.Position) < 80 then
                                local center = room:GetCenterPos()
                                local offset = grid.Position.X >= center.X and -150 or 150
                                actor.Position = room:FindFreePickupSpawnPosition(
                                    center + Vector(offset, slot * 40),
                                    0,
                                    true
                                )
                                actor.Velocity = Vector.Zero
                            end
                        end
                    end
                    break
                end
            end
        end
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    local status = frame()
    assert(status.phase ~= phases.failed, status.error)
    if not joined and renders >= (config.host and 260 or 320) then
        joined = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if status.phase == phases.lobby and not status.prepared and status.scene == 1 then
        if observed and not ordinary then
            assert(not config.host or goal == "trophy", "Challenge ended before the trophy")
            assert(waterSeen, "Missing flooded challenge scene")
            ordinary, observed, placed, started, chosen = true, false, false, false, false
        end
        local id = ordinary and 0 or 1007
        if config.host and status.challenge ~= id then
            _IsaacLanCommand("challenge", tostring(id))
        elseif status.challenge == id and not chosen then
            chosen = true
            _IsaacLanCommand("choose", "0:1")
        end
        if
            config.host
            and not started
            and status.challenge == id
            and status.players == 2
            and status.ready0 == 1
            and status.ready1 == 1
        then
            started = true
            _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
        end
    end
    local info, tick = native.api_info(), status.verified
    if info.ready == 1 and tick > 30 then
        assert(info.challenge == (ordinary and 0 or 1007))
        assert(native.rooms_with_player(config.host and 0 or 1, function()
            if config.host and not placed then
                scene()
                placed = true
            end
            if not observed and tick > 100 then
                checkScene(ordinary and "ORDINARY" or "CHALLENGE")
                observed = true
            end
            if not ordinary and not waterSeen and Game():GetRoom():HasWater() then
                for _, enemy in ipairs(Isaac.FindByType(EntityType.ENTITY_HORF)) do
                    if enemy.FrameCount > 35 then
                        checkScene("WATER")
                        waterSeen = true
                        break
                    end
                end
            end
        end))
        if observed and tick > 200 and not ordinary and config.host then
            finishAtLamb(tick)
        elseif ordinary and observed and tick > 180 and not complete then
            complete = true
            report("PASS challenge and ordinary scenes")
        end
    end
    return status
end
return {
    done = function()
        return complete
    end,
}
