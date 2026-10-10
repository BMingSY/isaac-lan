-- Execute the actual accelerated campaign against a native lifecycle model.
-- Player motion and victory remain external engine events in this model.
local root = assert(arg[1])
for _, host in ipairs({ true, false }) do
    local hooks, callbacks, messages = nil, {}, {}
    local clock, stage, roomIndex, clear, phase, scene, tick = 0, 1, 84, false, 0, 1, 0
    local points, items, moves, nextCalls = { 0, 0 }, {}, {}, 0
    local positions =
        { ["0"] = { index = 84, dimension = 0 }, ["1"] = { index = 84, dimension = 0 } }
    local vec = function(x, y)
        return {
            X = x,
            Y = y,
            Distance = function(a, b)
                return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
            end,
        }
    end
    local function sprite()
        return {
            GetAnimation = function()
                return "Idle"
            end,
            GetFrame = function()
                return 0
            end,
        }
    end
    local players = {}
    for slot = 0, 1 do
        local index = slot
        local methods = {
            ControllerIndex = slot + 1,
            EntityCollisionClass = 4,
            GetSprite = sprite,
            IsExtraAnimationFinished = function()
                return true
            end,
            SetMinDamageCooldown = function() end,
            HasCollectible = function(_, id)
                return items[index .. ":" .. id]
            end,
            AddCollectible = function(_, id)
                items[index .. ":" .. id] = true
            end,
            AddKeys = function() end,
            AddCoins = function() end,
            AddBombs = function() end,
            GetNumKeys = function()
                return 99
            end,
            GetNumCoins = function()
                return 99
            end,
            GetNumBombs = function()
                return 99
            end,
            ToPlayer = function()
                return players[index]
            end,
            FireTear = function()
                error("Campaign synthesized player firing")
            end,
        }
        players[slot] = setmetatable({}, {
            __index = function(_, key)
                return key == "Position" and vec(points[index + 1], 280) or methods[key]
            end,
            __newindex = function(_, key)
                error("Campaign directly wrote actor " .. key)
            end,
        })
    end
    local progress = (host and "\1" or "\0")
        .. string.rep(host and "\1" or "\0", 642)
        .. string.pack(">I4", host and 98765 or 321)
    local baseline = progress
    local native = {
        api_info = function()
            return { ready = phase == 3 and 1 or 0, runId = 1, worldEpoch = stage, nowMs = clock }
        end,
        input_bot = function()
            return true
        end,
        test_gamepad = function() end,
        net_progress = function()
            return progress
        end,
        rooms_ready = function()
            return phase == 3
        end,
        rooms_positions = function()
            return positions
        end,
        rooms_heads = function()
            return { ["0"] = 0, ["1"] = 1 }
        end,
        rooms_with_player = function(slot, fn)
            fn()
            return true
        end,
        rooms_move = function(slot, destination)
            assert(destination == 100 and not clear)
            moves[slot] = destination
            return true
        end,
        net_gate = function(...)
            hooks = table.pack(...)
            return true
        end,
    }
    local game = {
        GetLevel = function()
            return {
                GetStage = function()
                    return stage
                end,
                SetStage = function()
                    error("Campaign skipped native floors")
                end,
                GetRooms = function()
                    return {
                        Size = 1,
                        Get = function()
                            return { SafeGridIndex = 100, Data = { Type = 5 } }
                        end,
                    }
                end,
            }
        end,
        GetRoom = function()
            return {
                GetType = function()
                    return roomIndex == 100 and 5 or 1
                end,
                IsClear = function()
                    return clear
                end,
                SetClear = function()
                    error("Campaign forced native clearing")
                end,
                GetGridSize = function()
                    return 1
                end,
                GetGridEntity = function()
                    return {
                        State = clear and 1 or 0,
                        GetType = function()
                            return 17
                        end,
                    }
                end,
            }
        end,
        StartStageTransition = function()
            error("Campaign directly changed floors")
        end,
        End = function()
            error("Campaign synthesized victory")
        end,
    }
    local env = setmetatable({
        _IsaacLan = native,
        _IsaacLanTest = { host = host, port = 30890 },
        _IsaacLanModules = {
            ["api/public"] = {
                ready = function()
                    return phase == 3
                end,
                withView = function(fn)
                    fn()
                end,
            },
        },
        Game = function()
            return game
        end,
        Vector = vec,
        EntityType = {
            ENTITY_THE_LAMB = 273,
            ENTITY_ISAAC = 102,
            ENTITY_PICKUP = 5,
            ENTITY_EFFECT = 1000,
        },
        PickupVariant = { PICKUP_BIGCHEST = 340, PICKUP_COLLECTIBLE = 100 },
        EffectVariant = { HEAVEN_LIGHT_DOOR = 39 },
        GridEntityType = { GRID_TRAPDOOR = 17 },
        RoomType = { ROOM_BOSS = 5 },
        CollectibleType = {
            COLLECTIBLE_SPOON_BENDER = 3,
            COLLECTIBLE_POLAROID = 57,
            COLLECTIBLE_NEGATIVE = 78,
        },
        ModCallbacks = {
            MC_POST_FIRE_TEAR = 1,
            MC_POST_GAME_END = 2,
            MC_PRE_GAME_EXIT = 3,
            MC_PRE_PICKUP_COLLISION = 4,
        },
        Isaac = {
            AddCallback = function(_, id, fn)
                callbacks[id] = fn
            end,
            DebugString = function(text)
                messages[#messages + 1] = text
            end,
            ConsoleOutput = function() end,
            GetPlayer = function(slot)
                return players[slot]
            end,
            GetRoomEntities = function()
                if roomIndex ~= 100 then
                    return {}
                end
                if clear then
                    return {
                        {
                            Type = 5,
                            Variant = 340,
                            ToPickup = function()
                                return {
                                    Wait = 0,
                                    State = 0,
                                    EntityCollisionClass = 4,
                                    Touched = false,
                                    Position = vec(320, 280),
                                    GetSprite = sprite,
                                }
                            end,
                            ToNPC = function() end,
                        },
                    }
                end
                local npc = {
                    Type = stage == 11 and 273 or 20,
                    Variant = 0,
                    IsBoss = function()
                        return true
                    end,
                }
                npc.ToNPC = function()
                    return npc
                end
                return { npc }
            end,
        },
    }, { __index = _G })
    env._IsaacLanBotCommand = function(args)
        if args == "next" then
            nextCalls = nextCalls + 1
            if nextCalls % 2 == 1 then
                env.Isaac.ConsoleOutput("LANBOT error=no_known_exit\n")
                return
            end
        end
        env.Isaac.ConsoleOutput("LANBOT running task=attack\n")
    end
    env._IsaacLanCommand = function(action)
        if action == "host" or action == "join" then
            phase = 2
        elseif action == "choose" or action == "start" then
            phase, scene = 3, 2
        end
    end
    env._IsaacLanFrame = function()
        if phase == 3 then
            native.input_bot(1, 17)
        end
        return {
            phase = phase,
            scene = scene,
            players = 2,
            ready0 = 1,
            ready1 = 1,
            prepared = phase == 3,
        }
    end
    local file = assert(io.open(root .. "/tests/state_lanbot_campaign.lua"))
    local source = file:read("a")
    file:close()
    local inspect, coverage, terminal, fights, firing = assert(
        load(
            source .. "\nreturn function() return finished end, visited, bosses, fought, floorShots",
            "campaign",
            "t",
            env
        )
    )()
    native.net_gate(function() end, function() end, function() end, function()
        return true
    end, function() end, function()
        return true
    end)
    for _ = 1, 361 do
        clock = clock + 10
        env._IsaacLanFrame()
    end
    assert(phase == 3)
    for _, floor in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 10, 11 }) do
        stage, roomIndex, clear = floor, 84, false
        moves = {}
        for slot = 0, 1 do
            positions[tostring(slot)].index = 84
        end
        if floor ~= 1 then
            hooks[6](floor, 0, false)
        end
        for offset = 1, 150 do
            clock, tick = clock + 10, tick + 1
            points[1], points[2] = points[1] + 2, points[2] + 2
            if host then
                hooks[2](tick, 2, {})
            else
                hooks[4]("snapshot", tick, 0)
            end
            if host and moves[0] and moves[1] or not host and offset > 91 then
                roomIndex = 100
                for slot = 0, 1 do
                    positions[tostring(slot)].index = 100
                end
            end
            if roomIndex == 100 then
                for slot = 0, 1 do
                    local tear = { SpawnerEntity = players[slot], CollisionDamage = 3.5 }
                    callbacks[1](nil, tear)
                    assert(not host or tear.CollisionDamage == 3.5 or tear.CollisionDamage == 100)
                end
            end
            if offset > 120 then
                clear = true
            end
            env._IsaacLanFrame()
        end
        assert(roomIndex == 100 and nextCalls >= 2, "Native exit selection was never retried")
    end
    assert(not pcall(callbacks[2], nil, true), "Defeat was accepted")
    coverage[5] = nil
    assert(not pcall(callbacks[2], nil, false), "A skipped campaign floor was accepted")
    coverage[5] = true
    local savedTerminal = terminal["273:0"]
    terminal["273:0"] = nil
    assert(not pcall(callbacks[2], nil, false), "Missing terminal Boss was accepted")
    terminal["273:0"] = savedTerminal
    if host then
        local savedFight, savedShots = fights[5], firing[5]
        fights[5] = nil
        assert(not pcall(callbacks[2], nil, false), "Missing native floor Boss fight was accepted")
        fights[5], firing[5] = savedFight, { 0, 1 }
        assert(not pcall(callbacks[2], nil, false), "Floor without real firing was accepted")
        firing[5] = savedShots
    end
    callbacks[2](nil, false)
    assert(not pcall(callbacks[2], nil, false), "Duplicate victory was accepted")
    callbacks[3]()
    phase, scene, clock = 0, 1, clock + 4000
    progress = baseline:sub(1, -5) .. string.pack(">I4", 1)
    assert(not pcall(env._IsaacLanFrame), "Changed private progress counter was accepted")
    progress = baseline
    env._IsaacLanFrame()
    assert(inspect())
    assert(table.concat(messages, "\n"):find("PASS full LANBOT campaign", 1, true))
end
print("PASS LANBOT campaign native lifecycle, both actor shots, exit retry and cleanup guards")

-- Focused behavior diagnostics must also initialize in the Release sandbox
-- without io/LuaDebug; a missing set of behavior results cannot finish as PASS.
do
    local env = setmetatable({
        _IsaacLanTest = { host = true, port = "30000" },
        _IsaacLan = {
            net_gate = function()
                return true
            end,
            test_gamepad = function() end,
        },
        _IsaacLanFrame = function()
            return { verified = 1510, phase = 0 }
        end,
        Isaac = {
            AddCallback = function() end,
            DebugString = function() end,
            ConsoleOutput = function() end,
            ExecuteCommand = function() end,
        },
        ModCallbacks = { MC_ENTITY_TAKE_DMG = 1 },
    }, {
        __index = function(_, key)
            if key ~= "io" then
                return _G[key]
            end
        end,
    })
    assert(loadfile(root .. "/tests/state_lanbot.lua", "t", env))()
    assert(not pcall(env._IsaacLanFrame), "Incomplete behavior checks were accepted")
end
print("PASS Release behavior fixture initializes without io and rejects missing results")
