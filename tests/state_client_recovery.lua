-- One pair covers fresh ownership, manual reconnect, failed restore, retry,
-- automatic recovery, restart, ending and leaving. Processes stay throughout.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local Phase = native.net_phases()
local owner = { Name = "Client recovery lifecycle" }
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, starts, departures = 0, 0, 0
local linked, chosen, finished = false, false, false
local manual, failedRestore, retried, dropped, left = false, false, false, false, false
local prelaunchFailed, prelaunchRetried, prelaunchAt = false, false, nil
local failedAt, liveAt, lastConnected, firstPosition, origin, restartAt, lobbyAt
local sawRecovery, sawFailure, sawMovingHost, sawLobby = false, false, false, false
local RESTART_BUTTONS, CONFIRM_BUTTON, FIRST_CINEMATIC = 0x3c0, 0x1000, 2
local inputReady, deviceWait = native.input_ready, host and 0 or 45
local engineStart = native.net_engine_start
native.net_engine_start = function(...)
    if not host and manual and starts == 1 and not prelaunchFailed then
        prelaunchFailed = true
        error("isolated disconnect fixture: prelaunch rejection")
    end
    return engineStart(...)
end
native.input_ready = function()
    if deviceWait > 0 then
        assert(starts == 0, "Started before controller enumeration completed")
        deviceWait = deviceWait - 1
        return false
    end
    return inputReady()
end
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function()
    starts = starts + 1
    liveAt = nil
    report("RECOVERY_STARTED " .. starts)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function()
    return false
end, EntityType.ENTITY_PLAYER)
local function checkActors()
    local heads = native.rooms_heads()
    assert(heads["0"] ~= heads["1"], "Guest aliases the host's actor")
    for slot = 0, 1 do
        local p = Isaac.GetPlayer(assert(heads[tostring(slot)]))
        assert(p.ControllerIndex == slot + 1, "Wrong actor owner")
        assert(p:GetPlayerType() == (slot == 0 and 1 or 0), "Wrong selected character")
    end
    return Isaac.GetPlayer(heads["0"]), Isaac.GetPlayer(heads["1"])
end
local function menu(key)
    return _IsaacLanMenuRender(false, false, key, "", -1000, -1000, false, "", "")
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
    if status.phase == Phase.lobby and not chosen then
        chosen = true
        assert(native.net_choose(host and 1 or 0, 1))
    end
    if
        host
        and status.phase == Phase.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:1:0:0:0")
    end
    if status.recovering then
        assert(menu(0), "Recovery prompt is hidden")
        sawRecovery = true
    end
    if host then
        if starts == 2 and status.phase == Phase.lobby then
            assert(not status.prepared and not status.recovering)
            sawLobby = true
        end
        if lastConnected == 3 and status.connected == 1 then
            departures = departures + 1
        end
        lastConnected = status.connected
        if departures >= 4 and not finished then
            assert(sawMovingHost, "Host input never moved its own actor")
            assert(starts == 2 and sawLobby, "Restart or ending lost the host session")
            finished = true
            report("PASS client recovery lifecycle")
        end
    elseif status.phase == Phase.failed then
        if starts == 1 then
            assert(prelaunchFailed and status.recovering, status.error)
            prelaunchAt = prelaunchAt or renders
            if renders - prelaunchAt > 45 and not prelaunchRetried then
                prelaunchRetried = true
                menu(13)
            end
        elseif starts == 2 then
            assert(failedRestore and status.recovering, status.error)
            sawFailure = true
            failedAt = failedAt or renders
            if renders - failedAt > 90 and not retried and not status.prepared then
                retried = true
                assert(starts == 2, "A failed restore restarted in a loop")
                menu(13) -- Enter on the actual retry row.
            end
        else
            assert(starts == 3 and dropped, status.error)
        end
    elseif
        status.phase == Phase.running
        and status.prepared
        and status.verified >= 0
        and not status.recovering
    then
        liveAt = liveAt or status.verified
        if starts == 1 and status.verified - liveAt > 100 and not manual then
            manual = true
            _IsaacLanCommand("reconnect")
        end
    elseif starts == 5 and status.phase == Phase.lobby then
        assert(not status.prepared and not status.recovering)
        sawLobby = true
        lobbyAt = lobbyAt or renders
        if renders - lobbyAt > 30 and not left then
            assert(sawRecovery and sawFailure and prelaunchRetried and retried and dropped)
            left = true
            _IsaacLanCommand("leave")
        end
    elseif left and status.phase == Phase.idle and not finished then
        assert(not status.recovering and starts == 5 and sawLobby)
        finished = true
        report("PASS client recovery lifecycle")
    end
    local vote = false
    if status.phase == Phase.running and status.prepared then
        if host and starts == 1 and departures == 3 and status.connected == 3 then
            restartAt = restartAt or status.verified
            vote = status.verified - restartAt > 100
        elseif not host and starts == 4 and liveAt then
            vote = status.verified - liveAt > 100
        end
    end
    -- Exercise the shared exit boundary after recovery: unanimous restart,
    -- then the native ending returns both peers to the same lobby.
    native.test_gamepad(
        status.scene == 3 and (renders % 30 < 5 and CONFIRM_BUTTON or 0)
            or vote and RESTART_BUTTONS
            or 0
    )
    assert(not host or status.phase ~= Phase.failed, status.error)
    return status
end
native.net_gate = function(capture, apply, collect, restore, present, stage)
    if host then
        local h, p = checkActors()
        assert(p:GetNumCoins() == 0, "Restart retained the previous inventory")
        h.Position = Game():GetRoom():GetCenterPos()
        p:AddCoins(19)
        p:AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
        firstPosition = h.Position
        origin = Game():GetLevel():GetCurrentRoomIndex()
    end
    return gate(
        function()
            -- Exercise independent authoritative movement without real window focus.
            local t = _IsaacLanStatus().verified or 0
            local action = (host and 0 or 2) + math.floor(t / 20) % 2
            local values = {}
            for i = 0, 16 do
                values[i + 1] = t < 20 and i == action and 65535 or 0
            end
            return string.pack(">" .. string.rep("I2", 17), table.unpack(values))
        end,
        function(t, n, bytes)
            apply(t, n, bytes)
            if host and t == 10 then
                local h = checkActors()
                sawMovingHost = (h.Position - firstPosition):Length() > 10
            end
            if host and starts == 1 and t == 30 then
                local h, p = checkActors()
                assert(native.rooms_with_player(1, function()
                    p:UseCard(Card.CARD_JOKER, UseFlag.USE_NOANIM)
                end))
            end
            if host and starts == 1 and t == 90 then
                assert(Game():GetLevel():GetCurrentRoomIndex() == origin, "Guest moved the host")
                assert(native.rooms_with_player(1, function()
                    assert(Game():GetRoom():GetType() == RoomType.ROOM_DEVIL)
                end))
            end
            if host and starts == 2 and t == 150 then
                Game():End(FIRST_CINEMATIC)
            end
        end,
        collect,
        function(bytes, t, ...)
            if starts == 2 and not failedRestore then
                failedRestore = true
                error("isolated disconnect fixture: restore failure")
            end
            if starts == 3 and liveAt and t - liveAt > 100 and not dropped then
                dropped = true
                error("isolated disconnect fixture: connection loss")
            end
            local applied = restore(bytes, t, ...)
            if applied ~= false then
                -- Loading can render recursively with only the room's actors
                -- exposed. Check the complete roster after restoration returns.
                local h, p = checkActors()
                assert(
                    p:GetNumCoins() == 19
                        and p:HasCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY),
                    "Recovery lost inventory"
                )
                if t >= 90 and starts == 1 then
                    assert(Game():GetRoom():GetType() == RoomType.ROOM_DEVIL, "Wrong guest room")
                elseif starts > 1 then
                    local positions = native.rooms_positions()
                    assert(
                        positions["0"].index == positions["1"].index,
                        "Rejoining guest did not return to the host's room"
                    )
                end
            end
            return applied
        end,
        present,
        stage
    )
end
