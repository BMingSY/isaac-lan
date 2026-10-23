local root = assert(arg[1])
local testInput = dofile(root .. "/tests/support/input.lua")
_IsaacLanTestInput = testInput
LevelStateFlag = { STATE_MINESHAFT_ESCAPE = 22 }
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
        local guest = route == "poop" and "25:1" or route == "knife" and "7:1" or "0:1"
        assert(commands[2][2] == (not host and guest or "0:1"))
        _IsaacLan.rooms_ready = function()
            return false
        end
        local capture, input = _IsaacLan.net_gate()
        for _ = 0, 120 do
            input = capture()
        end
        local use = not host and route == "poop"
        local frame = testInput.decode(input)
        assert(frame.values[ButtonAction.ACTION_PILLCARD] == (use and testInput.maxValue or 0))
        assert(frame.values[11] == 0, "Poop fixture pressed Drop instead of Use")
        assert(frame.triggered == (use and 1 << ButtonAction.ACTION_PILLCARD or 0))
    end
end
for _, host in ipairs({ true, false }) do
    local commands = {}
    local status = { phase = 0, scene = 1, prepared = false }
    _IsaacLanTest = { host = host, port = "30220", homeOnly = true }
    _IsaacLan = {
        api_info = function()
            return { nowMs = 1000 }
        end,
        net_progress = function()
            return string.rep("\0", 700)
        end,
        test_gamepad = function() end,
        victory_lap_prompt = function()
            return false, 0, 0, false, false
        end,
        net_gate = function() end,
    }
    _IsaacLanFrame = function()
        return status
    end
    _IsaacLanCommand = function(name, value)
        commands[#commands + 1] = { name, value }
    end
    ModCallbacks = {
        MC_PRE_PICKUP_COLLISION = 1,
        MC_POST_GAME_END = 2,
        MC_PRE_GAME_EXIT = 3,
        MC_ENTITY_TAKE_DMG = 4,
    }
    EntityType = { ENTITY_PLAYER = 1 }
    local damageCallback
    Isaac = {
        AddCallback = function(_, id, fn, filter)
            if id == ModCallbacks.MC_ENTITY_TAKE_DMG then
                assert(filter == EntityType.ENTITY_PLAYER)
                damageCallback = fn
            end
        end,
        DebugString = function() end,
    }
    PickupVariant = { PICKUP_BIGCHEST = 340 }
    dofile(root .. "/tests/state_endings.lua")
    local blocked = assert(damageCallback)(nil, {}, 1, 0, { Type = 1000, Variant = 19 })
    if host then
        assert(blocked == false, "Route fixture did not block native player damage")
    else
        assert(blocked == nil, "Guest fixture intercepted authoritative damage")
    end
    for _ = 1, 400 do
        _IsaacLanFrame()
    end
    status.phase, status.players, status.ready0, status.ready1 = 2, 2, 1, 1
    _IsaacLanFrame()
    assert(commands[2][1] == "choose" and commands[2][2] == (host and "0:1" or "7:1"))
    if host then
        assert(
            commands[3][1] == "start" and commands[3][2] == "YV039KQF:0:0:7:0:0",
            "Home guest selection disagrees with native lobby start"
        )
    end
end
-- Localized text carries four source strings after its fallback title/body.
-- The concentrated audio fixture must consume those before the next event.
_IsaacLanTest = { host = false, port = "30220" }
local events = string.pack(
    ">I1I4I4I4I1I1I1s2s2s2s2s2s2",
    2,
    1,
    50,
    1,
    1,
    0,
    4,
    "0 - The Fool",
    "Where journey begins",
    "Items",
    "#FOOL_NAME",
    "Items",
    "#FOOL_DESC"
) .. string.pack(">I4I4I4I1I1I1I4I4I1", 2, 60, 1, 1, 0, 1, 0, 0, 0)
_IsaacLanState = {
    decode = function()
        return { [16] = { events, false, false, "pose" } }
    end,
}
_IsaacLan = {
    item_presentation_pose = function()
        return "pose"
    end,
    net_gate = function(_, _, _, restore)
        return restore
    end,
}
_IsaacLanFrame = function() end
ModCallbacks = { MC_USE_ITEM = 1, MC_USE_CARD = 2 }
dofile(root .. "/tests/state_guest_presentation_audio.lua")
local restore = _IsaacLan.net_gate(nil, nil, nil, function()
    return true
end)
assert(restore("world", 50, 0))
print("PASS side-route and Home lobby selection and localized audio fixture")
