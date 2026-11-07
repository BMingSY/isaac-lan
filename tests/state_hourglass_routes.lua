-- Native exits must be selectable again after a cross-floor hourglass rewind.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local womb, destination = LevelStage.STAGE4_2, LevelStage.STAGE5
local original, cathedral = StageType.STAGETYPE_ORIGINAL, StageType.STAGETYPE_WOTL
local hourglass = CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
local cases = {
    { user = 0, first = cathedral, source = womb },
    { user = 1, first = cathedral, source = womb },
    { user = 0, first = original, source = womb },
    { user = 1, first = original, source = womb },
    { user = 0, first = cathedral, source = LevelStage.STAGE4_3 },
    { user = 1, first = cathedral, source = LevelStage.STAGE4_3 },
}
local linked, chosen, finished, renders = false, false, false, 0
local caseIndex, departure, checked, received, snapshots = 1, 1, 0, 0, 0
local step, stepAt, boss, exitPosition = "init", 0
local light, exitDirection
local APPROACH_DISTANCE, CONTACT_OFFSET, APPROACH_PERIOD, APPROACH_FRAMES = 60, 4, 90, 20
local expectedReplica
local seenBoss = false
local function report(message)
    Isaac.DebugString("LAN_NETWORK SIDE hourglass-routes " .. message)
end
local function actor(slot, callback)
    assert(native.rooms_with_player(slot, function()
        callback(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function parkPlayers()
    -- The native trapdoor cannot open while either co-op player is nearby.
    for slot = 0, 1 do
        actor(slot, function(player)
            player.Position, player.Velocity = Vector(160 + slot * 40, 360), Vector.Zero
        end)
    end
end
local function mark(name, tick)
    step, stepAt = name, tick
    report("STEP case=" .. caseIndex .. " departure=" .. departure .. " " .. name)
end
local function chosenType(case, ordinal)
    return ordinal == 2 and (case.first == cathedral and original or cathedral) or case.first
end
local function enterExit(case)
    actor(case.user, function(player)
        exitPosition = nil
        if chosenType(case, departure) == cathedral then
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
            local room = Game():GetRoom()
            for index = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(index)
                if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then
                    exitPosition = grid.Position
                    break
                end
            end
            exitDirection = Vector(-1, 0)
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if
                    entity.Type == EntityType.ENTITY_EFFECT
                    and entity.Variant == EffectVariant.HEAVEN_LIGHT_DOOR
                then
                    exitDirection = (assert(exitPosition) - entity.Position):Normalized()
                    break
                end
            end
        end
        assert(exitPosition, "Native route entrance is missing")
        player.Position, player.Velocity = exitPosition + Vector(4, 0), Vector(1, 0)
    end)
end
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    native.test_gamepad(0)
    local status = frame()
    if status.phase == 4 or status.phase == 9 then
        Isaac.DebugString("LAN_NETWORK FAILED " .. status.error)
    end
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
    assert(finished or status.verified < 10000, "Hourglass routes timed out: " .. step)
    if not finished and checked == #cases * 3 then
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
            local case = cases[caseIndex]
            if not case then
                return
            end
            for slot = 0, 1 do
                actor(slot, function(player)
                    player:SetMinDamageCooldown(10000)
                    player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                end)
            end
            local level = Game():GetLevel()
            assert(tick - stepAt < 900, "Hourglass route step timed out: " .. step)
            if step == "init" and tick - stepAt > 90 then
                departure = 1
                seenBoss = false
                Game().TimeCounter = 0
                Game():SetStateFlag(GameStateFlag.STATE_HEAVEN_PATH, false)
                Game():SetStateFlag(GameStateFlag.STATE_SECRET_PATH, false)
                level:SetStage(case.source, original)
                Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
                mark("source", tick)
            elseif step == "source" and tick - stepAt > 120 then
                assert(level:GetStage() == case.source)
                boss = nil
                local rooms = level:GetRooms()
                for index = 0, rooms.Size - 1 do
                    local descriptor = rooms:Get(index)
                    if descriptor.Data.Type == RoomType.ROOM_BOSS then
                        boss = descriptor.SafeGridIndex
                        break
                    end
                end
                assert(boss, "Source floor lacks a native boss room")
                for slot = 0, 1 do
                    actor(slot, function(player)
                        if not player:HasCollectible(hourglass) then
                            player:AddCollectible(hourglass)
                        end
                    end)
                    assert(native.rooms_move(slot, boss, 0, -1))
                end
                mark("fight", tick)
            elseif step == "fight" and tick - stepAt > 60 then
                local clear
                actor(case.user, function(player)
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        if
                            entity:IsBoss()
                            and (
                                case.source ~= LevelStage.STAGE4_3
                                or entity.Type == EntityType.ENTITY_HUSH
                            )
                        then
                            seenBoss = true
                        end
                        if entity:IsActiveEnemy(false) and entity.FrameCount > 45 then
                            entity:TakeDamage(
                                1000000,
                                DamageFlag.DAMAGE_IGNORE_ARMOR,
                                EntityRef(player),
                                0
                            )
                        end
                    end
                    clear = Game():GetRoom():IsClear()
                end)
                if clear and seenBoss then
                    parkPlayers()
                    mark("exit", tick)
                end
            elseif step == "exit" and tick - stepAt > 90 then
                enterExit(case)
                report(
                    "DEPART user=" .. case.user .. " expected_type=" .. chosenType(case, departure)
                )
                mark("depart", tick)
            elseif step == "depart" then
                if level:GetStage() == case.source then
                    actor(case.user, function(player)
                        if chosenType(case, departure) == cathedral then
                            exitPosition =
                                assert(light and light.Ref, "Native light was removed").Position
                            player.Position, player.Velocity =
                                exitPosition + Vector(CONTACT_OFFSET, 0), Vector(1, 0)
                        else
                            -- Cross the opening from the side away from the Cathedral light.
                            local away = (tick - stepAt) % APPROACH_PERIOD < APPROACH_FRAMES
                            player.Position = exitPosition
                                + exitDirection * (away and APPROACH_DISTANCE or CONTACT_OFFSET)
                            player.Velocity = exitDirection * (away and -1 or 1)
                        end
                        if (tick - stepAt) % 120 == 0 then
                            report(
                                "CONTACT visible="
                                    .. tostring(player.Visible)
                                    .. " animation="
                                    .. player:GetSprite():GetAnimation()
                                    .. " position="
                                    .. player.Position.X
                                    .. ","
                                    .. player.Position.Y
                                    .. " controls="
                                    .. tostring(player:AreControlsEnabled())
                                    .. " cooldown="
                                    .. player.ControlsCooldown
                                    .. " heaven="
                                    .. tostring(
                                        Game():GetStateFlag(GameStateFlag.STATE_HEAVEN_PATH)
                                    )
                            )
                        end
                    end)
                else
                    report("ARRIVED stage=" .. level:GetStage() .. " type=" .. level:GetStageType())
                    assert(level:GetStage() == destination, "Host chose the wrong floor")
                    assert(
                        level:GetStageType() == chosenType(case, departure),
                        "Host reused the previous route after hourglass"
                    )
                    checked = checked + 1
                    mark("arrived", tick)
                end
            elseif step == "arrived" and tick - stepAt > 90 then
                if departure == 3 then
                    caseIndex = caseIndex + 1
                    mark("init", tick)
                else
                    actor(case.user, function(player)
                        player:UseActiveItem(hourglass, 0, -1)
                    end)
                    mark("rewind", tick)
                end
            elseif step == "rewind" then
                assert(
                    level:GetStage() == case.source,
                    "Hourglass did not restore the source floor"
                )
                for slot = 0, 1 do
                    actor(slot, function(player)
                        assert(level:GetCurrentRoomIndex() == boss, "Hourglass lost the boss room")
                        assert(Game():GetRoom():IsClear(), "Hourglass revived the cleared boss")
                    end)
                end
                parkPlayers()
                report(
                    "REWOUND heaven="
                        .. tostring(Game():GetStateFlag(GameStateFlag.STATE_HEAVEN_PATH))
                )
                departure = departure + 1
                mark("exit", tick)
            end
        end,
        collect,
        function(bytes, tick, ack, betweenUpdates, stable)
            if restore(bytes, tick, ack, betweenUpdates, stable) == false then
                return false
            end
            snapshots = snapshots + 1
            if expectedReplica then
                local level = Game():GetLevel()
                assert(level:GetStage() == expectedReplica.stage, "Replica floor differs")
                assert(
                    level:GetStageType() == expectedReplica.kind,
                    "Replica reused the previous route"
                )
                if expectedReplica.departure then
                    checked = checked + 1
                end
                report(
                    "CHECKED replica stage=" .. level:GetStage() .. " type=" .. level:GetStageType()
                )
                expectedReplica = nil
            end
            return true
        end,
        present,
        function(epoch, stage, stageType, animation, same, rewind, restart, cinematic, sourceRoom)
            if rewind and #rewind > 0 then
                local case = assert(cases[math.floor((received - 1) / 3) + 1])
                expectedReplica = { stage = case.source, kind = original }
            elseif not same then
                received = received + 1
                local index = math.floor((received - 1) / 3) + 1
                local ordinal = (received - 1) % 3 + 1
                local case = assert(cases[index], "Unexpected floor departure")
                assert(stage == case.source, "Departure did not originate at the route fork")
                expectedReplica =
                    { stage = destination, kind = chosenType(case, ordinal), departure = true }
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
return {
    done = function()
        return finished
    end,
}
