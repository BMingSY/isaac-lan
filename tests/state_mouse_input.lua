local testInput = assert(_IsaacLanTestInput)
-- Drive both owned windows with real mouse presses after MOUSE READY.
-- Finish by creating lan-test-mouse.done in each owned game directory.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, ready, done = 0, false, false, false, false
local captures, releases, pressed = 0, 0, false
local held, shots, seen = { 0, 0 }, { 0, 0 }, {}
local received = {}
local function report(value)
    Isaac.DebugString("LAN_NETWORK MOUSE " .. value)
end
local function pointer(bytes, slot)
    local target = testInput.decode(bytes, slot).pointer
    return target.active, Vector(target.x, target.y)
end
local expectedAddress, expectedPort = host and "host.example.com" or "127.0.0.1", tonumber(port)
local preferencesChecked, analogAim = false, false
function _IsaacLanFrame()
    renders = renders + 1
    if not preferencesChecked then
        preferencesChecked = true
        local reload = io.open("./lan-test-connection-reload", "r")
        if reload then
            reload:close()
            analogAim = true
            local address, savedPort = native.menu_connection()
            assert(
                address == expectedAddress and savedPort == expectedPort,
                "Restart lost connection preferences"
            )
            report("PREFERENCES_RELOADED")
        end
        native.menu_connection_save(expectedAddress, expectedPort)
    end
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
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
    if status.prepared and status.verified >= 150 and not ready then
        assert(Options.MouseControl, "Owned profile has not enabled native mouse control")
        ready = true
        report("READY")
    end
    if ready and not done then
        local marker = io.open("./lan-test-mouse.done", "r")
        if marker then
            marker:close()
            assert(captures > 3 and releases > 0, "Physical mouse press/release was not captured")
            if host then
                assert(held[1] > 3 and held[2] > 3, "Authority missed a peer's mouse")
                assert(
                    shots[1] > 0 and shots[2] > 0,
                    "Mouse did not produce aimed native tears for both players"
                )
            end
            done = true
            report(
                "PASS capture="
                    .. captures
                    .. " release="
                    .. releases
                    .. " shots="
                    .. shots[1]
                    .. ","
                    .. shots[2]
            )
        end
    end
    return status
end
native.net_gate = function(capture, apply, collect, restore, present, beginFloor)
    return gate(function()
        local bytes = capture()
        local active, target = pointer(bytes)
        if ready then
            if active then
                captures = captures + 1
                if not pressed then
                    report("PRESSED x=" .. target.X .. " y=" .. target.Y)
                end
            elseif pressed then
                releases = releases + 1
                report("RELEASED")
            end
            pressed = active
        end
        return bytes
    end, function(t, n, bytes)
        apply(t, n, bytes)
        if t == 0 then
            for i = 0, Game():GetNumPlayers() - 1 do
                local player = Isaac.GetPlayer(i)
                player.Position, player.Velocity = Vector(260 + i * 120, 280), Vector.Zero
                player:SetMinDamageCooldown(100000)
                if analogAim then
                    player:AddCollectible(CollectibleType.COLLECTIBLE_ANALOG_STICK)
                end
            end
        end
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity:IsActiveEnemy(false) then
                entity:Remove()
            end
        end
        Game():GetRoom():SetClear(true)
        for slot = 0, 1 do
            local active, target = pointer(bytes, slot)
            received[slot + 1] = active and target or nil
            if active then
                held[slot + 1] = held[slot + 1] + 1
            end
        end
    end, collect, restore, present, beginFloor)
end
local owner = { Name = "Mouse input acceptance" }
Isaac.AddCallback(owner, ModCallbacks.MC_POST_UPDATE, function()
    if not host or not ready then
        return
    end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_TEAR and not seen[entity.InitSeed] then
            seen[entity.InitSeed] = true
            local player = entity.SpawnerEntity and entity.SpawnerEntity:ToPlayer()
            local slot = player and player.ControllerIndex
            local target = slot and received[slot]
            if target then
                local expected = target - player.Position
                if expected:Length() > 5 and entity.Velocity:Length() > 1 then
                    -- Ordinary tears use the native four directions; Analog Stick
                    -- in the restart round exercises the continuous aim vector.
                    if not analogAim then
                        if math.abs(expected.X) > math.abs(expected.Y) then
                            expected = Vector(expected.X, 0)
                        else
                            expected = Vector(0, expected.Y)
                        end
                    end
                    local alignment = expected:Normalized():Dot(entity.Velocity:Normalized())
                    assert(
                        alignment > 0.95,
                        string.format(
                            "Native tear ignored mouse aim slot=%d target=%.2f,%.2f player=%.2f,%.2f velocity=%.2f,%.2f dot=%.3f frame=%d",
                            slot,
                            target.X,
                            target.Y,
                            player.Position.X,
                            player.Position.Y,
                            entity.Velocity.X,
                            entity.Velocity.Y,
                            alignment,
                            entity.FrameCount
                        )
                    )
                    shots[slot] = shots[slot] + 1
                    report(
                        "TEAR slot="
                            .. slot
                            .. " vx="
                            .. entity.Velocity.X
                            .. " vy="
                            .. entity.Velocity.Y
                    )
                end
            end
        end
    end
end)
