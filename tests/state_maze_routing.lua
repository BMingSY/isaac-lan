-- Native Maze routing with real door input; metadata is fixture-only.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local linked, chosen, finished, renders = false, false, false, 0
local phase, at, visit, steps = "setup", 0, 0, 0
local masks, rooms, seen = { 0, 0 }, {}, {}
local baseInput = native.input_bot
native.input_bot = function()
    return baseInput(finished and 0 or 1, finished and 0 or masks[host and 1 or 2])
end
local walker, resident, previous, intended, departure = 1, nil, nil, nil, nil
local redirected, occupied, redirectedOccupied, hostWalks = 0, 0, 0, 0
local ghostWalks, ghostRedirects, ghostMode = 0, 0, false
local marker, markerSeed, residentFrames, snapshots = nil, nil, 0, 0
local residentEnemy = nil
local acceptedPositions = {}
local inward = { Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) }
local buttons = { 1, 4, 2, 8 }
local function report(message)
    Isaac.DebugString("LAN_NETWORK MAZE " .. message)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end, 1))
end
local function clear(p)
    p:SetMinDamageCooldown(10000)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:IsActiveEnemy(false) and not (residentEnemy and residentEnemy.Ref == e) then
            e:Remove()
        end
    end
end
local function coherent(slot)
    local location = native.rooms_positions()[tostring(slot)]
    actor(slot, function(p, room)
        local level = Game():GetLevel()
        assert(
            level:GetRoomByIdx(level:GetCurrentRoomIndex(), location.dimension).SafeGridIndex
                == location.index,
            "Native/logical room mismatch"
        )
        assert(
            level:GetCurrentRoomDesc().SafeGridIndex == location.index,
            "Descriptor/key mismatch"
        )
        -- Native door walking can cross the room edge before the queued
        -- transfer commits. Check landing only after that transition settles.
        if phase ~= "walking" then
            assert(
                room:IsPositionInRoom(p.Position, 0),
                string.format(
                    "Arrival outside native room: role=%s slot=%d phase=%s room=%d x=%.2f y=%.2f snapshot=%s shape=%d frame=%d",
                    host and "host" or "client",
                    slot,
                    phase,
                    location.index,
                    p.Position.X,
                    p.Position.Y,
                    tostring(acceptedPositions[slot]),
                    room:GetRoomShape(),
                    room:GetFrameCount()
                )
            )
        end
        if host then
            clear(p)
        end
    end)
end
local function mark(value, t)
    phase, at = value, t
    report("STEP " .. value .. " tick=" .. t)
end
local function holdResidentCombat()
    if residentEnemy and residentEnemy.Ref and residentEnemy.Ref:Exists() then
        return
    end
    actor(1 - walker, function(_, room)
        local enemy = Isaac.Spawn(10, 0, 0, room:GetCenterPos() + Vector(-80, 0), Vector.Zero, nil)
        enemy:AddEntityFlags(EntityFlag.FLAG_FREEZE)
        enemy.EntityCollisionClass, enemy.CollisionDamage = 0, 0
        residentEnemy = EntityPtr(enemy)
        room:SetClear(false)
    end)
end
local function startWalk(t)
    local location = native.rooms_positions()[tostring(walker)]
    departure = location.index
    -- Maze's native candidates exclude cleared descriptors. Keep a reusable
    -- set of uncleared, unloaded rooms without replacing its RNG or selection.
    for _, index in ipairs(rooms) do
        if index ~= departure and index ~= resident then
            Game():GetLevel():GetRoomByIdx(index, 0).Clear = false
        end
    end
    if resident and departure ~= resident then
        holdResidentCombat()
    end
    actor(walker, function(p, room)
        local choices = {}
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            local d = door
                and door.TargetRoomIndex >= 0
                and Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex, 0)
            if d and d.Data and d.Data.Type == RoomType.ROOM_DEFAULT then
                choices[#choices + 1] = { slot = slot, door = door, index = d.SafeGridIndex }
            end
        end
        assert(#choices > 0, "No ordinary return door after Maze entry")
        local selected = choices[steps % #choices + 1]
        for _, choice in ipairs(choices) do
            if choice.index == resident and steps % 3 == 0 then
                selected = choice
                break
            end
            if selected.index == previous and choice.index ~= previous then
                selected = choice
            end
        end
        intended = selected.index
        selected.door:Open()
        p.Position = selected.door.Position + inward[selected.slot % 4 + 1] * 32
        p.Velocity = Vector.Zero
        masks[walker + 1] = buttons[selected.slot % 4 + 1]
    end)
    mark("walking", t)
end
local function advance(t)
    if t < 30 then
        return
    end
    for slot = 0, 1 do
        coherent(slot)
    end
    if marker then
        actor(1 - walker, function(_, room)
            assert(
                marker.Ref and marker.Ref:Exists() and marker.Ref.InitSeed == markerSeed,
                "Occupied-room entry replaced resident entities"
            )
            assert(room:GetFrameCount() >= residentFrames, "Occupied room was reinitialized")
            residentFrames = room:GetFrameCount()
        end)
    end
    local level = Game():GetLevel()
    if phase == "setup" then
        level:SetStage(11, StageType.STAGETYPE_ORIGINAL)
        Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
        mark("setup-floor", t)
    elseif phase == "setup-floor" and t - at >= 100 then
        assert(level:GetStage() == 11)
        level:RemoveCurses(level:GetCurses())
        local list = level:GetRooms()
        for i = 0, list.Size - 1 do
            local d = list:Get(i)
            if d.Data.Type == RoomType.ROOM_DEFAULT then
                rooms[#rooms + 1] = d.SafeGridIndex
            else
                -- The native Maze pool includes uncleared terminal bosses.
                -- Their team-gathering lifecycle invalidates the resident-room
                -- prerequisite, so keep this routing trial on ordinary rooms.
                level:GetRoomByIdx(d.SafeGridIndex, 0).Clear = true
            end
        end
        assert(#rooms >= 4)
        mark("visit", t)
    elseif phase == "visit" and t - at >= 12 then
        visit = visit + 1
        if rooms[visit] then
            assert(native.rooms_move(1, rooms[visit], 0, -1))
            at = t
        else
            resident = rooms[math.max(2, math.floor(#rooms / 2))]
            assert(native.rooms_move(0, resident, 0, -1))
            mark("ready", t)
        end
    elseif phase == "ready" and t - at >= 20 then
        actor(0, function(p, room)
            p.Position = room:GetCenterPos()
            local pickup =
                Isaac.Spawn(5, 100, 1, room:GetCenterPos() + Vector(60, 0), Vector.Zero, nil)
            marker, markerSeed, residentFrames =
                EntityPtr(pickup), pickup.InitSeed, room:GetFrameCount()
        end)
        level:AddCurse(LevelCurse.CURSE_OF_MAZE, false)
        mark("choose", t)
    elseif phase == "choose" and t - at >= 18 then
        if ghostMode then
            local survivorPosition
            actor(0, function(p)
                survivorPosition = p.Position
            end)
            actor(1, function(p, room)
                assert(p:IsCoopGhost(), "Guest lost its ghost state")
                assert(
                    native.rooms_positions()["1"].index == native.rooms_positions()["0"].index,
                    "Ghost rerouted instead of following the resolved destination"
                )
                assert(
                    room:IsPositionInRoom(p.Position, 0),
                    "Ghost followed into a missing quadrant"
                )
                assert(
                    -- Death can occur while already sharing the survivor's
                    -- room. Only a subsequent room transfer promises landing
                    -- beside them; native ghosts can move freely in one room.
                    ghostWalks == 0 or (p.Position - survivorPosition):Length() < 30,
                    "Ghost missed survivor landing"
                )
            end)
        end
        startWalk(t)
    elseif phase == "walking" then
        local current = native.rooms_positions()[tostring(walker)].index
        if current ~= departure then
            masks[walker + 1] = 0
            previous, steps = departure, steps + 1
            if current ~= intended then
                redirected = redirected + 1
                report(
                    "REDIRECT slot=" .. walker .. " requested=" .. intended .. " actual=" .. current
                )
                if current == resident then
                    redirectedOccupied = redirectedOccupied + 1
                end
                if ghostMode then
                    ghostRedirects = ghostRedirects + 1
                end
            end
            if current == resident then
                occupied = occupied + 1
                if residentEnemy and residentEnemy.Ref then
                    residentEnemy.Ref:Remove()
                end
                residentEnemy = nil
            end
            if walker == 0 then
                hostWalks = hostWalks + 1
            end
            if ghostMode then
                ghostWalks = ghostWalks + 1
            end
            seen[current] = true
            if walker == 1 and steps >= 100 and redirected >= 3 and occupied >= 2 then
                -- Keep the same processes: the host now walks, guest stays resident.
                marker.Ref:Remove()
                marker = nil
                if residentEnemy and residentEnemy.Ref then
                    residentEnemy.Ref:Remove()
                end
                residentEnemy = nil
                walker = 0
                resident = native.rooms_positions()["1"].index
                actor(1, function(p, room)
                    p.Position = room:GetCenterPos()
                    local pickup = Isaac.Spawn(
                        5,
                        100,
                        1,
                        room:GetCenterPos() + Vector(60, 0),
                        Vector.Zero,
                        nil
                    )
                    marker, markerSeed, residentFrames =
                        EntityPtr(pickup), pickup.InitSeed, room:GetFrameCount()
                end)
                mark("choose", t)
            elseif walker == 0 and hostWalks >= 30 and not ghostMode then
                marker.Ref:Remove()
                marker = nil
                if residentEnemy and residentEnemy.Ref then
                    residentEnemy.Ref:Remove()
                end
                residentEnemy = nil
                resident, ghostMode = nil, true
                actor(1, function(p)
                    p:ChangePlayerType(PlayerType.PLAYER_BLUEBABY_B)
                    p:Kill()
                end)
                mark("ghost-ready", t)
            elseif ghostMode and ghostWalks >= 30 and ghostRedirects >= 1 then
                level:RemoveCurses(level:GetCurses())
                level:SetStage(2, StageType.STAGETYPE_ORIGINAL)
                Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
                mark("floor", t)
            else
                mark("choose", t)
            end
        elseif t - at > 150 then
            error("Native door stalled after Maze: source=" .. departure .. " target=" .. intended)
        end
    elseif phase == "ghost-ready" and t - at >= 120 then
        mark("choose", t)
    elseif phase == "floor" and t - at > 120 then
        assert(native.rooms_ready())
        local count = 0
        for _ in pairs(seen) do
            count = count + 1
        end
        assert(count >= 4 and redirected >= 3 and occupied >= 2 and hostWalks >= 30)
        assert(ghostWalks >= 30 and ghostRedirects >= 1)
        finished = true
        mark("done", t)
        report(
            "PASS redirects="
                .. redirected
                .. " resident="
                .. occupied
                .. " redirected_resident="
                .. redirectedOccupied
                .. " walks="
                .. steps
                .. " ghost_walks="
                .. ghostWalks
                .. " ghost_redirects="
                .. ghostRedirects
        )
    end
    assert(steps < 240, "Maze coverage did not reach required cases")
end
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    if status.phase == 4 or status.phase == 9 then
        Isaac.DebugString("LAN_NETWORK FAILED " .. tostring(status.error))
    end
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
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
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    native.input_bot(1, finished and 0 or masks[host and 1 or 2])
    native.test_gamepad(0)
    return status
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if native.rooms_ready() and not finished then
            advance(t)
        end
    end, function(slot, t)
        local bytes, stable = collect(slot, t)
        if bytes then
            return string.pack(">s4", bytes) .. _IsaacLanState.encode({ masks, phase, finished }),
                stable
        end
    end, function(bytes, t, ack, betweenUpdates, stable)
        local body, pos = string.unpack(">s4", bytes)
        if restore(body, t, ack, betweenUpdates, stable) == false then
            return false
        end
        local meta = _IsaacLanState.decode(bytes:sub(pos))
        masks, phase = meta[1], meta[2]
        local fields = _IsaacLanModules["sync/fields"]
        local value =
            _IsaacLanModules["sync/world_schema"].unpack(_IsaacLanState.decode(body, stable), t)
        for _, actor in ipairs(value.actors) do
            local position = actor[fields.actor.entity][fields.entity.position]
            acceptedPositions[actor[fields.actor.controller] - 1] =
                string.format("%.2f,%.2f", position[1], position[2])
        end
        coherent(1)
        snapshots = snapshots + 1
        if meta[3] and not finished then
            assert(snapshots >= 100)
            finished = true
            report("PASS replica consistency snapshots=" .. snapshots)
        end
        return true
    end, present, beginFloor)
end
