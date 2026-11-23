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
local function finishAtLamb(tick)
    local game, level = Game(), Game():GetLevel()
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
        for slot = 0, 1 do
            local player = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
            player:AddCollectible(CollectibleType.COLLECTIBLE_NEGATIVE)
        end
        goal, goalTick = "sheol", tick
        level:SetStage(LevelStage.STAGE5, StageType.STAGETYPE_ORIGINAL)
        game:StartStageTransition(true, 0, Isaac.GetPlayer(0))
    elseif goal == "sheol" and tick > goalTick + 60 and level:GetStage() == LevelStage.STAGE5 then
        goalRoom = enterBoss(level, EntityType.ENTITY_SATAN)
        goal, goalTick = "satan", tick
    elseif
        goal == "dark room"
        and level:GetStage() == LevelStage.STAGE6
        and tick > goalTick + 90
    then
        assert(level:GetStageType() == StageType.STAGETYPE_ORIGINAL)
        goalRoom = enterBoss(level, EntityType.ENTITY_THE_LAMB)
        goal, goalTick, sawBoss = "lamb", tick, false
        report("DARK_ROOM")
    elseif (goal == "satan" or goal == "lamb") and level:GetCurrentRoomIndex() == goalRoom then
        local player = Isaac.GetPlayer(0)
        player:SetMinDamageCooldown(100)
        local satan = goal == "satan"
        local boss = satan and EntityType.ENTITY_SATAN or EntityType.ENTITY_THE_LAMB
        local reward = satan and PickupVariant.PICKUP_BIGCHEST or PickupVariant.PICKUP_TROPHY
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity.Type == boss then
                sawBoss = true
            end
            if entity:IsActiveEnemy(false) and tick > goalTick + 120 and tick % 15 == 0 then
                entity:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(player), 0)
            elseif
                entity.Type == EntityType.ENTITY_PICKUP
                and entity.Variant == reward
                and entity:ToPickup().Wait <= 0
                and game:GetRoom():IsClear()
            then
                assert(sawBoss and game:GetVictoryLap() == 0)
                player.Position, player.Velocity = entity.Position, Vector.Zero
                goal, goalTick = satan and "dark room" or "trophy", tick
                report(satan and "SATAN_CHEST" or "LAMB_TROPHY")
                break
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
