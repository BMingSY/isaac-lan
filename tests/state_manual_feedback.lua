-- One connection covers keyboard pause, native Azazel UI and split-room intros.
local native = assert(_IsaacLan)
local json = require("json")
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
local pauseFrames, pauseEdges, lastPause = nil, 0, false
local introSamples, introMotion, introStartX = 0, 0, nil
local chargeRooms, costs = {}, {}
local function phase(t)
    if t >= 120 and t < 190 then
        return "plain-before"
    elseif t >= 240 and t < 310 then
        return "shop"
    elseif t >= 340 and t < 390 then
        return "treasure"
    elseif t >= 620 and t < 690 then
        return "plain-after"
    elseif t >= 850 and t < 890 then
        return "boss"
    elseif t >= 1140 and t < 1440 then
        return "shop-moving-split"
    elseif t >= 1540 and t < 1840 then
        return "treasure-moving-split"
    elseif t >= 1940 and t < 2240 then
        return "boss-items-moving-split"
    elseif t >= 2340 and t < 2640 then
        return "boss-items-moving-together"
    end
end
local function cost(name, ms)
    local label = phase(_IsaacLanStatus().verified)
    if label then
        local key = label .. "/" .. name
        local v = costs[key] or { count = 0, total = 0, maximum = 0 }
        costs[key] = v
        v.count, v.total, v.maximum = v.count + 1, v.total + ms, math.max(v.maximum, ms)
    end
end
if not host then
    for _, name in ipairs({
        "sprite_state",
        "actor_pose",
        "room_layout",
        "rooms_sync",
        "map_refresh",
    }) do
        local original = native[name]
        native[name] = function(...)
            local began = Isaac.GetTime()
            local values = table.pack(original(...))
            cost(name, Isaac.GetTime() - began)
            return table.unpack(values, 1, values.n)
        end
    end
    local registry = _IsaacLanModules["compat/mods/registry"]
    -- Registration copies the adapter definition. Profile that registered copy.
    for i = 1, 64 do
        local name, definitions = debug.getupvalue(registry.register, i)
        if not name then
            break
        end
        if name == "definitions" then
            for id, entry in pairs(definitions) do
                local original = entry.definition.dispatch
                if original then
                    entry.definition.dispatch = function(...)
                        local began = Isaac.GetTime()
                        local values = table.pack(original(...))
                        cost(id, Isaac.GetTime() - began)
                        return table.unpack(values, 1, values.n)
                    end
                end
            end
            break
        end
    end
end
local frame = _IsaacLanFrame
local lastRenderTime, lastPhase
local originalWarning
function _IsaacLanFrame()
    renders = renders + 1
    if not finished and EID and EID.Config then
        if originalWarning == nil then
            originalWarning = EID.Config.DisableStartOfRunWarnings
        end
        EID.Config.DisableStartOfRunWarnings = true
    end
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
        report(
            "EID_TARGET "
                .. json.encode(
                    native.api_mod_info("@mods/external item descriptions_836319872/main.lua")
                )
        )
    end
    local s = frame()
    if not host then
        local now = Isaac.GetTime()
        if lastRenderTime then
            cost("render_interval", now - lastRenderTime)
        end
        lastRenderTime = now
        local currentPhase = phase(s.verified)
        if lastPhase and currentPhase ~= lastPhase then
            report("PERFORMANCE " .. json.encode(costs))
        end
        lastPhase = currentPhase
    end
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", host and "0:1" or "7:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:7:0:0")
    end
    native.test_gamepad(
        not host
                and s.verified >= 100
                and s.verified < 2650
                and (8192 | (s.verified >= 400 and s.verified < 430 and 8 or (s.verified >= 1140 and phase(
                    s.verified
                ) and (s.verified % 20 < 10 and 8 or 4)) or 0))
            or 0
    )
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.prepared then
        local paused = s.pause ~= 0
        if paused ~= lastPause then
            pauseEdges, lastPause = pauseEdges + 1, paused
            report("KEYBOARD_PAUSE_EDGE " .. pauseEdges .. " paused=" .. tostring(paused))
        end
        if not host and phase(s.verified) and renders % 12 == 0 then
            local p = Isaac.GetPlayer(1)
            local sprites = assert(native.actor_sprites(1, p:GetSprite()))
            local animation = sprites[4]:GetAnimation()
            assert(
                animation == "Charging" or animation == "Charged" or animation == "StartCharged",
                "Azazel charge UI missing after room entry: tick="
                    .. s.verified
                    .. " pose="
                    .. animation
            )
            local label = phase(s.verified)
            chargeRooms[label] = (chargeRooms[label] or 0) + 1
            report(
                "CHARGE_UI "
                    .. label
                    .. " animation="
                    .. animation
                    .. " frame="
                    .. sprites[4]:GetFrame()
            )
        end
    end
    if s.verified >= 2700 then
        pauseFrames = (pauseFrames or 0) + 1
        if host and pauseFrames % 181 == 1 and pauseFrames < 600 then
            local n = math.floor(pauseFrames / 181) + 1
            report("KEYBOARD_PAUSE_REQUEST " .. n .. (n <= 2 and " host" or " client"))
        end
        if pauseFrames >= 750 and not finished then
            assert(
                pauseEdges == 4 and not Game():IsPaused(),
                "Real Escape did not toggle both menus"
            )
            if not host then
                for _, label in ipairs({
                    "plain-before",
                    "shop",
                    "treasure",
                    "plain-after",
                    "boss",
                    "shop-moving-split",
                    "treasure-moving-split",
                    "boss-items-moving-split",
                    "boss-items-moving-together",
                }) do
                    assert((chargeRooms[label] or 0) >= 3, "Charge UI not observed in " .. label)
                end
                report("PERFORMANCE " .. json.encode(costs))
            else
                assert(introSamples >= 5 and introMotion > 25, "Host intro froze remote movement")
            end
            if originalWarning ~= nil then
                EID.Config.DisableStartOfRunWarnings = originalWarning
            end
            finished = true
            report("PASS manual feedback pause charge and split intro")
        end
    end
    return s
end
local origin, shop, treasure, boss
local function move(slot, index)
    assert(native.rooms_move(slot, index, 0, 0))
    report("MOVE slot=" .. slot .. " room=" .. index)
end
local function weapons(bytes)
    local result, cursor = {}, 11
    for i = 1, 5 do
        local exists
        exists, cursor = string.unpack(">B", bytes, cursor)
        if exists == 1 then
            local kind, delay, maximum, charge
            kind, delay, maximum, charge, cursor = string.unpack(">I4fff", bytes, cursor)
            result[i] = { kind, delay, maximum, charge }
        end
    end
    return result
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, b)
        before(t, n, b)
        if t == 30 then
            local level = Game():GetLevel()
            origin = level:GetCurrentRoomIndex()
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                if d.Data.Type == RoomType.ROOM_SHOP then
                    shop = d.SafeGridIndex
                elseif d.Data.Type == RoomType.ROOM_TREASURE then
                    treasure = d.SafeGridIndex
                elseif d.Data.Type == RoomType.ROOM_BOSS then
                    boss = d.SafeGridIndex
                end
            end
            assert(shop and treasure and boss, "Seed lacks benchmark rooms")
            assert(Isaac.GetPlayer(1):GetPlayerType() == PlayerType.PLAYER_AZAZEL)
            for i = 0, 1 do
                Isaac.GetPlayer(i):SetMinDamageCooldown(10000)
            end
            Isaac.GetPlayer(0).Position = Vector(160, 180)
            Isaac.GetPlayer(1).Position = Vector(240, 180)
            Options.ChargeBars = true
        elseif t == 200 then
            move(1, shop)
        elseif t == 320 then
            move(1, treasure)
        elseif t == 390 then
            Isaac.GetPlayer(1).Position = Vector(160, 180)
        elseif t == 400 then
            introStartX = Isaac.GetPlayer(1).Position.X
            move(0, boss)
        elseif t == 520 then
            report("HOST_INTRO_MOVEMENT samples=" .. introSamples .. " distance=" .. introMotion)
            assert(
                introSamples >= 5 and introMotion > 25,
                "Remote authority did not move during host intro"
            )
        elseif t == 580 then
            move(1, origin)
        elseif t == 700 then
            move(1, boss)
        elseif t == 900 then
            move(1, origin)
        elseif t == 980 then
            assert(native.rooms_with_player(0, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Kill()
                    end
                end
            end))
        elseif t == 1100 then
            move(1, shop)
        elseif t == 1500 then
            move(1, treasure)
        elseif t == 1850 then
            move(0, origin)
        elseif t == 1900 then
            move(1, boss)
        elseif t == 2300 then
            move(0, boss)
        end
        if t == 1110 or t == 1510 or t == 1910 or t == 2310 then
            Isaac.GetPlayer(1).Position = Vector(180, 180)
        end
        if t == 1910 then
            assert(native.rooms_with_player(1, function()
                -- Perf measures an item-bearing boss room, independently of
                -- this seed's native reward and remaining spawned flies.
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Remove()
                    end
                end
                Game():GetRoom():SetClear(true)
                if #Isaac.FindByType(5, 100, -1, false, false) == 0 then
                    Game():Spawn(5, 100, Vector(320, 280), Vector.Zero, nil, 13, 774411)
                end
            end))
        end
        if t == 1200 or t == 1600 or t == 2000 or t == 2400 then
            assert(native.rooms_with_player(1, function()
                local items = Isaac.FindByType(5, 100, -1, false, false)
                assert(#items > 0, "Benchmark room has no collectible pedestal")
                report(
                    "ROOM_ITEMS tick=" .. t .. " items=" .. #items .. " age=" .. items[1].FrameCount
                )
            end))
        end
    end, function(slot, t)
        if host and t >= 400 and t < 520 and native.presentation_active() then
            introSamples = introSamples + 1
            introMotion =
                math.max(introMotion, math.abs(Isaac.GetPlayer(1).Position.X - introStartX))
        end
        return collect(slot, t)
    end, function(bytes, t, ack)
        local began = Isaac.GetTime()
        if restore(bytes, t, ack) == false then
            return false
        end
        cost("restore", Isaac.GetTime() - began)
        Options.ChargeBars = true
        if phase(t) then
            local value = _IsaacLanState.decode(bytes)
            for _, actor in ipairs(value[9]) do
                if actor[2] == 2 and actor[6] then
                    local expected = weapons(actor[6])
                    local actual =
                        weapons(assert(native.actor_pose(Isaac.GetPlayer(actor[1]):GetSprite())))
                    assert(
                        expected[2] and actual[2] and expected[2][1] == 2,
                        "Natural Azazel weapon missing"
                    )
                    assert(
                        math.abs(expected[2][4] - actual[2][4]) < 0.0001,
                        "Charge differs from authority"
                    )
                end
            end
        end
        return true
    end, function(...)
        local began = Isaac.GetTime()
        present(...)
        cost("present", Isaac.GetTime() - began)
    end, beginFloor)
end
