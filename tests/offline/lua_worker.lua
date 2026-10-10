-- Test-only pipe protocol: no native extension, game files or window input.
local root = assert(arg[1])
assert(_VERSION == "Lua 5.3", "Offline tests require the game's Lua 5.3 language version")
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local inventory = dofile(root .. "/tests/fixtures/offline_inventory.lua")(root)
local entities = dofile(root .. "/tests/fixtures/offline_entities.lua")(root)
local bot = dofile(root .. "/tests/fixtures/offline_bot.lua")(root)
local function unhex(value)
    assert(#value % 2 == 0 and not value:find("[^0-9a-f]"), "Invalid request hex")
    return (value:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end
local function hex(value)
    return (
        value:gsub(".", function(byte)
            return string.format("%02x", string.byte(byte))
        end)
    )
end
local function stateEnvironment()
    local env = setmetatable({
        _IsaacLan = {},
        _IsaacLanPrediction = {},
        _IsaacLanModules = {
            ["sync/codec"] = codec,
            ["sync/entity_schema"] = dofile(root .. "/src/bridge/sync/entity_schema.lua"),
            ["sync/entity_codec"] = dofile(root .. "/src/bridge/sync/entity_codec.lua"),
            ["sync/world_schema"] = dofile(root .. "/src/bridge/sync/world_schema.lua"),
            ["presentation/actors"] = dofile(root .. "/src/bridge/presentation/actors.lua"),
            ["presentation/audio"] = dofile(root .. "/src/bridge/presentation/audio.lua"),
            ["presentation/motion"] = dofile(root .. "/src/bridge/presentation/motion.lua"),
            ["compat/transitions"] = dofile(root .. "/src/bridge/compat/transitions.lua"),
            ["compat/items/hourglass"] = dofile(root .. "/src/bridge/compat/items/hourglass.lua"),
            ["compat/items/r_key"] = dofile(root .. "/src/bridge/compat/items/r_key.lua"),
            ["compat/routes/home"] = dofile(root .. "/src/bridge/compat/routes/home.lua"),
            ["compat/routes/greed"] = dofile(root .. "/src/bridge/compat/routes/greed.lua"),
            ["compat/bosses/room_entry"] = dofile(
                root .. "/src/bridge/compat/bosses/room_entry.lua"
            ),
            ["runtime/transitions"] = dofile(root .. "/src/bridge/runtime/transitions.lua"),
            ["runtime/room_entry"] = dofile(root .. "/src/bridge/runtime/room_entry.lua"),
            ["sync/inventory"] = dofile(root .. "/src/bridge/sync/inventory.lua"),
            ["sync/entities"] = dofile(root .. "/src/bridge/sync/entities.lua"),
            ["sync/grids"] = dofile(root .. "/src/bridge/sync/grids.lua"),
            ["presentation/items"] = dofile(root .. "/src/bridge/presentation/items.lua"),
            ["runtime/floor"] = dofile(root .. "/src/bridge/runtime/floor.lua"),
            ["sync/npc"] = dofile(root .. "/src/bridge/sync/npc.lua"),
            ["sync/curses"] = dofile(root .. "/src/bridge/sync/curses.lua"),
            ["compat/items/black_candle"] = dofile(
                root .. "/src/bridge/compat/items/black_candle.lua"
            ),
            ["compat/routes/crawlspace"] = dofile(
                root .. "/src/bridge/compat/routes/crawlspace.lua"
            ),
            ["compat/bosses/dogma"] = dofile(root .. "/src/bridge/compat/bosses/dogma.lua"),
            ["compat/characters/lazarus"] = dofile(
                root .. "/src/bridge/compat/characters/lazarus.lua"
            ),
            ["compat/characters/blue_baby"] = dofile(
                root .. "/src/bridge/compat/characters/blue_baby.lua"
            ),
        },
        ItemType = { ITEM_ACTIVE = 2 },
        NullItemID = { ID_LOST_CURSE = 1 },
        Vector = function(x, y)
            return { X = x, Y = y }
        end,
    }, { __index = _G })
    assert(loadfile(root .. "/src/bridge/app/world.lua", "t", env))()
    return env
end
local actions = {
    version = function()
        return { _VERSION }
    end,
    codec = function(value)
        return { codec.decode(codec.encode(value)) }
    end,
    decode = function(value)
        local ok, result = pcall(codec.decode, unhex(value))
        if not ok then
            result = tostring(result)
        end
        return { ok, result }
    end,
    inventory_reset = function(ghost)
        inventory.reset(ghost)
        return inventory.read()
    end,
    inventory_apply = inventory.apply,
    inventory_read = inventory.read,
    entities_reset = function()
        entities.reset()
        return entities.read()
    end,
    entities_apply = entities.apply,
    entities_read = entities.read,
    bot_reset = bot.reset,
    bot_step = bot.step,
    bot_command = bot.command,
    bot_session = bot.session,
    state_init = function()
        local env = stateEnvironment()
        local state = assert(env._IsaacLanState)
        return {
            state.encode == codec.encode,
            state.decode == codec.decode,
            type(state.apply),
            type(state.capture),
            type(state.present),
        }
    end,
    room_entry = function(cleared, boss)
        local env, closed, animation = stateEnvironment(), 0, "Opened"
        env.RoomType = { ROOM_BOSS = 5 }
        env.GridEntityType = { GRID_TRAPDOOR = 17 }
        local rock = {
            State = 4,
            GetType = function()
                return 2
            end,
        }
        local trapdoor = {
            State = 2,
            GetType = function()
                return 17
            end,
            GetSprite = function()
                -- Vanilla J460 Sprite has Play, but no HasAnimation method.
                return {
                    Play = function(_, name, force)
                        assert(force)
                        animation = name
                    end,
                }
            end,
        }
        local room = {
            IsClear = function()
                return cleared
            end,
            GetType = function()
                return boss and 5 or 1
            end,
            GetGridSize = function()
                return 3
            end,
            GetGridEntity = function(_, index)
                return index == 0 and rock or index == 1 and trapdoor or nil
            end,
            GetDoor = function(_, slot)
                if slot == 0 or slot == 3 then
                    return {
                        Close = function(_, force)
                            assert(force)
                            closed = closed + 1
                        end,
                    }
                end
            end,
        }
        env.Game = function()
            return {
                GetRoom = function()
                    return room
                end,
            }
        end
        env._IsaacLanRoomEntered()
        return { closed, trapdoor.State, animation, rock.State }
    end,
}
for line in io.lines() do
    local ok, value = pcall(function()
        local request = codec.decode(unhex(line))
        return assert(actions[request[1]], "Unknown offline action")(table.unpack(request, 2))
    end)
    if not ok then
        value = tostring(value)
    end
    io.write(hex(codec.encode({ ok, value })), "\n")
    io.flush()
end
