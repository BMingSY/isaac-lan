-- Exercise the production world capture/apply chain, including floor barriers.
local root = assert(arg[1])
local function environment(difficulty)
    local level = {
        GreedModeWave = 0,
        DungeonReturnPosition = { X = 0, Y = 0 },
        DungeonReturnRoomIndex = 84,
        stage = 1,
        GetStage = function(self)
            return self.stage
        end,
        GetStageType = function()
            return 0
        end,
        SetStage = function(self, stage)
            self.stage = stage
        end,
        GetCurses = function()
            return 0
        end,
        GetRooms = function()
            return { Size = 0 }
        end,
    }
    local room = {
        IsClear = function()
            return true
        end,
        SetClear = function() end,
        GetFrameCount = function()
            return 20
        end,
        GetGridSize = function()
            return 0
        end,
    }
    local game = {
        IsGreedMode = function()
            return difficulty >= 2
        end,
        GetLevel = function()
            return level
        end,
        GetRoom = function()
            return room
        end,
        GetNumPlayers = function()
            return 0 -- Actor inventory has separate offline coverage.
        end,
        GetFrameCount = function()
            return 20
        end,
    }
    local position, ready, epoch = 84, true, 1
    local native = {
        rooms_positions = function()
            return { ["1"] = { index = position, dimension = 0 } }
        end,
        rooms_heads = function()
            return { ["1"] = 0 }
        end,
        rooms_with_player = function(slot, fn)
            assert(slot == 1)
            fn()
            return true
        end,
        rooms_connected = function()
            return 3
        end,
        rooms_sync = function(bytes)
            local _, count, slot, _, index = string.unpack(">BBBi4i4", bytes)
            assert(count == 1 and slot == 1)
            position = index
            return true
        end,
        rooms_ready = function()
            return ready
        end,
        rooms_begin_floor = function()
            ready = false
            return true
        end,
        net_floor_epoch = function()
            return epoch
        end,
        room_layout = function()
            return "layout"
        end,
        music_state = function()
            return "music"
        end,
        net_progress = function()
            return "progress"
        end,
        sound_events = function()
            return ""
        end,
        presentation_events = function()
            return ""
        end,
        item_presentation_events = function()
            return ""
        end,
        item_presentation_pose = function()
            return "pose"
        end,
        home_scene_pose = function()
            return "scene"
        end,
        item_presentation_sprite = function()
            return false
        end,
        home_scene_sprite = function()
            return false
        end,
        state_clock = function() end,
        door_slot = function()
            return true
        end,
        map_refresh = function()
            return true
        end,
        sound_reset = function() end,
        presentation_reset = function() end,
        rewind_reset = function() end,
    }
    local env = setmetatable({
        _IsaacLan = native,
        _IsaacLanPrediction = {},
        _IsaacLanStatus = function()
            return { pause = 1 }
        end,
        _IsaacLanModules = {},
        ItemType = { ITEM_ACTIVE = 2 },
        NullItemID = { ID_LOST_CURSE = 1 },
        CollectibleType = { COLLECTIBLE_BLACK_CANDLE = 260 },
        Vector = function(x, y)
            return { X = x, Y = y }
        end,
        Isaac = {
            GetRoomEntities = function()
                return {}
            end,
            GetTime = function()
                return 1000
            end,
            GetPlayer = function()
                return {
                    Position = { X = 100, Y = 100 },
                    GetSprite = function()
                        return {}
                    end,
                }
            end,
        },
        SFXManager = function()
            return {}
        end,
        Game = function()
            return game
        end,
    }, { __index = _G })
    for name in io.lines(root .. "/src/bridge/modules.txt") do
        if name ~= "api/public" and not name:match("^compat/mods/") then
            env._IsaacLanModules[name] =
                assert(loadfile(root .. "/src/bridge/" .. name .. ".lua", "t", env))()
        end
    end
    assert(loadfile(root .. "/src/bridge/app/world.lua", "t", env))()
    return {
        state = env._IsaacLanState,
        level = level,
        move = function(index)
            position = index
        end,
        floor = function(nextEpoch, stage, loaded)
            epoch, level.stage, ready = nextEpoch, stage, loaded
        end,
    }
end
for difficulty = 0, 3 do
    local host, guest = environment(difficulty), environment(difficulty)
    for tick, wave in ipairs({ 0, 1, 1, 8, 9, 10, 11, 12, 0 }) do
        host.level.GreedModeWave = wave
        local bytes = host.state.capture(1, tick)
        local view = host.state.decode(bytes)
        assert(
            view[18] == (difficulty >= 2 and wave or false),
            "Host omitted authoritative Greed wave"
        )
        guest.level.GreedModeWave = 4
        assert(guest.state.apply(bytes, tick, 0))
        assert(
            guest.level.GreedModeWave == (difficulty >= 2 and wave or 4),
            "Replica Greed HUD retained a local wave"
        )
        assert(guest.state.apply(bytes, tick, 0), "Repeated snapshots must be safe")
        -- Reproduce native room presentation after apply, before the HUD.
        guest.level.GreedModeWave = 6
        guest.state.present("", tick)
        assert(
            guest.level.GreedModeWave == (difficulty >= 2 and wave or 6),
            "Native update replaced the authoritative wave before HUD rendering"
        )
        host.move(tick % 2 == 0 and 85 or 84)
    end
    -- A future-floor snapshot must neither regenerate the floor nor write its wave.
    host.floor(2, 2, true)
    host.level.GreedModeWave = 0
    local bytes = host.state.capture(1, 30)
    guest.level.GreedModeWave = 8
    assert(not guest.state.apply(bytes, 30, 0))
    assert(guest.level.GreedModeWave == 8)
    assert(guest.state.beginFloor(2, 2, 0, 0, false))
    guest.state.present("", 30)
    assert(guest.level.GreedModeWave == 8, "Old HUD state crossed the floor begin barrier")
    assert(not guest.state.apply(bytes, 30, 0))
    guest.floor(2, 2, true)
    assert(guest.state.apply(bytes, 30, 0))
    assert(guest.level.GreedModeWave == (difficulty >= 2 and 0 or 8))
    assert(not guest.state.beginFloor(2, 2, 0, 0, false))
    -- Late old-floor state cannot restore a completed floor's wave.
    host.floor(1, 1, true)
    host.level.GreedModeWave = 12
    assert(not guest.state.apply(host.state.capture(1, 31), 31, 0))
    guest.state.reset()
    guest.level.GreedModeWave = 5
    guest.state.present("", 32)
    assert(guest.level.GreedModeWave == 5, "A new run retained the previous HUD wave")
    guest.floor(1, 1, true)
    assert(guest.state.apply(host.state.capture(1, 32), 32, 0))
end
-- Invalid or cross-mode state must not mutate the counter.
local factory = dofile(root .. "/src/bridge/compat/routes/greed.lua")
-- A completed arena can leave the independently entered exit locked. Repair
-- that room's clear flag without opening a grid or skipping a native floor.
for difficulty = 2, 3 do
    local stage, enemies, calls = 2, 0, 0
    local isGreed = true
    local arena, exit = { Clear = false }, { Clear = false, Data = { Type = 23 } }
    local level = {
        GreedModeWave = difficulty == 3 and 11 or 10,
        GetStage = function()
            return stage
        end,
        GetStartingRoomIndex = function()
            return 84
        end,
        GetRoomByIdx = function(_, index)
            return index == 84 and arena or exit
        end,
    }
    local room = {
        GetAliveEnemiesCount = function()
            return enemies
        end,
        SetClear = function(_, value)
            assert(value == true)
            exit.Clear = value
        end,
    }
    local game = {
        Difficulty = difficulty,
        IsGreedMode = function()
            return isGreed
        end,
        GetLevel = function()
            return level
        end,
        GetRoom = function()
            return room
        end,
    }
    local native = {
        rooms_positions = function()
            return { ["0"] = { index = 98, dimension = 0 }, ["1"] = { index = 98, dimension = 0 } }
        end,
        rooms_with_player = function(_, fn)
            calls = calls + 1
            fn()
            return true
        end,
    }
    local adapter = factory(function()
        return game
    end)
    adapter.authority(native, 23)
    assert(not exit.Clear and calls == 0, "Unfinished Boss arena unlocked the exit")
    arena.Clear = true
    level.GreedModeWave = level.GreedModeWave - 1
    adapter.authority(native, 23)
    assert(not exit.Clear and calls == 0, "Ordinary waves unlocked the exit")
    level.GreedModeWave = level.GreedModeWave + 1
    enemies = 1
    adapter.authority(native, 23)
    assert(not exit.Clear and calls == 1, "Living exit enemies were bypassed")
    enemies = 0
    adapter.authority(native, 23)
    assert(exit.Clear and calls == 2, "Completed split-room exit stayed locked")
    adapter.authority(native, 23)
    assert(calls == 2, "Repeated route step reran clear repair")
    exit.Clear, stage = false, 7
    adapter.authority(native, 23)
    assert(not exit.Clear and calls == 2, "Final Boss exit opened early")
    stage, isGreed = 2, false
    adapter.authority(native, 23)
    assert(not exit.Clear and calls == 2, "Normal mode was treated as Greed")
end
for difficulty = 0, 3 do
    local level = { GreedModeWave = 5 }
    local adapter = factory(function()
        return {
            IsGreedMode = function()
                return difficulty >= 2
            end,
            GetLevel = function()
                return level
            end,
        }
    end)
    for _, value in ipairs({ -1, 13, 1.5, math.huge, "1", true, {} }) do
        assert(not pcall(adapter.apply, value))
        assert(level.GreedModeWave == 5)
    end
    assert(not pcall(adapter.apply, nil))
    assert(pcall(adapter.apply, false) == (difficulty < 2))
    if difficulty < 2 then
        assert(not pcall(adapter.apply, 1))
    end
    assert(level.GreedModeWave == 5)
end
-- The concentrated engine fixture must select both difficulties from the
-- actual lobby in the ordinary Lua sandbox, before touching gameplay APIs.
for _, route in ipairs({ "greed", "greedier" }) do
    for _, host in ipairs({ true, false }) do
        local commands, messages, hooks = {}, {}, nil
        local status = { phase = 0 }
        local env = setmetatable({
            io = false,
            _IsaacLanTest = { host = host, port = "30420", route = route },
            _IsaacLan = {
                net_gate = function(...)
                    hooks = table.pack(...)
                end,
                test_gamepad = function(value)
                    assert(value == 0)
                end,
            },
            _IsaacLanFrame = function()
                return status
            end,
            _IsaacLanCommand = function(name, value)
                commands[#commands + 1] = { name, value }
                if name == "start" then
                    status.phase = 3
                end
            end,
            Isaac = {
                DebugString = function(text)
                    messages[#messages + 1] = text
                end,
            },
            Game = function()
                error("Menu preparation must not access game objects")
            end,
        }, { __index = _G })
        assert(loadfile(root .. "/tests/state_greed.lua", "t", env))()
        local original = function() end
        env._IsaacLan.net_gate(original, original, original, original, original, original)
        assert(hooks and hooks.n == 6)
        for _ = 1, 400 do
            env._IsaacLanFrame()
        end
        assert(#commands == 1 and commands[1][1] == (host and "host" or "join"))
        assert(commands[1][2] == (host and "30420" or "127.0.0.1:30420"))
        assert(messages[1] == "LAN_NETWORK MENU_READY")
        status.phase, status.players, status.ready0, status.ready1 = 2, 2, 1, 1
        env._IsaacLanFrame()
        assert(commands[2][1] == "choose" and commands[2][2] == "0:1")
        if host then
            assert(commands[3][1] == "start")
            assert(commands[3][2] == "YV039KQF:" .. (route == "greedier" and 3 or 2) .. ":0:0:0:0")
        else
            assert(#commands == 2, "Guest must not start a game")
        end
    end
end
dofile(root .. "/tests/greed_fixture.lua")
print(
    "PASS Greed/Greedier world waves, repeated states, rooms, floors, new runs and lobby fixtures"
)
