-- Native Continue can remap saved devices before MC_POST_GAME_STARTED.
-- Exercise the production bootstrap with ambiguous physical controller IDs.
local root = assert(arg[1])
local originalRegisterMod, originalRequire = RegisterMod, require
for _, controllers in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 1 } }) do
    local callbacks, assigned = {}, {}
    local players = { { ControllerIndex = controllers[1] }, { ControllerIndex = controllers[2] } }
    ModCallbacks =
        { MC_EXECUTE_CMD = 1, MC_POST_GAME_STARTED = 2, MC_POST_UPDATE = 3, MC_PRE_GAME_EXIT = 4 }
    Isaac = {
        AddCallback = function(_, id, fn)
            callbacks[id] = fn
        end,
        DebugString = function() end,
        GetPlayer = function(index)
            return players[index + 1]
        end,
    }
    Game = function()
        return {
            GetSeeds = function()
                return {
                    GetStartSeed = function()
                        return 123
                    end,
                    GetStartSeedString = function()
                        return "test"
                    end,
                }
            end,
        }
    end
    local noop = function() end
    _IsaacLan = {
        net_poll = function()
            return { phase = 3, players = 2, firstTick = 0 }
        end,
        net_engine_start = function()
            return true
        end,
        rooms_connected = function()
            return 3
        end,
        rooms_heads = function(restoredOrder)
            -- Physical IDs are ambiguous until the bridge explicitly rebinds.
            if restoredOrder == 1 then
                return { ["0"] = 0, ["1"] = 1 }
            end
            return { ["0"] = 1 }
        end,
        input_assign = function(index, controller)
            players[index + 1].ControllerIndex = controller
            assigned[index + 1] = controller
            return true
        end,
    }
    _IsaacLanState = { reset = noop }
    _IsaacLanModules = {
        ["api/public"] = { poll = noop, commit = noop, reset = noop, actions = { step = noop } },
        ["compat/registry"] = { observeMod = noop, observeRequire = noop },
        ["lanbot/observe"] = function()
            return { read = noop }
        end,
        ["lanbot/navigation"] = {},
        lanbot = function()
            return { command = noop, step = noop, poll = noop, reset = noop }
        end,
    }
    RegisterMod, require = originalRegisterMod, originalRequire
    dofile(root .. "/src/bridge/main.lua")
    _IsaacLanFrame()
    callbacks[ModCallbacks.MC_POST_GAME_STARTED](nil, true)
    assert(assigned[1] == 1 and assigned[2] == 2, "Continue lost or duplicated a LAN slot")
end
RegisterMod, require = originalRegisterMod, originalRequire
print("PASS continued roster binds before interpreting native device IDs")
