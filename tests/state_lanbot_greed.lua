-- Honest two-to-four-bot Greed attempt. Preparation grants only the requested initial
-- collectibles. All combat, pickups, buttons, doors and endings are native.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local playerCount = _IsaacLanTest.players or 2
assert(playerCount >= 2 and playerCount <= 4)
local baseFrame, baseGate, baseInput = _IsaacLanFrame, native.net_gate, native.input_bot
local bridge = assert(_IsaacLanModules["api/public"])
local owner = { Name = "LANBOT Greed challenge" }
local renders, linked, chosen, finished, equipped, started = 0, false, false, false, false, false
local outcome, beganAt, beganTick, seenGame, epoch, lastKey, progressedAt
local stage, wave, terminalBoss, endingObserved = 1, 0, false, false
local floors, completed, shots, hits, lastHealth, lastDead = {}, {}, {}, {}, {}, {}
local lastRooms = {}
for i = 1, playerCount do
    shots[i], hits[i] = 0, 0
end
local observedRooms = {}
local moveInputs, shootInputs, snapshots = 0, 0, 0
local winCallback, damageCallback, tearCallback
local result
local function report(text)
    Isaac.DebugString("LAN_NETWORK LANBOT_GREED " .. text)
end
local function command(args)
    local output, response = Isaac.ConsoleOutput, ""
    Isaac.ConsoleOutput = function(text)
        response = response .. text
    end
    local ok, err = pcall(_IsaacLanBotCommand, args)
    Isaac.ConsoleOutput = output
    if not ok or response:find("error=", 1, true) or response:find("LANBOT paused", 1, true) then
        assert(beganAt, err or response)
        report("BOT_ERROR detail=" .. tostring(err or response):gsub("\n", " "))
        result("bot_error")
        return false
    end
    if args == "status" then
        report(response:gsub("\n", ""))
    end
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
native.input_bot = function(active, buttons)
    if active == 1 then
        moveInputs = moveInputs + ((buttons & 15) ~= 0 and 1 or 0)
        shootInputs = shootInputs + ((buttons & 240) ~= 0 and 1 or 0)
    end
    return baseInput(active, buttons)
end
result = function(reason)
    if outcome then
        return
    end
    outcome = reason
    local statistics = {}
    for i = 1, playerCount do
        statistics[#statistics + 1] =
            string.format("shots%d=%d hits%d=%d", i - 1, shots[i], i - 1, hits[i])
    end
    report(
        string.format(
            "RESULT outcome=%s cleared=%s stage=%d wave=%d wall_s=%.3f simulation_s=%.3f %s native_ending=%s",
            reason,
            tostring(reason == "win"),
            stage,
            wave,
            (native.api_info().nowMs - beganAt) / 1000,
            (Game():GetFrameCount() - beganTick) / 30,
            table.concat(statistics, " "),
            tostring(endingObserved)
        )
    )
    if reason ~= "win" then
        finished = true
        report("PASS challenge observed outcome=" .. reason)
    end
end
winCallback = function(_, gameOver)
    if not beganAt then
        return
    end
    endingObserved = true
    if host and not gameOver then
        assert(stage == 7 and terminalBoss, "Win without the native Ultra Greed encounter")
        for i = 1, 7 do
            assert(floors[i], "Challenge skipped native floor " .. i)
            assert(i == 7 or completed[i], "Challenge skipped native Boss waves on floor " .. i)
        end
        for i = 1, playerCount do
            assert(shots[i] > 0, "Each bot must supply native shots")
        end
    end
    result(gameOver and "death" or "win")
end
damageCallback = function(_, entity, amount, flags, source)
    local p = entity:ToPlayer()
    if host and started and not outcome and p then
        report(
            "DAMAGE_ATTEMPT controller="
                .. p.ControllerIndex
                .. " amount="
                .. amount
                .. " flags="
                .. flags
                .. " source="
                .. source.Type
        )
    end
end
tearCallback = function(_, tear)
    if host then
        local p = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        if p and (p.ControllerIndex >= 1 and p.ControllerIndex <= playerCount) then
            shots[p.ControllerIndex] = shots[p.ControllerIndex] + 1
        end
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_END, winCallback)
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, damageCallback, EntityType.ENTITY_PLAYER)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, tearCallback)
local function advance()
    if not native.rooms_ready() or outcome then
        return
    end
    local game, level = Game(), Game():GetLevel()
    assert(game:IsGreedMode() and game.Difficulty == 2, "Expected ordinary Greed mode")
    if game:IsPaused() then
        progressedAt = native.api_info().nowMs
        return
    end
    if not equipped then
        assert(
            level:GetStage() == 1 and level.GreedModeWave == 0,
            "Preparation missed the initial floor"
        )
        beganAt, beganTick, progressedAt =
            native.api_info().nowMs, game:GetFrameCount(), native.api_info().nowMs
        for slot = 0, playerCount - 1 do
            actor(slot, function(p)
                assert(p:GetPlayerType() == PlayerType.PLAYER_ISAAC)
                local before = p:GetCollectibleCount()
                assert(p:GetCollectibleNum(CollectibleType.COLLECTIBLE_SACRED_HEART) == 0)
                assert(p:GetCollectibleNum(CollectibleType.COLLECTIBLE_WIRE_COAT_HANGER) == 0)
                p:AddCollectible(CollectibleType.COLLECTIBLE_SACRED_HEART)
                for _ = 1, 3 do
                    p:AddCollectible(CollectibleType.COLLECTIBLE_WIRE_COAT_HANGER)
                end
                assert(p:GetCollectibleCount() == before + 4)
                assert(p:GetCollectibleNum(CollectibleType.COLLECTIBLE_SACRED_HEART) == 1)
                assert(p:GetCollectibleNum(CollectibleType.COLLECTIBLE_WIRE_COAT_HANGER) == 3)
                report(
                    "LOADOUT slot="
                        .. slot
                        .. " sacred_heart=1 hangers=3 health="
                        .. (p:GetHearts() + p:GetSoulHearts())
                        .. " damage="
                        .. p.Damage
                        .. " fire_delay="
                        .. p.MaxFireDelay
                        .. " speed="
                        .. p.MoveSpeed
                )
            end)
        end
        equipped = true
    end
    stage, wave = level:GetStage(), level.GreedModeWave
    assert(stage >= 1 and stage <= 7, "Greed challenge left the native route")
    if not floors[stage] then
        floors[stage] = true
        report("FLOOR stage=" .. stage)
    end
    local key = stage .. ":" .. wave
    local deadCount = 0
    for slot = 0, playerCount - 1 do
        actor(slot, function(p)
            local room = game:GetRoom()
            local index = level:GetCurrentRoomIndex()
            local roomKey = stage .. ":" .. index
            if lastRooms[slot] ~= roomKey then
                local collision = room:GetGridCollision(room:GetGridIndex(p.Position))
                report(
                    "ENTRY slot="
                        .. slot
                        .. " stage="
                        .. stage
                        .. " room="
                        .. index
                        .. " x="
                        .. p.Position.X
                        .. " y="
                        .. p.Position.Y
                        .. " collision="
                        .. collision
                )
                if room:GetType() == RoomType.ROOM_SHOP then
                    assert(
                        collision == GridCollisionClass.COLLISION_NONE
                            or collision == GridCollisionClass.COLLISION_WALL_EXCEPT_PLAYER
                            or p.CanFly
                                and (collision == GridCollisionClass.COLLISION_PIT or collision == GridCollisionClass.COLLISION_OBJECT),
                        "Shop arrival landed in blocked terrain for slot " .. slot
                    )
                end
                lastRooms[slot] = roomKey
            end
            local health, dead = p:GetHearts() + p:GetSoulHearts(), p:IsDead() or p:IsCoopGhost()
            deadCount = deadCount + (dead and 1 or 0)
            if lastHealth[slot] and health < lastHealth[slot] then
                hits[slot + 1] = hits[slot + 1] + 1
                report(
                    "HIT slot="
                        .. slot
                        .. " health="
                        .. health
                        .. " stage="
                        .. stage
                        .. " wave="
                        .. wave
                )
            end
            if lastDead[slot] ~= dead then
                report("ACTOR slot=" .. slot .. " dead=" .. tostring(dead) .. " health=" .. health)
            end
            lastHealth[slot], lastDead[slot] = health, dead
            local enemies, hp = 0, 0
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == EntityType.ENTITY_ULTRA_GREED then
                    terminalBoss = true
                end
                if e:IsActiveEnemy(false) and not e:IsDead() then
                    enemies, hp = enemies + 1, hp + math.max(0, e.HitPoints)
                end
            end
            -- Repeating room transitions is not progress.
            key = key .. ":" .. enemies .. ":" .. math.floor(hp) .. ":" .. p:GetCollectibleCount()
            if
                stage < 7
                and wave >= 10
                and enemies == 0
                and level:GetRoomByIdx(level:GetCurrentRoomIndex(), 0).SafeGridIndex == level:GetRoomByIdx(
                    level:GetStartingRoomIndex(),
                    0
                ).SafeGridIndex
                and game:GetRoom():IsClear()
                and not completed[stage]
            then
                completed[stage] = true
                report("FLOOR_CLEAR stage=" .. stage .. " wave=" .. wave)
            end
        end)
    end
    if deadCount == playerCount then
        result("death")
        return
    end
    if key ~= lastKey then
        lastKey, progressedAt = key, native.api_info().nowMs
    end
    local now = native.api_info().nowMs
    if now - beganAt >= 1800000 then
        result("timeout")
    elseif now - progressedAt >= 180000 then
        result("stalled")
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if EID and EID.Config then
        EID.Config.DisableStartOfRunWarnings = true
    end
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = baseFrame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    local allReady = status.players == playerCount
    for slot = 0, playerCount - 1 do
        allReady = allReady and status["ready" .. slot] == 1
    end
    if host and status.phase == 2 and allReady then
        _IsaacLanCommand("start", "YV039KQF:2:0:0:0:0")
    end
    native.test_gamepad(outcome and status.scene == 3 and renders % 30 < 5 and 4096 or 0)
    local info = native.api_info()
    if status.scene == 2 and info.ready == 1 and bridge.ready() and not outcome then
        seenGame = true
        if not host then
            beganAt, beganTick = beganAt or info.nowMs, beganTick or Game():GetFrameCount()
            stage, wave = Game():GetLevel():GetStage(), Game():GetLevel().GreedModeWave
        end
        local hasLoadout = false
        for _, entry in ipairs(native.api_actors()) do
            if entry.owner == info.slot + 1 then
                local p = Isaac.GetPlayer(entry.index)
                hasLoadout = p:GetCollectibleNum(CollectibleType.COLLECTIBLE_SACRED_HEART) == 1
                    and p:GetCollectibleNum(CollectibleType.COLLECTIBLE_WIRE_COAT_HANGER) == 3
                break
            end
        end
        local current = info.runId .. ":" .. info.worldEpoch
        if hasLoadout and epoch ~= current then
            epoch, started = current, true
            command("mode run")
            command("on")
            report("BOT_ACTIVE epoch=" .. current)
        end
        if started and renders % 120 == 0 then
            command("status")
            local at = native.rooms_positions()[tostring(info.slot)]
            local key = current .. ":" .. at.index
            if not observedRooms[key] then
                observedRooms[key] = true
                bridge.withView(function()
                    local room, level = Game():GetRoom(), Game():GetLevel()
                    report(
                        "VIEW_ROOM index="
                            .. at.index
                            .. " canonical="
                            .. level:GetRoomByIdx(at.index, at.dimension).SafeGridIndex
                            .. " type="
                            .. room:GetType()
                    )
                    for slot = 0, 7 do
                        local door = room:GetDoor(slot)
                        if door then
                            report(
                                "VIEW_DOOR slot="
                                    .. slot
                                    .. " target="
                                    .. door.TargetRoomIndex
                                    .. " canonical="
                                    .. level:GetRoomByIdx(door.TargetRoomIndex, at.dimension).SafeGridIndex
                                    .. " type="
                                    .. door.TargetRoomType
                            )
                        end
                    end
                end)
            end
            report(
                "PROGRESS stage="
                    .. stage
                    .. " wave="
                    .. wave
                    .. " move_inputs="
                    .. moveInputs
                    .. " shoot_inputs="
                    .. shootInputs
            )
            for _, entry in ipairs(native.api_actors()) do
                if entry.owner == info.slot + 1 then
                    local p = Isaac.GetPlayer(entry.index)
                    local pose = not host and _IsaacLanState and _IsaacLanState.actorPose(p)
                    report(
                        string.format(
                            "ACTOR_STATE room=%d x=%.1f y=%.1f keys=%d coins=%d health=%d items=%d speed=%.3f",
                            native.rooms_positions()[tostring(info.slot)].index,
                            pose and pose.x or p.Position.X,
                            pose and pose.y or p.Position.Y,
                            p:GetNumKeys(),
                            p:GetNumCoins(),
                            p:GetHearts() + p:GetSoulHearts(),
                            p:GetCollectibleCount(),
                            p.MoveSpeed
                        )
                    )
                    if renders % 600 == 0 then
                        bridge.withView(function()
                            local room = Game():GetRoom()
                            local x, y =
                                pose and pose.x or p.Position.X, pose and pose.y or p.Position.Y
                            local radius, corners = p.Size or 12, {}
                            for _, offset in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
                                local cell = room:GetGridIndex(
                                    Vector(x + offset[1] * radius, y + offset[2] * radius)
                                )
                                corners[#corners + 1] = cell .. ":" .. room:GetGridCollision(cell)
                            end
                            report("MOBILITY grid_corners=" .. table.concat(corners, ","))
                            local count = 0
                            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                                if
                                    count < 16
                                    and (entity:ToPickup() or entity.Type == EntityType.ENTITY_SLOT)
                                then
                                    local pickup = entity:ToPickup()
                                    report(
                                        string.format(
                                            "NAV_OBJECT type=%d variant=%d x=%.1f y=%.1f size=%.1f price=%d wait=%d",
                                            entity.Type,
                                            entity.Variant,
                                            entity.Position.X,
                                            entity.Position.Y,
                                            entity.Size or 0,
                                            pickup and pickup.Price or 0,
                                            pickup and pickup.Wait or 0
                                        )
                                    )
                                    count = count + 1
                                end
                            end
                            for slot = 0, 7 do
                                local door = room:GetDoor(slot)
                                if door then
                                    report(
                                        string.format(
                                            "NAV_DOOR slot=%d x=%.1f y=%.1f open=%s locked=%s",
                                            slot,
                                            door.Position.X,
                                            door.Position.Y,
                                            tostring(door:IsOpen()),
                                            tostring(door:IsLocked())
                                        )
                                    )
                                end
                            end
                            report(
                                "COMBAT_CONTEXT range="
                                    .. p.TearRange
                                    .. " shoot_inputs="
                                    .. shootInputs
                                    .. " clear="
                                    .. tostring(Game():GetRoom():IsClear())
                            )
                            local count = 0
                            for _, enemy in ipairs(Isaac.GetRoomEntities()) do
                                if
                                    stage == 7
                                    and (
                                        enemy.Type == EntityType.ENTITY_SLOT
                                        or enemy.Type == EntityType.ENTITY_PICKUP
                                            and enemy.Variant == PickupVariant.PICKUP_BIGCHEST
                                    )
                                then
                                    report(
                                        string.format(
                                            "ENDING_OBJECT type=%d variant=%d x=%.1f y=%.1f radius=%.1f collision=%s state=%s wait=%s",
                                            enemy.Type,
                                            enemy.Variant,
                                            enemy.Position.X,
                                            enemy.Position.Y,
                                            enemy.Size,
                                            tostring(enemy.EntityCollisionClass),
                                            tostring(enemy:ToPickup() and enemy:ToPickup().State),
                                            tostring(enemy:ToPickup() and enemy:ToPickup().Wait)
                                        )
                                    )
                                end
                                if
                                    enemy.ToNPC
                                    and enemy:ToNPC()
                                    and enemy:IsActiveEnemy(false)
                                    and not enemy:IsDead()
                                then
                                    count = count + 1
                                    if count <= 12 then
                                        report(
                                            string.format(
                                                "FOE id=%s:%d:%d hp=%.1f x=%.1f y=%.1f vx=%.1f vy=%.1f invincible=%s vulnerable=%s line=%s radius=%.1f damage=%s",
                                                tostring(enemy.InitSeed),
                                                enemy.Type,
                                                enemy.Variant,
                                                enemy.HitPoints,
                                                enemy.Position.X,
                                                enemy.Position.Y,
                                                enemy.Velocity.X,
                                                enemy.Velocity.Y,
                                                tostring(enemy:IsInvincible()),
                                                tostring(enemy:IsVulnerableEnemy()),
                                                tostring(
                                                    Game():GetRoom():CheckLine(
                                                        p.Position,
                                                        enemy.Position,
                                                        3,
                                                        0,
                                                        false,
                                                        false
                                                    )
                                                ),
                                                enemy.Size,
                                                tostring(enemy.CollisionDamage)
                                            )
                                        )
                                    end
                                end
                            end
                        end)
                    end
                end
            end
        end
    elseif
        seenGame
        and status.phase == 0
        and status.scene == 1
        and not status.prepared
        and not finished
    then
        assert(started, "Local LANBOT never activated")
        finished = true
        report(
            "PASS challenge observed outcome="
                .. (outcome or "peer_returned")
                .. " move_inputs="
                .. moveInputs
                .. " shoot_inputs="
                .. shootInputs
                .. " snapshots="
                .. snapshots
        )
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        capture,
        function(t, n, b)
            before(t, n, b)
            if host then
                advance()
            end
        end,
        collect,
        function(...)
            if restore(...) == false then
                return false
            end
            snapshots = snapshots + 1
            return true
        end,
        present,
        beginFloor
    )
end

-- Explicit test-only lifecycle consumed by both suite coordinators.
return {
    done = function()
        return finished
    end,
    cleanup = function()
        command("off")
        native.input_bot = baseInput
    end,
}
