local root = assert(arg[1])
local function module(name)
    return dofile(root .. "/src/bridge/" .. name .. ".lua")
end
local rules, layout, codec =
    module("compat/routes/jericho_rules"),
    module("compat/routes/jericho_layout"),
    module("sync/codec")
local F, S = rules.fields, rules.stateFields
local function reject(fn)
    assert(not pcall(fn))
end
local model = rules.new()
for depth = 1, 6 do
    local floor, fresh = model.enter("floor" .. depth, depth)
    assert(fresh and model.state[S.chance] == math.min(100, depth * 25))
    assert(select(2, model.enter("floor" .. depth, depth)) == false)
    if depth == 4 then
        model.enter("xl-revisit", depth)
        assert(model.state[S.chance] == 100)
    end
end
local floor = model.find("floor6")
model.generate(floor, { 10, 20 }, { 1, 2 })
for depth = 7, 12 do
    model.enter("floor" .. depth, depth)
    assert(model.state[S.chance] == 1)
end
local checkpoint = codec.encode(model.snapshot())
assert(codec.encode(rules.new(codec.decode(checkpoint)).snapshot()) == checkpoint)
local bad = model.snapshot()
bad[S.chance] = 25
reject(function()
    rules.new(bad)
end)
local graph = { [10] = { 11 }, [11] = { 10, 20 }, [20] = { 11 }, [30] = {} }
local pair = rules.selectPair({ 10, 20, 30 }, graph, function()
    return 1
end)
assert(pair[1] == 10 and pair[2] == 20)
assert(not rules.selectPair({ 10, 30 }, graph, function()
    return 1
end))
local a, b = rules.random("seed"), rules.random("seed")
for _ = 1, 100 do
    assert(a(100) == b(100))
end
local function contacts(one, two, horn)
    return {
        { slot = 0, side = 1, plate = one, horn = horn },
        { slot = 1, side = 2, plate = two, horn = horn },
    }
end
assert(not model.step(floor, { { slot = 0, side = 1, plate = 1 } }))
assert(not model.step(floor, contacts(1))) -- holding before partner arrived cannot queue
model.step(floor, contacts())
assert(model.step(floor, contacts(1)) == "step")
assert(not model.step(floor, contacts(1)))
assert(model.step(floor, contacts(nil, 4)) == "wrong" and floor[F.progress] == 0)
model.step(floor, contacts())
assert(model.step(floor, contacts(1, 2)) == "wrong") -- strict ordering, not a simultaneous pair
for plate = 1, 6 do
    model.step(floor, contacts())
    assert(
        model.step(
            floor,
            contacts(plate % 2 == 1 and plate or nil, plate % 2 == 0 and plate or nil)
        ) == "step"
    )
    assert(floor[F.progress] == plate)
end
for _ = 1, rules.hornFrames - 1 do
    assert(not model.step(floor, contacts(nil, nil, true)))
end
assert(model.step(floor, contacts(nil, nil, true)) == "complete")
for _ = 1, 20 do
    assert(not model.step(floor, contacts(nil, nil, true)))
end
reject(function()
    model.step(floor, { { slot = 0, side = 1 }, { slot = 0, side = 2 } })
end)
assert(layout.contact(-160, -80, 0, 0, 1) == 1)
assert(layout.contact(160, -80, 0, 0, 1) == nil)
assert(select(2, layout.contact(10, -120, 0.2, 1, 1)))
assert(not select(2, layout.contact(0, -120, 0, -1, 1)))

-- Native GetRoomByIdx returns a nonempty fallback for missing dimension cells.
-- It must not exclude ordinary main rooms or mutate the sentinel's flags.
local function container(values)
    return {
        Size = #values,
        Get = function(_, i)
            return values[i + 1]
        end,
    }
end
local function descriptor(index, entity)
    return {
        SafeGridIndex = index,
        ListIndex = index,
        VisitedCount = 0,
        Flags = 0,
        Data = {
            Type = 1,
            Shape = 1,
            Subtype = 0,
            Spawns = container({ { Entries = container({ { Type = entity or 10 } }) } }),
        },
    }
end
local descs = {
    [10] = descriptor(10),
    [11] = descriptor(11),
    [20] = descriptor(20),
    [30] = descriptor(30, 33),
    [40] = descriptor(40, 965),
}
local sentinel = descriptor(84)
local map = module("compat/routes/jericho_map")({
    rules = rules,
    native = {
        room_connections = function(index)
            return graph[index] or {}
        end,
        room_empty_pair = function()
            return true
        end,
    },
    enums = {
        room = { ROOM_DEFAULT = 1 },
        shape = { ROOMSHAPE_1x1 = 1 },
        entity = { ENTITY_GAPER = 10, ENTITY_FIREPLACE = 33, ENTITY_MINECART = 965 },
        descriptor = {
            FLAG_RED_ROOM = 1024,
            FLAG_HAS_WATER = 32,
            FLAG_USE_ALTERNATE_BACKDROP = 4096,
        },
    },
})
local mapLevel = {
    GetRoomByIdx = function(_, index, dimension)
        return dimension == 0 and descs[index] or sentinel
    end,
    GetStartingRoomIndex = function()
        return 11
    end,
}
assert(not map.replaceable(descs[30], 11) and not map.replaceable(descs[40], 11))
local rockRoom = descriptor(50)
rockRoom.Data.Spawns =
    container({ { Entries = container({ { Type = 1000, Variant = 0, Subtype = 0 } }) } })
assert(map.replaceable(rockRoom, 11))
rockRoom.Data.Spawns =
    container({ { Entries = container({ { Type = 4500, Variant = 0, Subtype = 0 } }) } })
assert(not map.replaceable(rockRoom, 11), "Route button became replaceable terrain")
local selected = map.select(mapLevel, function()
    return 1
end)
assert(selected[1] == 10 and selected[2] == 20)
assert(map.install(mapLevel, selected, false))
assert(descs[10].Clear and descs[20].NoReward and not sentinel.Clear)

-- Real adapter: map generation, per-controller inputs, native payload restore,
-- independent pedestals, shared/per-room awards, mirror and repeat frames.
local vec = {}
vec.__index = vec
local function vector(x, y)
    return setmetatable({ X = x, Y = y }, vec)
end
function vec.__add(a, b)
    return vector(a.X + b.X, a.Y + b.Y)
end
function vec.__sub(a, b)
    return vector(a.X - b.X, a.Y - b.Y)
end
local info = {
    active = 1,
    authority = 1,
    ready = 1,
    challenge = 0,
    connected = 3,
    players = 2,
    roomOptions = 0,
}
local tick, scope, dimension, stage, ascent = 0, 0, 0, 4, false
local payload, revision = codec.encode({ rules.version, 100, false, 0, {} }), 1
local installs, awards, pickups, draws = {}, {}, {}, 0
local actors = {
    { Position = vector(0, 0), shot = vector(0, 0) },
    { Position = vector(0, 0), shot = vector(0, 0) },
}
for _, player in ipairs(actors) do
    function player:GetShootingInput()
        return self.shot
    end
end
local positions = { ["0"] = { index = 10, dimension = 0 }, ["1"] = { index = 20, dimension = 0 } }
local grids = { {}, {} }
local room = {}
function room:GetCenterPos()
    return vector(0, 0)
end
function room:GetGridIndex(p)
    return (p.X + 400) + (p.Y + 400) * 1000
end
function room:GetGridEntity(i)
    return grids[scope + 1][i]
end
function room:SpawnGridEntity(i, kind)
    grids[scope + 1][i] = {
        GetType = function()
            return kind
        end,
    }
end
function room:RemoveGridEntity(i)
    grids[scope + 1][i] = nil
end
function room:GetDecorationSeed()
    return 5
end
local level = {}
function level:GetStage()
    return stage
end
function level:GetStageType()
    return 0
end
function level:GetDungeonPlacementSeed()
    return 17
end
function level:IsAscent()
    return ascent
end
function level:GetCurrentRoomDesc()
    return { SafeGridIndex = positions[tostring(scope)].index, ListIndex = scope + dimension * 10 }
end
function level:GetRoomByIdx(index, dim)
    return { SafeGridIndex = index, ListIndex = (index == 10 and 0 or 1) + dim * 10 }
end
local game = { Challenge = 0 }
function game:GetLevel()
    return level
end
function game:GetRoom()
    return room
end
function game:IsPaused()
    return false
end
function game:IsGreedMode()
    return false
end
function game:GetFrameCount()
    return tick
end
function game:GetSeeds()
    return {
        GetStartSeed = function()
            return 3
        end,
        GetStageSeed = function()
            return 17
        end,
    }
end
function game:GetItemPool()
    return {
        GetCollectible = function(_, pool, decrease)
            assert(pool == 0 and decrease)
            draws = draws + 1
            return draws
        end,
    }
end
local native = {
    api_info = function()
        return info
    end,
    net_room_options = function()
        return { { key = "sharedClearCharge", flag = 2 } }
    end,
    rooms_positions = function()
        return positions
    end,
    net_run_state = function(value)
        if value then
            payload, revision = value, revision + 1
            return revision
        end
        return payload, revision
    end,
}
local function party()
    local seats = {}
    for slot = 0, 1 do
        if info.connected & (1 << slot) ~= 0 then
            seats[#seats + 1] = { slot = slot, actors = { actors[slot + 1] } }
        end
    end
    return seats
end
local adapter = module("compat/routes/jericho")({
    native = native,
    rules = rules,
    layout = layout,
    encode = codec.encode,
    decode = codec.decode,
    enums = {
        stage = { STAGE8 = 13 },
        pool = { POOL_TREASURE = 0 },
        entity = { ENTITY_NULL = 0, ENTITY_PICKUP = 5 },
        pickup = { PICKUP_COLLECTIBLE = 100 },
        grid = { GRID_PILLAR = 24 },
    },
    game = function()
        return game
    end,
    vector = vector,
    party = party,
    scoped = function(seat, fn)
        scope = seat.slot
        fn()
        scope = 0
    end,
    sound = function() end,
    map = {
        select = function()
            return { 10, 20 }
        end,
        install = function(_, p, restoring)
            installs[#installs + 1] = { p[1], p[2], restoring }
            return true
        end,
    },
    charge = {
        award = function(_, recipients, amount)
            assert(amount == 1)
            for _, seat in ipairs(party()) do
                if not recipients or recipients[seat.slot] then
                    awards[seat.slot] = (awards[seat.slot] or 0) + amount
                end
            end
        end,
    },
    spawn = function(_, _, item)
        pickups[#pickups + 1] = { slot = scope, item = item }
        return {
            ToPickup = function()
                return {}
            end,
        }
    end,
})
local function step()
    tick = tick + 1
    adapter.step()
end
step()
assert(draws == 2 and #installs == 1 and not installs[1][3])
assert(adapter.snapshot()[F.firstItem] == 1 and adapter.snapshot()[F.secondItem] == 2)
assert(#pickups == 0 and next(awards) == nil)
assert(adapter.separate(positions["0"]) and not adapter.separate({ index = 10, dimension = 1 }))
local initial = payload
-- Native layout reconstruction runs before readiness and may follow a Lua
-- reset. Only the saved pair's template spawns are suppressed; unrelated
-- rooms, alternate dimensions and replicas retain their native behavior.
adapter.reset()
info.ready = 0
assert(adapter.layoutSpawn()[1] == 0)
assert(payload == initial)
positions["0"].index = 30
assert(adapter.layoutSpawn() == nil)
positions["0"].index, info.ready = 10, 1
info.authority = 0
assert(adapter.layoutSpawn() == nil)
info.authority = 1
for plate = 1, 6 do
    for _, player in ipairs(actors) do
        player.Position = vector(0, 0)
    end
    step()
    local point = layout.plates[plate]
    actors[rules.plateSide(plate)].Position = vector(point[1], point[2])
    step()
    assert(adapter.snapshot()[F.progress] == plate)
    adapter.step()
    assert(adapter.snapshot()[F.progress] == plate)
end
local ready = payload
actors[1].Position, actors[2].Position = vector(0, -120), vector(0, 120)
actors[1].shot, actors[2].shot = vector(0, 1), vector(0, -1)
info.connected = 1
for _ = 1, 20 do
    step()
end
assert(not adapter.snapshot()[F.complete])
info.connected = 3
for _ = 1, 20 do
    step()
end
assert(adapter.snapshot()[F.complete] and awards[0] == 1 and awards[1] == 1)
assert(#pickups == 2 and pickups[1].item ~= pickups[2].item)
for _ = 1, 30 do
    step()
end
assert(#pickups == 2 and awards[0] == 1 and awards[1] == 1)
local completed = payload
adapter.reset()
step()
assert(payload == completed and draws == 2 and #pickups == 2 and awards[0] == 1)
-- Native rewind restores the matching history and inputs; shared mode pays
-- two room events to both eligible controllers, once each.
payload, revision, awards, pickups = ready, revision + 1, {}, {}
info.roomOptions = 2
for _ = 1, 20 do
    step()
end
assert(awards[0] == 2 and awards[1] == 2 and #pickups == 2)
-- Mirror contacts cannot advance, release a pedestal or charge.
payload, revision, awards, pickups = initial, revision + 1, {}, {}
positions["0"].dimension, positions["1"].dimension, dimension = 1, 1, 1
for _ = 1, 20 do
    step()
end
adapter.entered()
assert(adapter.layoutSpawn()[1] == 0)
assert(adapter.snapshot()[F.progress] == 0 and #pickups == 0 and next(awards) == nil)
info.authority = 0
adapter.apply(adapter.snapshot())
assert(adapter.view()[F.first] == 10)
adapter.apply(false)
assert(not adapter.view())
-- Ascent may revisit the same stage seed. Its native restored layouts must
-- not be replaced by a descending-floor puzzle, even with saved progress.
info.authority, ascent = 1, true
local installCount, saved = #installs, payload
adapter.level()
step()
adapter.entered()
assert(adapter.layoutSpawn() == nil)
assert(not adapter.snapshot() and #installs == installCount and payload == saved)
print("Jericho generation, sequence, contacts, persistence, mirror and awards passed")
