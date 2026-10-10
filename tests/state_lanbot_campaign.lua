-- Accelerated first-floor campaign: fixtures enter generated Boss rooms;
-- both LANBOTs supply combat, walking and native exit collision. No scripted
-- player motion, tear spawning, stage transition or victory is permitted.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local baseFrame, baseGate, baseInput = _IsaacLanFrame, native.net_gate, native.input_bot
local bridge = assert(_IsaacLanModules["api/public"])
local owner = { Name = "LANBOT native campaign" }
local renders, linked, chosen, finished, won = 0, false, false, false, false
local endedAt, localProgress, epoch, advanced, modeChanged
local visited, bosses, shots, motion, previous = {}, {}, { 0, 0 }, { 0, 0 }, {}
local fought, floorShots = {}, {}
local snapshots, floorEvents, moveInputs, shootInputs = 0, 0, 0, 0
local stage, stageAt, destination = nil, 0, nil
local winCallback, exitCallback, tearCallback, chestCallback
local chestContacts = 0
local function report(text)
    Isaac.DebugString("LAN_NETWORK LANBOT_CAMPAIGN " .. text)
end
local function command(args)
    local output, response = Isaac.ConsoleOutput, ""
    Isaac.ConsoleOutput = function(text)
        response = response .. text
    end
    local ok, error = pcall(_IsaacLanBotCommand, args)
    Isaac.ConsoleOutput = output
    assert(ok, error)
    assert(not response:find("decision_error", 1, true), response)
    if response:find("error=", 1, true) then
        assert(args == "next" and response:find("error=no_known_exit", 1, true), response)
        return false
    end
    assert(not response:find("LANBOT paused", 1, true), response)
    if args == "status" then
        report(response:gsub("\n", ""))
    end
    return true
end
native.input_bot = function(active, buttons)
    if active == 1 then
        moveInputs = moveInputs + ((buttons & 15) ~= 0 and 1 or 0)
        shootInputs = shootInputs + ((buttons & 240) ~= 0 and 1 or 0)
    end
    return baseInput(active, buttons)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function bossRoom()
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        if d.Data and d.SafeGridIndex >= 0 and d.Data.Type == RoomType.ROOM_BOSS then
            return d.SafeGridIndex
        end
    end
    error("No generated native Boss room")
end
local function observeFloor()
    local current = Game():GetLevel():GetStage()
    if not visited[current] then
        visited[current] = true
        report("FLOOR stage=" .. current)
    end
end
local function observeBoss(kind, variant)
    if kind == EntityType.ENTITY_THE_LAMB or kind == EntityType.ENTITY_ISAAC and variant == 1 then
        bosses[kind .. ":" .. variant] = true
    end
end
local function botStep()
    local info = native.api_info()
    if info.ready ~= 1 or not bridge.ready() or won then
        return
    end
    local key = info.runId .. ":" .. info.worldEpoch
    if epoch ~= key then
        epoch, advanced, modeChanged = key, false, false
        command("mode hold")
        command("on")
        report("BOT_ACTIVE epoch=" .. key)
    end
    local readyExit = false
    bridge.withView(function()
        local room = Game():GetRoom()
        if room:GetType() == RoomType.ROOM_BOSS and room:IsClear() then
            for index = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(index)
                if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR and grid.State == 1 then
                    readyExit = true
                    if renders % 120 == 0 then
                        local sprite = grid.GetSprite and grid:GetSprite()
                        report(
                            "NATIVE_EXIT_OBSERVED stage="
                                .. Game():GetLevel():GetStage()
                                .. " state="
                                .. grid.State
                                .. " animation="
                                .. (sprite and sprite:GetAnimation() or "-")
                        )
                    end
                end
            end
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if
                    e.Type == EntityType.ENTITY_PICKUP
                        and e.Variant == PickupVariant.PICKUP_BIGCHEST
                        and e:ToPickup().Wait <= 0
                    or e.Type == EntityType.ENTITY_EFFECT
                        and e.Variant == EffectVariant.HEAVEN_LIGHT_DOOR
                then
                    readyExit = true
                end
            end
        end
    end)
    if readyExit and not advanced then
        if not modeChanged then
            command("mode run")
            modeChanged = true
        end
        if command("next") then
            advanced = true
            report("BOT_NATIVE_EXIT_REQUEST stage=" .. Game():GetLevel():GetStage())
        end
    end
    if renders % 120 == 0 then
        command("status")
    end
end
chestCallback = function(_, pickup, collider)
    local p = collider:ToPlayer()
    if host and p and chestContacts < 30 then
        chestContacts = chestContacts + 1
        report(
            "CHEST_CONTACT stage="
                .. Game():GetLevel():GetStage()
                .. " state="
                .. pickup.State
                .. " wait="
                .. pickup.Wait
                .. " controller="
                .. p.ControllerIndex
                .. " distance="
                .. p.Position:Distance(pickup.Position)
                .. " animation="
                .. p:GetSprite():GetAnimation()
                .. " extra_done="
                .. tostring(p:IsExtraAnimationFinished())
        )
    end
end
tearCallback = function(_, tear)
    if host then
        local p = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        if p and (p.ControllerIndex == 1 or p.ControllerIndex == 2) then
            shots[p.ControllerIndex] = shots[p.ControllerIndex] + 1
            local floor = Game():GetLevel():GetStage()
            local evidence = floorShots[floor] or { 0, 0 }
            floorShots[floor] = evidence
            evidence[p.ControllerIndex] = evidence[p.ControllerIndex] + 1
            -- Preserve the native intro: do not let the guest fixture kill
            -- the Boss before the host has even received ordinary input.
            if evidence[1] > 0 and evidence[2] > 0 then
                tear.CollisionDamage = 100
            end
        end
    end
end
winCallback = function(_, gameOver)
    assert(not gameOver and not won, "Campaign requires exactly one native win")
    for i = 1, 8 do
        assert(visited[i], "Campaign skipped floor " .. i)
    end
    assert(visited[10] and visited[11], "Campaign skipped terminal route floors")
    assert(next(bosses), "Native terminal Boss was not observed")
    assert(moveInputs > 20 and shootInputs > 20, "LANBOT did not supply real movement and firing")
    if host then
        for _, floor in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 10, 11 }) do
            assert(
                fought[floor]
                    and floorShots[floor]
                    and floorShots[floor][1] > 0
                    and floorShots[floor][2] > 0,
                "Campaign did not fight native Boss floor " .. floor
            )
        end
        assert(
            shots[1] > 20 and shots[2] > 20 and motion[1] > 20 and motion[2] > 20,
            "Both LANBOT actors must actually walk and fire"
        )
        report(
            "ACTOR_EVIDENCE host_shots="
                .. shots[1]
                .. " guest_shots="
                .. shots[2]
                .. " host_motion="
                .. motion[1]
                .. " guest_motion="
                .. motion[2]
        )
    else
        assert(snapshots > 100 and floorEvents >= 9, "Replica missed native campaign state")
    end
    won, endedAt = true, native.api_info().nowMs
    report("NATIVE_WIN first_floor=1 movement=lanbot firing=lanbot exits=lanbot")
end
exitCallback = function()
    endedAt = native.api_info().nowMs
    report("EXIT_CALLBACK won=" .. tostring(won))
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, tearCallback)
Isaac.AddCallback(
    owner,
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    chestCallback,
    PickupVariant.PICKUP_BIGCHEST
)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_END, winCallback)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, exitCallback)
function _IsaacLanFrame()
    renders = renders + 1
    if EID and EID.Config then
        EID.Config.DisableStartOfRunWarnings = true
    end
    if not linked and renders >= (host and 300 or 360) then
        linked, localProgress = true, native.net_progress()
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
    native.test_gamepad(won and s.scene == 3 and renders % 30 < 5 and 4096 or 0)
    botStep()
    if
        won
        and not finished
        and native.api_info().nowMs - endedAt > 3000
        and s.phase == 0
        and s.scene == 1
        and not s.prepared
    then
        local progress = native.net_progress()
        for i = 2, 643 do
            assert(localProgress:byte(i) == 0 or progress:byte(i) == 1, "Lost prior achievement")
        end
        for _, id in ipairs({ 636, 637, 640 }) do
            assert(progress:byte(id + 2) == localProgress:byte(id + 2), "Inherited host progress")
        end
        assert(progress:sub(-4) == localProgress:sub(-4), "Replaced private progress counter")
        finished = true
        report("LOCAL_PROGRESS_RESTORED")
        report(
            "PASS full LANBOT campaign move_inputs="
                .. moveInputs
                .. " shoot_inputs="
                .. shootInputs
        )
    end
    return s
end
local function advance(t)
    if not native.rooms_ready() or won then
        return
    end
    observeFloor()
    local current = Game():GetLevel():GetStage()
    if stage ~= current then
        stage, stageAt, destination, previous = current, t, nil, {}
    end
    for slot = 0, 1 do
        actor(slot, function(p)
            p:SetMinDamageCooldown(10000)
            local sample = previous[slot]
            if sample then
                local distance = p.Position:Distance(sample)
                if distance > 0.01 and distance < 20 then
                    motion[slot + 1] = motion[slot + 1] + 1
                end
            end
            previous[slot] = Vector(p.Position.X, p.Position.Y)
            if current >= 10 and t % 60 == 0 then
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    local pickup = e.Type == EntityType.ENTITY_PICKUP and e:ToPickup()
                    if pickup and e.Variant == PickupVariant.PICKUP_BIGCHEST then
                        report(
                            "CHEST_STATE slot="
                                .. slot
                                .. " stage="
                                .. current
                                .. " state="
                                .. pickup.State
                                .. " wait="
                                .. pickup.Wait
                                .. " collision="
                                .. pickup.EntityCollisionClass
                                .. " animation="
                                .. pickup:GetSprite():GetAnimation()
                                .. " distance="
                                .. p.Position:Distance(pickup.Position)
                                .. " player_collision="
                                .. p.EntityCollisionClass
                                .. " player_animation="
                                .. p:GetSprite():GetAnimation()
                                .. " extra_done="
                                .. tostring(p:IsExtraAnimationFinished())
                        )
                    end
                end
            end
            if not p:HasCollectible(CollectibleType.COLLECTIBLE_SPOON_BENDER) then
                p:AddCollectible(CollectibleType.COLLECTIBLE_SPOON_BENDER)
                p:AddCollectible(CollectibleType.COLLECTIBLE_POLAROID)
                p:AddCollectible(CollectibleType.COLLECTIBLE_NEGATIVE)
                p:AddKeys(99 - p:GetNumKeys())
                p:AddCoins(99 - p:GetNumCoins())
                p:AddBombs(99 - p:GetNumBombs())
            end
        end)
    end
    if not destination and t - stageAt > 90 then
        destination = bossRoom()
        for slot = 0, 1 do
            assert(native.rooms_move(slot, destination, 0, -1))
        end
        report("BOSS_ENTRY_FIXTURE stage=" .. stage .. " room=" .. destination)
    end
    local positions = native.rooms_positions()
    if
        destination
        and positions["0"].index == destination
        and positions["1"].index == destination
    then
        actor(1, function()
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:ToNPC() and e:IsBoss() then
                    observeBoss(e.Type, e.Variant)
                    if not fought[current] then
                        fought[current] = true
                        report(
                            "NATIVE_BOSS_FIGHT stage="
                                .. current
                                .. " type="
                                .. e.Type
                                .. " variant="
                                .. e.Variant
                        )
                    end
                elseif
                    e.Type == EntityType.ENTITY_PICKUP
                    and e.Variant == PickupVariant.PICKUP_COLLECTIBLE
                then
                    -- Keep the declared weapon fixture stable across floors.
                    e:Remove()
                end
            end
        end)
    end
    assert(t - stageAt < 7200, "LANBOT campaign stalled on floor " .. current)
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        capture,
        function(t, n, b)
            before(t, n, b)
            if host then
                advance(t)
            end
        end,
        collect,
        function(bytes, t, ack)
            if restore(bytes, t, ack) == false then
                return false
            end
            snapshots = snapshots + 1
            observeFloor()
            bridge.withView(function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToNPC() then
                        observeBoss(e.Type, e.Variant)
                    end
                end
            end)
            return true
        end,
        present,
        function(...)
            floorEvents = floorEvents + 1
            return beginFloor(...)
        end
    )
end
