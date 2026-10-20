-- Compose with special_suite_driver.lua: each factory sets
-- _IsaacLanTest.releaseHourglass, appends this source, then returns
-- function() return finished end. No io, callbacks or debug-Lua API is needed.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local mode = assert(_IsaacLanTest.releaseHourglass)
local modes = {
    ["cross-floor"] = { difficulty = 0, cross = true },
    ["greed-start"] = { difficulty = 2, special = true },
    ["greed-neighbor"] = { difficulty = 2 },
    ["greedier-start"] = { difficulty = 3, special = true },
    ["greedier-neighbor"] = { difficulty = 3 },
}
local case = assert(modes[mode], "Unknown release hourglass case")
local hourglass, marker =
    CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, CollectibleType.COLLECTIBLE_PENTAGRAM
local WALK_AT, WALK_END = 1200, 1220
local frame, gate = _IsaacLanFrame, native.net_gate
local linked, chosen, started, finished, renders = false, false, false, false, 0
local phase, phaseAt, verified, snapshots = "init", 0, -1, 0
local initialStage, initialType, initialSeed, source, target
local beforeEpoch, useEpoch, checkpoint, trapIndex, trapPosition
local floorEvents, restartEvents, rewindEvents, reliableEpoch, restartEpoch = 0, 0, 0, nil, nil
local selected, savedLocations, arrivedAt, hostChecked, replicaChecked
local walkOrigins, walkDistances, walkingPrepared, lastHeartbeat = {}, {}, false, 0
local function report(text)
    Isaac.DebugString("LAN_NETWORK RELEASE_HOURGLASS case=" .. mode .. " " .. text)
end
local function mark(name, tick)
    phase, phaseAt = name, tick
    report("STEP " .. name .. " tick=" .. tick)
end
local function actor(slot, call)
    assert(native.rooms_with_player(slot, function()
        call(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function clear()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) or entity.Type == EntityType.ENTITY_PICKUP then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function usable()
    if
        not native.rooms_ready()
        or native.presentation_active()
        or native.rooms_connected() ~= 3
    then
        return false
    end
    local result = true
    for slot = 0, 1 do
        actor(slot, function(player)
            result = result
                and not player:IsDead()
                and not player:IsCoopGhost()
                and player:AreControlsEnabled()
                and player:IsExtraAnimationFinished()
        end)
    end
    return result
end
local function findRoom(kind)
    local level = Game():GetLevel()
    for i = 0, level:GetRooms().Size - 1 do
        local room = level:GetRooms():Get(i)
        if
            room.Data
            and room.Data.Type == kind
            and room.SafeGridIndex >= 0
            and room.SafeGridIndex ~= level:GetStartingRoomIndex()
        then
            return room.SafeGridIndex
        end
    end
    error("No side room for the release hourglass fixture")
end
local function roster()
    local result, positions = {}, native.rooms_positions()
    for slot = 0, 1 do
        actor(slot, function(player)
            result[slot + 1] = {
                index = positions[tostring(slot)].index,
                dimension = positions[tostring(slot)].dimension,
                x = player.Position.X,
                y = player.Position.Y,
                hearts = player:GetHearts(),
                maxHearts = player:GetMaxHearts(),
            }
        end)
    end
    return result
end
local function preparePlayers()
    for slot = 0, 1 do
        actor(slot, function(player)
            clear()
            player:AddCollectible(hourglass)
            player:AddCollectible(slot + 1)
            player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
            player:SetMinDamageCooldown(10000)
            player.Position = Game():GetRoom():GetCenterPos() + Vector(-100 + slot * 70, 80)
            player.Velocity = Vector.Zero
            if slot == 0 then
                player:AddCoins(20 - player:GetNumCoins())
            end
        end)
    end
end
local function mutateAndUse(t)
    if case.special then
        checkpoint = roster()
    end
    for slot = 0, 1 do
        actor(slot, function(player)
            clear()
            player:AddCollectible(marker)
            player:AddHearts(-2)
            if slot == 0 then
                player:AddCoins(7)
            end
        end)
    end
    useEpoch = native.api_info().worldEpoch
    actor(1, function(player)
        report(
            "NATIVE_USE slot=1 room="
                .. Game():GetLevel():GetCurrentRoomIndex()
                .. " first_visit="
                .. tostring(Game():GetRoom():IsFirstVisit())
                .. " epoch="
                .. useEpoch
        )
        player:UseActiveItem(hourglass, 0, -1)
    end)
    mark("used", t)
end
local function checkInventory(player, slot)
    assert(
        player.ControllerIndex == slot + 1 and player:GetPlayerType() == PlayerType.PLAYER_ISAAC,
        "Original Isaac/controller changed"
    )
    assert(
        player:HasCollectible(hourglass)
            and player:GetCollectibleNum(slot + 1, true) == 1
            and not player:HasCollectible(2 - slot),
        "Original independent inventory changed"
    )
    assert(
        player:GetNumCoins() == (case.special and 27 or 20),
        "Native route restored the wrong shared coins"
    )
    assert(
        player:HasCollectible(marker) == not not case.special,
        "Native route restored the wrong inventory version"
    )
end
local function checkResult(positionsStrict)
    local game, level, positions = Game(), Game():GetLevel(), native.rooms_positions()
    assert(
        game.Difficulty == case.difficulty and game:IsGreedMode() == (case.difficulty >= 2),
        "Native route changed the game mode"
    )
    assert(
        level:GetStage() == initialStage
            and level:GetStageType() == initialType
            and game:GetSeeds():GetStartSeed() == initialSeed,
        "Native route reached Home or changed the floor/seed"
    )
    for slot = 0, 1 do
        actor(slot, function(player)
            if positionsStrict then
                report(
                    "ACTOR slot="
                        .. slot
                        .. " room="
                        .. positions[tostring(slot)].index
                        .. " x="
                        .. player.Position.X
                        .. " y="
                        .. player.Position.Y
                        .. " coins="
                        .. player:GetNumCoins()
                        .. " hearts="
                        .. player:GetHearts()
                        .. " visible="
                        .. tostring(player.Visible)
                        .. " no_damage_blink="
                        .. tostring(player:HasEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK))
                )
            end
            checkInventory(player, slot)
            assert(player.Visible, "Native transition left a living player invisible")
            local position = positions[tostring(slot)]
            if case.special then
                assert(
                    position.index == GridRooms.ROOM_ERROR_IDX
                        and position.dimension == 0
                        and Game():GetRoom():GetType() == RoomType.ROOM_ERROR,
                    "Greed's native teleport was overwritten by old checkpoint locations"
                )
                if host then
                    assert(
                        player:GetHearts() == checkpoint[slot + 1].hearts - 2,
                        "Greed teleport incorrectly rewound damage"
                    )
                end
            elseif positionsStrict then
                local expected = assert((host and checkpoint or savedLocations)[slot + 1])
                assert(
                    position.index == expected.index and position.dimension == expected.dimension,
                    "Native rewind did not restore a saved team room"
                )
                -- The stage Hook captures the trapdoor contact position later
                -- than this fixture's pre-departure observation. Replicas use
                -- the exact coordinates carried by that native checkpoint.
                if not host or not case.cross then
                    assert(
                        player.Position:Distance(Vector(expected.x, expected.y)) < 2,
                        "Native rewind did not restore the saved position"
                    )
                else
                    assert(
                        Game():GetRoom():IsPositionInRoom(player.Position, 0),
                        "Cross-floor rewind returned a player outside the saved room"
                    )
                end
                if host then
                    assert(
                        player:GetHearts() == expected.hearts
                            and player:GetMaxHearts() == expected.maxHearts,
                        "Native rewind did not restore team health"
                    )
                end
            end
        end)
    end
end
local function observeWalk()
    for slot = 0, 1 do
        actor(slot, function(player)
            if walkOrigins[slot + 1] then
                walkDistances[slot + 1] = math.max(
                    walkDistances[slot + 1],
                    player.Position:Distance(walkOrigins[slot + 1])
                )
            end
        end)
    end
end
local function advance(t)
    if finished then
        return
    end
    if
        phase == "used"
        and case.special
        and native.rooms_ready()
        and native.api_info().worldEpoch == useEpoch + 1
    then
        -- ERROR-room rewards must not replace the inventory preservation oracle.
        for slot = 0, 1 do
            actor(slot, clear)
        end
    end
    if phase == "init" then
        if t < 30 or not usable() then
            return
        end
        local level = Game():GetLevel()
        assert(Game().Difficulty == case.difficulty and level:GetStage() == 1)
        initialStage, initialType, initialSeed =
            level:GetStage(), level:GetStageType(), Game():GetSeeds():GetStartSeed()
        source = level:GetStartingRoomIndex()
        target = findRoom(case.cross and RoomType.ROOM_DEFAULT or RoomType.ROOM_SHOP)
        preparePlayers()
        mark("prepared", t)
    elseif phase == "prepared" and t - phaseAt > 30 and usable() then
        if case.special then
            beforeEpoch = native.api_info().worldEpoch
            actor(0, function(player)
                player:UseActiveItem(CollectibleType.COLLECTIBLE_R_KEY, UseFlag.USE_NOANIM)
            end)
            report("PREPARE_NATIVE_R_KEY checkpoint_for_first_visit=true")
            mark("restart", t)
        elseif case.cross then
            assert(native.rooms_move(1, target, 0, -1))
            mark("cross-split", t)
        else
            checkpoint = roster()
            assert(native.rooms_move(1, target, 0, -1))
            mark("neighbor", t)
        end
    elseif phase == "restart" and t - phaseAt > 150 and usable() then
        assert(
            native.api_info().worldEpoch == beforeEpoch + 1,
            "R Key did not create exactly one checkpoint barrier"
        )
        local level = Game():GetLevel()
        assert(level:GetStage() == 1 and Game():IsGreedMode(), "R Key left Greed mode")
        initialStage, initialType, initialSeed =
            level:GetStage(), level:GetStageType(), Game():GetSeeds():GetStartSeed()
        source, target = level:GetStartingRoomIndex(), findRoom(RoomType.ROOM_SHOP)
        for slot = 0, 1 do
            actor(slot, function(player)
                assert(
                    Game():GetLevel():GetCurrentRoomIndex() == source
                        and Game():GetRoom():IsFirstVisit()
                )
                player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                player:SetMinDamageCooldown(10000)
            end)
        end
        assert(native.rooms_move(0, target, 0, -1))
        mark("special-source", t)
    elseif phase == "special-source" and t - phaseAt > 60 and usable() then
        assert(
            native.rooms_positions()["0"].index == target
                and native.rooms_positions()["1"].index == source
        )
        actor(1, function()
            assert(
                Game():GetRoom():IsFirstVisit(),
                "Greed native special branch needs a first visit"
            )
        end)
        mutateAndUse(t)
    elseif phase == "neighbor" and t - phaseAt > 60 and usable() then
        assert(
            native.rooms_positions()["1"].index == target
                and native.rooms_positions()["0"].index == source
        )
        mutateAndUse(t)
    elseif phase == "cross-split" and t - phaseAt > 60 and usable() then
        assert(native.rooms_positions()["1"].index == target)
        actor(1, clear)
        checkpoint = roster()
        beforeEpoch = native.api_info().worldEpoch
        actor(0, function(player)
            clear()
            local room = Game():GetRoom()
            trapIndex = room:GetGridIndex(room:GetCenterPos() + Vector(80, 0))
            assert(not room:GetGridEntity(trapIndex), "Trapdoor preparation grid is occupied")
            assert(room:SpawnGridEntity(trapIndex, GridEntityType.GRID_TRAPDOOR, 0, 187, 0))
            local trap = assert(room:GetGridEntity(trapIndex))
            trap.State = 2
            trapPosition = trap.Position
            player.Position, player.Velocity = room:GetCenterPos() - Vector(100, 0), Vector.Zero
        end)
        report("PREPARE_NATIVE_TRAPDOOR stage=1 expected=2")
        mark("trapdoor", t)
    elseif phase == "trapdoor" then
        if native.api_info().worldEpoch > beforeEpoch then
            mark("second-floor", t)
        elseif t - phaseAt > 30 then
            actor(0, function(player)
                player.Position, player.Velocity = trapPosition, Vector.Zero
            end)
        end
    elseif phase == "second-floor" and t - phaseAt > 150 and usable() then
        assert(
            native.api_info().worldEpoch == beforeEpoch + 1 and Game():GetLevel():GetStage() == 2,
            "Native trapdoor did not enter the second floor exactly once"
        )
        report("SECOND_FLOOR_READY native_exit=true")
        mutateAndUse(t)
    elseif phase == "used" and t - phaseAt > 180 and usable() then
        assert(
            native.api_info().worldEpoch == useEpoch + 1,
            "Hourglass generated multiple or missing transactions"
        )
        checkResult(true)
        hostChecked, arrivedAt = true, t
        report(
            "RESULT_PASS stage="
                .. Game():GetLevel():GetStage()
                .. " type="
                .. Game():GetLevel():GetStageType()
                .. " room0="
                .. native.rooms_positions()["0"].index
                .. " room1="
                .. native.rooms_positions()["1"].index
                .. " coins="
                .. (case.special and 27 or 20)
                .. " visible=true controls=true"
        )
        mark("wait-walk", t)
    elseif phase == "wait-walk" and t >= WALK_AT - 60 and usable() then
        assert(
            hostChecked and arrivedAt < WALK_AT - 60,
            "Native transition missed the shared input window"
        )
        for slot = 0, 1 do
            actor(slot, function(player)
                clear()
                -- ERROR-room exits occupy the lower center lane. Keep the
                -- movement check above them so it cannot initiate a new floor.
                player.Position = Game():GetRoom():FindFreePickupSpawnPosition(
                    Game():GetRoom():GetCenterPos() + Vector(-100 + slot * 70, -80),
                    0,
                    true
                )
                player.Velocity = Vector.Zero
                walkOrigins[slot + 1], walkDistances[slot + 1] = player.Position, 0
                report(
                    "VISUAL slot="
                        .. slot
                        .. " visible="
                        .. tostring(player.Visible)
                        .. " no_damage_blink="
                        .. tostring(player:HasEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK))
                )
            end)
        end
        walkingPrepared = true
        mark("walk", t)
    elseif phase == "walk" then
        observeWalk()
        if t > WALK_END + 90 and usable() then
            checkResult(false)
            for slot = 0, 1 do
                assert(walkDistances[slot + 1] > 5, "Normal movement remained locked")
                report("WALK_PASS slot=" .. slot .. " distance=" .. walkDistances[slot + 1])
            end
            finished = true
            report("PASS authority=true native_route=true")
        end
    end
    assert(t - phaseAt < 900 and t < WALK_END + 300, "Release hourglass phase stalled: " .. phase)
end
function _IsaacLanFrame()
    renders = renders + 1
    local status = frame()
    assert(status.phase ~= 4 and not (status.phase == 9 and status.error ~= ""), status.error)
    verified = status.verified
    native.test_gamepad(0)
    if not linked and renders >= (host and 300 or 360) and status.scene == 1 then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if status.phase == 2 then
        if not chosen then
            chosen = true
            assert(native.net_choose(0, 1))
        end
        if
            host
            and not started
            and status.players == 2
            and status.ready0 == 1
            and status.ready1 == 1
        then
            started = true
            _IsaacLanCommand("start", "YV039KQF:" .. case.difficulty .. ":0:0:0:0")
        end
    end
    if native.api_info().nowMs - lastHeartbeat > 10000 then
        lastHeartbeat = native.api_info().nowMs
        report("HEARTBEAT phase=" .. phase .. " verified=" .. verified)
    end
    return status
end
local function decodeTransition(bytes)
    -- Bounded read-only inspection of the native packet; no state is applied.
    local position = 1 + 2 + 4 * (4 + 523)
    local count
    count, position = string.unpack("B", bytes, position)
    assert(count == 2, "Native checkpoint lost a team member")
    local locations = {}
    for slot = 1, count do
        local dimension, index, x, y
        dimension, index, x, y, position = string.unpack(">i4i4ff", bytes, position)
        locations[slot] = { dimension = dimension, index = index, x = x, y = y }
    end
    local length
    length, position = string.unpack(">I4", bytes, position)
    position = position + length
    local present
    present, position = string.unpack("B", bytes, position)
    assert(present == 1, "Hourglass did not record its selected native transition")
    local index, direction, animation, dimension
    index, direction, animation, dimension, position = string.unpack(">i4i4i4i4", bytes, position)
    assert(position + 7 == #bytes, "Unexpected native rewind packet suffix")
    return { index = index, direction = direction, animation = animation, dimension = dimension },
        locations
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        function()
            local values = {}
            for action = 0, 15 do
                values[#values + 1] = string.pack(
                    ">I2",
                    verified >= WALK_AT
                            and verified < WALK_END
                            and action == ButtonAction.ACTION_RIGHT
                            and 65535
                        or 0
                )
            end
            return table.concat(values) .. string.pack(">I2", 0)
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
            initialStage, initialType, initialSeed =
                initialStage or value[4],
                initialType or value[5],
                initialSeed or Game():GetSeeds():GetStartSeed()
            if restartEpoch and value[14] == restartEpoch then
                initialStage, initialType, initialSeed =
                    value[4], value[5], Game():GetSeeds():GetStartSeed()
            end
            if reliableEpoch and value[14] >= reliableEpoch then
                assert(value[14] == reliableEpoch, "Replica received another unexpected transition")
                assert(
                    #value[9] == 2
                        and Game():GetLevel():GetStage() == value[4]
                        and Game():GetLevel():GetStageType() == value[5],
                    "Replica restored a different native world"
                )
                if not replicaChecked and t > (arrivedAt or t) + 120 and usable() then
                    checkResult(true)
                    replicaChecked = true
                    report(
                        "REPLICA_RESULT_PASS selected_index="
                            .. selected.index
                            .. " selected_animation="
                            .. selected.animation
                    )
                end
                arrivedAt = arrivedAt or t
                if t >= WALK_AT - 15 and not walkingPrepared and usable() then
                    assert(
                        replicaChecked,
                        "Replica did not validate before the shared input window"
                    )
                    for slot = 0, 1 do
                        actor(slot, function(player)
                            walkOrigins[slot + 1], walkDistances[slot + 1] = player.Position, 0
                        end)
                    end
                    walkingPrepared = true
                end
                if walkingPrepared then
                    observeWalk()
                end
                if not finished and t > WALK_END + 90 and usable() then
                    checkResult(false)
                    assert(replicaChecked and walkingPrepared and snapshots > 100)
                    assert(
                        rewindEvents == 1
                            and floorEvents == (case.cross and 1 or 0)
                            and restartEvents == (case.special and 1 or 0),
                        "Reliable transaction counts differ"
                    )
                    for slot = 0, 1 do
                        assert(
                            walkDistances[slot + 1] > 5,
                            "Replica did not observe normal movement"
                        )
                        report("WALK_PASS slot=" .. slot .. " distance=" .. walkDistances[slot + 1])
                    end
                    finished = true
                    report("PASS authority=false snapshots=" .. snapshots)
                end
            end
            return true
        end,
        present,
        function(epoch, stage, stageType, animation, same, rewind, restart, cinematic, ...)
            if #rewind > 0 then
                rewindEvents = rewindEvents + 1
                assert(
                    rewindEvents == 1 and animation == 12 and restart == 0,
                    "Unexpected duplicate rewind event"
                )
                selected, savedLocations = decodeTransition(rewind)
                assert(
                    selected.animation == (case.special and 3 or 12) and selected.dimension == 0,
                    "Replica did not receive the authority's native route"
                )
                assert(
                    not case.special or selected.index == GridRooms.ROOM_ERROR_IDX,
                    "Greed first-visit special route did not select I AM ERROR"
                )
                reliableEpoch = epoch
                report(
                    "SELECTED_NATIVE index="
                        .. selected.index
                        .. " direction="
                        .. selected.direction
                        .. " animation="
                        .. selected.animation
                        .. " dimension="
                        .. selected.dimension
                )
            elseif restart == 1 then
                restartEvents = restartEvents + 1
                restartEpoch = epoch
                assert(
                    case.special and restartEvents == 1 and animation == 0,
                    "Unexpected R Key event"
                )
            else
                floorEvents = floorEvents + 1
                assert(
                    case.cross and floorEvents == 1 and animation ~= 6 and restart == 0,
                    "Unexpected Home or native floor event"
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
                    .. " restart="
                    .. restart
                    .. " rewind_bytes="
                    .. #rewind
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

-- Explicit test-only lifecycle consumed by both suite coordinators.
return {
    done = function()
        return finished
    end,
}
