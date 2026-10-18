-- Exercise the real world capture/apply path with two independent crafting bags.
local root = assert(arg[1])
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local function module(name)
    return dofile(root .. "/src/bridge/" .. name .. ".lua")
end
local function noop() end
local empty = string.rep("\0", 12)
local function payload(materials, preview)
    return string.char(table.unpack(materials)) .. string.pack(">I4", preview)
end
local function environment()
    local positions = {
        ["0"] = { index = 84, dimension = 0 },
        ["1"] = { index = 84, dimension = 0 },
    }
    local epoch, stage, ready = 1, 1, true
    local function vector(x, y)
        return setmetatable({ X = x, Y = y }, {
            __mul = function(v, scale)
                return vector(v.X * scale, v.Y * scale)
            end,
        })
    end
    local players = {}
    for index = 0, 1 do
        local p = {
            Type = 1,
            ControllerIndex = index + 1,
            Position = vector(100 + index * 80, 100),
            activeSlot = 2,
            ghost = false,
            bag = empty,
            itemState = 0,
            reads = 0,
        }
        function p:GetPlayerType()
            return 23
        end
        function p:IsCoopGhost()
            return self.ghost
        end
        function p:GetActiveItem(slot)
            return slot == self.activeSlot and 710 or 0
        end
        function p:GetItemState()
            return self.itemState
        end
        function p:GetSprite()
            return self
        end
        function p:ToPlayer()
            return self
        end
        players[index] = p
    end
    local room = { SetClear = noop }
    local level = {
        GetStage = function()
            return stage
        end,
        GetStageType = function()
            return 0
        end,
        GetRooms = function()
            return { Size = 0 }
        end,
        GetCurses = function()
            return 0
        end,
        SetStage = function(_, value)
            stage = value
        end,
    }
    local game = {
        GetLevel = function()
            return level
        end,
        GetRoom = function()
            return room
        end,
        GetNumPlayers = function()
            return 2
        end,
        GetFrameCount = function()
            return 20
        end,
        IsGreedMode = function()
            return false
        end,
    }
    local native = {
        actor_companions = function(bytes)
            assert(bytes == "\0")
            return true
        end,
        rooms_positions = function()
            return positions
        end,
        rooms_heads = function()
            return { ["0"] = 0, ["1"] = 1 }
        end,
        rooms_connected = function()
            return 3
        end,
        net_floor_epoch = function()
            return epoch
        end,
        rooms_ready = function()
            return ready
        end,
        rooms_begin_floor = function()
            ready = false
            return true
        end,
        rooms_with_player = function(_, fn)
            fn()
            return true
        end,
        rooms_sync = function(bytes)
            local _, count, cursor = string.unpack(">BB", bytes)
            for _ = 1, count do
                local slot, dimension, index, x, y
                slot, dimension, index, x, y, cursor = string.unpack(">Bi4i4ff", bytes, cursor)
                positions[tostring(slot)] = { index = index, dimension = dimension }
            end
            return true
        end,
        actor_crafting_bag = function(p, value)
            if value == nil then
                p.reads = p.reads + 1
                return p.bag
            end
            assert(#value == 12)
            p.bag = value
            return true
        end,
        actor_sprites = function()
            return {}
        end,
        actor_pose = function()
            return "pose"
        end,
        actor_ghost = function(index, ghost)
            players[index].ghost = ghost == 1
            return true
        end,
        room_layout = function()
            return true
        end,
        room_rails = function(value)
            return value == nil and string.rep("\255", 448) or true
        end,
        room_water_current = function()
            return true
        end,
        net_progress = function()
            return "progress"
        end,
        presentation_events = function(value)
            return value == nil and "" or true
        end,
        music_state = function()
            return true
        end,
        door_slot = function()
            return true
        end,
        map_refresh = function()
            return true
        end,
        state_clock = noop,
        sound_reset = noop,
        presentation_reset = noop,
        rewind_reset = noop,
    }
    local modules = {}
    for _, name in ipairs({
        "sync/codec",
        "sync/world_schema",
        "sync/fields",
        "sync/capture",
        "sync/replica",
        "sync/actor_roster",
        "runtime/floor",
        "runtime/transitions",
        "compat/transitions",
        "compat/routes/home",
        "compat/routes/greed",
        "compat/routes/victory_lap",
        "compat/items/hourglass",
        "compat/items/r_key",
        "compat/items/crafting_bag",
        "compat/characters/blue_baby",
    }) do
        modules[name] = module(name)
    end
    modules["sync/entities"], modules["sync/grids"] =
        function()
            return noop
        end, function()
            return noop
        end
    modules["sync/npc"], modules["sync/entity_schema"] = {}, function()
        return {}
    end
    modules["sync/entity_links"] = dofile(root .. "/src/bridge/sync/entity_links.lua")
    modules["compat/bosses/held_bombs"] = dofile(root .. "/src/bridge/compat/bosses/held_bombs.lua")
    modules["compat/bosses/visuals"] = dofile(root .. "/src/bridge/compat/bosses/visuals.lua")
    modules["compat/bosses/dogma"] = function()
        return {}
    end
    modules["compat/items/black_candle"] = noop
    modules["sync/curses"] = {
        capture = function()
            return 0
        end,
        apply = function()
            return false
        end,
    }
    local function inert()
        return {
            capture = function()
                return false
            end,
            apply = noop,
            reset = noop,
        }
    end
    for _, name in ipairs({
        "sync/deals",
        "sync/pills",
        "presentation/items",
        "presentation/audio",
        "compat/routes/crawlspace",
        "compat/items/glitched",
        "compat/items/temporary_effects",
    }) do
        modules[name] = inert
    end
    modules["presentation/actors"] = function()
        return { apply = noop, reset = noop }
    end
    modules["presentation/motion"] = function()
        return { present = noop, reset = noop, track = noop }
    end
    modules["presentation/attachments"] = function()
        return { capture = noop, present = noop }
    end
    modules["compat/characters/keeper"] = function()
        return {}
    end
    modules["compat/characters/lazarus"] = function()
        return {
            resolve = function(index)
                return players[index]
            end,
            prune = noop,
        }
    end
    modules["sync/inventory"] = function()
        return {
            sameItems = module("sync/inventory")(modules["sync/fields"])({}).sameItems,
            capture = function(p)
                return { 23, {}, {}, {}, {}, {}, {}, {}, p.ghost }
            end,
            apply = function(p, value)
                -- Reproduce native inventory/character setters clearing private state.
                p.bag = empty
            end,
        }
    end
    modules["sync/entity_codec"] = function()
        return {
            capture = function(p)
                return { p.ControllerIndex, 1, 0, 0, 0, { 100, 100 }, { 0, 0 } }
            end,
            apply = noop,
            reset = noop,
            sprite = function()
                return {}
            end,
            applySprite = noop,
            vec = function(v)
                return vector(v[1], v[2])
            end,
        }
    end
    modules["sync/room"] = function()
        return function()
            return { true, 20, {}, {}, false, "layout", false, { 0, 0 } }
        end
    end
    for _, name in ipairs({
        "sync/inventory",
        "sync/room",
        "sync/entity_codec",
        "sync/entities",
        "sync/grids",
        "sync/deals",
        "presentation/actors",
        "presentation/motion",
        "presentation/attachments",
        "compat/characters/lazarus",
        "compat/items/black_candle",
    }) do
        local factory = modules[name]
        modules[name] = function()
            return factory
        end
    end
    local env = setmetatable({
        _IsaacLan = native,
        _IsaacLanPrediction = {
            new = function()
                return { confirm = noop }
            end,
        },
        _IsaacLanModules = modules,
        ItemType = { ITEM_ACTIVE = 2 },
        NullItemID = { ID_LOST_CURSE = 1 },
        Game = function()
            return game
        end,
        SFXManager = function()
            return {}
        end,
        Vector = vector,
        GetPtrHash = function(entity)
            return entity
        end,
        EntityPtr = function(p)
            return { Ref = p }
        end,
        Isaac = {
            GetPlayer = function(index)
                return players[index]
            end,
            GetTime = function()
                return 1000
            end,
        },
    }, { __index = _G })
    for name, values in pairs(enums) do
        env[name] = values
    end
    assert(loadfile(root .. "/src/bridge/app/world.lua", "t", env))()
    return {
        state = env._IsaacLanState,
        players = players,
        positions = positions,
        floor = function(nextEpoch, nextStage, loaded)
            epoch, stage, ready = nextEpoch, nextStage, loaded
        end,
    }
end
local host, guest = environment(), environment()
local first = payload({ 1, 8, 12, 15, 22, 29, 2, 3 }, 25)
local second = payload({ 12, 1, 22, 29, 0, 0, 0, 0 }, 0)
host.players[0].bag, host.players[1].bag = first, second
for tick = 1, 5 do
    host.players[0].itemState = tick % 2 == 0 and 710 or 0
    host.players[1].itemState = tick % 2 == 0 and 0 or 710
    -- Offscreen actors must carry the same private state as rendered actors.
    host.positions["1"].index = tick % 2 == 0 and 85 or 84
    for slot = 0, 1 do
        local bytes = host.state.capture(slot, tick)
        local view = host.state.decode(bytes)
        assert(
            view[1] == 25 and view[9][1][8][1] == first and view[9][2][8][1] == second,
            "World snapshot omitted or mixed the two players' crafting bags"
        )
        assert(view[9][1][8][2] == (tick % 2 == 0) and view[9][2][8][2] == (tick % 2 ~= 0))
        assert(guest.state.apply(bytes, tick, 0))
        assert(
            guest.players[0].bag == first and guest.players[1].bag == second,
            "Inventory setters erased bag state or the guest restored only its own bag"
        )
        assert(guest.state.apply(bytes, tick, 0), "Repeated views must be safe")
    end
    assert(
        host.players[0].reads == tick and host.players[1].reads == tick,
        "Same-tick views must reuse immutable per-actor bag captures"
    )
end
-- A material rotation changes the native order even when the recipe is unchanged.
first = payload({ 8, 12, 15, 22, 29, 2, 3, 1 }, 25)
host.players[0].bag = first
host.players[1].bag = empty -- Crafting consumes the complete bag.
local bytes = host.state.capture(1, 6)
assert(guest.state.apply(bytes, 6, 0))
assert(guest.players[0].bag == first and guest.players[1].bag == empty)
-- Losing the item clears a stale remote preview, including a bag in the main slot.
host.players[0].activeSlot = -1
host.players[1].activeSlot, host.players[1].bag = 0, second
assert(guest.state.apply(host.state.capture(0, 7), 7, 0))
assert(guest.players[0].bag == empty and guest.players[1].bag == second)
host.floor(2, 2, true)
bytes = host.state.capture(1, 8)
local before = guest.players[1].bag
assert(not guest.state.apply(bytes, 8, 0) and guest.players[1].bag == before)
assert(guest.state.beginFloor(2, 2, 0, 0, false))
assert(not guest.state.apply(bytes, 8, 0))
guest.floor(2, 2, true)
assert(guest.state.apply(bytes, 8, 0) and guest.players[1].bag == second)
host.state.reset()
guest.state.reset()
host.players[1].bag = empty
assert(guest.state.apply(host.state.capture(1, 9), 9, 0))
assert(guest.players[1].bag == empty, "New session retained old crafting materials")
local adapter = module("compat/items/crafting_bag")({
    actor_crafting_bag = function()
        error("Ghost hidden inventory must remain owned by native conversion")
    end,
}, enums.CollectibleType)
host.players[1].ghost = true
assert(adapter.capture(host.players[1]) == false)
adapter.apply(host.players[1], false)
assert(not pcall(adapter.apply, host.players[0], nil), "Missing schema field was accepted")
assert(not pcall(adapter.apply, host.players[0], empty), "Old bag schema was accepted")
-- The native fixture must select the same two characters in lobby and start settings.
for _, isHost in ipairs({ true, false }) do
    local commands, status, input = {}, { phase = 0, verified = 0 }, nil
    local env = setmetatable({
        _IsaacLanTest = { host = isHost, port = "30240" },
        _IsaacLan = {
            test_gamepad = noop,
            net_gate = function(capture)
                input = capture
            end,
        },
        ButtonAction = { ACTION_PILLCARD = 9, ACTION_SHOOTRIGHT = 7 },
        _IsaacLanFrame = function()
            return status
        end,
        _IsaacLanCommand = function(name, value)
            commands[#commands + 1] = { name, value }
        end,
        Isaac = { DebugString = noop, AddCallback = noop },
        ModCallbacks = { MC_POST_KNIFE_UPDATE = 1 },
        EntityFlag = enums.EntityFlag,
    }, { __index = _G })
    assert(loadfile(root .. "/tests/state_crafting_bag.lua", "t", env))()
    for _ = 1, 400 do
        env._IsaacLanFrame()
    end
    status.phase, status.players, status.ready0, status.ready1 = 2, 2, 1, 1
    env._IsaacLanFrame()
    assert(commands[2][1] == "choose" and commands[2][2] == "23:1")
    if isHost then
        assert(commands[3][1] == "start" and commands[3][2] == "YV039KQF:0:23:23:0:0")
    else
        assert(#commands == 2)
    end
    status.phase = 3
    env._IsaacLan.net_gate(noop, noop, noop, noop, noop, noop)
    for _, sample in ipairs({ { 31, 9, true }, { 32, 9, false }, { 40, 7, true }, { 41, 7, false } }) do
        status.verified = sample[1]
        env._IsaacLanFrame()
        local bytes = input()
        assert(#bytes == 34)
        assert(string.unpack(">I2", bytes, sample[2] * 2 + 1) == 65535)
        local edges = string.unpack(">I2", bytes, 33)
        assert(
            ((edges & (1 << sample[2])) ~= 0) == sample[3],
            "Native fixture dropped or repeated the equip/shoot press edge"
        )
    end
end
print(
    "PASS both crafting bags through production world snapshots, rooms, rotations, consumption, floors and resets"
)
