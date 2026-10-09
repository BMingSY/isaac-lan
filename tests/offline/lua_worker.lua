-- Test-only pipe protocol: no native extension, game files or window input.
local root = assert(arg[1])
assert(_VERSION == "Lua 5.3", "Offline tests require the game's Lua 5.3 language version")
local codec = dofile(root .. "/src/bridge/state/codec.lua")
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
        local env = setmetatable({
            _IsaacLan = {},
            _IsaacLanPrediction = {},
            _IsaacLanModules = {
                ["state/codec"] = codec,
                ["state/inventory"] = dofile(root .. "/src/bridge/state/inventory.lua"),
                ["state/entities"] = dofile(root .. "/src/bridge/state/entities.lua"),
            },
            ItemType = { ITEM_ACTIVE = 2 },
            NullItemID = { ID_LOST_CURSE = 1 },
            Vector = function(x, y)
                return { X = x, Y = y }
            end,
        }, { __index = _G })
        assert(loadfile(root .. "/src/bridge/state.lua", "t", env))()
        local state = assert(env._IsaacLanState)
        return {
            state.encode == codec.encode,
            state.decode == codec.decode,
            type(state.apply),
            type(state.capture),
            type(state.present),
        }
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
