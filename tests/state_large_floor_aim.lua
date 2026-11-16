-- All cases share native processes. Coordinator files belong to this test run.
local native, input = assert(_IsaacLan), assert(_IsaacLanTestInput)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local file = assert(io.open("./lan-test-role.txt"))
local ordinal = assert(({ host = 0, client = 1, client2 = 2, client3 = 3 })[file:read("*l")])
file:close()
local cases = {}
if not challengeFilter or challengeFilter == 1004 then
    cases[#cases + 1] = { id = 1004, players = 2 }
end
if not challengeFilter or challengeFilter == 1005 then
    for players = 2, challengeMaxPlayers do
        cases[#cases + 1] = { id = 1005, players = players }
    end
end
local function read(name)
    local handle = io.open(challengeCoordination .. "/" .. name .. ".txt")
    if not handle then
        return
    end
    local value = handle:read("*a")
    handle:close()
    return value
end
local function write(name, value)
    local handle = assert(io.open(challengeCoordination .. "/" .. name .. ".txt", "w"))
    handle:write(tostring(value))
    handle:close()
end
local current, case, step, stepAt, startAt = 0, nil, "init", 0, 0
local linked, chosen, started, participated, complete = false, false, false, false, false
local snapshots, previous, phaseSamples, shotOwners = 0, 0, 0, {}
local reconnectRequested, reconnectJoined, reconnectAt = false, false, 0
local nextFloor, goalRoom, trophy, originalRoom
local appliedInputs
local inputRooms = {}
local renders = 0
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
local function report(message)
    Isaac.DebugString("LAN_NETWORK LARGE_AIM case=" .. current .. " " .. message)
end
local function mark(name, tick)
    step, stepAt, phaseSamples, shotOwners = name, tick, 0, {}
    write("mode", name)
    report(name .. " tick=" .. tick)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local directions = { Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) }
local firing = {
    ButtonAction.ACTION_SHOOTRIGHT,
    ButtonAction.ACTION_SHOOTDOWN,
    ButtonAction.ACTION_SHOOTLEFT,
    ButtonAction.ACTION_SHOOTUP,
}
local moving = {
    ButtonAction.ACTION_UP,
    ButtonAction.ACTION_LEFT,
    ButtonAction.ACTION_DOWN,
    ButtonAction.ACTION_RIGHT,
}
local motion = { Vector(0, -1), Vector(-1, 0), Vector(0, 1), Vector(1, 0) }
local function pointer(seat)
    return Vector(280, 360) + directions[seat + 1] * 300
end
local function checkAim(info, mouse, moves)
    for slot = 0, case.players - 1 do
        if info.connected & (1 << slot) ~= 0 then
            actor(slot, function(player)
                local source = (slot + case.players - 1) % case.players
                local expected = info.connected & (1 << source) ~= 0 and directions[source + 1]
                    or Vector.Zero
                if mouse then
                    local received = input.decode(appliedInputs, slot).pointer
                    local cursor = pointer(source)
                    assert(
                        received.active and received.x == cursor.X and received.y == cursor.Y,
                        "Rotated pointer bytes differ from the opening source seat"
                    )
                    local offset = pointer(source) - player.Position
                    expected = math.abs(offset.X) > math.abs(offset.Y) and Vector(offset.X, 0)
                        or Vector(0, offset.Y)
                    expected = expected:Normalized()
                end
                local actual = player:GetShootingInput()
                assert(
                    mouse or (actual - expected):LengthSquared() < 0.001,
                    string.format(
                        "Wrong shooter seat=%d phase=%s actual=%.3f,%.3f expected=%.3f,%.3f",
                        slot,
                        step,
                        actual.X,
                        actual.Y,
                        expected.X,
                        expected.Y
                    )
                )
                if moves then
                    assert(
                        (player:GetMovementInput() - motion[slot + 1]):LengthSquared() < 0.001,
                        "Movement changed owner"
                    )
                end
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity.Type == EntityType.ENTITY_TEAR and entity.SpawnerEntity then
                        local owner = entity.SpawnerEntity:ToPlayer()
                        if owner and not mouse then
                            shotOwners[owner.ControllerIndex] = true
                        elseif
                            owner
                            and owner.ControllerIndex == slot + 1
                            and entity.FrameCount <= 4
                            and entity.Velocity:LengthSquared() > 1
                        then
                            assert(
                                expected:Dot(entity.Velocity:Normalized()) > 0.95,
                                string.format(
                                    "Mouse tear seat=%d position=%.2f,%.2f velocity=%.2f,%.2f expected=%.2f,%.2f frame=%d",
                                    slot,
                                    player.Position.X,
                                    player.Position.Y,
                                    entity.Velocity.X,
                                    entity.Velocity.Y,
                                    expected.X,
                                    expected.Y,
                                    entity.FrameCount
                                )
                            )
                            shotOwners[slot + 1] = true
                        end
                    end
                end
            end)
        end
    end
    phaseSamples = phaseSamples + 1
end
local function park()
    for slot = 0, case.players - 1 do
        if native.api_info().connected & (1 << slot) ~= 0 then
            actor(slot, function(player)
                local game, room = Game(), Game():GetRoom()
                local index = game:GetLevel():GetCurrentRoomIndex()
                if
                    case.id == 1005
                    and step ~= "goal-floor"
                    and step ~= "boss"
                    and step ~= "trophy"
                    and not inputRooms[index]
                then
                    inputRooms[index] = true
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        if entity:IsActiveEnemy(false) then
                            entity:Remove()
                        end
                    end
                    for gridIndex = 0, room:GetGridSize() - 1 do
                        local grid = room:GetGridEntity(gridIndex)
                        if
                            grid
                            and grid:GetType() ~= GridEntityType.GRID_WALL
                            and grid:GetType() ~= GridEntityType.GRID_DOOR
                        then
                            room:RemoveGridEntity(gridIndex, 0, false)
                        end
                    end
                    room:SetClear(true)
                end
                player.Position, player.Velocity =
                    room:GetCenterPos() + Vector(-100 + slot * 40, 80), Vector.Zero
                player:SetMinDamageCooldown(10000)
            end)
        end
    end
end
local function beginGoal(t)
    mark("goal-floor", t)
    Game():GetLevel():SetStage(case.id == 1004 and 8 or 6, StageType.STAGETYPE_ORIGINAL)
    Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
end
local function advance(t)
    if
        not case
        or not started
        or not host
        or native.api_info().ready ~= 1
        or not native.rooms_ready()
    then
        return
    end
    local info, game = native.api_info(), Game()
    assert(info.challenge == case.id and info.players == case.players and game.Challenge == 0)
    assert(game.Difficulty == Difficulty.DIFFICULTY_NORMAL)
    assert(_IsaacLanStatus().roomOptions == 0, "Challenge forced an optional room rule")
    if step ~= "collect" then
        park()
    end
    if step == "init" and t > 60 then
        originalRoom = game:GetLevel():GetCurrentRoomIndex()
        if case.id == 1004 then
            nextFloor = 1
            mark("large-floor", t)
        else
            assert(game:GetLevel():GetRooms().Size < 40, "Large floor rule leaked to 1005")
            mark("directions", t)
        end
    elseif step == "large-floor" and t - stepAt > 45 then
        local level = game:GetLevel()
        assert(level:GetStage() == nextFloor)
        local replica = read("floor-" .. current .. "-" .. nextFloor)
        if not replica then
            assert(t - stepAt < 600, "Missing client floor confirmation")
            return
        end
        assert(tonumber(replica) == level:GetRooms().Size, "Replica large floor layout differs")
        report("FLOOR stage=" .. nextFloor .. " rooms=" .. level:GetRooms().Size)
        assert(level:GetRooms().Size >= 40, "Native large floor generation was not selected")
        if nextFloor < 8 then
            nextFloor = nextFloor + 1
            level:SetStage(nextFloor, StageType.STAGETYPE_ORIGINAL)
            game:StartStageTransition(true, 0, Isaac.GetPlayer(0))
            mark("large-floor", t)
        else
            mark("goal-floor", t)
        end
    elseif step == "directions" and t - stepAt > 20 then
        checkAim(info, false, true)
        if phaseSamples > 45 then
            for slot = 1, case.players do
                assert(shotOwners[slot], "A seat never fired native tears")
            end
            local level, target = game:GetLevel(), nil
            for index = 0, level:GetRooms().Size - 1 do
                local desc = level:GetRooms():Get(index)
                if
                    desc.Data.Type == RoomType.ROOM_DEFAULT
                    and desc.Data.Shape == RoomShape.ROOMSHAPE_1x1
                    and desc.SafeGridIndex ~= originalRoom
                then
                    target = desc.SafeGridIndex
                    break
                end
            end
            assert(target and native.rooms_move(1, target, 0, -1))
            mark("split", t)
        end
    elseif step == "split" and t - stepAt > 30 then
        local locations = native.rooms_positions()
        assert(locations["0"].index ~= locations["1"].index, "Unexpected forced gathering")
        checkAim(info, false, false)
        if phaseSamples > 30 then
            mark("mouse", t)
        end
    elseif step == "mouse" and t - stepAt > 20 then
        checkAim(info, true, false)
        if phaseSamples > 30 then
            for slot = 1, case.players do
                assert(shotOwners[slot], "A seat never fired from the rotated mouse pointer")
            end
            actor(1, function(player)
                player:AddCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
            end)
            mark("charge", t)
        end
    elseif step == "charge" and t - stepAt > 100 then
        mark("release", t)
    elseif step == "release" and t - stepAt > 8 then
        local laser = false
        actor(1, function(player)
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_LASER and entity.SpawnerEntity then
                    local owner = entity.SpawnerEntity:ToPlayer()
                    laser = laser or owner and owner.ControllerIndex == 2
                end
            end
            assert(laser, "Source release did not fire the recipient's charged weapon")
            player:RemoveCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
        end)
        actor(0, function(player)
            player:Die()
        end)
        mark("ghost", t)
    elseif step == "ghost" and t - stepAt > 90 then
        actor(0, function(player)
            assert(player:IsCoopGhost(), "Death did not produce a cooperative ghost")
        end)
        actor(1, function(player)
            assert(
                player:GetShootingInput().X > 0.99,
                "Ghost lost its original shooting assignment"
            )
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_TEAR then
                    shotOwners[2] = true
                end
            end
        end)
        assert(shotOwners[2], "Ghost input did not produce a native attack")
        assert(native.actor_ghost(native.rooms_heads()["0"], 0))
        actor(0, function(player)
            player:Revive()
            player:AddHearts(6)
            assert(not player:IsCoopGhost())
        end)
        mark("disconnect", t)
    elseif
        step == "disconnect"
        and info.connected ~= (1 << case.players) - 1
        and t - stepAt > 30
    then
        checkAim(info, false, false)
        mark("rejoin", t)
    elseif step == "rejoin" and info.connected == (1 << case.players) - 1 and t - stepAt > 90 then
        checkAim(info, false, false)
        beginGoal(t)
    elseif step == "goal-floor" and t - stepAt > 45 then
        local level = game:GetLevel()
        for index = 0, level:GetRooms().Size - 1 do
            local desc = level:GetRooms():Get(index)
            if desc.Data.Type == RoomType.ROOM_BOSS then
                goalRoom = desc.SafeGridIndex
            end
        end
        assert(goalRoom)
        for slot = 0, case.players - 1 do
            assert(native.rooms_move(slot, goalRoom, 0, -1))
        end
        mark("boss", t)
    elseif step == "boss" and t - stepAt > 60 then
        actor(0, function()
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity:IsActiveEnemy(false) then
                    entity:Kill()
                elseif
                    entity.Type == EntityType.ENTITY_PICKUP
                    and entity.Variant == PickupVariant.PICKUP_TROPHY
                then
                    trophy = EntityPtr(entity)
                end
            end
        end)
        if trophy then
            mark("trophy", t)
        end
    elseif step == "trophy" and t - stepAt > 60 then
        actor(case.players - 1, function(player)
            local pickup = assert(trophy.Ref)
            assert(pickup:Exists() and pickup:ToPickup().Wait <= 0)
            for index = 0, game:GetRoom():GetGridSize() - 1 do
                local grid = game:GetRoom():GetGridEntity(index)
                assert(not grid or grid:GetType() ~= GridEntityType.GRID_TRAPDOOR)
            end
            player.Position, player.Velocity = pickup.Position, Vector.Zero
        end)
        mark("collect", t)
    end
    assert(t - stepAt < 1200, "Challenge phase stalled: " .. step)
end

native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        function()
            local mode, values = read("mode"), {}
            local active = case and case.id == 1005 and native.api_info().active == 1
            if
                active
                and (
                    mode == "directions"
                    or mode == "split"
                    or mode == "ghost"
                    or mode == "disconnect"
                    or mode == "rejoin"
                )
            then
                values[firing[ordinal + 1]] = input.maxValue
                if mode == "directions" then
                    values[moving[ordinal + 1]] = input.maxValue
                end
            elseif active and mode == "charge" and ordinal == 0 then
                values[ButtonAction.ACTION_SHOOTRIGHT] = input.maxValue
            end
            local buttons = 0
            for action, value in pairs(values) do
                if value > 0 then
                    buttons = buttons | (1 << action)
                end
            end
            local pointerInput
            if active and mode == "mouse" then
                local at = pointer(ordinal)
                pointerInput = { active = true, x = at.X, y = at.Y }
            end
            local bytes = input.encode({
                values = values,
                triggered = buttons & ~previous,
                pointer = pointerInput,
            })
            previous = buttons
            return bytes
        end,
        function(t, players, bytes)
            before(t, players, bytes)
            appliedInputs = bytes
            advance(t)
        end,
        collect,
        function(...)
            if restore(...) == false then
                return false
            end
            snapshots = snapshots + 1
            if case and case.id == 1004 and Game():GetFrameCount() > 20 then
                assert(Game().Challenge == 0 and Game():GetLevel():GetRooms().Size >= 40)
                local level = Game():GetLevel()
                write("floor-" .. current .. "-" .. level:GetStage(), level:GetRooms().Size)
            end
        end,
        present,
        beginFloor
    )
end

function _IsaacLanFrame()
    renders = renders + 1
    local status = baseFrame()
    local now = native.api_info().nowMs
    native.test_gamepad(0)
    if renders == 60 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local requested = tonumber(read("case"))
    if requested and requested > #cases then
        if not complete then
            complete = true
            Isaac.DebugString("LAN_NETWORK PASS large floor and aiming challenges")
        end
        return status
    end
    if requested and requested ~= current then
        if status.scene == 1 and not status.prepared and status.phase ~= 0 then
            _IsaacLanCommand("close")
            return status
        end
        if status.phase ~= 0 or status.scene ~= 1 or status.prepared then
            return status
        end
        current, case, startAt =
            requested, assert(cases[requested]), now + (requested == 1 and 8000 or 2000)
        linked, chosen, started, participated = false, false, false, false
        reconnectRequested, reconnectJoined, reconnectAt = false, false, 0
        step, stepAt, snapshots, previous, trophy, goalRoom = "init", 0, 0, 0, nil, nil
        inputRooms = {}
        if host then
            write("mode", "init")
        end
        report("BEGIN players=" .. case.players .. " challenge=" .. case.id)
    end
    if not case or ordinal >= case.players then
        return status
    end
    if not linked and now >= startAt + ordinal * 700 then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
    end
    if status.phase == 2 and not participated then
        if host and status.challenge ~= case.id then
            _IsaacLanCommand("challenge", tostring(case.id))
        elseif status.challenge == case.id and not chosen then
            chosen = true
            _IsaacLanCommand("choose", "0:1")
        end
        local ready = status.challenge == case.id and status.players == case.players
        for slot = 0, case.players - 1 do
            ready = ready and status["ready" .. slot] == 1
        end
        if host and ready and not started then
            started = true
            _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
        end
    end
    local info = native.api_info()
    if info.ready == 1 then
        participated, started = true, true
    end
    local mode = read("mode")
    if case.id == 1005 and ordinal == case.players - 1 then
        if mode == "disconnect" and not reconnectRequested and info.ready == 1 then
            reconnectRequested, reconnectAt = true, now
            assert(native.net_command(4))
            return status
        elseif
            mode == "rejoin"
            and reconnectRequested
            and not reconnectJoined
            and now - reconnectAt > 2000
            and status.scene == 1
            and not status.prepared
        then
            reconnectJoined = true
            _IsaacLanCommand("join", "127.0.0.1:" .. port)
        end
    end
    if
        participated
        and mode == "collect"
        and status.phase == 2
        and status.scene == 1
        and not status.prepared
    then
        assert(host or snapshots > 30, "Missing replica coverage")
        write("done-" .. current .. "-" .. ordinal, "pass")
    end
    if host then
        local done = true
        for slot = 0, case.players - 1 do
            done = done and read("done-" .. current .. "-" .. slot) ~= nil
        end
        if done then
            write("case", current + 1)
        end
    end
    if status.phase == 4 or status.phase == 9 and status.error ~= "" then
        Isaac.DebugString("LAN_NETWORK FAILED " .. status.error)
    end
    return status
end
