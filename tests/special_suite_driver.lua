local native, host = _IsaacLan, _IsaacLanTest.host
local originalFrame, originalGate = _IsaacLanFrame, native.net_gate
local current, exiting, endedAt, finished, requested = 1, false, 0, false, false
local caseFrame, done
local coordinator
local function activate()
    _IsaacLanFrame, native.net_gate = originalFrame, originalGate
    done = fixtures[current]()
    caseFrame = _IsaacLanFrame
end
activate()
coordinator = function()
    local status = caseFrame()
    if done() and not exiting then
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
