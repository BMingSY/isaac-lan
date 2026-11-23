-- Render the same actors, enemies and pickup in the challenge and the following ordinary run.
local native, config = _IsaacLan, _IsaacLanTest
local frame, phases = _IsaacLanFrame, native.net_phases()
local renders, joined, chosen, started = 0, false, false, false
local ordinary, placed, observed, complete = false, false, false, false
local goal, goalRoom, goalTick
local waterSeen = false
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
local function finishAtMom(tick)
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
        goal, goalTick = "floor", tick
        level:SetStage(LevelStage.STAGE3_2, StageType.STAGETYPE_ORIGINAL)
        game:StartStageTransition(true, 0, Isaac.GetPlayer(0))
    elseif goal == "floor" and tick > goalTick + 60 and level:GetStage() == LevelStage.STAGE3_2 then
        for index = 0, level:GetRooms().Size - 1 do
            local desc = level:GetRooms():Get(index)
            if desc.Data.Type == RoomType.ROOM_BOSS then
                goalRoom = desc.SafeGridIndex
            end
        end
        assert(goalRoom)
        for slot = 0, 1 do
            assert(native.rooms_move(slot, goalRoom, 0, -1))
        end
        goal, goalTick = "boss", tick
    elseif goal == "boss" and tick > goalTick + 60 and level:GetCurrentRoomIndex() == goalRoom then
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity:IsActiveEnemy(false) then
                entity:Kill()
            elseif
                entity.Type == EntityType.ENTITY_PICKUP
                and entity.Variant == PickupVariant.PICKUP_TROPHY
                and entity:ToPickup().Wait <= 0
            then
                Isaac.GetPlayer(0).Position = entity.Position
                goal = "trophy"
                report("TROPHY")
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
            finishAtMom(tick)
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
