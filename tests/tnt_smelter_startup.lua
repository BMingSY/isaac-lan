local root = assert(arg[1])
local phases = { idle = 0, lobby = 2, failed = 4 }
local originalIO = io
for _, host in ipairs({ true, false }) do
    local commands, menus = {}, 0
    local function frame()
        return { phase = phases.idle }
    end
    local function gate() end
    local function menu(available, value)
        menus = menus + 1
        return available, value
    end
    _IsaacLan = {
        net_phases = function()
            return phases
        end,
        net_gate = gate,
        test_gamepad = function() end,
    }
    _IsaacLanTest, _IsaacLanTestInput = { host = host, port = "31457" }, {}
    _IsaacLanModules = { ["sync/fields"] = {}, ["sync/world_schema"] = {} }
    _IsaacLanFrame, _IsaacLanMenuRender = frame, menu
    _IsaacLanCommand = function(action, value)
        commands[#commands + 1] = { action, value }
    end
    Isaac = { DebugString = function() end }
    TrinketType = { TRINKET_CANCER = 39, TRINKET_CURVED_HORN = 35 }
    ModCallbacks = { MC_POST_RENDER = 2 }
    RegisterMod = function()
        return { AddCallback = function() end }
    end
    -- The ordinary game Lua sandbox has no debug-only file IO library.
    io = nil
    local scenario = dofile(root .. "/tests/state_tnt_smelter.lua")
    for _ = 1, 500 do
        _IsaacLanFrame()
    end
    assert(#commands == 0, "Fixture connected before selecting a native save")
    local available, value = _IsaacLanMenuRender(true, "forwarded")
    assert(available and value == "forwarded" and menus == 1)
    for _ = 1, 10 do
        _IsaacLanFrame()
    end
    assert(#commands == 0, "Fixture omitted the post-selection startup verification interval")
    for _ = 1, 500 do
        _IsaacLanFrame()
    end
    assert(#commands == 1 and commands[1][1] == (host and "host" or "join"))
    assert(commands[1][2] == (host and "31457" or "127.0.0.1:31457"))
    scenario.cleanup()
    assert(_IsaacLanFrame == frame and _IsaacLanMenuRender == menu and _IsaacLan.net_gate == gate)
end
io = originalIO
print("PASS fixture save selection, startup qualification and callback cleanup")
