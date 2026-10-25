local root = assert(arg[1])
local function module(name)
    return dofile(root .. "/src/bridge/" .. name .. ".lua")
end
local rules = module("compat/challenges/battle_royale_rules")
local phase = rules.phase
for _, count in ipairs({ 2, 3, 4 }) do
    local round = rules.new()
    round.start()
    assert(not round.step(30, (1 << count) - 1, false))
    assert(not round.step(30, 1, true), "Pending original revival must delay victory")
    assert(round.step(30, 1, false) == "winner")
    assert(round.state.scores[1] == 0, "Survival alone must not score")
    assert(not round.enter(1) and round.enter(0))
    assert(not round.clear(1) and round.clear(0))
    assert(not round.clear(0) and round.state.scores[1] == 1, "Repeated clear must not score twice")
    assert(not round.leave(1), "Only the winner may skip rewards")
    assert(round.leave(0))
    round.start()
    assert(round.step(1, 1, false) == "winner" and round.enter(0))
    assert(round.step(1, 0, false) == "next")
    assert(round.state.scores[1] == 1, "Boss defeat must retain the previous match point")
    round.start()
    assert(round.step(1, 0, false) == "next", "Simultaneous elimination has no winner")
    assert(round.state.scores[1] == 1)
    round.start()
    assert(round.step(1, 1, false) == "winner" and round.enter(0) and round.clear(0))
    assert(round.state.phase == phase.trophy and round.state.scores[1] == 2)
    assert(not round.leave(0), "Championship must finish through the trophy")
    local copy = rules.read(round.snapshot())
    assert(copy.scores[1] == 2)
    copy.scores[1] = 0
    assert(round.state.scores[1] == 2, "Views must not mutate authority state")
end
for _, case in ipairs({
    { 0, 0, 12 },
    { 2699, 0, 12 },
    { 2700, 2, 10 },
    { 5400, 4, 8 },
    { 7200, 6, 6 },
}) do
    local zone = rules.zone(case[1])
    assert(zone.left == case[2] and zone.right == case[3])
end
assert(not rules.outside(84, 9000) and rules.outside(83, 7200))
assert(rules.outside(-3, 0) and rules.pressure(9900) > rules.pressure(9000))
local invalid = rules.new().snapshot()
invalid[rules.fields.scores][1] = 3
assert(not pcall(rules.read, invalid))

-- Exercise the actual adapter through layout, normal deaths, portal contact,
-- native clear awards, optional loot, another floor, Mom and the trophy.
local enums = {
    collectible = { COLLECTIBLE_D6 = 105, COLLECTIBLE_DOGMA = 633, COLLECTIBLE_SYNTHOIL = 345 },
    stageType = { STAGETYPE_ORIGINAL = 0, STAGETYPE_AFTERBIRTH = 2 },
    transition = { FADE = 0 },
    pool = { POOL_BOSS = 2 },
    entity = { ENTITY_PICKUP = 5, ENTITY_MOM = 45, ENTITY_PROJECTILE = 9 },
    pickup = { PICKUP_COLLECTIBLE = 100, PICKUP_TROPHY = 370, PICKUP_BIGCHEST = 340 },
    room = { ROOM_BOSS = 5, ROOM_DEFAULT = 1 },
    shape = { ROOMSHAPE_1x1 = 1 },
    damage = { DAMAGE_NO_PENALTIES = 1 },
}
local function vector(x, y)
    return setmetatable({ X = x, Y = y }, {
        __add = function(a, b)
            return vector(a.X + b.X, a.Y + b.Y)
        end,
    })
end
local players, positions, entities = {}, {}, {}
local info = { active = 1, authority = 1, ready = 1, connected = 3, players = 2, slot = 0 }
local frame, activeSlot, floorRequests, finishes, momSpawns = 0, nil, 0, 0, 0
for slot = 0, 1 do
    local p = {
        ControllerIndex = slot + 1,
        Position = vector(320, 280),
        items = {},
        hearts = 2,
        max = 6,
        soul = 4,
        coins = 19,
        ghost = false,
        dead = false,
        reviving = false,
    }
    if slot == 0 then
        p.items[105] = 1
    end
    function p:GetCollectibleNum(id)
        return self.items[id] or 0
    end
    function p:HasCollectible(id)
        return self:GetCollectibleNum(id) > 0
    end
    function p:AddCollectible(id)
        self.items[id] = self:GetCollectibleNum(id) + 1
    end
    function p:RemoveCollectible(id)
        self.items[id] = self:GetCollectibleNum(id) - 1
    end
    function p:IsCoopGhost()
        return self.ghost
    end
    function p:IsDead()
        return self.dead
    end
    function p:WillPlayerRevive()
        return self.reviving
    end
    function p:AddControlsCooldown() end
    function p:Revive()
        self.dead, self.ghost = false, false
    end
    function p:GetEffectiveMaxHearts()
        return self.max
    end
    function p:GetHearts()
        return self.hearts
    end
    function p:AddHearts(amount)
        self.hearts = self.hearts + amount
    end
    function p:TakeDamage(amount)
        self.hearts = self.hearts - amount
    end
    function p:AnimateTeleport() end
    players[slot], positions[tostring(slot)] = p, { index = 84, dimension = 0 }
end
local clear = false
local room = {
    GetCenterPos = function()
        return vector(320, 280)
    end,
    FindFreePickupSpawnPosition = function(_, p)
        return p
    end,
    IsClear = function()
        return clear
    end,
    SetClear = function(_, value)
        clear = value
    end,
}
local level = {
    SetStage = function(_, stage, kind)
        assert(stage >= 1 and stage <= 5 and kind <= 2)
    end,
    GetRoomByIdx = function(_, index)
        return { Data = { Type = (index == 100 or index == 101) and 5 or 1 } }
    end,
}
local game = {
    GetFrameCount = function()
        return frame
    end,
    IsPaused = function()
        return false
    end,
    GetLevel = function()
        return level
    end,
    GetRoom = function()
        return room
    end,
    StartStageTransition = function(_, same, _, player)
        assert(same and player == players[0])
        floorRequests = floorRequests + 1
    end,
    GetItemPool = function()
        return {
            GetCollectible = function()
                return 345
            end,
        }
    end,
}
local native = {
    api_info = function()
        return info
    end,
    api_actors = function()
        return { { index = 0, owner = 1, role = 1 }, { index = 1, owner = 2, role = 1 } }
    end,
    rooms_positions = function()
        return positions
    end,
    rooms_with_player = function(slot, fn, only)
        assert(activeSlot == nil and only == 1)
        activeSlot = slot
        fn()
        activeSlot = nil
        return true
    end,
    api_move = function(slot, index, dimension)
        if index == 101 then
            momSpawns = momSpawns + 1
        end
        positions[tostring(slot)] = { index = index, dimension = dimension }
        players[slot].Position = vector(320, 280)
        return true
    end,
    rooms_revive_player = function(slot)
        players[slot]:Revive()
        return true
    end,
    net_finish_challenge = function()
        finishes = finishes + 1
        return true
    end,
}
local function spawn(kind, variant, subtype)
    if kind == 45 then
        momSpawns = momSpawns + 1
    end
    local entity = { Type = kind, Variant = variant, SubType = subtype, InitSeed = #entities + 10 }
    function entity:ToPickup()
        return self
    end
    function entity:IsActiveEnemy()
        return self.Type == 45
    end
    function entity:Remove()
        self.removed = true
    end
    function entity:Morph(t, v, s)
        self.Type, self.Variant, self.SubType = t, v, s
    end
    entities[#entities + 1] = entity
    return entity
end
local battle = module("compat/challenges/battle_royale")({
    native = native,
    rules = rules,
    enums = enums,
    game = function()
        return game
    end,
    player = function(index)
        return players[index]
    end,
    vector = vector,
    ref = function()
        return {}
    end,
    spawn = spawn,
    entities = function()
        return entities
    end,
    random = function(low)
        return low
    end,
    config = function()
        return {
            GetCollectible = function(_, id)
                return { Quality = id == 345 and 3 or 0 }
            end,
        }
    end,
    visibility = {
        reset = function() end,
        observe = function() end,
        project = function(map)
            return map
        end,
    },
    map = {
        build = function()
            return { boss = 100, finalBoss = 101, spawns = { 0, 168 } }
        end,
        removeExits = function() end,
        escape = function() end,
    },
})
local function tick(count)
    for _ = 1, count do
        frame = frame + 1
        battle.step(info)
    end
end
battle.onLayoutReady(info, level)
assert(floorRequests == 1 and players[0]:GetCollectibleNum(105) == 0)
battle.onLayoutReady(info, level)
assert(players[0].hearts == 6 and players[0].soul == 4 and players[0].coins == 19)
assert(positions["0"].index == 0 and positions["1"].index == 168)
assert(not battle.allow("coop_revive") and not battle.allow("game_over"))
assert(not battle.allow("specialRoomGather"), "Battle royale must not gather competitors")
assert(not battle.allow("floor"))
players[1].dead, players[1].reviving = true, true
tick(120)
assert(battle.view().phase == phase.survival, "Normal extra lives remain eligible")
players[1].dead, players[1].reviving = false, false
tick(1)
players[1].ghost = true
tick(1)
local portal = assert(battle.view().portal)
players[0].Position = vector(portal.x, portal.y)
tick(31)
assert(battle.view().phase == phase.boss and players[0]:GetCollectibleNum(633) == 1)
assert(players[1].ghost and not battle.allow("coop_revive"))
assert(battle.canEnter({ info = info, slot = 1, room = 100, dimension = 0 }), "Ghost can spectate")
assert(not battle.canEnter({ info = info, slot = 0, room = 84, dimension = 0 }))
tick(1)
players[0].dead, players[0].reviving = true, true
tick(120)
positions["0"].index = 84
players[0].dead, players[0].reviving = false, false
tick(1)
assert(positions["0"].index == 100 and players[0]:GetCollectibleNum(633) == 1)
spawn(5, 100, 1)
local extra = spawn(5, 100, 2)
clear = true
tick(40)
assert(battle.view().scores[1] == 1 and battle.view().phase == phase.reward)
assert(entities[1].SubType == 345 and extra.SubType == 2, "Only the base reward is guaranteed")
assert(players[0]:GetCollectibleNum(633) == 0 and players[1].ghost)
assert(
    not battle.canEnter({ info = info, slot = 0, room = 84, dimension = 0 }),
    "Reward choice stays with the winner"
)
portal = assert(battle.view().portal)
players[1].Position = vector(portal.x, portal.y)
tick(40)
assert(floorRequests == 1, "The defeated player cannot choose the next round")
players[0].Position = vector(320, 280)
tick(1)
players[0].Position = vector(portal.x, portal.y)
tick(1)
assert(floorRequests == 2 and battle.view().scores[1] == 1, "Skipping rewards retains the win")
players[0]:AddCollectible(105)
players[0]:AddCollectible(633)
clear, entities = false, {}
battle.onLayoutReady(info, level)
assert(not players[1].ghost and players[0]:HasCollectible(105), "Only the starting D6 is removed")
players[1].ghost = true
tick(1)
portal = assert(battle.view().portal)
players[0].Position = vector(portal.x, portal.y)
tick(32)
assert(momSpawns == 1, "Match point directly starts Mom")
clear = true
tick(40)
assert(battle.view().phase == phase.trophy and players[0]:GetCollectibleNum(633) == 1)
local trophy = entities[#entities]
trophy.Wait = 0
battle.collide(trophy, players[1])
assert(finishes == 0)
battle.collide(trophy, players[0])
battle.collide(trophy, players[0])
assert(finishes == 1)
local saved = battle.snapshot()
info.authority = 0
battle.apply(saved)
assert(battle.view().scores[1] == 2, "Reconnect restores round progress")
battle.reset()
assert(battle.view() == nil)
print("battle royale round and adapter tests passed")

-- Expand through native door creation to its fixed point, including lower
-- indexes introduced after a scan has passed them. Native failures stay closed.
enums.grid = { GRID_TRAPDOOR = 17, GRID_STAIRS = 18 }
enums.effect = { HEAVEN_LIGHT_DOOR = 39 }
enums.entity.ENTITY_EFFECT = 1000
local descriptors = { [84] = { SafeGridIndex = 84, Data = { Type = 1 } } }
local roomCount = 1
local generatedLevel = {
    GetRooms = function()
        return { Size = roomCount }
    end,
    GetRoomByIdx = function(_, index)
        return descriptors[index]
    end,
    MakeRedRoomDoor = function(_, index, door)
        local x, y = index % 13, index // 13
        local offset = { [0] = { -1, 0 }, [1] = { 0, -1 }, [2] = { 1, 0 }, [3] = { 0, 1 } }
        local d = offset[door]
        if not d then
            return false
        end
        x, y = x + d[1], y + d[2]
        if x < 0 or x >= 13 or y < 0 or y >= 13 then
            return false
        end
        local target = y * 13 + x
        if target == 0 or descriptors[target] then
            return false
        end
        descriptors[target] = {
            SafeGridIndex = target,
            Data = {
                Type = (target == 83 or target == 85) and 5 or 1,
                Shape = 1,
                Spawns = {
                    Size = target == 83 and 1 or 0,
                    Get = function()
                        return {
                            Entries = {
                                Size = 1,
                                Get = function()
                                    return { Type = 45 }
                                end,
                            },
                        }
                    end,
                },
            },
        }
        roomCount = roomCount + 1
        return true
    end,
}
local map = module("compat/challenges/battle_royale_map")({
    native = {
        room_special_template = function(index, kind, variant, seed)
            assert(kind == 5 and variant == 1060 and seed > 0)
            assert(descriptors[index].Data.Type == 1)
            descriptors[index].Data.Type = kind
            return true
        end,
    },
    rules = rules,
    enums = enums,
    random = function(limit)
        return limit
    end,
    entities = function()
        return {}
    end,
})
local built = map.build(generatedLevel)
assert(roomCount == 168 and built.boss == 85)
local occupied = {}
for _, index in ipairs(built.spawns) do
    assert(descriptors[index] and index ~= built.boss and not occupied[index])
    occupied[index] = true
end
assert(built.spawns[1] == 1 and built.spawns[4] == 168, "Missing corner uses nearest native room")
local opened, removed = {}, {}
local testRoom = {
    GetDoor = function(_, slot)
        return {
            TargetRoomType = slot == 0 and enums.room.ROOM_BOSS or 1,
            SetLocked = function(_, locked)
                assert(not locked)
            end,
            Open = function()
                opened[slot] = true
            end,
        }
    end,
    GetGridSize = function()
        return 2
    end,
    GetGridEntity = function(_, index)
        return {
            GetType = function()
                return index == 0 and enums.grid.GRID_TRAPDOOR or enums.grid.GRID_STAIRS
            end,
        }
    end,
    RemoveGridEntity = function(_, index)
        removed[index] = true
    end,
}
map.escape(testRoom)
assert(not opened[0] and opened[1] and opened[7], "Escape keeps boss doors restricted")
map.removeExits(testRoom)
assert(removed[0] and not removed[1], "Exploration retains crawlspace stairs")
map.removeExits(testRoom, true)
assert(removed[1], "Boss settlement removes alternative exits")
print("battle royale map generation and escape tests passed")
