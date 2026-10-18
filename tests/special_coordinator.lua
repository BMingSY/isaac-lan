local root = assert(arg[1])
Options = {}
local now, commands, case, passes = 0, 0, 0, 0
local s = { phase = 3, scene = 2, prepared = true }
local flags = { false, false }
local frame = function()
    return s
end
local gate = function() end
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
now = 2999
coordinator()
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
now = 7001
coordinator()
assert(commands == 2)
s = { phase = 0, scene = 1, prepared = false }
now = 8001
coordinator()
coordinator()
assert(passes == 1, "Suite finished early or reported completion more than once")
print("PASS continuous native suite coordination, completion grace and wrapper cleanup")
