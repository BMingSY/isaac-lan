local native = assert(_IsaacLan)
local owner = { Name = "Isolated native frontend test" }
local file = assert(io.open("./lan-test-role.txt", "r"))
local host = file:read("*l") == "host"
file:close()
local linked, finished, warned = false, false, false
local countFile = assert(io.open("./lan-test-player-count.txt", "r"))
local total = tonumber(countFile:read("*l"))
countFile:close()
local function report(s)
    Isaac.DebugString("LAN_NETWORK " .. s)
end
local starts, renders, chosen = 0, 0, false
local portFile = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = portFile:read("*l")
portFile:close()
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function()
    starts = starts + 1
    assert(linked and starts == 1, "Network start depended on an earlier solo game")
    report("GAME_STARTED " .. Game():GetSeeds():GetStartSeedString())
end)
local pulses, edges, runRenders = 0, 0, nil
local pauseCheckTick, checkedEdges = nil, 0
local previousPause = false
local lastPulse = 0
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= 300 then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    if host and runRenders then
        runRenders = runRenders + 1
        local press = runRenders % 61 == 0 and pulses < 8
        native.test_gamepad(press and 16 or 0)
        if press then
            lastPulse = Isaac.GetTime()
            pulses = pulses + 1
            report("PAUSE_PULSE " .. pulses .. " time=" .. Isaac.GetTime())
        end
    end
    local status = frame()
    if status.prepared then
        local paused = Game():IsPaused()
        if paused ~= previousPause then
            previousPause = paused
            edges = edges + 1
            checkedEdges = edges
            report(
                "PAUSE_TRANSITION "
                    .. edges
                    .. " time="
                    .. Isaac.GetTime()
                    .. " latency="
                    .. (host and Isaac.GetTime() - lastPulse or -1)
            )
            if host and paused then
                assert(
                    Isaac.GetTime() - lastPulse < 150,
                    "Local pause was queued behind network frames"
                )
            end
        end
    end
    if host and not runRenders and status.verified >= 20 then
        runRenders = 0
    end
    if status.phase == 2 and status.modMismatch == 1 and not warned then
        warned = true
        report("MOD_WARNING advisory only; lobby joined")
    end
    if status.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0" .. ":1")
        chosen = true
    end
    if linked then
        if status.phase == 4 or status.phase == 9 then
            report("FAILED phase=" .. status.phase .. " " .. status.error)
        end
        if
            host
            and status.phase == 2
            and status.players == total
            and status.ready0 == 1
            and status.ready1 == 1
        then
            _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
        end
        if status.verified >= 600 and not finished then
            if host then
                assert(
                    pulses == 8 and edges == 8,
                    "Short pause presses were lost: sent=" .. pulses .. " accepted=" .. edges
                )
            end
            assert(
                edges == 8 and checkedEdges == 8 and not Game():IsPaused(),
                "Pause menu did not follow all eight presses"
            )
            report("PAUSE_MENU eight short presses opened and closed on both peers")
            assert(starts == 1, "Native menu start was not exercised")
            finished = true
            report("VERIFIED " .. status.verified)
            report("PASS authoritative short pause presses")
        end
    end
    return status
end
