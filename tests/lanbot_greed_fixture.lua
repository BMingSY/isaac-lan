-- Exercise the actual challenge lifecycle with native events supplied by the
-- model. Reject gameplay writes, extra grants and synthesized damage/shots.
local root = assert(arg[1])
local Phase = dofile(root .. "/tests/fixtures/net_phases.lua")
for _, ownerCase in ipairs({ { 2, 0 }, { 2, 1 }, { 4, 0 }, { 4, 1 }, { 4, 2 }, { 4, 3 } }) do
    local playerCount, localSlot = table.unpack(ownerCase)
    local host = localSlot == 0
    for _, ending in ipairs({ "win", "death", "stalled", "bot_error" }) do
        local phase, scene, clock, tick, stage, wave = 0, 1, 0, 0, 1, 0
        local hooks, callbacks, logs, commands, players = nil, {}, {}, {}, {}
        local grants, inputCalls, entities = 0, 0, {}
        local botFault, paused, shop, collision = false, false, false, 0
        local returned = false
        local health, counts = {}, {}
        for i = 1, playerCount do
            health[i], counts[i] = 6, {}
        end
        local function forbidden()
            error("Challenge changed native gameplay")
        end
        for slot = 0, playerCount - 1 do
            local index = slot
            local methods = {
                ControllerIndex = index + 1,
                Damage = 9.1,
                MaxFireDelay = 4,
                MoveSpeed = 0.85,
                Position = { X = 120, Y = 280 },
                GetNumKeys = function()
                    return 0
                end,
                GetNumCoins = function()
                    return 0
                end,
                GetPlayerType = function()
                    return 0
                end,
                GetHearts = function()
                    return health[index + 1]
                end,
                GetSoulHearts = function()
                    return 0
                end,
                IsDead = function()
                    return health[index + 1] == 0
                end,
                IsCoopGhost = function()
                    return false
                end,
                GetCollectibleCount = function()
                    local total = 1 -- Isaac's existing D6.
                    for _, count in pairs(counts[index + 1]) do
                        total = total + count
                    end
                    return total
                end,
                GetCollectibleNum = function(_, id)
                    return counts[index + 1][id] or 0
                end,
                AddCollectible = function(_, id)
                    assert(host and stage == 1 and wave == 0)
                    assert(id == 182 or id == 32, "Challenge granted an unrequested item")
                    local maximum = id == 182 and 1 or 3
                    local value = (counts[index + 1][id] or 0) + 1
                    assert(value <= maximum, "Challenge repeatedly granted its loadout")
                    counts[index + 1][id] = value
                    grants = grants + 1
                    if id == 182 then
                        health[index + 1] = 8
                    end -- Native Sacred Heart effect.
                end,
                ToPlayer = function()
                    return players[index]
                end,
                SetMinDamageCooldown = forbidden,
                TakeDamage = forbidden,
                AddHearts = forbidden,
                AddSoulHearts = forbidden,
                FireTear = forbidden,
                AddEntityFlags = forbidden,
            }
            players[index] = setmetatable({}, { __index = methods, __newindex = forbidden })
        end
        if not host then
            for i = 1, playerCount do
                counts[i] = { [182] = 1, [32] = 3 }
                health[i] = 8
            end
        end
        local room = {
            GetGridIndex = function(_, position)
                assert(position.X and position.Y)
                return 1
            end,
            GetGridCollision = function()
                return collision
            end,
            GetType = function()
                return shop and 2 or 1
            end,
            GetDoor = function() end,
            IsClear = function()
                return true
            end,
        }
        local level = {
            GetRoomByIdx = function(_, index)
                return { SafeGridIndex = index }
            end,
            GetStage = function()
                return stage
            end,
            GetStartingRoomIndex = function()
                return 84
            end,
            GetCurrentRoomIndex = function()
                return shop and 70 or 84
            end,
            SetStage = forbidden,
        }
        setmetatable(level, {
            __index = function(_, key)
                if key == "GreedModeWave" then
                    return wave
                end
            end,
            __newindex = forbidden,
        })
        local game = {
            Difficulty = 2,
            IsPaused = function()
                return paused
            end,
            IsGreedMode = function()
                return true
            end,
            GetLevel = function()
                return level
            end,
            GetRoom = function()
                return room
            end,
            GetFrameCount = function()
                return tick
            end,
            StartStageTransition = forbidden,
        }
        _IsaacLan = {
            net_phases = function()
                return Phase
            end,
            api_info = function()
                return {
                    ready = phase == 3 and 1 or 0,
                    slot = localSlot,
                    runId = 1,
                    worldEpoch = stage,
                    nowMs = clock,
                }
            end,
            api_actors = function()
                local roster = {}
                for i = 0, playerCount - 1 do
                    roster[#roster + 1] = { index = i, owner = i + 1 }
                end
                return roster
            end,
            rooms_ready = function()
                return phase == 3
            end,
            rooms_positions = function()
                local positions = {}
                for i = 0, playerCount - 1 do
                    positions[tostring(i)] = { index = 84 }
                end
                return positions
            end,
            rooms_heads = function()
                local heads = {}
                for i = 0, playerCount - 1 do
                    heads[tostring(i)] = i
                end
                return heads
            end,
            rooms_with_player = function(_, fn)
                fn()
                return true
            end,
            rooms_move = forbidden,
            input_bot = function(active, buttons)
                assert(active == 1 and buttons == 255, "Challenge altered normal bot input")
                inputCalls = inputCalls + 1
                return true
            end,
            test_gamepad = function(buttons)
                assert(buttons == 0 or scene == 3 and buttons == 4096)
            end,
            net_gate = function(...)
                hooks = table.pack(...)
                return true
            end,
        }
        _IsaacLanModules = {
            ["api/public"] = {
                withView = function(fn)
                    return fn()
                end,
                ready = function()
                    return phase == 3
                end,
            },
        }
        _IsaacLanTest = { host = host, port = 30990, players = playerCount }
        _IsaacLanFrame = function()
            return {
                phase = phase,
                scene = scene,
                prepared = false,
                players = playerCount,
                ready0 = returned and 0 or 1,
                ready1 = returned and 0 or 1,
                ready2 = returned and 0 or 1,
                ready3 = returned and 0 or 1,
            }
        end
        _IsaacLanCommand = function(command, args)
            if command == "host" or command == "join" then
                phase = 2
            elseif command == "start" then
                assert(host and args == "YV039KQF:2:0:0:0:0")
                phase, scene = 3, 2
            end
        end
        _IsaacLanBotCommand = function(args)
            commands[#commands + 1] = args
            if args == "on" then
                _IsaacLan.input_bot(1, 255)
            end
            Isaac.ConsoleOutput(
                botFault and "LANBOT paused reason=decision_error\n" or "LANBOT running\n"
            )
        end
        ModCallbacks = { MC_POST_GAME_END = 1, MC_ENTITY_TAKE_DMG = 2, MC_POST_FIRE_TEAR = 3 }
        EntityType = { ENTITY_PLAYER = 1, ENTITY_ULTRA_GREED = 406 }
        PlayerType = { PLAYER_ISAAC = 0 }
        RoomType = { ROOM_SHOP = 2 }
        GridCollisionClass = {
            COLLISION_NONE = 0,
            COLLISION_WALL_EXCEPT_PLAYER = 2,
            COLLISION_PIT = 1,
            COLLISION_OBJECT = 3,
        }
        CollectibleType = { COLLECTIBLE_SACRED_HEART = 182, COLLECTIBLE_WIRE_COAT_HANGER = 32 }
        Vector = function(x, y)
            return { X = x, Y = y }
        end
        Game = function()
            return game
        end
        Isaac = {
            GetPlayer = function(index)
                return assert(players[index])
            end,
            GetRoomEntities = function()
                return entities
            end,
            AddCallback = function(_, id, callback)
                assert(not callbacks[id])
                callbacks[id] = callback
            end,
            DebugString = function(text)
                logs[#logs + 1] = text
            end,
            ConsoleOutput = function() end,
            Spawn = forbidden,
            ExecuteCommand = forbidden,
        }
        dofile(root .. "/tests/state_lanbot_greed.lua")
        _IsaacLan.net_gate(function() end, function() end, function() end, function()
            return true
        end, function() end, function() end)
        for _ = 1, 362 do
            _IsaacLanFrame()
        end
        if not host then
            phase, scene = 3, 2
        end
        local function frame()
            tick, clock = tick + 1, clock + 33
            hooks[2](tick, 2, "")
            _IsaacLanFrame()
        end
        frame()
        frame()
        assert(inputCalls > 0 and (not host or grants == playerCount * 4))
        assert(callbacks[2](nil, players[0], 1, 0, { Type = 20 }) == nil, "Damage was suppressed")
        local tear = setmetatable({}, {
            __index = { SpawnerEntity = players[0], CollisionDamage = 9.1 },
            __newindex = forbidden,
        })
        callbacks[3](nil, tear)
        for i = 1, playerCount - 1 do
            callbacks[3](nil, { SpawnerEntity = players[i] })
        end
        if host then
            shop, collision = true, 3
            local ok, err = pcall(frame)
            assert(
                not ok and tostring(err):find("Shop arrival landed in blocked terrain", 1, true),
                "A blocked shop arrival was accepted"
            )
            shop, collision = false, 0
            frame()
        end
        paused = true
        clock = clock + 180001
        frame()
        assert(not table.concat(logs, "\n"):find("RESULT", 1, true), "Pause counted as a stall")
        paused = false
        frame()
        if ending == "win" then
            for floor = 1, 7 do
                stage, wave = floor, floor < 7 and 10 or 0
                if floor == 7 then
                    entities = {
                        {
                            Type = 406,
                            HitPoints = 100,
                            IsActiveEnemy = function()
                                return true
                            end,
                            IsDead = function()
                                return false
                            end,
                        },
                    }
                end
                frame()
            end
            callbacks[1](nil, false)
        elseif ending == "death" then
            for i = 1, playerCount do
                health[i] = 0
            end
            frame()
            callbacks[1](nil, true)
        elseif ending == "bot_error" then
            botFault = true
            for _ = 1, 120 do
                frame()
            end
        elseif host then
            -- Repeated arena/shop transitions must not restart the stall clock.
            local position = 84
            _IsaacLan.rooms_positions = function()
                local locations = {}
                for slot = 0, playerCount - 1 do
                    locations[tostring(slot)] = { index = slot == 1 and position or 84 }
                end
                return locations
            end
            for i = 1, 20 do
                position = i % 2 == 0 and 84 or 70
                clock = clock + 9000
                frame()
            end
        end
        phase, scene, returned = ending == "win" and Phase.lobby or Phase.idle, 1, true
        _IsaacLanFrame()
        local text = table.concat(logs, "\n")
        assert(text:find("PASS challenge observed", 1, true), text)
        if host or ending ~= "stalled" then
            assert(
                text:find(
                    "RESULT outcome=" .. ending .. " cleared=" .. tostring(ending == "win"),
                    1,
                    true
                ),
                text
            )
        end
        assert(not host or grants == playerCount * 4, "Preparation was repeated during progression")
        if host and ending == "win" then
            for i = 0, playerCount - 1 do
                assert(text:find("shots" .. i .. "=1", 1, true), "Missing actor shot statistics")
            end
        end
        assert(
            not host or ending ~= "win" or inputCalls == 7,
            "Bot did not refresh across native floors"
        )
    end
end
print(
    "lanbot Greed fixture: two/four owners, native win, death, stall, bot error; no gameplay cheats"
)
