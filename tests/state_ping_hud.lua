local testInput = assert(_IsaacLanTestInput)
-- Concentrated two-peer visual acceptance; uses one game per peer throughout.
local native = assert(_IsaacLan)
local socket = require("socket")
local host, port = _IsaacLanTest.host, tostring(_IsaacLanTest.port)
local function report(message)
    Isaac.DebugString("LAN_NETWORK " .. message)
end
local frame, menu, getStatus = _IsaacLanFrame, _IsaacLanMenuRender, _IsaacLanStatus
local frames, linked, chosen, done = 0, false, false, false
local uiFrames, lastPhase, seen = 0, -1, {}
local initialOffset
local validationAt, expired, recovered, slowed = nil, false, false, false
local inputSequence, lastAck, expected = 0, 0, nil
local inputTimes = {}
local checked, maxError, maxSync = 0, 0, 0
local function checkTiming()
    local status = getStatus()
    if not expected or status.sync1 < 0 then
        return
    end
    local error = math.abs(status.sync1 - expected)
    maxError, maxSync = math.max(maxError, error), math.max(maxSync, status.sync1)
    checked = checked + 1
    assert(error <= 5, "Sync timing differs: measured=" .. status.sync1 .. " expected=" .. expected)
end
local function elapsed()
    return validationAt and Isaac.GetTime() - validationAt or -1
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
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
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if status.phase == 4 or status.phase == 9 then
        report("FAILED " .. status.error)
    end
    return status
end
function _IsaacLanMenuRender(available, visible, ...)
    local status = getStatus()
    if not status.prepared or status.phase ~= 3 or status.verified < 40 then
        return menu(available, visible, ...)
    end
    uiFrames = uiFrames + 1
    initialOffset = initialOffset or Options.HUDOffset
    local phase = math.min(8, math.floor((uiFrames - 1) / 90))
    local hud = Game():GetHUD()
    Options.HUDOffset = phase == 1 and 1 or initialOffset
    hud:SetVisible(phase ~= 5)
    local overrides = { [2] = { 65534, 65534 }, [3] = { 50, 280 }, [4] = { -1, -1 } }
    if overrides[phase] then
        status.network1, status.sync1 = table.unpack(overrides[phase])
    end
    -- Only the display reads synthetic values; transport RTT stays intact.
    _IsaacLanStatus = function()
        return status
    end
    local ok, result = pcall(menu, available, phase == 6, ...)
    _IsaacLanStatus = getStatus
    assert(ok, result)
    local huds = native.presentation_player_huds()
    if phase == 5 then
        assert(next(huds) == nil, "Hidden HUD retained ping anchors")
    end
    if phase ~= lastPhase and (phase == 5 or huds["0"] and huds["1"]) then
        lastPhase, seen[phase] = phase, true
        local function rectangle(slot)
            local value = huds[tostring(slot)]
            return value and string.format("%.1f,%.1f,layout=%d", value.x, value.y, value.layout)
                or "hidden"
        end
        report(
            "PING_HUD phase="
                .. phase
                .. " host="
                .. rectangle(0)
                .. " guest="
                .. rectangle(1)
                .. " rtt="
                .. (status.network1 or -1)
                .. " sync="
                .. (status.sync1 or -1)
        )
        if phase == 0 then
            report("VISUAL_READY")
        end
    end
    if phase == 8 and status.verified >= 650 and not validationAt then
        for index = 0, 8 do
            assert(seen[index], "HUD acceptance phase missing: " .. index)
        end
        assert(Game():GetLevel():GetStage() == 2, "Floor transition did not finish")
        assert((getStatus().network1 or -1) >= 0, "No measured RTT reached the display")
        assert((getStatus().sync1 or -1) >= 0, "No measured sync response reached the display")
        assert(huds["0"] and huds["1"], "Player HUD identity lost across floor")
        Options.HUDOffset = initialOffset
        validationAt = Isaac.GetTime()
        expected = nil
        report("PING_HUD application pause started")
    end
    local age = elapsed()
    if age > 4000 and age < 4500 and not expired then
        assert(status.network1 >= 0, "Application pause stopped network measurement")
        assert(status.sync1 == -1, "Application pause retained a stale sync value")
        expired = true
        report("PING_HUD sync expired independently of network")
    end
    if age > 6500 and age < 7500 and status.sync1 >= 0 then
        recovered = true
    end
    if age > 9000 and age < 11000 and status.sync1 >= 120 then
        slowed = true
    end
    if age > 13000 and not done then
        assert(
            expired and recovered and slowed,
            "Missing expiry, recovery or slow-application reading"
        )
        assert(status.network1 >= 0 and status.sync1 >= 0, "Measurements did not recover")
        if not host then
            assert(
                checked > 100 and maxError <= 5,
                "Displayed sync differs from independent timing"
            )
            report(
                "PING_HUD timing samples="
                    .. checked
                    .. " error_ms="
                    .. maxError
                    .. " max_sync="
                    .. maxSync
            )
        end
        done = true
        report("PASS network/sync HUD, timing, expiry, recovery, room and floor")
    end
    return phase == 6 and false or result
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        function()
            inputTimes[inputSequence] = socket.gettime() * 1000
            inputTimes[inputSequence - 256] = nil
            inputSequence = inputSequence + 1
            return testInput.neutral
        end,
        function(t, n, buttons)
            before(t, n, buttons)
            for index = 0, Game():GetNumPlayers() - 1 do
                Isaac.GetPlayer(index):SetMinDamageCooldown(60)
            end
            if t == 200 then
                local origin = native.rooms_positions()["1"].index
                local rooms = Game():GetLevel():GetRooms()
                for index = 0, rooms.Size - 1 do
                    local room = rooms:Get(index)
                    if room.SafeGridIndex ~= origin and room.Data.Type == RoomType.ROOM_DEFAULT then
                        assert(native.rooms_move(1, room.SafeGridIndex, 0, 0))
                        report("PING_HUD remote room changed")
                        break
                    end
                end
            end
            if t == 420 then
                assert(native.rooms_with_player(0, function()
                    Game():GetRoom():SetClear(true)
                    Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
                end))
                report("PING_HUD floor transition")
            end
        end,
        collect,
        function(bytes, tick, ack, half, stable)
            -- The previous restore has returned through C++ and published its sample.
            -- Native room changes can render reentrantly inside the current restore.
            checkTiming()
            local age = elapsed()
            if age >= 0 and age < 5000 then
                return false
            end
            if age >= 8000 and age < 11000 then
                socket.sleep(0.1)
            end
            local applied = restore(bytes, tick, ack, half, stable)
            if applied ~= false and ack > lastAck and inputTimes[ack] then
                lastAck = ack
                expected = socket.gettime() * 1000 - inputTimes[ack]
            end
            return applied
        end,
        present,
        function(...)
            inputTimes, expected = {}, nil
            return beginFloor(...)
        end
    )
end
