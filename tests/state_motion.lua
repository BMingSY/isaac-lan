local native = assert(_IsaacLan)
local owner = { Name = "Isolated authoritative state regression" }
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local renders, linked, chosen, finished = 0, false, false, false
local motionFile, moveSign, motionSamples =
    host and nil or assert(io.open("./lan-test-digest-motion.csv", "w")), 0, 0
local lastAuthority, wallFrames, settledFrames = nil, 0, 0
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
    moveSign = not host and samples >= 30 and (math.floor((samples - 30) / 30) % 2 == 0 and 1 or -1)
        or 0
    if not host and samples >= 600 then
        moveSign = samples < 710 and 1 or samples >= 800 and samples < 850 and -1 or 0
    end
    native.test_gamepad(moveSign == 1 and 8 or moveSign == -1 and 4 or 0)
    if s.verified >= 1000 and not finished then
        if not host then
            assert(
                wallFrames > 20 and settledFrames > 20,
                "Wall and stop checks were not exercised"
            )
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
        Isaac.GetPlayer(i):SetMinDamageCooldown(10000)
    end
    return gate(function()
        samples = samples + 1
        return capture()
    end, function(t, n, b)
        before(t, n, b)
        ticks = t
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
            for i = 0, room:GetGridSize() - 1 do
                if
                    room:GetGridEntity(i)
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
        if t % 120 == 0 then
            report("HOST tick=" .. t)
        end
    end, function(slot, t)
        local bytes = collect(slot, t)
        if t == 150 or t == 300 then
            local out = assert(io.open("./authority-" .. t .. ".bin", "wb"))
            out:write(bytes)
            out:close()
        end
        return bytes
    end, function(bytes, t, ack)
        if restore(bytes, t, ack) == false then
            return false
        end
        corrected = corrected + 1
        local v = _IsaacLanState.decode(bytes)
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
    if host or not _IsaacLanStatus().prepared or not motionFile then
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
    motionFile:write(
        string.format(
            "%.3f,%d,%d,%.6f,%.6f,%d\n",
            Isaac.GetTime() / 1000,
            _IsaacLanStatus().verified,
            samples,
            p.Position.X,
            p.Position.Y,
            moveSign
        )
    )
    if samples >= 650 and samples < 710 then
        assert(p.Position.X < 540, "Prediction crossed the rock barrier")
        wallFrames = wallFrames + 1
    end
    if samples >= 950 and lastAuthority then
        assert(
            p.Position:Distance(lastAuthority) < 0.5,
            "Stopped prediction did not converge to authority"
        )
        settledFrames = settledFrames + 1
    end
end)
