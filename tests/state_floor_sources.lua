-- One pair: crawlspace entry/return and native hole/light floor departures.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local linked, chosen, finished, renders = false, false, false, 0
local cases = {
    { user = 0, hush = false, light = true, destination = 10 },
    { user = 1, hush = false, light = true, destination = 10 },
    { user = 0, hush = true, destination = 9 },
    { user = 0, hush = false, destination = 10 },
    { user = 1, hush = true, destination = 9 },
    { user = 1, hush = false, destination = 10 },
}
local caseIndex, checked, received, snapshots = 1, 0, 0, 0
local step, stepAt, boss, exitPosition = "crawlspace-init", 0
local crawlspaceSource, crawlspaceEntrance, crawlspaceSeen, crawlspaceReturned
local holePoses, lightPoses = 0, 0
local light
local frame = _IsaacLanFrame
local dpadUp = 0x0001 -- XINPUT_GAMEPAD_DPAD_UP, not the action-input bitmap.
local lightContactOffset, departureTimeout = 4, 600
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
local function contactExit(case, player)
    if case.light then
        exitPosition = assert(light and light.Ref, "Native light was removed").Position
        player.Position, player.Velocity =
            exitPosition + Vector(lightContactOffset, 0), Vector(1, 0)
    else
        player.Position, player.Velocity = exitPosition, Vector.Zero
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    local status = frame()
    local climb = not host
        and native.rooms_ready()
        and Game():GetRoom():GetType() == RoomType.ROOM_DUNGEON
    native.test_gamepad(climb and dpadUp or 0)
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
    assert(finished or status.verified < 1500 * #cases, "Floor-source fixture timed out: " .. step)
    if not finished and checked == #cases then
        assert(crawlspaceSeen and crawlspaceReturned, "Missing crawlspace entry/return")
        assert(host or holePoses == 4 and lightPoses == 2, "Missing both native departure poses")
        finished = true
        report("PASS departures=" .. checked .. " snapshots=" .. snapshots .. " crawlspace=true")
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
            if step == "crawlspace-init" and tick - stepAt > 40 then
                crawlspaceSource = native.rooms_positions()["1"].index
                actor(0, function(player)
                    player.Position, player.Velocity = Vector(580, 280), Vector.Zero
                end)
                actor(1, function(player)
                    local room = Game():GetRoom()
                    local index = room:GetGridIndex(Vector(240, 280))
                    assert(not room:GetGridEntity(index), "Staircase grid is occupied")
                    assert(room:SpawnGridEntity(index, GridEntityType.GRID_STAIRS, 0, 123, 0))
                    crawlspaceEntrance = room:GetGridPosition(index)
                    player.Position, player.Velocity =
                        crawlspaceEntrance + Vector(60, 0), Vector.Zero
                end)
                mark("crawlspace-enter", tick)
            elseif step == "crawlspace-enter" and tick - stepAt > 30 then
                if native.rooms_positions()["1"].index == GridRooms.ROOM_DUNGEON_IDX then
                    crawlspaceSeen = true
                    actor(1, function(player)
                        assert(Game():GetRoom():GetType() == RoomType.ROOM_DUNGEON)
                        player.Position, player.Velocity = Vector(120, 200), Vector.Zero
                    end)
                    report("CHECKED host crawlspace entry")
                    mark("crawlspace-return", tick)
                else
                    actor(1, function(player)
                        player.Position, player.Velocity =
                            crawlspaceEntrance + Vector(4, 0), Vector(1, 0)
                    end)
                end
            elseif step == "crawlspace-return" then
                if native.rooms_positions()["1"].index == crawlspaceSource then
                    crawlspaceReturned = true
                    report("CHECKED host crawlspace return")
                    mark("init", tick)
                end
                assert(tick - stepAt < 240, "Crawlspace ladder did not return to its source")
            elseif step == "init" and tick - stepAt > 40 then
                Game().TimeCounter = 0
                Game():SetStateFlag(GameStateFlag.STATE_HEAVEN_PATH, false)
                Game():SetStateFlag(GameStateFlag.STATE_SECRET_PATH, false)
                Game():GetLevel():SetStage(8, 0)
                if caseIndex == 1 then
                    Game():StartStageTransition(true, 0)
                    report("BINDING player=omitted")
                elseif caseIndex == 2 then
                    Game():StartStageTransition(true, 0, nil)
                    report("BINDING player=nil")
                else
                    Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
                    report("BINDING player=explicit")
                end
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
                    if case.light then
                        for _, entity in ipairs(Isaac.GetRoomEntities()) do
                            if
                                entity.Type == EntityType.ENTITY_EFFECT
                                and entity.Variant == EffectVariant.HEAVEN_LIGHT_DOOR
                            then
                                light = EntityPtr(entity)
                                exitPosition = entity.Position
                                break
                            end
                        end
                    else
                        for i = 0, room:GetGridSize() - 1 do
                            local grid = room:GetGridEntity(i)
                            if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then
                                exitPosition = grid.Position
                                break
                            end
                        end
                    end
                    assert(exitPosition, "Native route entrance is missing")
                    contactExit(case, player)
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
                    assert(
                        Game():GetLevel():GetStageType()
                            == (
                                case.light and StageType.STAGETYPE_WOTL
                                or StageType.STAGETYPE_ORIGINAL
                            ),
                        "Host chose the wrong stage type"
                    )
                    checked = checked + 1
                    report("CHECKED host case=" .. caseIndex .. " stage=" .. case.destination)
                    caseIndex = caseIndex + 1
                    mark("init", tick)
                else
                    actor(case.user, function(player)
                        contactExit(case, player)
                        if (tick - stepAt) % 120 == 0 then
                            report(
                                "CONTACT user="
                                    .. case.user
                                    .. " visible="
                                    .. tostring(player.Visible)
                                    .. " animation="
                                    .. player:GetSprite():GetAnimation()
                                    .. " position="
                                    .. player.Position.X
                                    .. ","
                                    .. player.Position.Y
                                    .. " entrance="
                                    .. exitPosition.X
                                    .. ","
                                    .. exitPosition.Y
                                    .. " subtype="
                                    .. (case.light and light.Ref.SubType or -1)
                                    .. " frame="
                                    .. player:GetSprite():GetFrame()
                                    .. " heaven="
                                    .. tostring(
                                        Game():GetStateFlag(GameStateFlag.STATE_HEAVEN_PATH)
                                    )
                            )
                        end
                    end)
                    assert(
                        tick - stepAt < departureTimeout,
                        "Native entrance did not start a floor transition"
                    )
                end
            end
        end,
        collect,
        function(bytes, tick, ack, betweenUpdates, stable)
            if restore(bytes, tick, ack, betweenUpdates, stable) == false then
                return false
            end
            snapshots = snapshots + 1
            local roomIndex = native.rooms_positions()["1"].index
            if received == 0 and roomIndex == GridRooms.ROOM_DUNGEON_IDX then
                if not crawlspaceSeen then
                    report("CHECKED replica crawlspace entry")
                end
                crawlspaceSeen = true
            elseif received == 0 and crawlspaceSeen and not crawlspaceReturned then
                crawlspaceReturned = true
                report("CHECKED replica crawlspace return")
            end
            local case = cases[received]
            if case and checked < received then
                assert(
                    Game():GetLevel():GetStage() == case.destination,
                    "Replica chose its own floor branch"
                )
                assert(
                    Game():GetLevel():GetStageType()
                        == (case.light and StageType.STAGETYPE_WOTL or StageType.STAGETYPE_ORIGINAL),
                    "Replica stage type differs"
                )
                checked = received
                report("CHECKED replica case=" .. received .. " stage=" .. case.destination)
            end
        end,
        present,
        function(
            epoch,
            stage,
            stageType,
            animation,
            same,
            rewind,
            restart,
            cinematic,
            sourceRoom,
            departureAnimation
        )
            if not same then
                received = received + 1
                local case = assert(cases[received], "Unexpected extra floor event")
                assert(
                    stage == 8 and animation == 0,
                    "Departure did not use the native floor transition"
                )
                assert((sourceRoom == -8) == case.hush, "Reliable event lost the chosen entrance")
                if case.user == 0 then
                    assert(
                        sourceRoom ~= Game():GetLevel():GetCurrentRoomIndex(),
                        "Fixture did not expose split-room routing"
                    )
                end
                local expected = case.light and "LightTravel" or "Trapdoor"
                assert(
                    departureAnimation == expected,
                    "Reliable event lost the authoritative entrance action: "
                        .. tostring(departureAnimation)
                )
                report(
                    "EVENT case="
                        .. received
                        .. " source="
                        .. sourceRoom
                        .. " animation="
                        .. departureAnimation
                )
            end
            local accepted = beginFloor(
                epoch,
                stage,
                stageType,
                animation,
                same,
                rewind,
                restart,
                cinematic,
                sourceRoom,
                departureAnimation
            )
            if not same then
                local expected = cases[received].light and "LightTravel" or "Trapdoor"
                actor(1, function(player)
                    assert(
                        player:GetSprite():GetAnimation() == expected,
                        "Replica displayed the wrong departure: "
                            .. player:GetSprite():GetAnimation()
                    )
                end)
                if cases[received].light then
                    lightPoses = lightPoses + 1
                else
                    holePoses = holePoses + 1
                end
                report("CHECKED replica pose=" .. expected)
            end
            return accepted
        end
    )
end

-- Explicit test-only lifecycle consumed by both suite coordinators.
return {
    done = function()
        return finished
    end,
}
