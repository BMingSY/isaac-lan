-- One pair, four native Womb II departures with opposite room contexts.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local linked, chosen, finished, renders = false, false, false, 0
local cases = {
    { user = 0, hush = true, destination = 9 },
    { user = 0, hush = false, destination = 10 },
    { user = 1, hush = true, destination = 9 },
    { user = 1, hush = false, destination = 10 },
}
local caseIndex, checked, received, snapshots = 1, 0, 0, 0
local step, stepAt, boss, exitPosition = "init", 0
local frame = _IsaacLanFrame
local function report(message)
    Isaac.DebugString("LAN_NETWORK SIDE floor-sources " .. message)
end
local function actor(slot, callback)
    assert(native.rooms_with_player(slot, function()
        callback(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function mark(name, tick)
    step, stepAt = name, tick
    report("STEP case=" .. caseIndex .. " " .. name)
end
function _IsaacLanFrame()
    renders = renders + 1
    native.test_gamepad(0)
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    local fixture = status.scene == 1 and select(2, native.progress_values(640, 522))
    if not linked and fixture == (host and 98765 or 321) and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
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
        _IsaacLanCommand("start", "YPVLAR60:0:0:0:0:0")
    end
    assert(finished or status.verified < 6000, "Floor-source fixture timed out: " .. step)
    if not finished and checked == #cases then
        finished = true
        report("PASS departures=" .. checked .. " snapshots=" .. snapshots)
    end
    return status
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(tick, count, bytes)
            before(tick, count, bytes)
            if finished or not native.rooms_ready() then
                return
            end
            for slot = 0, 1 do
                actor(slot, function(player)
                    player:SetMinDamageCooldown(10000)
                end)
            end
            local case = cases[caseIndex]
            if step == "init" and tick - stepAt > 40 then
                Game().TimeCounter = 0
                Game():SetStateFlag(GameStateFlag.STATE_HEAVEN_PATH, false)
                Game():SetStateFlag(GameStateFlag.STATE_SECRET_PATH, false)
                Game():GetLevel():SetStage(8, 0)
                Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
                mark("source", tick)
            elseif step == "source" and tick - stepAt > 120 then
                assert(Game():GetLevel():GetStage() == 8)
                local list = Game():GetLevel():GetRooms()
                boss = nil
                for i = 0, list.Size - 1 do
                    local descriptor = list:Get(i)
                    if descriptor.Data.Type == RoomType.ROOM_BOSS then
                        boss = descriptor.SafeGridIndex
                        break
                    end
                end
                assert(boss, "Womb II lacks its native boss room")
                for slot = 0, 1 do
                    assert(native.rooms_move(slot, boss, 0, -1))
                end
                mark("fight", tick)
            elseif step == "fight" and tick - stepAt > 60 then
                local clear, entrance
                actor(0, function(player)
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        if entity:IsActiveEnemy(false) and entity.FrameCount > 45 then
                            entity:TakeDamage(
                                1000000,
                                DamageFlag.DAMAGE_IGNORE_ARMOR,
                                EntityRef(player),
                                0
                            )
                        end
                    end
                    local room = Game():GetRoom()
                    clear = room:IsClear()
                    for slot = 0, 7 do
                        local door = room:GetDoor(slot)
                        if door and door.TargetRoomIndex == -8 and door:IsOpen() then
                            entrance = true
                        end
                    end
                end)
                if clear and entrance then
                    local hushSlot = case.hush and case.user or 1 - case.user
                    assert(native.rooms_move(hushSlot, -8, 0, -1))
                    mark("split", tick)
                end
            elseif step == "split" and tick - stepAt > 90 then
                local positions = native.rooms_positions()
                assert(positions["0"].index ~= positions["1"].index, "Players did not split")
                actor(case.user, function(player)
                    local room = Game():GetRoom()
                    local index = Game():GetLevel():GetCurrentRoomIndex()
                    assert(
                        index == (case.hush and -8 or boss),
                        "Wrong authoritative departure room"
                    )
                    exitPosition = nil
                    for i = 0, room:GetGridSize() - 1 do
                        local grid = room:GetGridEntity(i)
                        if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then
                            exitPosition = grid.Position
                            break
                        end
                    end
                    assert(exitPosition, "Native exit trapdoor is missing")
                    player.Position, player.Velocity = exitPosition, Vector.Zero
                    report(
                        "DEPART user="
                            .. case.user
                            .. " source="
                            .. index
                            .. " viewport="
                            .. positions["1"].index
                    )
                end)
                mark("depart", tick)
            elseif step == "depart" then
                if Game():GetLevel():GetStage() ~= 8 then
                    assert(
                        Game():GetLevel():GetStage() == case.destination,
                        "Host chose the wrong branch"
                    )
                    assert(Game():GetLevel():GetStageType() == 0, "Host chose the wrong stage type")
                    checked = checked + 1
                    report("CHECKED host case=" .. caseIndex .. " stage=" .. case.destination)
                    caseIndex = caseIndex + 1
                    mark("init", tick)
                else
                    actor(case.user, function(player)
                        player.Position, player.Velocity = exitPosition, Vector.Zero
                    end)
                end
            end
        end,
        collect,
        function(bytes, tick, ack)
            if restore(bytes, tick, ack) == false then
                return false
            end
            snapshots = snapshots + 1
            local case = cases[received]
            if case and checked < received then
                assert(
                    Game():GetLevel():GetStage() == case.destination,
                    "Replica chose its own floor branch"
                )
                assert(Game():GetLevel():GetStageType() == 0, "Replica stage type differs")
                checked = received
                report("CHECKED replica case=" .. received .. " stage=" .. case.destination)
            end
        end,
        present,
        function(epoch, stage, stageType, animation, same, rewind, restart, cinematic, sourceRoom)
            if not same then
                received = received + 1
                local case = assert(cases[received], "Unexpected extra floor event")
                assert(stage == 8 and animation == 0, "Departure did not use the native trapdoor")
                assert((sourceRoom == -8) == case.hush, "Reliable event lost the chosen entrance")
                if case.user == 0 then
                    assert(
                        sourceRoom ~= Game():GetLevel():GetCurrentRoomIndex(),
                        "Fixture did not expose split-room routing"
                    )
                end
                report("EVENT case=" .. received .. " source=" .. sourceRoom)
            end
            return beginFloor(
                epoch,
                stage,
                stageType,
                animation,
                same,
                rewind,
                restart,
                cinematic,
                sourceRoom
            )
        end
    )
end

-- Explicit test-only lifecycle consumed by both suite coordinators.
return {
    done = function()
        return finished
    end,
}
