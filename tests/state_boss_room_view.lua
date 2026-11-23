-- Visit the generated Mega Satan arena and complete the native Boss Rush with
-- the guest. Sample the rendered local room between snapshots as well as on entry.
local native, config = _IsaacLan, _IsaacLanTest
local host, gate, frame = config.host, native.net_gate, _IsaacLanFrame
local phases = native.net_phases()
local mega, rush = GridRooms.ROOM_MEGA_SATAN_IDX, GridRooms.ROOM_BOSSRUSH_IDX
local joined, chosen, started, renders, tick = false, false, false, 0, -1
local step, since, observed = "start", 0, {}
local hitAt
local closedGap, openAfter, left, firstWave, lastWave, totalWaves =
    false, false, false, nil, nil, nil

local function mark(message)
    Isaac.DebugString("LAN_NETWORK BOSS_ROOM " .. message)
end
local function advance(name, t)
    step, since = name, t
    mark(name .. " tick=" .. t)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end, 1))
end
local function move(slot, index)
    assert(native.rooms_move(slot, index, 0, -1))
end
local function floor(stage, kind)
    actor(1, function(p)
        Game():GetLevel():SetStage(stage, kind)
        Game():StartStageTransition(true, RoomTransitionAnim.FADE, p)
    end)
end
local function exitDoor(room)
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door then
            return door
        end
    end
end
local function sample()
    local room, level = Game():GetRoom(), Game():GetLevel()
    local idx = level:GetCurrentRoomIndex()
    if level:GetStage() == LevelStage.STAGE6 and idx == mega then
        local body = Isaac.FindByType(EntityType.ENTITY_MEGA_SATAN, 0)[1]
        if body then
            local floor = assert(native.room_floor_sprite(Isaac.GetPlayer(0):GetSprite()))
            local animation = floor:GetAnimation()
            if animation == "Intro" and floor:GetFrame() > 0 then
                observed.summoning = true
            end
            assert(
                room:GetBackdropType() == BackdropType.MEGA_SATAN,
                "Chest backdrop behind Mega Satan"
            )
            if
                body.Visible
                and body.HitPoints > 0
                and body.HitPoints < body.MaxHitPoints
                and not observed.arena
            then
                assert(
                    observed.summoning and animation == "Idle2",
                    "Mega Satan summoning circle stayed dark"
                )
                observed.arena = true
                hitAt = tick
                mark(
                    "arena backdrop="
                        .. room:GetBackdropType()
                        .. " floor="
                        .. animation
                        .. " animation="
                        .. body:GetSprite():GetAnimation()
                )
            end
        end
    elseif idx == rush then
        local active, done = room:IsAmbushActive(), room:IsAmbushDone()
        local door = exitDoor(room)
        if lastWave and lastWave > 0 and not done then
            assert(
                active and door and not door:IsOpen(),
                "Boss Rush reopened before the final clear"
            )
        end
        if active then
            local wave, total = native.room_ambush_wave()
            if wave ~= lastWave then
                mark(
                    string.format(
                        "wave=%d/%d open=%s",
                        wave,
                        total,
                        tostring(door and door:IsOpen())
                    )
                )
                firstWave, lastWave, totalWaves = firstWave or wave, wave, total
            end
            if wave > 0 and door then
                assert(not door:IsOpen(), "Boss Rush door opened during a wave")
                if wave < total and room:GetAliveEnemiesCount() == 0 then
                    closedGap = true
                end
            end
        elseif done and door and door:IsOpen() then
            openAfter = true
        end
    elseif level:GetStage() == LevelStage.STAGE3_2 and openAfter then
        assert(not room:IsAmbushActive())
        left = true
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not joined and renders >= (host and 300 or 360) then
        joined = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= phases.failed, status.error)
    if status.phase == phases.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == phases.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
        and not started
    then
        started = true
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if status.prepared and native.api_info().ready == 1 and status.verified > 0 then
        tick = status.verified
        native.api_with_local_view(sample)
        if left and not observed.complete then
            assert(observed.arena and closedGap and lastWave == totalWaves and totalWaves > 2)
            assert(host and firstWave >= 2 or not host and firstWave <= 1, "Wrong wave on entry")
            observed.complete = true
            mark("PASS arena, active waves, intermission doors and cleared exit")
        end
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if not native.rooms_ready() then
            return
        end
        local level = Game():GetLevel()
        if step == "start" and t >= 30 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:SetMinDamageCooldown(100000)
                end)
            end
            floor(LevelStage.STAGE6, StageType.STAGETYPE_WOTL)
            advance("chest", t)
        elseif step == "chest" and level:GetStage() == LevelStage.STAGE6 and t - since > 100 then
            move(1, mega)
            advance("fight", t)
        elseif step == "fight" then
            if native.rooms_positions()["0"].index == mega then
                actor(0, function(p)
                    p.Position, p.Velocity = Vector(320, 350), Vector.Zero
                end)
            end
            actor(1, function(p)
                p.Position, p.Velocity = Vector(320, t - since < 90 and 440 or 350), Vector.Zero
                if not hitAt and t - since > 300 and t % 15 == 0 then
                    local body = Isaac.FindByType(EntityType.ENTITY_MEGA_SATAN, 0)[1]
                    if body and body.Visible and body:IsVulnerableEnemy() then
                        body:TakeDamage(2, 0, EntityRef(p), 0)
                    end
                end
            end)
            assert(t - since < 1400, "Mega Satan never became vulnerable")
            if hitAt and t - hitAt > 120 then
                floor(LevelStage.STAGE3_2, StageType.STAGETYPE_ORIGINAL)
                advance("depths", t)
            end
        elseif step == "depths" and level:GetStage() == LevelStage.STAGE3_2 and t - since > 110 then
            local rooms, bossIndex = level:GetRooms()
            for i = 0, rooms.Size - 1 do
                local descriptor = rooms:Get(i)
                if descriptor.Data.Type == RoomType.ROOM_BOSS then
                    bossIndex = descriptor.SafeGridIndex
                end
            end
            assert(bossIndex, "Depths II did not generate Mom's room")
            move(1, bossIndex)
            advance("mom", t)
        elseif step == "mom" and t - since > 60 then
            actor(1, function()
                local room = Game():GetRoom()
                for _, enemy in ipairs(Isaac.GetRoomEntities()) do
                    if enemy:IsActiveEnemy(false) then
                        enemy:Remove()
                    end
                end
                room:SetClear(true)
                room:TrySpawnBossRushDoor(true, true)
            end)
            move(1, rush)
            advance("pedestal", t)
        elseif step == "pedestal" and t - since > 40 then
            actor(1, function(p)
                local items =
                    Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)
                assert(#items > 0, "Generated Boss Rush has no pedestal")
                p.Position, p.Velocity = items[1].Position, Vector.Zero
            end)
            advance("waves", t)
        elseif step == "waves" then
            local active, done, wave
            actor(1, function(p)
                local room = Game():GetRoom()
                p:SetMinDamageCooldown(1000)
                active, done = room:IsAmbushActive(), room:IsAmbushDone()
                wave = active and native.room_ambush_wave() or 0
                if active then
                    p.Position = room:GetCenterPos()
                    if t % 48 == 0 then
                        for _, enemy in ipairs(Isaac.GetRoomEntities()) do
                            if enemy:IsActiveEnemy(false) then
                                enemy:Remove()
                            end
                        end
                    end
                end
            end)
            if active and wave >= 2 and native.rooms_positions()["0"].index ~= rush then
                move(0, rush)
            end
            if done then
                advance("reward", t)
            end
            assert(t - since < 2600, "Boss Rush never finished")
        elseif step == "reward" and t - since > 100 then
            for slot = 0, 1 do
                move(slot, level:GetStartingRoomIndex())
            end
            advance("outside", t)
        end
    end, collect, restore, present, beginFloor)
end
return {
    done = function()
        return observed.complete
    end,
}
