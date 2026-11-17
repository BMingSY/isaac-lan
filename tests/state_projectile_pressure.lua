-- Fixed native populations and the reported loadout; no recorder in timed runs.
local native, config = _IsaacLan, _IsaacLanTest
local options = _IsaacLanProjectileFixture or {}
local fields = _IsaacLanModules["sync/fields"]
local schema = _IsaacLanModules["sync/world_schema"]
local Phase = native.net_phases()
local json = require("json")
local frame, gate, diagnostics = _IsaacLanFrame, native.net_gate, native.diagnostics_sample
local firstTick, duration, warmup = 60, 360, 90
local cases = {
    { name = "idle" },
    { name = "lachryphagy-brimstone-sacred-heart", combo = true },
    { name = "tears-200", tears = 200 },
    { name = "tears-500", tears = 500 },
    { name = "lasers-64", lasers = 64 },
}
local tick, renders, linked, chosen, finished = 0, 0, false, false, false
local samples, tracked, lastRender = {}, {}, nil
local measured, origin, other, floorSeed = false, nil, nil, nil
local checkedViews, afterFloor, lastChecked = 0, 0, -math.huge
local comboLasers = 0
local observer = RegisterMod("Projectile pressure observations", 1)
local function observeLaser()
    if tick >= firstTick + duration and tick < firstTick + 2 * duration then
        comboLasers = comboLasers + 1
    end
end
observer:AddCallback(ModCallbacks.MC_POST_LASER_INIT, observeLaser)
local items = {
    CollectibleType.COLLECTIBLE_LACHRYPHAGY,
    CollectibleType.COLLECTIBLE_BRIMSTONE,
    CollectibleType.COLLECTIBLE_SACRED_HEART,
}
local function phase()
    local index = math.floor((tick - firstTick) / duration) + 1
    return cases[index], index, (tick - firstTick) % duration
end
local function sample(name, value)
    local case, index, elapsed = phase()
    if not case or elapsed < warmup or elapsed >= duration - 10 then
        return
    end
    samples[index] = samples[index] or {}
    local group = samples[index]
    group[name] = group[name] or { count = 0, sum = 0, max = 0 }
    local stat = group[name]
    stat.count, stat.sum, stat.max = stat.count + 1, stat.sum + value, math.max(stat.max, value)
    if name == "render" or name == "capture" or name == "apply" then
        stat.values = stat.values or {}
        stat.values[#stat.values + 1] = value
    end
end
native.diagnostics_sample = function(name, value)
    sample(name, value)
    return diagnostics(name, value)
end
local function report()
    assert(comboLasers > 0, "Reported loadout never fired a laser")
    for index, case in ipairs(cases) do
        local metrics = assert(samples[index], "Missing pressure phase: " .. case.name)
        assert(metrics.render and metrics.render.count >= 100, "Insufficient steady frames")
        local views = metrics[config.host and "capture" or "apply"]
        assert(views and views.count >= 100, "Insufficient completed views")
        for _, stat in pairs(metrics) do
            stat.mean = stat.sum / stat.count
            stat.sum = nil
            if stat.values then
                table.sort(stat.values)
                stat.p50 = stat.values[math.ceil(#stat.values * 0.5)]
                stat.p95 = stat.values[math.ceil(#stat.values * 0.95)]
                stat.values = nil
            end
        end
        Isaac.DebugString("LAN_PROJECTILE_PRESSURE " .. json.encode({
            role = config.host and "host" or "client",
            case = case.name,
            spawned_lasers = case.combo and comboLasers or nil,
            metrics = metrics,
        }))
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (config.host and 60 or 120) then
        linked = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= Phase.failed, status.error)
    if status.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        config.host
        and status.phase == Phase.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    tick = status.verified
    local current, _, at = phase()
    native.test_gamepad(
        not config.host and current and current.combo and at % 300 < 270 and 0x1000 or 0
    )
    local now = Isaac.GetTime()
    if lastRender then
        sample("render", now - lastRender)
    end
    lastRender = now
    if status.prepared and native.rooms_ready() and phase() then
        if not config.host then
            sample("sync_ms", status.sync1 or 0)
        end
        local case, _, elapsed = phase()
        if elapsed >= warmup and tick % 30 == 0 then
            local tears, lasers = 0, 0
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == EntityType.ENTITY_TEAR then
                    tears = tears + 1
                end
                if e.Type == EntityType.ENTITY_LASER then
                    lasers = lasers + 1
                end
            end
            sample("tears", tears)
            sample("lasers", lasers)
            assert(not case.tears or tears == case.tears, "Tear population differs")
            assert(not case.lasers or lasers == case.lasers, "Laser population differs")
        end
    end
    if tick >= firstTick + duration * #cases and not measured then
        report()
        measured = true
    end
    if
        measured
        and (not options.verify or tick >= firstTick + duration * #cases + 450)
        and not finished
    then
        if options.verify then
            -- The verified network clock can lead the last applied view during
            -- floor preparation. Wait for actual post-floor observations.
            if not config.host and (checkedViews <= 20 or afterFloor < 2) then
                assert(
                    tick < firstTick + duration * #cases + 750,
                    "Missing link/cleanup observations: views="
                        .. checkedViews
                        .. " postFloor="
                        .. afterFloor
                )
                return status
            end
            Isaac.DebugString("LAN_PROJECTILE_VERIFY " .. json.encode({
                role = config.host and "host" or "client",
                checked_views = checkedViews,
                after_floor = afterFloor,
                last_checked = lastChecked ~= -math.huge and lastChecked or nil,
            }))
        end
        finished = true
        Isaac.DebugString("LAN_NETWORK PASS projectile pressure")
    end
    return status
end
local function setup(case)
    assert(native.rooms_with_player(1, function()
        local room = Game():GetRoom()
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e.Type ~= EntityType.ENTITY_PLAYER then
                e:Remove()
            end
        end
        room:SetClear(true)
        room:Update()
        tracked = {}
        local player = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
        for _, item in ipairs(items) do
            if player:HasCollectible(item) then
                player:RemoveCollectible(item)
            end
        end
        player:ChangePlayerType(case.combo and PlayerType.PLAYER_KEEPER or PlayerType.PLAYER_ISAAC)
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            -- Later correctness phases split the players into different rooms.
            if
                tick <= firstTick + duration * #cases
                or p.ControllerIndex == player.ControllerIndex
            then
                p.Position, p.Velocity = Vector(100, 220 + i * 60), Vector.Zero
                p:SetMinDamageCooldown(100000)
            end
        end
        if case.combo then
            for _, item in ipairs(items) do
                player:AddCollectible(item, 0, false)
            end
        end
        for i = 1, case.tears or 0 do
            local tear = assert(
                Isaac.Spawn(
                    EntityType.ENTITY_TEAR,
                    TearVariant.BLUE,
                    0,
                    Vector(200 + (i % 25) * 12, 160 + math.floor(i / 25) * 10),
                    Vector.Zero,
                    player
                ):ToTear()
            )
            tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
            tear.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
            tracked[#tracked + 1] = EntityPtr(tear)
        end
        for i = 1, case.lasers or 0 do
            local laser = EntityLaser.ShootAngle(
                1,
                Vector(180, 240),
                i * 360 / case.lasers,
                duration + 100,
                Vector.Zero,
                player
            )
            laser.DisableFollowParent = true
            laser.MaxDistance = 150
            laser.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
            laser.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
            tracked[#tracked + 1] = EntityPtr(laser)
        end
        Isaac.DebugString("LAN_PROJECTILE_PRESSURE_BEGIN " .. json.encode({
            case = case.name,
            tick = tick,
            now = Isaac.GetTime(),
        }))
    end))
end
local function verifyLifecycle(t)
    if not options.verify then
        return
    end
    local elapsed = t - firstTick - duration * #cases
    if elapsed == 0 then
        setup({})
        local level = Game():GetLevel()
        origin = level:GetStartingRoomIndex()
        local rooms = level:GetRooms()
        for i = 0, rooms.Size - 1 do
            local room = rooms:Get(i)
            if
                room.Data
                and room.Data.Type == RoomType.ROOM_DEFAULT
                and room.SafeGridIndex ~= origin
            then
                other = room.SafeGridIndex
                break
            end
        end
        assert(other, "No adjacent lifecycle room")
    elseif elapsed == 30 or elapsed == 150 then
        setup({})
        if elapsed == 150 then
            assert(native.rooms_move(0, other, 0, -1))
        end
        assert(native.rooms_move(1, other, 0, -1))
    elseif elapsed == 90 or elapsed == 210 then
        setup({})
        if elapsed == 210 then
            assert(native.rooms_move(0, origin, 0, -1))
        end
        assert(native.rooms_move(1, origin, 0, -1))
    elseif elapsed == 40 or elapsed == 100 or elapsed == 160 or elapsed == 220 then
        -- Let room retirement complete before allocating the next population.
        setup({ tears = 200 })
    elseif elapsed == 300 then
        setup({})
        floorSeed = Game():GetSeeds():GetStageSeed(Game():GetLevel():GetStage())
        assert(native.rooms_with_player(1, function()
            local player = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
            player:UseActiveItem(CollectibleType.COLLECTIBLE_FORGET_ME_NOW, UseFlag.USE_NOANIM, -1)
        end))
    elseif elapsed == 390 then
        assert(Game():GetSeeds():GetStageSeed(Game():GetLevel():GetStage()) ~= floorSeed)
        setup({ tears = 200 })
    end
end
local function verifyLinks(bytes, t, stable)
    if not options.verify or t < lastChecked + 30 then
        return
    end
    lastChecked = t
    local view = schema.unpack(_IsaacLanState.decode(bytes, stable), t)
    local refs = {}
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        local id = e:GetData().__isaac_lan_replica
        if id then
            refs[id] = e
        end
    end
    for _, actor in ipairs(view.actors) do
        refs[actor[fields.actor.entity][fields.entity.id]] =
            Isaac.GetPlayer(actor[fields.actor.index])
    end
    for _, value in ipairs(view.room[fields.room.entities]) do
        local entity = assert(refs[value[fields.entity.id]], "Missing synchronized entity")
        for name, field in pairs({
            Parent = fields.entity.parent,
            SpawnerEntity = fields.entity.spawner,
            Child = fields.entity.child,
            Target = fields.entity.target,
        }) do
            local expected, actual = refs[value[field]], entity[name]
            assert(value[field] == 0 or expected, "Missing authoritative link target")
            assert(
                (not actual and not expected)
                    or (actual and expected and GetPtrHash(actual) == GetPtrHash(expected)),
                "Synchronized " .. name .. " differs"
            )
        end
        assert(
            entity.EntityCollisionClass == EntityCollisionClass.ENTCOLL_NONE,
            "Replica enabled native collisions"
        )
    end
    checkedViews = checkedViews + 1
    if t >= firstTick + duration * #cases + 390 then
        afterFloor = afterFloor + 1
    end
end
local function updateTracked(t)
    for i, pointer in ipairs(tracked) do
        local e = assert(pointer.Ref, "Native pressure entity expired")
        local tear = e:ToTear()
        if tear then
            tear.Height, tear.FallingSpeed, tear.FallingAcceleration = -30, 0, 0
            tear.Position = Vector(
                200 + (i % 25) * 12 + math.sin(t / 10 + i) * 8,
                160 + math.floor(i / 25) * 10
            )
            tear.Velocity = Vector.Zero
        elseif e:ToLaser() then
            e:ToLaser().AngleDegrees = (i * 360 / #tracked + t) % 360
        end
    end
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, ...)
        before(t, ...)
        if finished then
            return
        end
        tick = t
        local case, _, elapsed = phase()
        if case and elapsed == 0 then
            setup(case)
        end
        verifyLifecycle(t)
        if options.verify and #tracked > 0 then
            assert(native.rooms_with_player(1, function()
                updateTracked(t)
            end))
        else
            updateTracked(t)
        end
    end, function(...)
        local began = Isaac.GetTime()
        local bytes, stable = collect(...)
        sample("capture", Isaac.GetTime() - began)
        sample("raw_bytes", #bytes)
        return bytes, stable
    end, function(bytes, t, ack, between, stable)
        tick = t
        local began = Isaac.GetTime()
        local result = restore(bytes, t, ack, between, stable)
        sample("apply", Isaac.GetTime() - began)
        sample("raw_bytes", #bytes)
        if result ~= false then
            verifyLinks(bytes, t, stable)
        end
        return result
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        observer:RemoveCallback(ModCallbacks.MC_POST_LASER_INIT, observeLaser)
        native.test_gamepad(0)
        native.diagnostics_sample = diagnostics
        _IsaacLanFrame, native.net_gate = frame, gate
    end,
}
