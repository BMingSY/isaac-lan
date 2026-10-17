-- Pure-dodging demonstration. Only the fixture masks firing; the production
-- LANBOT movement policy, native Spider AI, collision and damage stay intact.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local baseFrame, baseGate, baseInput = _IsaacLanFrame, native.net_gate, native.input_bot
local bridge = assert(_IsaacLanModules["api/public"])
local owner = { Name = "LANBOT Spider survival" }
local renders, linked, chosen, finished = 0, false, false, false
local armed, released, botStarted, seenScene = false, false, false, false
local parked, origin, armedAt, startTick, startMs, firstSeen
local lastHealth, hits, tears, moveInputs, maskedFire = 6, 0, 0, 0, 0
local spiders, damageCallback, freezeCallback, tearCallback = {}, nil, nil, nil
local spiderMotion, actorMotion, lastPosition = false, 0, nil
local function report(text)
    Isaac.DebugString("LAN_NETWORK LANBOT_SPIDERS " .. text)
end
local function command(args)
    local output, response = Isaac.ConsoleOutput, ""
    Isaac.ConsoleOutput = function(text)
        response = response .. text
    end
    local ok, err = pcall(_IsaacLanBotCommand, args)
    Isaac.ConsoleOutput = output
    assert(ok, err)
    assert(not response:find("error=", 1, true), response)
    if args == "status" then
        report(response:gsub("\n", ""))
    end
end
native.input_bot = function(active, buttons)
    if active == 1 then
        moveInputs = moveInputs + ((buttons & 15) ~= 0 and 1 or 0)
        maskedFire = maskedFire + ((buttons & 240) ~= 0 and 1 or 0)
    end
    return baseInput(active, buttons & 15)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function clearFixtureRoom()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type ~= EntityType.ENTITY_PLAYER then
            e:Remove()
        end
    end
end
freezeCallback = function(_, npc)
    if host and armed and not released and spiders[npc.InitSeed] then
        return true -- Suppress AI only while the nine Spiders are staged.
    end
end
damageCallback = function(_, entity, amount, flags, source)
    local p = entity:ToPlayer()
    if host and released and not finished and p and p.ControllerIndex == 2 then
        report(
            "DAMAGE_ATTEMPT amount=" .. amount .. " flags=" .. flags .. " source=" .. source.Type
        )
    end
end
tearCallback = function()
    tears = tears + 1
    assert(false, "Pure-dodging demonstration fired a native tear")
end
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_NPC_UPDATE, freezeCallback, EntityType.ENTITY_SPIDER)
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, damageCallback, EntityType.ENTITY_PLAYER)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, tearCallback)
local function advance(t, bytes)
    if not native.rooms_ready() or finished then
        return
    end
    if not parked then
        actor(1, function()
            origin = Game():GetLevel():GetCurrentRoomIndex()
            assert(Game():GetLevel():GetStage() == 1, "Spider scene must start on floor one")
            for slot = 0, 7 do
                local door = Game():GetRoom():GetDoor(slot)
                if door and door.TargetRoomIndex >= 0 and door.TargetRoomIndex ~= origin then
                    parked = door.TargetRoomIndex
                    break
                end
            end
        end)
        assert(parked, "No separate room for the idle host")
        assert(native.rooms_move(0, parked, 0, -1))
        return
    end
    local positions = native.rooms_positions()
    if positions["0"].index ~= parked then
        return
    end
    assert(positions["1"].index == origin, "Subject escaped the starting room")
    if not armed then
        actor(0, clearFixtureRoom)
        actor(1, function(p)
            clearFixtureRoom()
            assert(p:GetPlayerType() == 0 and p:GetHearts() == 6 and p:GetMaxHearts() == 6)
            assert(p:GetSoulHearts() == 0 and p:GetCollectibleCount() <= 1)
            assert(math.abs(p.MoveSpeed - 1) < 0.001, "Fixture must preserve default Isaac speed")
            local room, center = Game():GetRoom(), Game():GetRoom():GetCenterPos()
            local first, last =
                room:GetGridPosition(0), room:GetGridPosition(room:GetGridSize() - 1)
            local top, bottom = room:GetTopLeftPos(), room:GetBottomRightPos()
            report(
                string.format(
                    "ROOM_BOUNDS physical=%.1f,%.1f:%.1f,%.1f grid=%.1f,%.1f:%.1f,%.1f",
                    top.X,
                    top.Y,
                    bottom.X,
                    bottom.Y,
                    first.X,
                    first.Y,
                    last.X,
                    last.Y
                )
            )
            p.Position, p.Velocity = center - Vector(180, 0), Vector.Zero
            for row = -1, 1 do
                for col = -1, 1 do
                    local pos = center + Vector(col * 40, row * 40)
                    local npc = Isaac.Spawn(EntityType.ENTITY_SPIDER, 0, 0, pos, Vector.Zero, nil)
                        :ToNPC()
                    assert(npc:GetChampionColorIdx() == -1, "Expected ordinary half-heart Spiders")
                    spiders[npc.InitSeed] = { entity = npc, position = pos, health = npc.HitPoints }
                end
            end
            room:SetClear(false)
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door then
                    door:Close(true)
                end
            end
            report(
                "ARMED room="
                    .. origin
                    .. " host_room="
                    .. parked
                    .. " hearts=6 speed="
                    .. p.MoveSpeed
                    .. " spiders=9 spacing=40 firing=disabled"
            )
        end)
        armed, armedAt = true, t
        return
    end
    local alive = 0
    actor(1, function(p)
        for _, entry in pairs(spiders) do
            local npc = entry.entity
            assert(
                npc:Exists() and not npc:IsDead() and npc.HitPoints == entry.health,
                "Spider was killed or damaged"
            )
            alive = alive + 1
            local distance = npc.Position:Distance(entry.position)
            if not released then
                assert(distance < 0.1, "Staged Spider moved before LANBOT input")
            elseif distance > 2 then
                spiderMotion = true
            end
        end
        assert(alive == 9 and tears == 0)
        if not released then
            -- Wire input is 16 big-endian values plus a trigger word per slot.
            -- A real guest movement value proves LANBOT is on before AI starts.
            local movement = 0
            for action = 0, 3 do
                movement = movement | string.unpack(">I2", bytes, 35 + action * 2)
            end
            if t - armedAt >= 90 and movement ~= 0 then
                released, startTick, startMs = true, t, native.api_info().nowMs
                assert(p:GetHearts() == 6, "Subject took damage during staging")
                report("RELEASE tick=" .. t .. " now_ms=" .. startMs .. " guest_input=" .. movement)
            end
            return
        end
        local health = p:GetHearts() + p:GetSoulHearts()
        assert(health <= lastHealth, "Pure-dodging scene gained health")
        local seconds = (native.api_info().nowMs - startMs) / 1000
        if health < lastHealth then
            assert(lastHealth - health == 1, "Ordinary Spider must remove one half heart per hit")
            hits, lastHealth = hits + 1, health
            report(
                string.format(
                    "HIT number=%d wall_s=%.3f simulation_s=%.3f hearts=%d",
                    hits,
                    seconds,
                    (t - startTick) / 30,
                    health
                )
            )
        end
        if lastPosition and p.Position:Distance(lastPosition) > 0.1 then
            actorMotion = actorMotion + 1
        end
        lastPosition = Vector(p.Position.X, p.Position.Y)
        local dead = p:IsDead() or p:IsCoopGhost() or health == 0
        if dead or seconds >= 180 then
            assert(
                spiderMotion and actorMotion > 10,
                "Native Spider/player movement was not observed"
            )
            assert(not dead or hits == 6, "Death did not follow six ordinary half-heart hits")
            finished = true
            report(
                string.format(
                    "RESULT dead=%s wall_s=%.3f simulation_s=%.3f hits=%d hearts=%d spiders_alive=%d tears=%d actor_motion=%d",
                    tostring(dead),
                    seconds,
                    (t - startTick) / 30,
                    hits,
                    health,
                    alive,
                    tears,
                    actorMotion
                )
            )
        elseif t % 120 == 0 then
            report(
                string.format(
                    "STATE wall_s=%.3f hearts=%d x=%.1f y=%.1f spiders_alive=%d",
                    seconds,
                    health,
                    p.Position.X,
                    p.Position.Y,
                    alive
                )
            )
        end
    end)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = baseFrame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    native.test_gamepad(0)
    if not host and s.scene == 2 and native.api_info().ready == 1 and bridge.ready() then
        seenScene = true
        bridge.withView(function()
            local count = 0
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == EntityType.ENTITY_SPIDER then
                    count = count + 1
                end
            end
            if count == 9 then
                firstSeen = firstSeen or native.api_info().nowMs
                if not botStarted and native.api_info().nowMs - firstSeen >= 3000 then
                    command("mode hold")
                    command("on")
                    botStarted = true
                    report("BOT_ACTIVE firing=masked movement=production_lanbot")
                end
            end
        end)
        if botStarted and renders % 120 == 0 then
            command("status")
        end
    elseif not host and seenScene and s.phase == 0 and s.scene == 1 and not s.prepared then
        assert(botStarted and moveInputs > 10 and tears == 0, "Guest did not supply pure movement")
        if not finished then
            finished = true
            report(
                "GUEST_FINISHED move_inputs="
                    .. moveInputs
                    .. " masked_fire="
                    .. maskedFire
                    .. " tears="
                    .. tears
            )
        end
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(capture, function(t, n, b)
        before(t, n, b)
        if host then
            advance(t, b)
        end
    end, collect, restore, present, beginFloor)
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
