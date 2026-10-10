-- Reproduce deferred native room transfers in the actual engine fixture.
local root = assert(arg[1])
for _, scenario in ipairs({ { 2, false }, { 3, false }, { 2, true }, { 3, true } }) do
    local difficulty, campaign = table.unpack(scenario)
    local callbacks, clock, tears, terminalVariant = {}, 0, {}, 0
    local main, shop, exit, active, terminal = 84, 70, 98, 84, 58
    local stage, ready = 1, true
    local positions = { ["0"] = { index = main }, ["1"] = { index = main } }
    local pending, hooks, wave, clear, enemy, coins, bought, spawned =
        {}, nil, 0, false, true, 0, false, 0
    local vector
    local vectorMethods = {
        __add = function(a, b)
            return vector(a.X + b.X, a.Y + b.Y)
        end,
    }
    vector = function(x, y)
        return setmetatable({ X = x, Y = y }, vectorMethods)
    end
    local button = {
        Position = vector(320, 280),
        State = 0,
        GetType = function()
            return 20
        end,
        GetVariant = function()
            return 2
        end,
        GetSprite = function()
            return {
                GetAnimation = function()
                    return "Off"
                end,
            }
        end,
    }
    local trapdoor = {
        Position = vector(320, 280),
        State = 1,
        GetType = function()
            return 17
        end,
    }
    local players, presses = {}, 0
    for slot = 0, 1 do
        players[slot] = {
            SetMinDamageCooldown = function() end,
            AddCoins = function(_, delta)
                coins = coins + delta
            end,
            GetNumCoins = function()
                return coins
            end,
            HasCollectible = function()
                return bought
            end,
            AreControlsEnabled = function()
                return true
            end,
            FireTear = function()
                local tear = {}
                tears[#tears + 1] = tear
                return tear
            end,
        }
    end
    local function spawnData(kind, entity)
        return {
            Type = kind,
            SpawnCount = 1,
            Spawns = {
                Get = function()
                    return {
                        EntryCount = 1,
                        Entries = {
                            Get = function()
                                return { Type = entity }
                            end,
                        },
                    }
                end,
            },
        }
    end
    local descriptors = {
        { SafeGridIndex = shop, Data = { Type = 2 } },
        { SafeGridIndex = exit, Data = { Type = 23 } },
    }
    local level = {
        GetStage = function()
            return stage
        end,
        SetStage = function(_, value)
            assert(not campaign, "Full campaign directly skipped native floors")
            stage = value
        end,
        GetStartingRoomIndex = function()
            return main
        end,
        GetRooms = function()
            if stage == 7 then
                descriptors = {
                    { SafeGridIndex = 71, Data = spawnData(5, 50) },
                    { SafeGridIndex = terminal, Data = spawnData(difficulty == 3 and 5 or 1, 406) },
                }
            end
            return {
                Size = #descriptors,
                Get = function(_, i)
                    return descriptors[i + 1]
                end,
            }
        end,
    }
    local game = {
        Difficulty = difficulty,
        IsGreedMode = function()
            return true
        end,
        GetLevel = function()
            return level
        end,
        StartStageTransition = function(_, same, animation, player)
            assert(not campaign, "Full campaign directly started a stage transition")
            assert(same and animation == 0 and player == players[1])
            ready = false
        end,
        GetRoom = function()
            return {
                IsClear = function()
                    return clear
                end,
                GetGridSize = function()
                    return 1
                end,
                GetGridEntity = function()
                    return active == main and button or active == exit and trapdoor or nil
                end,
            }
        end,
    }
    local native = {
        api_info = function()
            return { nowMs = clock }
        end,
        net_progress = function()
            return "\1" .. string.rep("\1", 642) .. string.pack(">I4", 98765)
        end,
        test_gamepad = function() end,
        rooms_ready = function()
            return ready
        end,
        rooms_move = function(slot, index)
            pending[slot] = index
            return true
        end,
        rooms_positions = function()
            return positions
        end,
        rooms_heads = function()
            return { ["0"] = 0, ["1"] = 1 }
        end,
        rooms_with_player = function(slot, fn)
            local previous = active
            active = positions[tostring(slot)].index
            fn()
            active = previous
            return true
        end,
        net_gate = function(...)
            hooks = table.pack(...)
        end,
    }
    local env = setmetatable({
        _IsaacLan = native,
        _IsaacLanFrame = function()
            return { phase = 0, scene = 1, prepared = false }
        end,
        _IsaacLanCommand = function() end,
        _IsaacLanTest = {
            host = true,
            route = difficulty == 3 and "greedier" or "greed",
            port = "30420",
            greedCampaign = campaign,
        },
        Vector = setmetatable({ Zero = vector(0, 0) }, {
            __call = function(_, x, y)
                return vector(x, y)
            end,
        }),
        EntityPtr = function(e)
            return { Ref = e }
        end,
        EntityRef = function(p)
            return p
        end,
        RoomType = { ROOM_SHOP = 2, ROOM_GREED_EXIT = 23 },
        GridEntityType = { GRID_PRESSURE_PLATE = 20, GRID_TRAPDOOR = 17 },
        DamageFlag = { DAMAGE_IGNORE_ARMOR = 1 },
        CollectibleType = { COLLECTIBLE_SAD_ONION = 1 },
        EntityType = { ENTITY_PICKUP = 5, ENTITY_ULTRA_GREED = 406 },
        PickupVariant = { PICKUP_COIN = 20, PICKUP_COLLECTIBLE = 100, PICKUP_BIGCHEST = 340 },
        ModCallbacks = { MC_POST_GAME_END = 1, MC_PRE_GAME_EXIT = 2 },
        Game = function()
            return game
        end,
        Isaac = {
            AddCallback = function(_, id, callback)
                callbacks[id] = callback
            end,
            DebugString = function(text)
                if text:find(" BUTTON ", 1, true) then
                    presses = presses + 1
                end
            end,
            GetPlayer = function(slot)
                return players[slot]
            end,
            GetRoomEntities = function()
                if active == terminal then
                    if campaign and clear then
                        return {
                            {
                                Type = 5,
                                Variant = 340,
                                Position = vector(320, 280),
                                ToNPC = function() end,
                            },
                        }
                    end
                    local npc = {
                        Type = 406,
                        Variant = terminalVariant,
                        Position = vector(320, 280),
                        IsBoss = function()
                            return true
                        end,
                        IsActiveEnemy = function()
                            return true
                        end,
                        IsDead = function()
                            return false
                        end,
                    }
                    npc.ToNPC = function()
                        return npc
                    end
                    return { npc }
                end
                if active ~= main then
                    return {}
                end
                return {
                    {
                        IsActiveEnemy = function()
                            return enemy
                        end,
                        TakeDamage = function()
                            enemy = false
                        end,
                    },
                    {
                        Type = 5,
                        Variant = 20,
                        IsActiveEnemy = function()
                            return false
                        end,
                    },
                }
            end,
            Spawn = function(_, _, _, position)
                assert(active == shop, "Shop pickup spawned before the queued transfer completed")
                spawned = spawned + 1
                local pickup = {
                    Position = position,
                    Wait = 0,
                    Exists = function()
                        return not bought
                    end,
                }
                pickup.ToPickup = function()
                    return pickup
                end
                return pickup
            end,
        },
    }, { __index = _G })
    assert(loadfile(root .. "/tests/state_greed.lua", "t", env))()
    if campaign then
        for _ = 1, 300 do
            env._IsaacLanFrame()
        end
    end
    local noop = function() end
    native.net_gate(noop, noop, noop, noop, noop, noop)
    local function tick(t, nextWave)
        clock = t * 1000
        if nextWave then
            wave = nextWave
        end
        level.GreedModeWave = wave
        hooks[2](t, 0, "")
    end
    local function arrive()
        for slot, index in pairs(pending) do
            positions[tostring(slot)].index = index
        end
        pending = {}
    end
    tick(30, 0)
    arrive()
    tick(40, 1)
    tick(130, 1)
    for nextWave = 2, (difficulty == 3 and 9 or 8) do
        tick(130 + nextWave, nextWave)
    end
    tick(140)
    assert(presses == 3, "Enemy death alone must not re-arm the wave button")
    clear = true
    tick(150)
    tick(179)
    assert(presses == 3, "Wave button was pressed before its reset animation")
    local t = 180
    tick(t)
    assert(presses == 4)
    for nextWave = wave + 1, (difficulty == 3 and 11 or 10) do
        t = t + 1
        tick(t, nextWave)
    end
    t = t + 30
    tick(t)
    t = t + 1
    tick(t, difficulty == 3 and 12 or 11)
    assert(pending[1] == nil, "Clear left the arena before native rewards could finish")
    tick(t + 89)
    assert(pending[1] == nil, "Reward waiting ended early")
    t = t + 90
    tick(t)
    assert(pending[1] == shop and spawned == 0, "Shop setup ignored the transfer barrier")
    tick(t + 15)
    assert(spawned == 0, "Elapsed time alone must not complete a room transfer")
    arrive()
    tick(t + 16)
    assert(spawned == 1 and coins == 30)
    bought, coins = true, 15
    tick(t + 17)
    assert(pending[1] == exit, "Purchase did not queue the native exit")
    tick(t + 40)
    assert(positions["1"].index == shop)
    arrive()
    trapdoor.State = 0
    tick(t + 41)
    assert(
        players[1].Position.X == trapdoor.Position.X + 160 and stage == 1,
        "Closed native exit was contacted before its opening animation"
    )
    trapdoor.State = 1
    t = t + 1
    tick(t + 41)
    assert(players[1].Position == trapdoor.Position, "Exit setup did not use the arrived room")
    if campaign then
        tick(t + 42)
        assert(
            players[1].Position.X == trapdoor.Position.X + 160 and stage == 1,
            "Missed initial exit contact was not retried"
        )
        tick(t + 103)
        assert(
            players[1].Position.X == trapdoor.Position.X + 4
                and players[1].Velocity.X == 1
                and stage == 1,
            "Exit retry bypassed native collision"
        )
        t = t + 40
    end
    stage = 2
    positions["0"].index, positions["1"].index = main, main
    tick(t + 80, 0)
    if not campaign then
        assert(
            stage == 7 and not ready,
            "Terminal preparation bypassed the native floor transaction"
        )
        tick(t + 81)
        assert(pending[1] == nil, "Terminal lookup ran before floor initialization")
        ready = true
        tick(t + 82)
        assert(pending[1] == terminal, "Terminal fixture chose the preceding Greed miniboss room")
        arrive()
        positions["0"].index = terminal -- Native finalCombat gathering has its own C++ coverage.
        tick(t + 173)
        tick(t + 264)
    else
        assert(stage == 2 and ready, "Campaign skipped floor two")
        t = math.ceil((t + 81) / 15) * 15
        for floor = 2, 6 do
            assert(stage == floor)
            clear, enemy = false, true
            tick(t, 0)
            arrive()
            local normal, bosses = difficulty == 3 and 9 or 8, difficulty == 3 and 11 or 10
            for w = 1, normal do
                t = t + 15
                if w == normal then
                    clear = true
                end
                tick(t, w)
            end
            t = t + 30
            tick(t)
            for w = normal + 1, bosses do
                t = t + 15
                tick(t, w)
            end
            t = t + 30
            tick(t)
            t = t + 15
            tick(t, difficulty == 3 and 12 or 11)
            assert(pending[1] == nil, "A later floor skipped reward completion")
            t = t + 90
            tick(t)
            assert(pending[1] == exit, "Campaign did not use the generated exit")
            t = t + 15
            tick(t)
            arrive()
            tick(t + 1)
            assert(players[1].Position == trapdoor.Position)
            stage = floor + 1
            positions["0"].index, positions["1"].index = main, main
            t = t + 90
            tick(t, 0)
        end
        assert(stage == 7)
        t = t + 1
        tick(t)
        assert(pending[1] == terminal)
        arrive()
        positions["0"].index = terminal
        clear = false
        t = t + 91
        tick(t)
        t = math.ceil(t / 3) * 3 + 3
        tick(t)
        assert(
            #tears > 0 and tears[#tears].CollisionDamage == 100,
            "Boss did not use bounded native tears"
        )
        if difficulty == 3 then
            assert(not pcall(callbacks[1], nil, false), "Win without the golden phase was accepted")
            terminalVariant = 1
            t = t + 3
            tick(t)
        end
        clear = true
        t = t + 3
        tick(t)
        t = t + 3
        tick(t)
        assert(players[1].Position.X > 320, "Ending chest collision was never arranged")
        assert(not pcall(callbacks[1], nil, true), "Defeat was accepted as a win")
        callbacks[1](nil, false)
        assert(not pcall(callbacks[1], nil, false), "Duplicate win callback was accepted")
        callbacks[2]()
        clock = clock + 4000
        env._IsaacLanFrame()
    end
end
print("PASS Greed fixture transfers, seven-floor waves, native Boss phases, win and cleanup")
