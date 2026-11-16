local native = assert(_IsaacLan)
local owner = { Name = "Isolated authoritative state regression" }
local host, port
if _IsaacLanTest then
    host, port = _IsaacLanTest.host, _IsaacLanTest.port
else
    local f = assert(io.open("./lan-test-role.txt", "r"))
    host = f:read("*l") == "host"
    f:close()
    f = assert(io.open("./lan-test-menu-port.txt", "r"))
    port = f:read("*l")
    f:close()
end
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local renders, linked, chosen, finished = 0, false, false, false
local motionFile, moveSign, motionSamples = nil, 0, 0
if not host and io then
    motionFile = assert(io.open("./lan-test-digest-motion.csv", "w"))
end
local lastAuthority, wallFrames, settledFrames = nil, 0, 0
local gridCases = {
    {
        prepare = 1040,
        move = 1060,
        turn = 1100,
        reverse = 1140,
        stop = 1180,
        kind = GridEntityType.GRID_POOP,
        size = 10,
    },
    {
        prepare = 1220,
        move = 1240,
        turn = 1280,
        reverse = 1320,
        stop = 1360,
        kind = GridEntityType.GRID_ROCK,
        size = 10,
    },
}
local gridCenter, gridStart = Vector(360, 280), Vector(300, 280)
local pad = { up = 1, down = 2, left = 4, right = 8 }
local finishTick, breakTick, walkThroughTick, stopAfterBreak = 1500, 1380, 1400, 1440
local contactLeadTicks, settledLeadTicks = 20, 20
local gridRemovalLeadTicks = 10
local maximumAllowedContactSpeed, minimumContactSamples = 450, 100
local contactSamples, maximumContactSpeed, brokenGridSamples = {}, 0, 0
local previousContact, previousContactTime, previousContactCase
local fixtureRoom, fixtureDoors = nil, {}
local function checkRoom()
    local locations = native.rooms_positions()
    if not fixtureRoom and locations["0"] then
        fixtureRoom = { index = locations["0"].index, dimension = locations["0"].dimension }
    end
    assert(fixtureRoom, "Motion fixture has no starting room")
    for slot = 0, 1 do
        local location = locations[tostring(slot)]
        assert(
            location
                and location.index == fixtureRoom.index
                and location.dimension == fixtureRoom.dimension,
            "Motion fixture left its room: slot="
                .. slot
                .. " expected="
                .. fixtureRoom.dimension
                .. ":"
                .. fixtureRoom.index
                .. " actual="
                .. (location and (location.dimension .. ":" .. location.index) or "missing")
        )
    end
end
local originalFrame = _IsaacLanFrame
local ticks, corrected, samples = 0, 0, 0
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = originalFrame()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.prepared and native.api_info().ready == 1 then
        checkRoom()
    end
    samples = s.verified
    moveSign = not host and samples >= 30 and (math.floor((samples - 30) / 30) % 2 == 0 and 1 or -1)
        or 0
    if not host and samples >= 600 then
        moveSign = samples < 710 and 1 or samples >= 800 and samples < 850 and -1 or 0
    end
    local buttons = moveSign == 1 and pad.right or moveSign == -1 and pad.left or 0
    if not host then
        for _, case in ipairs(gridCases) do
            if samples >= case.move and samples < case.stop then
                buttons = samples < case.turn and pad.right
                    or samples < case.reverse and (pad.right | pad.down)
                    or (pad.left | pad.up)
            end
        end
        if samples >= walkThroughTick and samples < stopAfterBreak then
            buttons = pad.right
        end
    end
    native.test_gamepad(buttons)
    if s.verified >= finishTick and not finished then
        if not host then
            assert(
                wallFrames > 20 and settledFrames > 20,
                "Wall and stop checks were not exercised"
            )
            for index in ipairs(gridCases) do
                assert(
                    (contactSamples[index] or 0) > minimumContactSamples,
                    "Round-grid contact was not exercised"
                )
            end
            assert(brokenGridSamples > 20, "Broken-grid passage was not exercised")
            report("GRID_CONTACT maximum_speed=" .. maximumContactSpeed)
        end
        finished = true
        if motionFile then
            motionFile:flush()
        end
        report("PASS continuous local movement")
    end
    return s
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        player:SetMinDamageCooldown(10000)
        player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
    end
    return gate(function()
        return capture()
    end, function(t, n, b)
        before(t, n, b)
        ticks = t
        checkRoom()
        if t == 0 then
            report("AUTHORITY host simulation begins")
        end
        if t == 0 then
            for i = 0, 1 do
                Isaac.GetPlayer(i).Position = Vector(320, 220 + i * 60)
            end
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type ~= 1 then
                    e:Remove()
                end
            end
            local room = Game():GetRoom()
            -- Alternating input can drift into an open doorway under latency.
            -- This fixture measures one room's collision, not room transfer.
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door then
                    fixtureDoors[slot] = { locked = door:IsLocked(), opened = door:IsOpen() }
                    door:Close(true)
                    door:SetLocked(true)
                end
            end
            for i = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(i)
                if
                    grid
                    and grid:GetType() ~= GridEntityType.GRID_DOOR
                    and room:GetGridCollision(i) ~= GridCollisionClass.COLLISION_WALL
                then
                    room:RemoveGridEntity(i, 0, false)
                end
            end
        end
        if t == 580 then
            local room = Game():GetRoom()
            for y = 240, 320, 40 do
                room:SpawnGridEntity(
                    room:GetGridIndex(Vector(560, y)),
                    GridEntityType.GRID_ROCK,
                    0,
                    1,
                    0
                )
            end
        end
        for _, case in ipairs(gridCases) do
            if t == case.prepare - gridRemovalLeadTicks then
                local room = Game():GetRoom()
                room:RemoveGridEntity(room:GetGridIndex(gridCenter), 0, false)
            end
            if t == case.prepare then
                local room = Game():GetRoom()
                local index = room:GetGridIndex(gridCenter)
                room:SpawnGridEntity(index, case.kind, 0, 1, 0)
                local grid = room:GetGridEntity(index)
                assert(grid and grid:GetType() == case.kind, "Contact grid was not created")
                local player = Isaac.GetPlayer(1)
                player.Position, player.Velocity = gridStart, Vector.Zero
                report("GRID_CONTACT kind=" .. case.kind .. " size=" .. player.Size)
            end
        end
        if t == breakTick then
            local room = Game():GetRoom()
            room:RemoveGridEntity(room:GetGridIndex(gridCenter), 0, false)
            local player = Isaac.GetPlayer(1)
            player.Position, player.Velocity = gridStart, Vector.Zero
        end
        if t % 120 == 0 then
            report("HOST tick=" .. t)
        end
    end, function(slot, t)
        local bytes, stable = collect(slot, t)
        if io and (t == 150 or t == 300) then
            local out = assert(io.open("./authority-" .. t .. ".bin", "wb"))
            out:write(bytes)
            out:close()
        end
        return bytes, stable
    end, function(bytes, t, ack, betweenUpdates, stable)
        if restore(bytes, t, ack, betweenUpdates, stable) == false then
            return false
        end
        corrected = corrected + 1
        local v = _IsaacLanState.decode(bytes, stable)
        lastAuthority = Vector(v[9][2][3][6][1], v[9][2][3][6][2])
        assert(native.rooms_connected() == v[6], "Roster not restored")
        for _, actor in ipairs(v[9]) do
            local p = Isaac.GetPlayer(actor[1])
            assert(
                math.abs(p.Position.X - actor[3][6][1]) < 0.01
                    and math.abs(p.Position.Y - actor[3][6][2]) < 0.01,
                "Actor position not restored"
            )
            assert(p:GetNumCoins() == actor[4][5][1], "Resources not restored")
        end
        assert(native.rooms_with_player(1, function()
            local ids = {}
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:Exists() then
                    ids[e:GetData().__isaac_lan_replica or -1] = e
                end
            end
            for _, e in ipairs(v[11][3]) do
                local actual = assert(ids[e[1]], "Authoritative entity missing")
                assert(
                    actual.Type == e[2] and actual.Variant == e[3] and actual.SubType == e[4],
                    "Entity identity differs"
                )
                assert(
                    math.abs(actual.Position.X - e[6][1]) < 0.01
                        and math.abs(actual.Position.Y - e[6][2]) < 0.01,
                    "Entity position differs"
                )
            end
        end))
        if corrected % 90 == 0 then
            report("CLIENT corrected=" .. corrected .. " hostTick=" .. t)
        end
    end, present, beginFloor)
end

Isaac.AddCallback(owner, ModCallbacks.MC_POST_RENDER, function()
    if host or finished or not _IsaacLanStatus().prepared then
        return
    end
    local p
    for i = 0, Game():GetNumPlayers() - 1 do
        local actor = Isaac.GetPlayer(i)
        if actor.ControllerIndex == 2 then
            p = actor
            break
        end
    end
    if not p then
        return
    end
    motionSamples = motionSamples + 1
    if motionFile then
        motionFile:write(
            string.format(
                "%.3f,%d,%d,%.6f,%.6f,%d,%.6f,%.6f\n",
                Isaac.GetTime() / 1000,
                _IsaacLanStatus().verified,
                samples,
                p.Position.X,
                p.Position.Y,
                moveSign,
                lastAuthority and lastAuthority.X or 0,
                lastAuthority and lastAuthority.Y or 0
            )
        )
    end
    if samples >= 650 and samples < 710 then
        assert(p.Position.X < 540, "Prediction crossed the rock barrier")
        wallFrames = wallFrames + 1
    end
    if samples >= 950 and samples < gridCases[1].prepare and lastAuthority then
        assert(
            p.Position:Distance(lastAuthority) < 0.5,
            "Stopped prediction did not converge to authority"
        )
        settledFrames = settledFrames + 1
    end
    for index, case in ipairs(gridCases) do
        if samples >= case.move + contactLeadTicks and samples < case.stop then
            local grid = Game():GetRoom():GetGridEntityFromPos(gridCenter)
            assert(grid and grid:GetType() == case.kind, "Contact grid was not restored")
            assert(math.abs(p.Size - case.size) < 0.01, "Contact body size was not restored")
            local now = Isaac.GetTime() / 1000
            if previousContact and previousContactCase == index and now > previousContactTime then
                local speed = p.Position:Distance(previousContact) / (now - previousContactTime)
                maximumContactSpeed = math.max(maximumContactSpeed, speed)
                assert(
                    speed < maximumAllowedContactSpeed,
                    "Grid corner released a burst of prediction correction"
                )
            end
            previousContact, previousContactTime, previousContactCase = p.Position, now, index
            contactSamples[index] = (contactSamples[index] or 0) + 1
            if samples >= case.turn - 10 and samples < case.turn and lastAuthority then
                assert(
                    p.Position:Distance(lastAuthority) < 0.5,
                    "Grid contact stopped short of authority"
                )
            end
        end
    end
    if samples >= stopAfterBreak + settledLeadTicks then
        assert(p.Position.X > gridCenter.X + p.Size, "Broken grid kept blocking prediction")
        assert(p.Position:Distance(lastAuthority) < 0.5, "Broken-grid motion failed to settle")
        brokenGridSamples = brokenGridSamples + 1
    end
end)

-- Explicit test-only lifecycle consumed by both suite coordinators.
return {
    done = function()
        return finished
    end,
    cleanup = function()
        if next(fixtureDoors) then
            native.rooms_with_player(0, function()
                local location = native.rooms_positions()["0"]
                if
                    location
                    and location.index == fixtureRoom.index
                    and location.dimension == fixtureRoom.dimension
                then
                    local room = Game():GetRoom()
                    for slot, prior in pairs(fixtureDoors) do
                        local door = room:GetDoor(slot)
                        if door then
                            door:SetLocked(prior.locked)
                            if prior.opened then
                                door:Open()
                            end
                        end
                    end
                end
            end)
            fixtureDoors = {}
        end
        if motionFile then
            motionFile:close()
            motionFile = nil
        end
    end,
}
