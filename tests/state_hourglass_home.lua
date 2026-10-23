local testInput = assert(_IsaacLanTestInput)
-- One group of four processes. Native route selection is never patched by the fixture.
local native, port = assert(_IsaacLan), _IsaacLanTest.port
local file = assert(io.open("./lan-test-role.txt", "r"))
local ordinal = assert(({ host = 0, client = 1, client2 = 2, client3 = 3 })[file:read("*l")])
file:close()
local host = ordinal == 0
local hourglass = CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
local marker = CollectibleType.COLLECTIBLE_PENTAGRAM
local cases = {}
for _, players in ipairs(hourglassPlayers or { 2, 3, 4 }) do
    local difficulty = players == 3 and 1 or 0
    cases[#cases + 1] = {
        name = "home-" .. players,
        players = players,
        home = true,
        user = players == 3 and 0 or players == 4 and 3 or 1,
        mover = players == 3 and 1 or 0,
        restart = players ~= 2,
        difficulty = difficulty,
    }
    cases[#cases + 1] = {
        name = "rewind-host-" .. players,
        players = players,
        home = false,
        user = 0,
        mover = 0,
        difficulty = difficulty,
    }
    cases[#cases + 1] = {
        name = "rewind-guest-" .. players,
        players = players,
        home = false,
        user = 1,
        mover = 1,
        difficulty = difficulty,
    }
end
local current, case, renders, verified = 0, nil, 0, -1
local linked, chosen, started, participated, menuDone, reported =
    false, false, false, false, false, false
local startAt, exitedAt, phase, phaseAt, lastHeartbeat = 0, nil, "init", 0, 0
local sourceRoom, targetRoom, checkpoint, useEpoch, walkStart, walkOrigins, walkDistances
local homeEvents, rewindEvents, restartEvents, snapshots, replicaArrived = 0, 0, 0, 0, false
local restartEpoch
local leaveRequested, rejoinRequested, rejoinRestored, sawDisconnected = false, false, false, false
local rejoinReported, runId = false, nil
local owner = { Name = "Native Home and hourglass team acceptance" }
local function read(name)
    local f = io.open(hourglassCoordination .. "/" .. name, "r")
    if not f then
        return nil
    end
    local value = f:read("*a")
    f:close()
    return value ~= "" and value or nil
end
local function write(name, value)
    local f = assert(io.open(hourglassCoordination .. "/" .. name, "w"))
    f:write(value)
    f:close()
end
local function report(value)
    Isaac.DebugString(
        "LAN_NETWORK HOURGLASS_HOME case=" .. (case and case.name or "boot") .. " " .. value
    )
end
local function mark(name, tick)
    phase, phaseAt = name, tick
    report("STEP " .. name .. " tick=" .. tick .. " ms=" .. native.api_info().nowMs)
end
local function actor(slot, call)
    assert(native.rooms_with_player(slot, function()
        call(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function clear()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function usableParty()
    if
        not native.rooms_ready()
        or native.presentation_active()
        or native.rooms_connected() ~= (1 << case.players) - 1
    then
        return false
    end
    local usable = true
    for slot = 0, case.players - 1 do
        actor(slot, function(player)
            usable = usable
                and not player:IsDead()
                and not player:IsCoopGhost()
                and player:AreControlsEnabled()
                and player:IsExtraAnimationFinished()
        end)
    end
    return usable
end
local function otherRoom(source, adjacent)
    local level = Game():GetLevel()
    for i = 0, level:GetRooms().Size - 1 do
        local room = level:GetRooms():Get(i)
        local delta = math.abs(room.SafeGridIndex - source)
        if
            room.Data
            and room.SafeGridIndex >= 0
            and room.SafeGridIndex ~= source
            and room.Data.Type == RoomType.ROOM_DEFAULT
            and (level:GetStage() == 13 or room.Data.Shape == RoomShape.ROOMSHAPE_1x1)
            and (not adjacent or delta == 1 or delta == 13)
            and (level:GetStage() ~= 13 or room.Data.Variant ~= 4)
        then
            return room.SafeGridIndex
        end
    end
    error("No safe ordinary room for the hourglass fixture")
end
local function roster()
    local values, positions = {}, native.rooms_positions()
    for slot = 0, case.players - 1 do
        actor(slot, function(player)
            values[slot + 1] = {
                index = positions[tostring(slot)].index,
                dimension = positions[tostring(slot)].dimension,
                x = player.Position.X,
                y = player.Position.Y,
                hearts = player:GetHearts(),
                maxHearts = player:GetMaxHearts(),
            }
        end)
    end
    return values
end
local function checkInventory(player, slot)
    assert(
        player.ControllerIndex == slot + 1 and player:GetPlayerType() == PlayerType.PLAYER_ISAAC,
        "Original controller or character changed"
    )
    assert(
        player:GetNumCoins() == (case.home and 27 or 20),
        "Native route lost or incorrectly rewound shared coins"
    )
    assert(player:HasCollectible(hourglass), "Native route lost the real hourglass")
    assert(player:GetCollectibleNum(slot + 1, true) == 1, "Native route lost a player's passive")
    assert(
        player:HasCollectible(marker) == case.home,
        "Home/rewind restored the wrong inventory version"
    )
    for other = 0, case.players - 1 do
        if other ~= slot then
            assert(not player:HasCollectible(other + 1), "Player inventories were exchanged")
        end
    end
end
local function checkTeam(rewound)
    local level, positions = Game():GetLevel(), native.rooms_positions()
    assert(
        level:GetStage() == (case.home and 13 or 1) and level:GetStageType() == 0,
        "Team reached a different floor"
    )
    for slot = 0, case.players - 1 do
        actor(slot, function(player)
            checkInventory(player, slot)
            assert(player.Visible, "Native transition left a player hidden")
            if rewound then
                local expected = checkpoint[slot + 1]
                local actual = positions[tostring(slot)]
                assert(
                    actual.index == expected.index and actual.dimension == expected.dimension,
                    "Rewind did not restore a saved team room"
                )
                assert(
                    player.Position:Distance(Vector(expected.x, expected.y)) < 2,
                    "Rewind did not restore a saved position"
                )
                assert(
                    player:GetHearts() == expected.hearts
                        and player:GetMaxHearts() == expected.maxHearts,
                    "Rewind did not restore health"
                )
            end
        end)
    end
end
local function advance(t)
    if phase == "init" then
        if t < 30 or not usableParty() then
            return
        end
        local level = Game():GetLevel()
        sourceRoom = level:GetStartingRoomIndex()
        assert(
            sourceRoom == 84 and level:GetStage() == 1 and level:GetStageType() == 0,
            "Fixed seed did not start in ordinary Basement room 84"
        )
        for slot = 0, case.players - 1 do
            actor(slot, function(player)
                assert(
                    Game():GetLevel():GetCurrentRoomIndex() == sourceRoom
                        and Game():GetRoom():IsFirstVisit(),
                    "Fixture no longer has a first-visit starting room"
                )
                clear()
                player:AddCollectible(hourglass)
                player:AddCollectible(slot + 1)
                player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                player:SetMinDamageCooldown(10000)
                player.Position, player.Velocity = Vector(240 + slot * 55, 300), Vector.Zero
                if slot == 0 then
                    player:AddCoins(20 - player:GetNumCoins())
                end
            end)
        end
        targetRoom = otherRoom(sourceRoom, true)
        mark("prepared", t)
    elseif phase == "prepared" and t - phaseAt > 30 and usableParty() then
        if case.restart then
            restartEpoch = native.api_info().worldEpoch
            actor(0, function(player)
                player:UseActiveItem(CollectibleType.COLLECTIBLE_R_KEY, UseFlag.USE_NOANIM)
            end)
            report("NATIVE_R_KEY epoch=" .. restartEpoch)
            mark("r-key", t)
        else
            if case.home then
                report("FRESH_START_PASS native_start_room_without_r_key")
            else
                checkpoint = roster()
            end
            assert(native.rooms_move(case.mover, targetRoom, 0, -1))
            mark("checkpoint-entry", t)
        end
    elseif phase == "r-key" and t - phaseAt > 180 and usableParty() then
        local level = Game():GetLevel()
        assert(
            native.api_info().worldEpoch == restartEpoch + 1,
            "R Key did not produce exactly one new world"
        )
        assert(
            level:GetStage() == 1 and level:GetStageType() <= 2,
            "R Key did not create an ordinary first floor"
        )
        sourceRoom = level:GetStartingRoomIndex()
        for slot = 0, case.players - 1 do
            actor(slot, function(player)
                assert(
                    native.rooms_positions()[tostring(slot)].index == sourceRoom
                        and Game():GetRoom():IsFirstVisit(),
                    "R Key did not leave every player in the first-visit starting room"
                )
                assert(
                    player:GetNumCoins() == 20
                        and player:HasCollectible(hourglass)
                        and player:GetCollectibleNum(slot + 1, true) == 1,
                    "R Key lost original inventory"
                )
                clear()
                player:SetMinDamageCooldown(10000)
            end)
        end
        targetRoom = otherRoom(sourceRoom, true)
        report(
            "R_KEY_PASS epoch="
                .. native.api_info().worldEpoch
                .. " room="
                .. sourceRoom
                .. " type="
                .. level:GetStageType()
        )
        assert(native.rooms_move(case.mover, targetRoom, 0, -1))
        mark("checkpoint-entry", t)
    elseif phase == "checkpoint-entry" and t - phaseAt > 90 and usableParty() then
        local positions = native.rooms_positions()
        for slot = 0, case.players - 1 do
            assert(
                positions[tostring(slot)].index == (slot == case.mover and targetRoom or sourceRoom),
                "Initial split did not enter the intended room"
            )
        end
        actor(case.mover == 0 and 1 or 0, function()
            assert(
                Game():GetRoom():IsFirstVisit(),
                "The observing starting-room viewport is no longer first visit"
            )
        end)
        for slot = 0, case.players - 1 do
            actor(slot, function(player)
                clear()
                player:AddCollectible(marker)
                if slot == 0 then
                    player:AddCoins(7)
                end
            end)
        end
        useEpoch = native.api_info().worldEpoch
        write("used-" .. current .. ".txt", tostring(useEpoch))
        report(
            "NATIVE_USE user="
                .. case.user
                .. " host_room="
                .. positions["0"].index
                .. " guest_room="
                .. positions["1"].index
                .. " epoch="
                .. useEpoch
        )
        actor(case.user, function(player)
            player:UseActiveItem(hourglass, 0, -1)
        end)
        mark("transition", t)
    elseif phase == "transition" and t - phaseAt > 180 and usableParty() then
        assert(
            native.api_info().worldEpoch == useEpoch + 1,
            "One use produced multiple or missing world transitions"
        )
        checkTeam(not case.home)
        local positions = native.rooms_positions()
        if case.home then
            for slot = 1, case.players - 1 do
                assert(
                    positions[tostring(slot)].index == positions["0"].index
                        and positions[tostring(slot)].dimension == positions["0"].dimension,
                    "Home did not gather the whole team"
                )
            end
        end
        report(
            "TRANSITION_PASS stage="
                .. Game():GetLevel():GetStage()
                .. " type=0 epoch="
                .. native.api_info().worldEpoch
                .. " controls=true coins="
                .. (case.home and 27 or 20)
        )
        write("arrived-" .. current .. ".txt", "ready")
        mark("arrival-visual", t)
    elseif phase == "arrival-visual" and t - phaseAt > 90 and usableParty() then
        walkOrigins, walkDistances = {}, {}
        for slot = 0, case.players - 1 do
            actor(slot, function(player)
                clear()
                local room = Game():GetRoom()
                player.Position = room:FindFreePickupSpawnPosition(
                    room:GetCenterPos() + Vector(-90 + slot * 55, 40),
                    0,
                    true
                )
                player.Velocity = Vector.Zero
                walkOrigins[slot + 1], walkDistances[slot + 1] = player.Position, 0
            end)
        end
        walkStart = t + 30
        write("walk-" .. current .. ".txt", tostring(walkStart))
        mark("walk", t)
    elseif phase == "walk" then
        for slot = 0, case.players - 1 do
            actor(slot, function(player)
                walkDistances[slot + 1] = math.max(
                    walkDistances[slot + 1],
                    player.Position:Distance(walkOrigins[slot + 1])
                )
            end)
        end
        if t > walkStart + 60 and usableParty() then
            for slot = 0, case.players - 1 do
                assert(
                    walkDistances[slot + 1] > 5,
                    "Normal movement remained locked for slot " .. slot
                )
                report("WALK_PASS slot=" .. slot .. " distance=" .. walkDistances[slot + 1])
            end
            checkTeam(false)
            local index = native.rooms_positions()["0"].index
            targetRoom = otherRoom(index, false)
            assert(native.rooms_move(case.players - 1, targetRoom, 0, -1))
            mark("post-transition-split", t)
        end
    elseif phase == "post-transition-split" and t - phaseAt > 90 and usableParty() then
        local positions = native.rooms_positions()
        assert(
            positions[tostring(case.players - 1)].index == targetRoom
                and positions["0"].index ~= targetRoom,
            "Post-transition split did not preserve separate rooms"
        )
        actor(case.players - 1, clear)
        checkTeam(false)
        report("SPLIT_PASS stage=" .. Game():GetLevel():GetStage())
        if case.home and case.players == 4 then
            write("rejoin-" .. current .. ".txt", "leave")
            mark("rejoin", t)
        else
            mark("exit-ready", t)
        end
    elseif phase == "rejoin" then
        local mask = native.rooms_connected()
        if mask ~= 15 then
            sawDisconnected = true
        end
        if
            sawDisconnected
            and mask == 15
            and read("rejoined-" .. current .. ".txt")
            and usableParty()
        then
            checkTeam(false)
            report("HOME_REJOIN_PASS original_slot=3 stage=13")
            mark("exit-ready", t)
        end
    elseif phase == "exit-ready" and t - phaseAt > 60 then
        checkTeam(false)
        write("complete-" .. current .. ".txt", "ready")
        mark("save-exit", t)
        assert(native.net_command(3))
    end
    assert(t - phaseAt < 1800, "Hourglass phase stalled: " .. phase)
end
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    exitedAt = native.api_info().nowMs
    report("NATIVE_EXIT")
end)
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
function _IsaacLanFrame()
    renders = renders + 1
    local status = baseFrame()
    local now = native.api_info().nowMs
    native.test_gamepad(0)
    if renders == 60 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if renders == 300 then
        write("boot-" .. ordinal .. ".txt", "ready")
    end
    for slot = 0, 3 do
        if not read("boot-" .. slot .. ".txt") then
            return status
        end
    end
    local requested = tonumber(read("case.txt"))
    if not requested then
        return status
    end
    if requested > #cases then
        if not reported then
            reported = true
            Isaac.DebugString("LAN_NETWORK PASS native Home hourglass team")
        end
        return status
    end
    if requested ~= current then
        if status.phase ~= 0 or status.scene ~= 1 or status.prepared then
            return status
        end
        current, case = requested, assert(cases[requested])
        linked, chosen, started, participated, menuDone = false, false, false, false, false
        startAt, exitedAt, phase, phaseAt = now + 2000, nil, "init", 0
        homeEvents, rewindEvents, restartEvents, snapshots, replicaArrived = 0, 0, 0, 0, false
        restartEpoch = nil
        sourceRoom, targetRoom, checkpoint, useEpoch, walkStart = nil, nil, nil, nil, nil
        walkOrigins, walkDistances = nil, nil
        leaveRequested, rejoinRequested, rejoinRestored, sawDisconnected =
            false, false, false, false
        rejoinReported, runId = false, nil
        report(
            "BEGIN ordinal="
                .. ordinal
                .. " players="
                .. case.players
                .. " difficulty="
                .. case.difficulty
        )
    end
    if ordinal >= case.players then
        return status
    end
    if status.phase == 4 or status.phase == 9 and status.error ~= "" then
        error("Hourglass session failed: " .. status.error)
    end
    verified = status.verified
    if not linked and now >= startAt + ordinal * 900 and status.scene == 1 then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
    end
    if status.phase == 2 then
        if not chosen then
            chosen = true
            assert(native.net_choose(0, 1))
        end
        local ready = status.players == case.players
        for slot = 0, case.players - 1 do
            ready = ready and status["ready" .. slot] == 1
        end
        if host and ready and not started then
            started = true
            _IsaacLanCommand("start", "YV039KQF:" .. case.difficulty .. ":0:0:0:0")
        end
    end
    if ordinal == 3 and case.home and case.players == 4 then
        if not leaveRequested and read("rejoin-" .. current .. ".txt") and status.phase == 3 then
            leaveRequested = true
            assert(native.net_command(4))
            report("HOME_REJOIN_LEAVE slot=3")
            return status
        elseif
            leaveRequested
            and not rejoinRequested
            and exitedAt
            and status.phase == 0
            and status.scene == 1
            and not status.prepared
            and now - exitedAt > 1500
        then
            rejoinRequested, exitedAt = true, nil
            _IsaacLanCommand("join", "127.0.0.1:" .. port)
            report("HOME_REJOIN_REQUEST")
        end
    end
    local info = native.api_info()
    if info.ready == 1 then
        participated = true
        runId = runId or info.runId
        assert(
            info.slot == ordinal
                and info.players == case.players
                and info.challenge == 0
                and status.difficulty == case.difficulty
                and info.runId == runId,
            "Session identity or original slot changed"
        )
        if rejoinRequested and rejoinRestored and not rejoinReported then
            rejoinReported = true
            assert(Game():GetLevel():GetStage() == 13 and Game():GetLevel():GetStageType() == 0)
            write("rejoined-" .. current .. ".txt", "ready")
            report("HOME_REJOIN_RESTORED slot=3 stage=13")
        end
    end
    if
        participated
        and exitedAt
        and not menuDone
        and (not leaveRequested or rejoinRequested)
        and status.phase == 0
        and status.scene == 1
        and not status.prepared
        and now - exitedAt > 2000
    then
        assert(read("complete-" .. current .. ".txt"), "Case exited before its checks completed")
        assert(host or snapshots > 100 and replicaArrived, "Replica did not validate the new world")
        assert(
            host
                or homeEvents == (case.home and 1 or 0)
                    and rewindEvents == (case.home and 0 or 1)
                    and restartEvents == (case.restart and 1 or 0),
            "Reliable Home/rewind transaction was duplicated or omitted"
        )
        menuDone = true
        write("done-" .. current .. "-" .. ordinal .. ".txt", "done")
        report(
            "PASS home_events="
                .. homeEvents
                .. " rewind_events="
                .. rewindEvents
                .. " restart_events="
                .. restartEvents
                .. " snapshots="
                .. snapshots
        )
    end
    if host and menuDone then
        local done = true
        for slot = 0, case.players - 1 do
            done = done and read("done-" .. current .. "-" .. slot .. ".txt") ~= nil
        end
        if done then
            write("case.txt", tostring(current + 1))
        end
    end
    if now - lastHeartbeat > 10000 then
        lastHeartbeat = now
        report("HEARTBEAT phase=" .. status.phase .. " step=" .. phase .. " tick=" .. verified)
    end
    assert(menuDone or now - startAt < 180000, "Native hourglass case stalled")
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        function()
            local start = tonumber(read("walk-" .. current .. ".txt"))
            local moving = start and verified >= start and verified < start + 30
            return testInput.buttons(moving and 1 << ButtonAction.ACTION_RIGHT or 0)
        end,
        function(t, n, bytes)
            before(t, n, bytes)
            advance(t)
        end,
        collect,
        function(bytes, t, ack, betweenUpdates, stable)
            if restore(bytes, t, ack, betweenUpdates, stable) == false then
                return false
            end
            snapshots = snapshots + 1
            local value = _IsaacLanState.decode(bytes, stable)
            local epoch = tonumber(read("used-" .. current .. ".txt"))
            if epoch and value[14] > epoch then
                local level = Game():GetLevel()
                assert(
                    value[14] == epoch + 1
                        and level:GetStage() == value[4]
                        and level:GetStageType() == value[5],
                    "Replica did not apply the single authoritative world"
                )
                assert(
                    value[4] == (case.home and 13 or 1) and value[5] == 0,
                    "Replica viewport reselected a different native route"
                )
                local expectedPlayers = case.players
                if
                    case.home
                    and case.players == 4
                    and read("rejoin-" .. current .. ".txt")
                    and native.rooms_connected() == 7
                then
                    expectedPlayers = 3
                end
                assert(#value[9] == expectedPlayers, "Transition lost a connected replica actor")
                for _, entry in ipairs(value[9]) do
                    assert(
                        expectedPlayers ~= 3 or case.players ~= 4 or entry[2] ~= 4,
                        "Disconnected P4 remained in the active replica roster"
                    )
                    checkInventory(Isaac.GetPlayer(entry[1]), entry[2] - 1)
                end
                if not replicaArrived then
                    replicaArrived = true
                    report(
                        "REPLICA_ARRIVED stage="
                            .. value[4]
                            .. " type="
                            .. value[5]
                            .. " epoch="
                            .. value[14]
                    )
                end
                if rejoinRequested and #value[9] == 4 and native.rooms_connected() == 15 then
                    rejoinRestored = true
                end
            end
            return true
        end,
        present,
        function(epoch, stage, stageType, animation, same, rewind, restart, cinematic, ...)
            local length = #rewind
            if restart == 1 then
                restartEvents = restartEvents + 1
                assert(
                    case.restart
                        and length == 0
                        and animation == 0
                        and restartEvents == 1
                        and homeEvents == 0
                        and rewindEvents == 0,
                    "Expected one real R Key before Home"
                )
            elseif length == 0 then
                homeEvents = homeEvents + 1
                assert(
                    case.home
                        and animation == 6
                        and not same
                        and homeEvents == 1
                        and rewindEvents == 0,
                    "Expected exactly one native Home transaction"
                )
            else
                rewindEvents = rewindEvents + 1
                assert(
                    not case.home and animation == 12 and rewindEvents == 1 and homeEvents == 0,
                    "Expected exactly one native rewind transaction"
                )
            end
            report(
                "FLOOR_EVENT epoch="
                    .. epoch
                    .. " source="
                    .. stage
                    .. ":"
                    .. stageType
                    .. " animation="
                    .. animation
                    .. " rewind_bytes="
                    .. length
                    .. " restart="
                    .. restart
            )
            return beginFloor(
                epoch,
                stage,
                stageType,
                animation,
                same,
                rewind,
                restart,
                cinematic,
                ...
            )
        end
    )
end
