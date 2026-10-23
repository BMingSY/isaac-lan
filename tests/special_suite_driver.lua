local native, host = _IsaacLan, _IsaacLanTest.host
local originalFrame, originalGate = _IsaacLanFrame, native.net_gate
local current, exiting, endedAt, finished, requested = 1, false, 0, false, false
local caseFrame, scenario
local coordinator
local function activate()
    _IsaacLanFrame, native.net_gate = originalFrame, originalGate
    scenario = createScenario(fixtures[current])
    caseFrame = _IsaacLanFrame
end
coordinator = function()
    Options.FoundHUD, Options.ExtraHUDStyle = true, 1
    if not scenario then
        local status = originalFrame()
        if status.scene == 1 and status.phase == 0 then
            activate()
            _IsaacLanFrame = coordinator
        end
        return status
    end
    local ok, status = pcall(scenario.call, exiting and originalFrame or caseFrame)
    if not ok then
        local clean, message = pcall(scenario.cleanup)
        error(tostring(status) .. (clean and "" or "; cleanup: " .. tostring(message)))
    end
    if not exiting and scenario.done() then
        scenario.cleanup()
        exiting, endedAt = true, native.api_info().nowMs
        Isaac.DebugString("LAN_NETWORK SPECIAL_CASE_PASS index=" .. current)
    end
    if
        exiting
        and host
        and not requested
        and status.phase == 3
        and native.api_info().nowMs - endedAt > 2000
    then
        requested = true
        assert(native.net_command(3))
    end
    if
        exiting
        and status.phase == 2
        and status.scene == 1
        and not status.prepared
        and native.api_info().nowMs - endedAt > 3000
        and (not host or status.players == 1)
    then
        -- Native endings already returned both peers to the lobby. Close that
        -- completed session before activating a fixture that establishes its own.
        -- Wait for guests to leave instead of assuming their endings finish
        -- within a fixed offset of the host's presentation clock.
        _IsaacLanCommand("close")
    end
    if
        exiting
        and status.phase == 0
        and status.scene == 1
        and not status.prepared
        and native.api_info().nowMs - endedAt > 3000
    then
        if current == #fixtures then
            if not finished then
                finished = true
                Isaac.DebugString("LAN_NETWORK PASS all selected character and side routes")
            end
        else
            current, exiting, requested = current + 1, false, false
            activate()
            _IsaacLanFrame = coordinator
        end
    end
    return status
end
_IsaacLanFrame = coordinator
