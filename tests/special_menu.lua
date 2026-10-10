local root = assert(arg[1])
for _, route in ipairs({ "poop", "knife", "hush" }) do
    for _, host in ipairs({ true, false }) do
        local commands, ready = {}, 0
        local status = { scene = 1, phase = 0, verified = 0 }
        _IsaacLanTest = { host = host, port = "30220", route = route }
        _IsaacLan = {
            net_gate = function(capture)
                return capture
            end,
            test_gamepad = function() end,
            progress_values = function()
                return true, host and 98765 or 321
            end,
        }
        _IsaacLanFrame = function()
            return status
        end
        _IsaacLanCommand = function(name, value)
            commands[#commands + 1] = { name, value }
        end
        Isaac = {
            DebugString = function(message)
                if message == "LAN_NETWORK MENU_READY" then
                    ready = ready + 1
                end
            end,
        }
        ButtonAction = { ACTION_PILLCARD = 10 }
        dofile(root .. "/tests/state_side_routes.lua")
        for _ = 1, 400 do
            _IsaacLanFrame()
        end
        assert(ready == 1, "Engine runner cannot observe this fixture's menu readiness")
        assert(#commands == 1 and commands[1][1] == (host and "host" or "join"))
        assert(commands[1][2] == (host and "30220" or "127.0.0.1:30220"))
        status.phase, status.players = 2, 1
        _IsaacLanFrame()
        _IsaacLanFrame()
        assert(#commands == 2 and commands[2][1] == "choose")
        assert(commands[2][2] == (not host and route == "poop" and "25:1" or "0:1"))
        local capture, input = _IsaacLan.net_gate()
        for _ = 0, 120 do
            input = capture()
        end
        local use = not host and route == "poop"
        assert(string.unpack(">I2", input, 21) == (use and 65535 or 0))
        assert(string.unpack(">I2", input, 23) == 0, "Poop fixture pressed Drop instead of Use")
        assert(string.unpack(">I2", input, 33) == (use and 1 << 10 or 0))
    end
end
print("PASS side-route host and guest lobby readiness and character selection")
