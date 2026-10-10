-- Reproduce deferred native room transfers in the actual engine fixture.
local root = assert(arg[1])
for _, difficulty in ipairs({ 2, 3 }) do
    local main, shop, exit, active, terminal = 84, 70, 98, 84, 58
    local stage, ready = 1, true
    local positions = { ["0"] = { index = main }, ["1"] = { index = main } }
    local pending, hooks, wave, clear, enemy, coins, bought, spawned =
        {}, nil, 0, false, true, 0, false, 0
    local vector = function(x, y)
        return { X = x, Y = y }
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
        _IsaacLanFrame = function() end,
        _IsaacLanTest = {
            host = true,
            route = difficulty == 3 and "greedier" or "greed",
            port = "30420",
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
        PickupVariant = { PICKUP_COIN = 20, PICKUP_COLLECTIBLE = 100 },
        Game = function()
            return game
        end,
        Isaac = {
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
                    return { { Type = 406 } }
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
    local noop = function() end
    native.net_gate(noop, noop, noop, noop, noop, noop)
    local function tick(t, nextWave)
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
    tick(t + 41)
    assert(players[1].Position == trapdoor.Position, "Exit setup did not use the arrived room")
    stage = 2
    positions["0"].index, positions["1"].index = main, main
    tick(t + 80, 0)
    assert(stage == 7 and not ready, "Terminal preparation bypassed the native floor transaction")
    tick(t + 81)
    assert(pending[1] == nil, "Terminal lookup ran before floor initialization")
    ready = true
    tick(t + 82)
    assert(pending[1] == terminal, "Terminal fixture chose the preceding Greed miniboss room")
    arrive()
    positions["0"].index = terminal -- Native finalCombat gathering has its own C++ coverage.
    tick(t + 173)
    tick(t + 264)
end
print("PASS Greed fixture waits for native transfers, buttons and the generated Ultra Greed arena")
