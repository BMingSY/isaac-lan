local root = assert(arg[1])
local function module(name)
    return dofile(root .. "/src/bridge/" .. name .. ".lua")
end
local rules = module("compat/challenges/battle_royale_rules")
local phase = rules.phase
local plan = { 0, 14, 42, 56 }
for _, count in ipairs({ 2, 3, 4 }) do
    local round = rules.new()
    round.start(plan)
    assert(not round.step(30, (1 << count) - 1, false))
    assert(not round.step(30, 1, true), "Pending original revival must delay victory")
    assert(round.step(30, 1, false) == "winner")
    assert(round.state.scores[1] == 0, "Survival alone must not score")
    assert(not round.enter(1) and round.enter(0))
    assert(not round.clear(1) and round.clear(0))
    assert(not round.clear(0) and round.state.scores[1] == 1, "Repeated clear must not score twice")
    assert(not round.leave(1), "Only the winner may skip rewards")
    assert(round.leave(0))
    round.start(plan)
    assert(round.step(1, 1, false) == "winner" and round.enter(0))
    assert(round.step(1, 0, false) == "next")
    assert(round.state.scores[1] == 1, "Boss defeat must retain the previous match point")
    round.start(plan)
    assert(round.step(1, 0, false) == "next", "Simultaneous elimination has no winner")
    assert(round.state.scores[1] == 1)
    round.start(plan)
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
    { 2700, 1, 9 },
    { 5400, 3, 7 },
    { 7200, 4, 4 },
}) do
    local zone = rules.zone({ elapsed = case[1], zones = plan })
    assert(zone.left == case[2] and zone.right == case[3])
end
assert(not rules.outside(56, { elapsed = 9000, zones = plan }))
assert(rules.outside(84, { elapsed = 7200, zones = plan }), "Center is not always safe")
assert(rules.outside(-3, { elapsed = 0, zones = plan }))
assert(rules.pressure(9900) > rules.pressure(9000))
-- Every allowed final room, including all four edges/corners, can be chosen.
-- Random offsets must stay nested, retain the chosen room and survive the wire.
math.randomseed(1003)
local variations = {}
for target = 0, rules.width * rules.width - 1 do
    local zones = rules.plan({ target }, math.random)
    local round = rules.new()
    round.start(zones)
    local copy = rules.read(round.snapshot())
    assert(copy.zones[4] == target)
    for step = 1, #rules.zoneSizes do
        local elapsed = rules.shrinkFrames[step - 1] or 0
        assert(not rules.outside(target, { zones = zones, elapsed = elapsed }))
    end
    variations[zones[2]] = true
    copy.zones[4] = -1
    zones[4] = -1
    assert(round.state.zones[4] == target, "Plans and views must not mutate live zones")
end
local variationCount = 0
for _ in pairs(variations) do
    variationCount = variationCount + 1
end
assert(variationCount > 10, "Shrink locations must vary")
for _, zones in ipairs({ { 0, 5, 42, 56 }, { 0, 14, 0, 56 }, { 0, 14, 42, 168 }, { 0, 14, 42 } }) do
    local round = rules.new()
    round.start(zones)
    assert(not pcall(rules.read, round.snapshot()), "Invalid zone plan accepted")
end
local invalid = rules.new().snapshot()
invalid[rules.fields.scores][1] = 3
assert(not pcall(rules.read, invalid))
for _, field in ipairs({ rules.fields.zones, rules.fields.scores }) do
    local round = rules.new()
    round.start(plan)
    local sparse = round.snapshot()
    sparse[field][2] = nil
    assert(
        not pcall(rules.read, sparse),
        "A sparse progress array must be rejected before rendering"
    )
end

-- Exercise the actual adapter through layout, normal deaths, portal contact,
-- native clear awards, optional loot, another floor, Mom and the trophy.
local enums = {
    collectible = {
        COLLECTIBLE_D6 = 105,
        COLLECTIBLE_DOGMA = 633,
        COLLECTIBLE_SYNTHOIL = 345,
        COLLECTIBLE_CHAOS = 402,
    },
    stageType = { STAGETYPE_ORIGINAL = 0, STAGETYPE_AFTERBIRTH = 2 },
    transition = { FADE = 0 },
    pool = { POOL_BOSS = 2, POOL_TREASURE = 0 },
    entity = { ENTITY_PICKUP = 5, ENTITY_MOM = 45, ENTITY_PROJECTILE = 9 },
    pickup = { PICKUP_COLLECTIBLE = 100, PICKUP_TROPHY = 370, PICKUP_BIGCHEST = 340 },
    room = { ROOM_BOSS = 5, ROOM_DEFAULT = 1, ROOM_SHOP = 2, ROOM_TREASURE = 4 },
    shape = {
        ROOMSHAPE_1x1 = 1,
        ROOMSHAPE_IH = 2,
        ROOMSHAPE_IV = 3,
        ROOMSHAPE_1x2 = 4,
        ROOMSHAPE_IIV = 5,
        ROOMSHAPE_2x1 = 6,
        ROOMSHAPE_IIH = 7,
        ROOMSHAPE_2x2 = 8,
        ROOMSHAPE_LTL = 9,
        ROOMSHAPE_LTR = 10,
        ROOMSHAPE_LBL = 11,
        ROOMSHAPE_LBR = 12,
    },
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
    function p:AddCollectible(id, _, firstTime)
        if id == 633 and firstTime ~= nil then
            assert(firstTime, "Temporary Dogma must run the native pickup effects")
            assert(activeSlot == slot, "Dogma must target the winner")
            local index = positions[tostring(slot)].index
            assert(index == 100 or index == 101, "Dogma must be picked up inside the boss room")
        end
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
    function p:SetMinDamageCooldown() end
    players[slot], positions[tostring(slot)] = p, { index = 84, dimension = 0 }
end
local clear, escapes = false, 0
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
    rewards = module("compat/challenges/battle_royale_rewards")({
        enums = enums,
        game = function()
            return game
        end,
        config = function()
            return {
                GetCollectible = function(_, id)
                    return { Quality = id == 345 and 3 or 0 }
                end,
            }
        end,
        random = function(low)
            return low
        end,
        entities = function()
            return entities
        end,
        spawn = spawn,
        vector = vector,
    }),
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
            return { boss = 100, finalBoss = 101, spawns = { 0, 168 }, zones = plan }
        end,
        removeExits = function() end,
        openResources = function() end,
        clearSpawn = function()
            local index = positions[tostring(activeSlot)].index
            assert(index == 0 or index == 168, "Spawn cleanup must wait for arrival")
        end,
        escape = function()
            escapes = escapes + 1
        end,
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
assert(battle.view().phase == phase.portal and battle.view().elapsed < rules.shrinkFrames[1])
local stoppedAt = battle.view().elapsed
-- No walking into a portal, even if an item changes the winner's room.
positions["0"].index = 84
players[0].Position = vector(10, 10)
tick(31)
assert(battle.view().elapsed == stoppedAt, "Automatic portal must stop survival pressure")
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
assert(entities[1].SubType == 345 and extra.SubType == 345, "Boss rewards use Chaos draws")
assert(not players[0]:HasCollectible(402), "Reward drawing must clean up its temporary Chaos")
assert(players[0]:GetCollectibleNum(633) == 1 and players[1].ghost)
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
assert(players[0]:GetCollectibleNum(633) == 0, "Remove temporary Dogma at the fake floor boundary")
players[0]:AddCollectible(105)
players[0]:AddCollectible(633)
clear, entities = false, {}
battle.onLayoutReady(info, level)
assert(not players[1].ghost and players[0]:HasCollectible(105), "Only the starting D6 is removed")
players[1].ghost = true
tick(1)
assert(battle.view().portal)
tick(32)
assert(momSpawns == 1, "Match point directly starts Mom")
players[0].ghost = true
tick(1)
assert(
    floorRequests == 3 and players[0]:GetCollectibleNum(633) == 1,
    "Failed boss removes only the temporary copy"
)
battle.onLayoutReady(info, level)
assert(not players[0].ghost and players[0]:GetCollectibleNum(633) == 1)
players[1].ghost = true
tick(33)
assert(momSpawns == 2 and players[0]:GetCollectibleNum(633) == 2)
clear = true
tick(40)
assert(battle.view().phase == phase.trophy and players[0]:GetCollectibleNum(633) == 2)
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
-- Exercise environment damage through the authoritative room scope, including
-- cadence, a room which becomes unsafe, and the five-minute final-room limit.
info.authority = 1
for _, player in pairs(players) do
    player.dead, player.ghost = false, false
    player.hearts = 6
end
battle.onLayoutReady(info, level)
battle.onLayoutReady(info, level)
tick(1)
local roundStart = frame
positions["0"].index, positions["1"].index = 56, 0
frame = roundStart + rules.shrinkFrames[1] - 1
tick(1)
assert(players[0].hearts == 6 and players[1].hearts == 4 and escapes >= 2)
battle.step(info)
assert(players[1].hearts == 4, "Repeated update must not repeat circle damage")
positions["1"].index = 56
frame = roundStart + rules.shrinkFrames[2] - 1
tick(1)
assert(players[1].hearts == 4, "Re-entering the safe zone must stop damage")
positions["1"].index = 84
frame = roundStart + rules.shrinkFrames[3] - 1
tick(1)
assert(
    players[0].hearts == 6 and players[1].hearts == 0,
    "Center must take damage when final zone is elsewhere"
)
frame = roundStart + rules.survivalFrames - 1
tick(1)
assert(players[0].hearts == 2, "Overtime must also pressure the final safe room")
battle.reset()
print("battle royale round and adapter tests passed")

-- Expand through native door creation to its fixed point, including lower
-- indexes introduced after a scan has passed them. Native failures stay closed.
enums.grid = { GRID_TRAPDOOR = 17, GRID_STAIRS = 18, GRID_WALL = 15, GRID_DOOR = 16 }
enums.effect = { HEAVEN_LIGHT_DOOR = 39 }
enums.entity.ENTITY_EFFECT = 1000
enums.entity.ENTITY_BOMBDROP, enums.entity.ENTITY_LASER = 4, 7
local descriptors =
    { [84] = { SafeGridIndex = 84, GridIndex = 84, Data = { Type = 1, Shape = 1, Doors = 15 } } }
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
        assert(d, "Invalid door slot would create an I AM ERROR entrance")
        x, y = x + d[1], y + d[2]
        assert(x >= 0 and x < 13 and y >= 0 and y < 13, "Out-of-map red door")
        local target = y * 13 + x
        if target == 0 or descriptors[target] then
            return false
        end
        descriptors[target] = {
            SafeGridIndex = target,
            GridIndex = target,
            Data = {
                Type = (target == 83 or target == 85) and 5 or 1,
                Shape = 1,
                Doors = 15,
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
local spawnEntities, spawnGrids = {}, {}
local map = module("compat/challenges/battle_royale_map")({
    resources = function(_, layout)
        assert(
            layout.zones and layout.spawns and layout.finalBoss,
            "Reserve the encounter and zones before resources"
        )
    end,
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
    random = function(low, high)
        return high or low
    end,
    entities = function()
        return spawnEntities
    end,
})
local built = map.build(generatedLevel)
assert(roomCount == 168 and built.boss == 85)
local final = built.zones[#rules.zoneSizes]
assert(final == 168 and descriptors[final].Data.Type == enums.room.ROOM_DEFAULT)
assert(final ~= built.boss and final ~= built.finalBoss and final ~= 0)
local occupied = {}
for _, index in ipairs(built.spawns) do
    assert(descriptors[index] and index ~= built.boss and not occupied[index])
    occupied[index] = true
end
assert(built.spawns[1] == 1 and built.spawns[4] == 168, "Missing corner uses nearest native room")
-- Cover large/thin/L room boundaries, including GridIndex != SafeGridIndex.
-- A rejected generation may not install an error door as a side effect.
for _, case in ipairs({
    { shape = enums.shape.ROOMSHAPE_1x1, origin = 0, safe = 0, slots = "2,3" },
    { shape = enums.shape.ROOMSHAPE_1x2, origin = 0, safe = 0, slots = "2,3,6" },
    { shape = enums.shape.ROOMSHAPE_IIV, origin = 154, safe = 154, mask = 10, slots = "1" },
    { shape = enums.shape.ROOMSHAPE_2x1, origin = 0, safe = 0, slots = "2,3,7" },
    { shape = enums.shape.ROOMSHAPE_IIH, origin = 154, safe = 154, mask = 5, slots = "0" },
    { shape = enums.shape.ROOMSHAPE_2x2, origin = 154, safe = 154, slots = "0,1,4,5" },
    { shape = enums.shape.ROOMSHAPE_LTL, origin = 0, safe = 1, slots = "0,1,2,3,6,7" },
    { shape = enums.shape.ROOMSHAPE_LTR, origin = 154, safe = 154, slots = "0,1,2,4,5" },
    { shape = enums.shape.ROOMSHAPE_LBL, origin = 154, safe = 154, slots = "0,1,3,4,5" },
    { shape = enums.shape.ROOMSHAPE_LBR, origin = 154, safe = 154, slots = "0,1,4,5,6,7" },
}) do
    descriptors = {}
    for index = 80, 88 do
        descriptors[index] = {
            GridIndex = index,
            SafeGridIndex = index,
            Data = {
                Type = index == 85 and 5 or 1,
                Shape = 1,
                Doors = 0,
                Spawns = { Size = 0 },
            },
        }
    end
    descriptors[case.safe] = {
        GridIndex = case.origin,
        SafeGridIndex = case.safe,
        Data = {
            Type = 1,
            Shape = case.shape,
            Doors = case.mask or 255,
            Spawns = { Size = 0 },
        },
    }
    local slots = {}
    generatedLevel.MakeRedRoomDoor = function(_, index, slot)
        assert(index == case.safe)
        slots[#slots + 1] = slot
        return false
    end
    map.build(generatedLevel)
    assert(
        table.concat(slots, ",") == case.slots,
        "Invalid red-door geometry for shape " .. case.shape
    )
end
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
local resourceDoors, clear = {}, false
for slot, kind in ipairs({
    enums.room.ROOM_TREASURE,
    enums.room.ROOM_SHOP,
    enums.room.ROOM_BOSS,
    enums.room.ROOM_DEFAULT,
}) do
    resourceDoors[slot - 1] = {
        TargetRoomType = kind,
        locked = true,
        opened = false,
        SetLocked = function(self, value)
            self.locked = value
        end,
        Open = function(self)
            self.opened = true
        end,
    }
end
local resourceRoom = {
    GetDoor = function(_, slot)
        return resourceDoors[slot]
    end,
    IsClear = function()
        return clear
    end,
}
map.openResources(resourceRoom)
assert(not resourceDoors[0].locked and not resourceDoors[1].locked)
for _, door in pairs(resourceDoors) do
    assert(not door.opened, "Free entrances preserve combat barriers")
end
clear = true
map.openResources(resourceRoom)
assert(resourceDoors[0].opened and resourceDoors[1].opened)
for slot = 2, 3 do
    assert(resourceDoors[slot].locked and not resourceDoors[slot].opened)
end
-- Spawn safety removes invulnerable enemies/traps without invoking death
-- effects, and leaves resources, players and door allocations intact.
for index, kind in ipairs({ 10, 33, 9, 4, 7, 5, 1 }) do
    spawnEntities[index] = {
        Type = kind,
        IsEnemy = function()
            return kind == 10 or kind == 33
        end,
        Remove = function(self)
            self.removed = true
        end,
    }
end
for index, kind in ipairs({ 2, 7, 12, 15, 16 }) do
    spawnGrids[index - 1] = {
        GetType = function()
            return kind
        end,
    }
end
local spawnClear = false
map.clearSpawn({
    RemoveGridEntity = function(_, index, delay, debris)
        assert(delay == 0 and not debris)
        spawnGrids[index] = nil
    end,
    GetGridSize = function()
        return 5
    end,
    GetGridEntity = function(_, index)
        return spawnGrids[index]
    end,
    SetClear = function(_, value)
        spawnClear = value
    end,
})
assert(spawnClear and not spawnGrids[0] and not spawnGrids[1] and not spawnGrids[2])
assert(spawnGrids[3] and spawnGrids[4], "Keep native walls and door connections")
for index, entity in ipairs(spawnEntities) do
    assert(not not entity.removed == (index <= 5))
end
print("battle royale map generation and escape tests passed")
