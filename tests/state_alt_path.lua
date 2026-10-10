-- One ordinary-sandbox pair: native alt trapdoors and unequal unlock progress.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local owner = { Name = "Natural alternate-path floor regression" }
local function report(value)
    Isaac.DebugString("LAN_NETWORK " .. value)
end
local function progress()
    return native.net_progress():byte(409)
end
local linked, chosen, exiting, exited, renders = false, false, false, false, 0
local floorEvents, checkpoints, snapshots = 0, {}, 0
local frame = _IsaacLanFrame
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    exited, renders = true, 0
end)
function _IsaacLanFrame()
    renders = renders + 1
    if EID and EID.Config then
        EID.Config.DisableStartOfRunWarnings = true
    end
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    native.test_gamepad(0)
    if exited then
        if renders == 90 then
            assert(progress() == (host and 1 or 0), "Shared alt unlock replaced local progress")
            assert(host or floorEvents == 6, "Native floor events were not all checked")
            assert(host or snapshots > 200, "Replica floor views were not checked")
            report("LOCAL_UNLOCK_RESTORED secret_exit=" .. progress())
            report("PASS natural alternate-path trapdoors and unequal unlocks")
        end
        return status
    end
    if
        not linked
        and renders >= (host and 300 or 360)
        and progress() == (host and 1 or 0)
        and native.net_progress():byte(642) == (host and 1 or 0)
    then
        linked = true
        report("LOCAL_UNLOCK_BASELINE secret_exit=" .. progress())
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", Seeds.Seed2String(1477942995):gsub("%s", "") .. ":0:0:0:0:0")
    end
    if status.prepared and native.api_info().tick >= 2340 and not exiting then
        exiting = true
        if host then
            assert(
                checkpoints.guest
                    and checkpoints.host
                    and checkpoints.continue
                    and checkpoints.mines
            )
            assert(native.net_command(3))
        end
    end
    return status
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
local function source()
    Game():SetStateFlag(GameStateFlag.STATE_SECRET_PATH, false)
    Game():SetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH, false)
    Game():GetLevel():SetStage(2, StageType.STAGETYPE_ORIGINAL)
    Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
end
local function verify(name, stage, kind)
    assert(native.rooms_ready(), "Floor still loading: " .. name)
    local level = Game():GetLevel()
    assert(not stage or level:GetStage() == stage, name .. " stage=" .. level:GetStage())
    assert(not kind or level:GetStageType() == kind, name .. " type=" .. level:GetStageType())
    local positions = native.rooms_positions()
    assert(positions["0"].index == positions["1"].index, name .. " left the roster on old rooms")
    checkpoints[name] = true
    report("CHECKED " .. name .. " stage=" .. level:GetStage() .. " type=" .. level:GetStageType())
end
local function entrance(slot)
    for i = 0, 1 do
        actor(i, function(p)
            p:SetMinDamageCooldown(10000)
            p.Position = Vector(100, 100)
        end)
    end
    local descriptor = Game():GetLevel():GetRoomByIdx(GridRooms.ROOM_SECRET_EXIT_IDX, 0)
    assert(descriptor and descriptor.Data, "Boss clear did not generate the alternate entrance")
    assert(native.rooms_move(slot, GridRooms.ROOM_SECRET_EXIT_IDX, 0, -1))
    report("ENTRANCE slot=" .. slot)
end
local function bossRoom(slot)
    local level = Game():GetLevel()
    for i = 0, level:GetRooms().Size - 1 do
        local d = level:GetRooms():Get(i)
        if d.Data.Type == RoomType.ROOM_BOSS then
            assert(native.rooms_move(slot, d.SafeGridIndex, 0, -1))
            actor(slot, function(p)
                p:SetMinDamageCooldown(10000)
                p.Position = Vector(100, 100)
            end)
            return
        end
    end
    error("Source floor lacks a Boss room")
end
local function defeatBoss(slot)
    actor(slot, function()
        assert(Game():GetRoom():GetType() == RoomType.ROOM_BOSS)
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity:IsActiveEnemy(false) then
                entity:Kill()
            end
        end
    end)
    report("NATIVE_BOSS_DEATH slot=" .. slot)
end
local trap
local function prepare(slot, ordinary)
    actor(slot, function(p)
        clear()
        local room = Game():GetRoom()
        if not ordinary then
            assert(room:GetType() == RoomType.ROOM_SECRET_EXIT, "Missing native alt entrance")
        end
        trap = nil
        for index = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(index)
            if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then
                trap = grid.Position
                grid.State = 2
                grid:GetSprite():Play("Open", true)
                break
            end
        end
        if ordinary and not trap then
            local index = room:GetGridIndex(room:GetCenterPos() + Vector(80, 0))
            room:SpawnGridEntity(index, GridEntityType.GRID_TRAPDOOR, 0, 123, 0)
            local grid = assert(room:GetGridEntity(index))
            grid.State = 2
            grid:GetSprite():Play("Open", true)
            trap = grid.Position
        end
        assert(trap, "Entrance lacks a native trapdoor")
        p.Position = Vector(100, 100)
    end)
end
local function step(slot)
    actor(slot, function(p)
        p.Position, p.Velocity = trap, Vector.Zero
        report("STEP_NATIVE slot=" .. slot .. " room=" .. Game():GetRoom():GetType())
    end)
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, bytes)
            before(t, n, bytes)
            if t == 30 or t == 1060 then
                source()
            elseif t == 210 then
                verify("source guest", 2, StageType.STAGETYPE_ORIGINAL)
                bossRoom(1)
            elseif t == 340 then
                defeatBoss(1)
            elseif t == 430 then
                entrance(1)
            elseif t == 450 then
                prepare(1)
            elseif t == 480 then
                step(1)
            elseif t == 720 then
                verify("guest", 2, StageType.STAGETYPE_REPENTANCE)
                report("VISUAL_READY")
            elseif t == 740 then
                prepare(0, true)
            elseif t == 760 then
                step(0)
            elseif t == 1020 then
                verify("continue")
            elseif t == 1240 then
                verify("source host", 2, StageType.STAGETYPE_ORIGINAL)
                bossRoom(0)
            elseif t == 1370 then
                defeatBoss(0)
            elseif t == 1460 then
                entrance(0)
            elseif t == 1480 then
                prepare(0)
            elseif t == 1510 then
                step(0)
            elseif t == 1750 then
                verify("host", 2, StageType.STAGETYPE_REPENTANCE)
            elseif t == 1770 then
                bossRoom(1)
            elseif t == 1880 then
                defeatBoss(1)
            elseif t == 1970 then
                entrance(1)
            elseif t == 1990 then
                prepare(1)
            elseif t == 2020 then
                step(1)
            elseif t == 2300 then
                verify("mines", 3, StageType.STAGETYPE_REPENTANCE)
            end
        end,
        collect,
        function(bytes, t, ack)
            if restore(bytes, t, ack) == false then
                return false
            end
            snapshots = snapshots + 1
            if t == 720 or t == 1750 then
                verify(t == 720 and "guest" or "host", 2, StageType.STAGETYPE_REPENTANCE)
            elseif t == 1020 then
                verify("continue")
            elseif t == 2300 then
                verify("mines", 3, StageType.STAGETYPE_REPENTANCE)
            end
        end,
        present,
        function(epoch, stage, kind, animation, same, rewind, rKey)
            floorEvents = floorEvents + 1
            local secret = Game():GetStateFlag(GameStateFlag.STATE_SECRET_PATH)
            if floorEvents == 1 or floorEvents == 3 or floorEvents == 4 then
                assert(not secret, "Previous alternate route leaked into normal floor regeneration")
            else
                assert(secret, "Native floor event lost authoritative trapdoor route flag")
            end
            report("FLOOR_BEGIN epoch=" .. epoch .. " secret=" .. tostring(secret))
            return beginFloor(epoch, stage, kind, animation, same, rewind, rKey)
        end
    )
end
