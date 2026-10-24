local root = assert(arg[1])
Options = {}
local now, commands, case, passes = 0, 0, 0, 0
local s = { phase = 3, scene = 2, prepared = true }
local flags = { false, false }
local frame = function()
    return s
end
local gate = function() end
local closes = 0
_IsaacLanCommand = function(command)
    assert(command == "close" and s.phase == 2 and not s.prepared)
    closes = closes + 1
    s = { phase = 0, scene = 1, prepared = false }
end
_IsaacLanTest = { host = true }
_IsaacLanFrame = frame
_IsaacLan = {
    net_gate = gate,
    api_info = function()
        return { nowMs = now }
    end,
    net_command = function(command)
        assert(command == 3)
        commands = commands + 1
        return true
    end,
}
Isaac = {
    DebugString = function(message)
        if message:find("PASS all selected", 1, true) then
            passes = passes + 1
        end
    end,
}
fixtures = {}
for i = 1, 2 do
    fixtures[i] = function()
        assert(
            _IsaacLanFrame == frame and _IsaacLan.net_gate == gate,
            "Previous case wrappers leaked"
        )
        case = i
        _IsaacLanFrame = function()
            return frame()
        end
        _IsaacLan.net_gate = function() end
        return {
            done = function()
                return flags[i]
            end,
            cleanup = function()
                _IsaacLanFrame, _IsaacLan.net_gate = frame, gate
            end,
        }
    end
end
Isaac.AddCallback = function() end
Isaac.RemoveCallback = function() end
_IsaacLan.test_gamepad = function() end
createScenario = dofile(root .. "/tests/support/scenario.lua")
dofile(root .. "/tests/special_suite_driver.lua")
local coordinator = _IsaacLanFrame
assert(case == 0)
coordinator()
assert(case == 0, "Fixture activated before reaching the native menu")
s = { phase = 0, scene = 1, prepared = false }
coordinator()
assert(case == 1)
s = { phase = 3, scene = 2, prepared = true }
coordinator()
flags[1], now = true, 1000
coordinator()
assert(commands == 0)
assert(
    _IsaacLanFrame == coordinator and _IsaacLan.net_gate == gate,
    "Standalone cleanup removed the suite's frame loop"
)
now = 2999
_IsaacLanFrame()
assert(commands == 0, "Host exited before the guest completion grace period")
now = 3001
coordinator()
assert(commands == 1)
s = { phase = 0, scene = 1, prepared = false }
now = 4001
coordinator()
assert(case == 2 and _IsaacLanFrame == coordinator, "Next fixture replaced the coordinator")
s = { phase = 3, scene = 2, prepared = true }
flags[2], now = true, 5000
coordinator()
-- A native ending reaches the lobby before the suite's gameplay-exit grace.
s = { phase = 2, scene = 1, prepared = false, players = 2 }
now = 8499
coordinator()
assert(commands == 1 and closes == 0)
now = 8501
coordinator()
assert(closes == 0, "Host closed before the guest finished its native ending")
s.players = 1
coordinator()
assert(closes == 1 and passes == 0, "Native lobby cleanup was skipped or ended early")
coordinator()
coordinator()
assert(passes == 1, "Suite finished early or reported completion more than once")

-- A guest closes the completed lobby before the host's grace period, then
-- activates the next fixture with clean wrappers in the same process.
flags, case, now = { false, false }, 0, 0
s = { phase = 0, scene = 1, prepared = false }
_IsaacLanTest.host = false
_IsaacLanFrame, _IsaacLan.net_gate = frame, gate
dofile(root .. "/tests/special_suite_driver.lua")
coordinator = _IsaacLanFrame
coordinator()
assert(case == 1)
flags[1], now = true, 1000
s = { phase = 2, scene = 1, prepared = false }
coordinator()
now = 3999
coordinator()
assert(closes == 1)
now = 4001
coordinator()
assert(closes == 2 and commands == 1, "Guest did not leave the completed lobby first")
coordinator()
assert(case == 2 and _IsaacLanFrame == coordinator)
print("PASS continuous native suite coordination, completion grace and wrapper cleanup")
