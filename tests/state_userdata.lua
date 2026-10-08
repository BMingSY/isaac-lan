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
local laserSamples = 0
local originalFrame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = originalFrame()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", host and "7:1" or "0:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "P09ZPSPM:0:7:0:0:0")
    end
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.verified >= 600 and not finished then
        assert(laserSamples > 0, "No actual laser was serialized/restored")
        finished = true
        report("LASER samples=" .. laserSamples)
        report("PASS report seed serialization")
    end
    return s
end
local gate = native.net_gate
local ticks, corrected, samples = 0, 0, 0
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    for i = 0, Game():GetNumPlayers() - 1 do
        Isaac.GetPlayer(i):SetMinDamageCooldown(10000)
    end
    return gate(function()
        samples = samples + 1
        local v = {}
        for i = 1, 16 do
            v[i] = 0
        end
        if samples > 20 and samples < 450 then
            v[host and 6 or 5] = 65535
        end
        local pieces = {}
        for i = 1, 16 do
            pieces[i] = string.pack(">I2", v[i])
        end
        pieces[17] = string.pack(">I2", 0)
        return table.concat(pieces)
    end, function(t, n, b)
        before(t, n, b)
        ticks = t
        if t == 0 then
            report("AUTHORITY host simulation begins")
        end
        if t == 30 then
            assert(native.rooms_move(0, 85, 0, 0))
            assert(native.rooms_move(1, 85, 0, 0))
            report("HOST report room=85")
        end
        if t == 80 then
            assert(native.rooms_with_player(1, function()
                Isaac.Spawn(EntityType.ENTITY_STONEY, 0, 0, Vector(460, 240), Vector.Zero, nil)
            end))
        end
        if t % 120 == 0 then
            report("HOST tick=" .. t)
        end
    end, function(slot, t)
        local bytes = collect(slot, t)
        for _, e in ipairs(_IsaacLanState.decode(bytes)[11][3]) do
            if e[2] == 7 then
                laserSamples = laserSamples + 1
            end
        end
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
                if e[2] == 7 then
                    laserSamples = laserSamples + 1
                    assert(
                        native.laser_path(actual:GetSprite()) == e[20],
                        "Laser sampling path differs"
                    )
                end
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
        if t >= 40 and t <= 45 then
            Isaac.GetPlayer(1):AddCoins(-7)
            for _ = 1, 100 do
                Random()
            end
        end
        if t % 120 == 0 then
            assert(native.rooms_with_player(1, function()
                local count, live = 0, 0
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    count = count + 1
                    if e:Exists() then
                        live = live + 1
                    end
                end
                report("CLIENT entities=" .. count .. " live=" .. live)
            end))
        end
        if t >= 150 and t < 154 then
            assert(native.rooms_with_player(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type ~= 1 and e:Exists() then
                        e:Remove()
                        break
                    end
                end
                Isaac.Spawn(
                    EntityType.ENTITY_EFFECT,
                    EffectVariant.WALL_BUG,
                    0,
                    Vector(80, 80),
                    Vector.Zero,
                    nil
                )
            end))
        end
    end, present, beginFloor)
end
