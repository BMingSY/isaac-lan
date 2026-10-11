-- One native host and up to three guests: Delirium and shared-egress recovery.
-- Player protection and encounter/loadout preparation are explicit fixtures.
-- Boss AI, projectiles, normal inputs, and production synchronization run normally.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local players = _IsaacLanTest.players or 2
local config = _IsaacLanDeliriumFixture or { seconds = 60, loadouts = {} }
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
local phase, phaseAt, enteredAt = "setup", nil, nil
local linked, chosen, finished, exitRequested, passed = false, false, false, false, false
local renders, rawBytes, lastSample, lastRender, maxRender = 0, 0, 0, nil, 0
local bossSeed, lastForm, formChanges, warmIndex, warmAt = nil, nil, 0, 1, nil
local warmEntity, snapshots = nil, 0
local returnRoom
local history = {
    { 20, 0 },
    { 62, 0 },
    { 68, 1 },
    { 71, 0 },
    { 73, 0 },
    { 78, 1 },
    { 81, 1 },
    { 83, 0 },
    { 84, 0 },
    { 99, 0 },
    { 265, 0 },
    { 269, 0 },
    { 271, 0 },
    { 273, 0 },
    { 410, 0 },
    { 411, 0 },
}
local function report(text)
    Isaac.DebugString("LAN_NETWORK DELIRIUM_PERF " .. text)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function clean()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type ~= EntityType.ENTITY_PLAYER then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function cleanPreparationPickups()
    -- Applying the reference inventory spawns temporary room loot. Keep the
    -- preparation arena clear; combat effects remain on the normal sync path.
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if
            entity.Type == EntityType.ENTITY_PICKUP
            or (
                entity.Type == EntityType.ENTITY_EFFECT
                and entity.Variant == EffectVariant.PICKUP_GHOST
            )
        then
            entity:Remove()
        end
    end
end
local function mark(name, now)
    phase, phaseAt = name, now
    report("PHASE name=" .. name .. " now_ms=" .. now .. " tick=" .. _IsaacLanStatus().verified)
end
local function hasDelirium(data)
    if not data then
        return false
    end
    for i = 0, data.SpawnCount - 1 do
        local spawn = data.Spawns:Get(i)
        for j = 0, spawn.EntryCount - 1 do
            if spawn.Entries:Get(j).Type == EntityType.ENTITY_DELIRIUM then
                return true
            end
        end
    end
    return false
end
local function protect()
    for slot = 0, players - 1 do
        actor(slot, function(player)
            player:SetMinDamageCooldown(10000)
        end)
    end
end
local function currentBoss()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        -- Delirium keeps Type 412 while its native form/InitSeed can change.
        if entity.Type == EntityType.ENTITY_DELIRIUM and entity:ToNPC() then
            return entity:ToNPC()
        end
    end
end
local function advance()
    if not native.rooms_ready() or finished then
        return
    end
    local now = native.api_info().nowMs
    protect()
    if phase == "setup" then
        actor(0, clean)
        for slot = 0, players - 1 do
            actor(slot, function(player)
                for _, id in ipairs(config.loadouts[slot] or {}) do
                    player:AddCollectible(id)
                end
                player:AddSoulHearts(24)
                player.Position = Game():GetRoom():GetCenterPos() + Vector(slot * 80 - 40, 60)
            end)
        end
        actor(0, cleanPreparationPickups)
        mark("baseline", now)
    elseif phase == "baseline" then
        actor(0, cleanPreparationPickups)
        if now - phaseAt >= 10000 then
            mark("encounter-history", now)
        end
    elseif phase == "encounter-history" then
        if warmEntity and now - warmAt >= 800 then
            actor(0, function(player)
                local npc = warmEntity.Ref
                if npc and npc:Exists() and not npc:IsDead() then
                    npc.HitPoints = 1
                    npc:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(player), 0)
                end
            end)
        end
        if warmEntity and now - warmAt >= 1200 then
            actor(0, clean)
            warmEntity, warmAt, warmIndex = nil, nil, warmIndex + 1
        end
        if not warmEntity and history[warmIndex] then
            actor(0, function()
                local value = history[warmIndex]
                local npc = assert(
                    Isaac.Spawn(
                        value[1],
                        value[2],
                        0,
                        Game():GetRoom():GetCenterPos(),
                        Vector.Zero,
                        nil
                    )
                        :ToNPC()
                )
                warmEntity, warmAt = EntityPtr(npc), now
                report(
                    "HISTORY type="
                        .. value[1]
                        .. " variant="
                        .. value[2]
                        .. " boss="
                        .. tostring(npc:IsBoss())
                )
            end)
        elseif not warmEntity then
            actor(0, function(player)
                Game():GetLevel():SetStage(12, StageType.STAGETYPE_ORIGINAL)
                Game():StartStageTransition(true, 0, player)
            end)
            mark("floor-loading", now)
        end
    elseif
        phase == "floor-loading"
        and Game():GetLevel():GetStage() == 12
        and now - phaseAt > 14000
    then
        local rooms = Game():GetLevel():GetRooms()
        local target
        for index = 0, rooms.Size - 1 do
            local room = rooms:Get(index)
            if hasDelirium(room.Data) or hasDelirium(room.OverrideData) then
                target = room.SafeGridIndex
                report("NATIVE_ROOM index=" .. target .. " name=" .. room.Data.Name)
                break
            end
        end
        assert(target, "Native Delirium room is missing")
        returnRoom = native.rooms_positions()["0"].index
        assert(native.rooms_move(0, target, 0, -1))
        actor(0, function()
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_DELIRIUM then
                    bossSeed = entity.InitSeed
                end
            end
        end)
        mark("boss-arrival", now)
    elseif phase == "boss-arrival" and now - phaseAt > 6000 then
        local locations = native.rooms_positions()
        for slot = 1, players - 1 do
            assert(
                locations["0"].index == locations[tostring(slot)].index,
                "Delirium did not gather players"
            )
        end
        actor(0, function()
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if
                    entity.Type == EntityType.ENTITY_DELIRIUM
                    or (
                        not bossSeed
                        and entity:ToNPC()
                        and entity:ToNPC():IsBoss()
                        and entity.MaxHitPoints >= 5000
                    )
                then
                    bossSeed = entity.InitSeed
                end
            end
        end)
        assert(bossSeed, "Native Delirium did not spawn")
        enteredAt = now
        mark("combat", now)
    elseif phase == "combat" and now - phaseAt >= config.seconds * 1000 then
        actor(0, function()
            local boss = assert(currentBoss(), "Delirium disappeared before low-health phase")
            boss.HitPoints = boss.MaxHitPoints * 0.25
            report("LOW_HEALTH hp=" .. boss.HitPoints .. " max_hp=" .. boss.MaxHitPoints)
        end)
        mark("combat-low-health", now)
    elseif phase == "combat-low-health" and now - phaseAt >= config.seconds * 1000 then
        if (config.bandwidth or 0) > 0 then
            mark("combat-bandwidth", now)
        else
            actor(0, clean)
            mark("recovery", now)
        end
    elseif phase == "combat-bandwidth" and now - phaseAt >= config.seconds * 1000 then
        actor(0, clean)
        mark("recovery", now)
    elseif phase == "recovery" and now - phaseAt >= 15000 then
        local target = assert(returnRoom)
        for slot = 0, players - 1 do
            assert(native.rooms_move(slot, target, 0, -1))
        end
        mark("room-transition", now)
    elseif phase == "room-transition" and now - phaseAt >= 5000 then
        actor(0, function(player)
            Game():GetLevel():SetStage(1, StageType.STAGETYPE_ORIGINAL)
            Game():StartStageTransition(true, 0, player)
        end)
        mark("final-floor", now)
    elseif
        phase == "final-floor"
        and now - phaseAt >= 15000
        and Game():GetLevel():GetStage() == 1
    then
        finished = true
        native.input_bot(0, 0)
        report("HOST_DONE form_changes=" .. formChanges .. " combat_ms=" .. (now - enteredAt))
    end
    if phase == "combat" or phase == "combat-low-health" or phase == "combat-bandwidth" then
        actor(0, function()
            local boss = assert(currentBoss(), "Delirium disappeared during combat")
            bossSeed = boss.InitSeed
            local minimum = phase == "combat" and 0.55 or 0.15
            if boss.HitPoints < boss.MaxHitPoints * minimum then
                boss.HitPoints = boss.MaxHitPoints * minimum
            end
            if phase ~= "combat" then
                boss.HitPoints = math.min(boss.HitPoints, boss.MaxHitPoints * 0.25)
            end
            local form = boss:GetSprite():GetFilename()
            if lastForm and lastForm ~= form then
                formChanges = formChanges + 1
                report("FORM value=" .. form .. " now_ms=" .. now)
            end
            lastForm = form
        end)
    end
end
local function sample(status, now)
    if not native.rooms_ready() or native.api_info().ready ~= 1 then
        return
    end
    local count, projectiles, effects, kind, variant, hp, maxhp = 0, 0, 0, 0, 0, 0, 0
    local playerX, playerY, tears = 0, 0, 0
    actor(status.slot, function(player)
        playerX, playerY = player.Position.X, player.Position.Y
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            count = count + 1
            projectiles = projectiles + (entity.Type == EntityType.ENTITY_PROJECTILE and 1 or 0)
            effects = effects + (entity.Type == EntityType.ENTITY_EFFECT and 1 or 0)
            tears = tears + (entity.Type == EntityType.ENTITY_TEAR and 1 or 0)
            local npc = entity:ToNPC()
            if npc and npc:IsBoss() and entity.MaxHitPoints > maxhp then
                kind, variant, hp, maxhp =
                    entity.Type, entity.Variant, entity.HitPoints, entity.MaxHitPoints
            end
        end
    end)
    report(
        "SAMPLE now_ms="
            .. now
            .. " tick="
            .. status.verified
            .. " phase="
            .. phase
            .. " render_max_ms="
            .. maxRender
            .. " ping="
            .. (status["ping" .. (host and 1 or status.slot)] or -1)
            .. " entities="
            .. count
            .. " projectiles="
            .. projectiles
            .. " effects="
            .. effects
            .. " raw="
            .. rawBytes
            .. " boss_type="
            .. kind
            .. " boss_variant="
            .. variant
            .. " boss_hp="
            .. hp
            .. " boss_max_hp="
            .. maxhp
            .. " form_changes="
            .. formChanges
            .. " snapshots="
            .. snapshots
            .. " player_x="
            .. playerX
            .. " player_y="
            .. playerY
            .. " tears="
            .. tears
    )
    maxRender = 0
end
function _IsaacLanFrame()
    local now = native.api_info().nowMs
    if lastRender then
        maxRender = math.max(maxRender, now - lastRender)
    end
    lastRender = now
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = baseFrame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "7:1")
    end
    if host and status.phase == 2 and status.players == players then
        local ready, choices = true, {}
        for slot = 0, 3 do
            choices[#choices + 1] = slot < players and "7" or "0"
            if slot < players and status["ready" .. slot] ~= 1 then
                ready = false
            end
        end
        if ready then
            _IsaacLanCommand("start", "9AAWT3VR:0:" .. table.concat(choices, ":"))
        end
    end
    native.test_gamepad(0)
    if status.scene == 2 and native.api_info().ready == 1 then
        if now - lastSample >= 1000 then
            lastSample = now
            sample(status, now)
        end
    end
    if host and finished and not exitRequested then
        exitRequested = true
        assert(native.net_command(3))
    end
    if exitRequested and status.phase == 0 and status.scene == 1 and not status.prepared then
        if not passed then
            passed = true
            report("PASS Delirium performance reproduction")
        end
    elseif
        not host
        and snapshots > 0
        and status.phase == 0
        and status.scene == 1
        and not status.prepared
    then
        if not finished then
            finished = true
            report("PASS Delirium performance reproduction")
        end
    end
    return status
end
-- The native input sampler calls this immediately before composing input.
-- Refreshing only from the UI frame would be cleared by the regular bot.
function _IsaacLanBotFrame()
    local info = native.api_info()
    local mask = 0
    if info.ready == 1 and native.rooms_ready() and not finished then
        actor(_IsaacLanStatus().slot, function(player)
            local boss = currentBoss()
            if boss then
                local direction = math.floor(info.nowMs / 4000) % 4
                mask = ({ 2, 8, 1, 4 })[direction + 1]
                local delta = boss.Position - player.Position
                local shoot = math.abs(delta.X) > math.abs(delta.Y) and (delta.X < 0 and 16 or 32)
                    or (delta.Y < 0 and 64 or 128)
                mask = mask | shoot
            end
        end)
    end
    assert(native.input_bot(mask ~= 0 and 1 or 0, mask))
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(capture, function(t, n, b)
        before(t, n, b)
        if host then
            advance()
        end
    end, function(slot, tick)
        local bytes = collect(slot, tick)
        rawBytes = #bytes
        native.diagnostics_counter("fixture_world_raw_bytes", rawBytes)
        return bytes
    end, function(...)
        local result = restore(...)
        if result ~= false then
            snapshots = snapshots + 1
        end
        return result
    end, present, beginFloor)
end
