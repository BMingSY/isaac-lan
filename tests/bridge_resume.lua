-- Native Continue can remap saved devices before MC_POST_GAME_STARTED.
-- Exercise the production bootstrap with ambiguous physical controller IDs.
local root = assert(arg[1])
local originalRegisterMod, originalRequire = RegisterMod, require
for _, controllers in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 1 } }) do
    local callbacks, assigned = {}, {}
    local phase, frame, gates, restores, cancelGate = 3, 9, 0, 0, false
    local closes = {}
    local players = { { ControllerIndex = controllers[1] }, { ControllerIndex = controllers[2] } }
    ModCallbacks = {
        MC_EXECUTE_CMD = 1,
        MC_POST_GAME_STARTED = 2,
        MC_POST_UPDATE = 3,
        MC_PRE_GAME_EXIT = 4,
        MC_PRE_PICKUP_COLLISION = 5,
    }
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
            GetRoom = function()
                return {
                    GetFrameCount = function()
                        return frame
                    end,
                }
            end,
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
        api_info = function()
            return { ready = 0 }
        end,
        net_poll = function()
            return { phase = phase, players = 2, firstTick = 0 }
        end,
        net_engine_start = function()
            return true
        end,
        rooms_connected = function()
            return 3
        end,
        rooms_heads = function(restoredOrder)
            -- Physical IDs are ambiguous until the bridge explicitly rebinds.
            if restoredOrder == 1 or (assigned[1] == 1 and assigned[2] == 2) then
                return { ["0"] = 0, ["1"] = 1 }
            end
            return { ["0"] = 1 }
        end,
        input_assign = function(index, controller)
            players[index + 1].ControllerIndex = controller
            assigned[index + 1] = controller
            return true
        end,
        rooms_enable = function()
            return true
        end,
        rooms_positions = function()
            return {}
        end,
        net_gate = function(...)
            assert(select("#", ...) == 6)
            gates = gates + 1
            if cancelGate then
                callbacks[ModCallbacks.MC_PRE_GAME_EXIT]()
            end
            return true
        end,
        net_restore_rooms = function()
            restores = restores + 1
            return true
        end,
        net_close = function(...)
            -- The real native API rejects an explicitly supplied nil argument.
            local n, gameExit = select("#", ...), ...
            assert(n == 0 or (n == 1 and gameExit == 1))
            closes[#closes + 1] = n
            phase = 0
        end,
    }
    _IsaacLanState =
        { reset = noop, capture = noop, apply = noop, present = noop, beginFloor = noop }
    _IsaacLanModules = {
        ["runtime/session"] = dofile(root .. "/src/bridge/runtime/session.lua"),
        ["compat/characters/keeper"] = dofile(root .. "/src/bridge/compat/characters/keeper.lua"),
        ["compat/mods/observation"] = dofile(root .. "/src/bridge/compat/mods/observation.lua"),
        ["api/public"] = { poll = noop, commit = noop, reset = noop, actions = { step = noop } },
        ["compat/mods/registry"] = { observeMod = noop, observeRequire = noop },
        ["lanbot/observe"] = function()
            return { read = noop }
        end,
        ["lanbot/navigation"] = {},
        lanbot = function()
            return { command = noop, step = noop, poll = noop, reset = noop }
        end,
    }
    RegisterMod, require = originalRegisterMod, originalRequire
    dofile(root .. "/src/bridge/app/main.lua")
    _IsaacLanFrame()
    callbacks[ModCallbacks.MC_POST_GAME_STARTED](nil, true)
    assert(assigned[1] == 1 and assigned[2] == 2, "Continue lost or duplicated a LAN slot")
    callbacks[ModCallbacks.MC_POST_UPDATE]()
    assert(gates == 0 and not _IsaacLanFrame().prepared)
    frame = 10
    callbacks[ModCallbacks.MC_POST_UPDATE]()
    callbacks[ModCallbacks.MC_POST_UPDATE]()
    assert(gates == 1 and restores == 1 and _IsaacLanFrame().prepared)
    callbacks[ModCallbacks.MC_PRE_GAME_EXIT]()
    assert(closes[1] == 1 and not _IsaacLanFrame().prepared)
    -- An inline native exit during gate must retain the native save guard and
    -- cancel restore. Repeated updates must not resurrect the old preparation.
    phase, cancelGate = 3, true
    _IsaacLanFrame()
    callbacks[ModCallbacks.MC_POST_GAME_STARTED](nil, true)
    callbacks[ModCallbacks.MC_POST_UPDATE]()
    callbacks[ModCallbacks.MC_POST_UPDATE]()
    assert(closes[2] == 1 and gates == 2 and restores == 1 and not _IsaacLanFrame().prepared)
    _IsaacLanCommand("close")
    assert(closes[3] == 0)
end
RegisterMod, require = originalRegisterMod, originalRequire
print("PASS continued roster binding, startup gates, cancellation and native close arguments")
