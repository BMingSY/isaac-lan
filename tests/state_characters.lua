local testInput = assert(_IsaacLanTestInput)
local native = assert(_IsaacLan)
local config = assert(_IsaacLanTest)
local owner = { Name = "Isolated native frontend test" }
local host, port = config.host, config.port
local linked, finished = false, false
local total = config.players
local fields = assert(_IsaacLanModules["sync/fields"])
local expectedArrival, arrivals = nil, 0
local restoredSoul, restoredSkeleton = false, false
local function report(s)
    Isaac.DebugString("LAN_NETWORK " .. s)
end
local entered = _IsaacLanRoomEntered
function _IsaacLanRoomEntered(...)
    local check = expectedArrival
        and Game():GetLevel():GetCurrentRoomIndex() == expectedArrival.index
        and Isaac.GetPlayer(0).ControllerIndex == expectedArrival.slot + 1
    local blocked, positions = false, {}
    if check then
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            positions[i] = p.Position
            blocked = blocked
                or Game():GetRoom():GetGridCollisionAtPos(p.Position)
                    ~= GridCollisionClass.COLLISION_NONE
        end
        if expectedArrival.mustCorrect then
            assert(blocked, "Travel fixture did not reproduce an obstructed native landing")
        end
    end
    local residentPosition = check and expectedArrival.resident.Position
    entered(...)
    if check then
        assert(
            (expectedArrival.resident.Position - residentPosition):LengthSquared() < 0.01,
            "Arrival correction moved the resident"
        )
        local room = Game():GetRoom()
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            assert(not p.CanFly, "Travel fixture requires grounded arriving bodies")
            assert(room:IsPositionInRoom(p.Position, p.Size), "Arrival crossed the room boundary")
            if not blocked then
                assert(
                    (p.Position - positions[i]):LengthSquared() < 0.01,
                    "Safe native landing was moved"
                )
            end
            for _, offset in ipairs({
                Vector.Zero,
                Vector(-1, -1),
                Vector(-1, 1),
                Vector(1, -1),
                Vector(1, 1),
            }) do
                assert(
                    room:GetGridCollisionAtPos(p.Position + offset * p.Size)
                        == GridCollisionClass.COLLISION_NONE,
                    "Doorless arrival overlaps an obstacle"
                )
            end
        end
        arrivals = arrivals + 1
        report(
            "TRAVEL "
                .. expectedArrival.name
                .. " clear; bodies="
                .. Game():GetNumPlayers()
                .. " corrected="
                .. tostring(blocked)
        )
        expectedArrival.resident.ControlsEnabled = true
        expectedArrival = nil
    end
end
local starts, renders, chosen, initialStage = 0, 0, false, nil
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function()
    starts = starts + 1
    assert(linked and starts == 1, "Network start depended on an earlier solo game")
    report("GAME_STARTED " .. Game():GetSeeds():GetStartSeedString())
    initialStage = Game():GetLevel():GetStage()
end)
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= 300 then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
    if status.phase == 2 and not chosen then
        _IsaacLanCommand("choose", (host and "19" or "16") .. ":1")
        chosen = true
    end
    if linked then
        if status.phase == 4 then
            report("FAILED " .. status.error)
        end
        if
            host
            and status.phase == 2
            and status.players == total
            and status.ready0 == 1
            and status.ready1 == 1
        then
            _IsaacLanCommand("start", "YV039KQF:0:19:16:0:0")
        end
        if status.verified >= 760 and not finished then
            assert(starts == 1, "Native menu start was not exercised")
            assert(
                Game():GetLevel():GetStage() > initialStage,
                "Floor transition was not completed"
            )
            if not host then
                assert(
                    restoredSoul and restoredSkeleton,
                    "Both replica form transitions were not observed"
                )
            end
            finished = true
            report("VERIFIED " .. status.verified)
            report("PASS authoritative character forms")
        end
    end
    return status
end

local gate = native.net_gate
native.net_gate = function(capture, apply, collect, restore, present, beginFloor)
    local tick, inputTick = -1, 0
    local first, other
    local switched, returned = false, false
    local function obstructedArrival(slot, destination, kind, name, nativeTransition)
        assert(native.rooms_with_player(1, function()
            local room, p = Game():GetRoom(), Isaac.GetPlayer(0)
            assert(Game():GetLevel():GetCurrentRoomIndex() == destination)
            local point = room:GetGridPosition(room:GetGridIndex(room:GetCenterPos()))
            local index = room:GetGridIndex(point)
            room:RemoveGridEntity(index, 0, false)
            room:Update()
            assert(room:SpawnGridEntity(index, kind, 0, 123, 0))
            local collision = kind == GridEntityType.GRID_PIT and GridCollisionClass.COLLISION_PIT
                or GridCollisionClass.COLLISION_SOLID
            room:GetGridEntity(index).CollisionClass = collision
            assert(
                room:GetGridCollisionAtPos(point) == collision,
                "Travel obstacle has no collision"
            )
            if not p:HasCollectible(CollectibleType.COLLECTIBLE_TRANSCENDENCE) then
                p:AddCollectible(CollectibleType.COLLECTIBLE_TRANSCENDENCE, 0, false)
            end
            p.ControlsEnabled = false
            p.Position, p.Velocity = point, Vector.Zero
            assert(p.CanFly, "Resident must be able to stand above the obstacle")
            expectedArrival = {
                slot = slot,
                index = destination,
                name = name,
                position = point,
                resident = p,
                mustCorrect = kind == GridEntityType.GRID_ROCK,
            }
        end, 1))
        if nativeTransition then
            assert(native.rooms_with_player(slot, function()
                for i = 0, Game():GetNumPlayers() - 1 do
                    local p = Isaac.GetPlayer(i)
                    p.Position, p.Velocity = expectedArrival.position, Vector.Zero
                end
                Game():GetLevel().EnterDoor = -1
                Game():GetLevel().LeaveDoor = -1
                Game():StartRoomTransition(
                    destination,
                    -1,
                    RoomTransitionAnim.TELEPORT,
                    Isaac.GetPlayer(0),
                    0
                )
            end, 1))
        else
            assert(native.rooms_teleport(slot, destination, 0))
        end
    end
    local function synthetic()
        local values = {}
        local trigger = 0
        if not host and (inputTick == 120 or inputTick == 360) then
            trigger = 1 << 11
        end
        for action = 0, testInput.actionCount - 1 do
            local direction = ({ 0, 2, 1, 3 })[math.floor(inputTick / 20) % 4 + 1]
            local v = (
                (inputTick < 400 and (action == direction or action == 5))
                or (action == 11 and trigger ~= 0)
            )
                    and testInput.maxValue
                or 0
            values[action] = v
        end
        inputTick = inputTick + 1
        return testInput.encode({ values = values, triggered = trigger })
    end
    return gate(
        synthetic,
        function(t, n, b)
            tick = t
            apply(t, n, b)
            if not first then
                local level = Game():GetLevel()
                first = level:GetCurrentRoomIndex()
                for i = 0, level:GetRooms().Size - 1 do
                    local desc = level:GetRooms():Get(i)
                    if
                        desc.SafeGridIndex ~= first
                        and desc.Data.Type == RoomType.ROOM_DEFAULT
                        and desc.Data.Shape == RoomShape.ROOMSHAPE_1x1
                    then
                        other = desc.SafeGridIndex
                        break
                    end
                end
                assert(other)
            end
            local moves = {
                [20] = { 1, other },
                [80] = { 0, other },
                [200] = { 1, first },
                [420] = { 1, other },
                [520] = { 0, first },
            }
            if moves[t] then
                assert(native.rooms_move(moves[t][1], moves[t][2], 0, 0))
            end
            if t == 300 then
                obstructedArrival(0, first, GridEntityType.GRID_ROCK, "resolved rock", false)
            elseif t == 460 then
                obstructedArrival(0, other, GridEntityType.GRID_ROCK, "native teleport", true)
            elseif t == 550 then
                obstructedArrival(0, other, GridEntityType.GRID_PIT, "resolved pit", false)
            elseif t == 590 then
                assert(arrivals == 3, "Travel cases were not completed")
                assert(native.rooms_with_player(0, function()
                    Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
                end, 1))
            end
            for i = 0, Game():GetNumPlayers() - 1 do
                Isaac.GetPlayer(i):SetMinDamageCooldown(60)
            end
            if t % 60 == 30 then
                local positions = native.rooms_positions()
                for slot = 0, 1 do
                    assert(native.rooms_with_player(slot, function()
                        for _, entity in ipairs(Isaac.GetRoomEntities()) do
                            local p = entity:ToPlayer()
                            if p then
                                assert(
                                    positions[tostring(p.ControllerIndex - 1)].index
                                        == Game():GetLevel():GetCurrentRoomIndex(),
                                    "Character companion was left in a different room"
                                )
                                if
                                    p:GetPlayerType() == PlayerType.PLAYER_THESOUL
                                    and t > 120
                                    and t < 360
                                then
                                    switched = true
                                elseif
                                    switched
                                    and p:GetPlayerType() == PlayerType.PLAYER_THEFORGOTTEN
                                then
                                    returned = true
                                end
                            end
                        end
                    end))
                end
            end
            if t == 700 then
                assert(switched and returned, "Forgotten did not switch to Soul and back")
                report("CHARACTERS native form switching and transfers verified")
            end
        end,
        collect,
        function(bytes, t, ack, betweenUpdates, stable)
            if restore(bytes, t, ack, betweenUpdates, stable) == false then
                return false
            end
            local v = _IsaacLanState.decode(bytes, stable)
            for _, actor in ipairs(v[9]) do
                local player = Isaac.GetPlayer(actor[1])
                assert(
                    player.ControllerIndex == actor[2] and player:GetPlayerType() == actor[4][1],
                    "Character replica differs"
                )
                local inventory = actor[fields.actor.inventory]
                local hidden = inventory[fields.inventory.subplayer]
                if hidden then
                    local other = assert(player:GetSubPlayer(), "Replica hidden body is missing")
                    assert(
                        other:GetPlayerType() == hidden[fields.subplayer.type],
                        "Hidden replica form differs"
                    )
                    local hearts = hidden[fields.subplayer.hearts]
                    for _, name in ipairs({
                        "Soul",
                        "Black",
                        "Bone",
                        "Max",
                        "Broken",
                        "Eternal",
                        "Golden",
                        "Rotten",
                    }) do
                        local field = fields.hearts[name:lower()]
                        assert(
                            other["Get" .. name .. "Hearts"](other) == hearts[field],
                            "Hidden replica " .. name .. " hearts differ"
                        )
                    end
                    assert(
                        other:GetHearts() == hearts[fields.hearts.red],
                        "Hidden replica red hearts differ"
                    )
                    if player:GetPlayerType() == PlayerType.PLAYER_THESOUL then
                        restoredSoul = true
                    elseif restoredSoul then
                        restoredSkeleton = true
                    end
                end
            end
        end,
        present,
        beginFloor
    )
end
