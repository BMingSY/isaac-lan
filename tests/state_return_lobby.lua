-- Exercise the native ending/exit boundary and reuse one room for three runs.
-- Game:End selects the cinematic; this fixture does not validate a Boss route.
local native = assert(_IsaacLan)
local Phase = native.net_phases()
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame, render = _IsaacLanFrame, _IsaacLanMenuRender
local startedAt = Isaac.GetTime()
local joined, chosen, started, complete = false, false, false, false
local run, wins, exits, lobbyRun, visibleRun = 0, 0, 0, 0, 0
local checkedRun = 0
local lobbyAt, movieAt, runId, baseline = nil, nil, nil, nil
local GAMEPAD_CONFIRM, FIRST_CINEMATIC = 0x1000, 2
local alternate = 0
local function report(message)
    Isaac.DebugString("LAN_NETWORK RETURN_LOBBY " .. message)
end
Isaac.AddCallback({}, ModCallbacks.MC_POST_GAME_STARTED, function()
    run = run + 1
    movieAt = nil
    report("START run=" .. run)
end)
Isaac.AddCallback({}, ModCallbacks.MC_POST_GAME_END, function(_, over)
    assert(not over, "Expected a winning ending")
    wins = wins + 1
    report("WIN run=" .. run)
end)
Isaac.AddCallback({}, ModCallbacks.MC_PRE_GAME_EXIT, function()
    if not complete then
        exits = exits + 1
        report("EXIT run=" .. run)
    end
end)
function _IsaacLanMenuRender(available, visible, ...)
    local result = render(available, visible, ...)
    local s = _IsaacLanStatus()
    if result and available and wins > 0 and s.phase == Phase.lobby and visibleRun < wins then
        visibleRun = wins
        report("SELECTION_VISIBLE run=" .. wins)
    end
    return result
end
function _IsaacLanFrame()
    local s = frame()
    if complete then
        native.test_gamepad(0)
        return s
    end
    assert(s.phase ~= Phase.failed, s.error)
    if not joined and Isaac.GetTime() - startedAt > 15000 then
        joined = true
        baseline = native.net_progress()
        local choices = native.net_characters()
        alternate = choices[2] or 0
        Isaac.DebugString("LAN_NETWORK MENU_READY")
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
    end
    if wins > lobbyRun and s.phase == Phase.lobby and s.scene == 1 then
        assert(not s.prepared and exits == wins, "Lobby opened before native exit")
        assert(s.players == 2 and s.connected == 3 and s.slot == (host and 0 or 1), "Room lost")
        assert(s["ready" .. s.slot] == 0, "Old ready state survived")
        assert(native.net_progress():sub(-4) == baseline:sub(-4), "Private progress replaced")
        lobbyRun, lobbyAt, chosen, started = wins, Isaac.GetTime(), false, false
        report("LOBBY run=" .. run .. " port=" .. s.port)
    end
    local canChoose = run == 0 or (lobbyAt and Isaac.GetTime() - lobbyAt > 4000)
    if s.phase == Phase.lobby and not chosen and canChoose then
        assert(run == 0 or visibleRun == wins, "LAN selection was not automatically visible")
        chosen = true
        -- Respect this profile's unlocked choices; empty profiles only have Isaac.
        _IsaacLanCommand("choose", (wins % 2 == 1 and alternate or 0) .. ":1")
    end
    if
        host
        and not started
        and s.phase == Phase.lobby
        and s.players == 2
        and s.ready0 == 1
        and s.ready1 == 1
    then
        started = true
        _IsaacLanCommand(
            "start",
            (wins % 2 == 0 and "N024KHNP" or "YV039KQF")
                .. ":0:"
                .. s.choice0
                .. ":"
                .. s.choice1
                .. ":0:0"
        )
    end
    local buttons = 0
    if s.scene == 3 then
        movieAt = movieAt or Isaac.GetTime()
        -- Alternate which peer skips first without stealing OS focus.
        local first = (run == 1) == host
        if Isaac.GetTime() - movieAt > (first and 1000 or 6000) then
            buttons = Isaac.GetTime() % 500 < 100 and GAMEPAD_CONFIRM or 0
        end
    end
    native.test_gamepad(buttons)
    return s
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local function check(t)
        if t < 30 or checkedRun == run then
            return
        end
        checkedRun = run
        local s = _IsaacLanStatus()
        assert(s.runId ~= runId, "Next run reused its identity")
        runId = s.runId
        local p = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(s.slot)]))
        assert(
            p:GetPlayerType() == (run % 2 == 0 and alternate or 0),
            "New character selection ignored"
        )
        assert(not p:HasCollectible(333), "Inventory survived the ending")
        report("FRESH_ROSTER run=" .. run .. " character=" .. p:GetPlayerType())
        if run == 3 then
            assert(wins == 2 and exits == 2 and visibleRun == 2, "Missing ending/selection cycle")
            complete = true
            report("PASS two endings and three runs in one room")
        end
    end
    return gate(
        function()
            return string.rep("\0", 43)
        end,
        function(t, n, b)
            before(t, n, b)
            check(t)
            if t == 70 and run < 3 then
                for slot = 0, 1 do
                    Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
                        :AddCollectible(333)
                end
            end
            if t == 120 and run < 3 then
                Game():End(FIRST_CINEMATIC)
            end
        end,
        collect,
        function(bytes, t, ack, between, stable)
            local result = restore(bytes, t, ack, between, stable)
            check(t)
            return result
        end,
        present,
        beginFloor
    )
end
