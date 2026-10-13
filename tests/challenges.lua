local root = assert(arg[1])
local routeFactory = dofile(root .. "/src/bridge/compat/routes/challenge_lamb.lua")
local coordinator = dofile(root .. "/src/bridge/runtime/challenges.lua")
local stage, kind, clear, enemy = 11, 0, true, 273
local finish, morphs, transitions, layouts = 0, 0, {}, 0
local chestEnding = 0
local grids, effects, pendingRemoval, gridRemovals = {}, {}, {}, 0
local enums = {
    entity = { ENTITY_PICKUP = 5, ENTITY_THE_LAMB = 273, ENTITY_EFFECT = 1000 },
    pickup = { PICKUP_BIGCHEST = 340, PICKUP_TROPHY = 370 },
    grid = { GRID_TRAPDOOR = 17, GRID_STAIRS = 18 },
    effect = { HEAVEN_LIGHT_DOOR = 39 },
    room = { ROOM_BOSS = 5 },
    stage = { STAGE3_2 = 6, STAGE4_1 = 7, STAGE4_2 = 8, STAGE4_3 = 9, STAGE5 = 10, STAGE6 = 11 },
    stageType = { STAGETYPE_ORIGINAL = 0, STAGETYPE_WOTL = 1 },
}
local data = {
    Type = 5,
    SpawnCount = 1,
    Spawns = {
        Get = function()
            return {
                EntryCount = 1,
                Entries = {
                    Get = function()
                        return { Type = enemy }
                    end,
                },
            }
        end,
    },
}
local level = {
    GetStage = function()
        return stage
    end,
    GetStageType = function()
        return kind
    end,
    GetCurrentRoomDesc = function()
        return { Data = data }
    end,
    SetStage = function(_, nextStage, nextKind)
        stage, kind = nextStage, nextKind
    end,
}
local game = {
    GetLevel = function()
        return level
    end,
    GetRoom = function()
        return {
            IsClear = function()
                return clear
            end,
            GetGridSize = function()
                return 12
            end,
            GetGridEntity = function(_, index)
                return grids[index]
            end,
            RemoveGridEntity = function(_, index, trail, decoration)
                assert(trail == 0 and decoration == false and grids[index])
                gridRemovals = gridRemovals + 1
                pendingRemoval[index] = true
            end,
        }
    end,
    StartStageTransition = function(_, same, animation, player)
        assert(
            player and player.IsCoopGhost and player.IsDead,
            "Stage transition requires a player"
        )
        assert(same == true and animation == 0)
        transitions[#transitions + 1] = { stage, kind, same, animation, player }
    end,
}
local info = {
    active = 1,
    ready = 1,
    authority = 1,
    challenge = 1001,
    challengeVersion = 2,
    players = 4,
    connected = 15,
    runId = "first",
}
local ghost, dead = false, false
local player = {
    ControllerIndex = 1,
    IsCoopGhost = function()
        return ghost
    end,
    IsDead = function()
        return dead
    end,
}
local collider = {
    ToPlayer = function()
        return player
    end,
}
local function chest()
    return {
        Variant = 340,
        Wait = 0,
        Morph = function(self, entity, variant, subtype)
            assert(entity == 5 and variant == 370 and subtype == 0)
            self.Variant = variant
            morphs = morphs + 1
        end,
    }
end
local native = {
    net_challenges = function()
        return { ["1001"] = { version = 2, id = 1001, route = "lamb" } }
    end,
    api_info = function()
        return info
    end,
}
local route = routeFactory({
    game = function()
        return game
    end,
    player = function(index)
        assert(index == 0)
        return player
    end,
    enums = enums,
    finish = function()
        finish = finish + 1
        return true
    end,
    chestEnding = function()
        return chestEnding
    end,
    entities = function()
        return effects
    end,
})
local rule = coordinator({
    native = native,
    game = function()
        return game
    end,
    routes = { lamb = route },
    maps = {
        [1001] = {
            onLayoutReady = function()
                layouts = layouts + 1
            end,
            canEnter = function(ctx)
                return ctx.slot ~= 1 or ctx.room ~= 42
            end,
        },
    },
})
-- Ordinary games and clients cannot morph rewards or complete on their own.
for _, state in ipairs({ { 0, 1 }, { 1001, 0 } }) do
    info.challenge, info.authority = state[1], state[2]
    local p = chest()
    rule.pickup(p)
    rule.collide(p, collider)
    assert(p.Variant == 340 and finish == 0 and #transitions == 0)
end
info.challenge, info.authority = 1001, 1
for _, state in ipairs({ { 1, 1, 15 }, { 1, 0, 15 }, { 0, 1, 15 }, { 1, 1, 14 } }) do
    info.authority, info.ready, info.connected = table.unpack(state)
    assert(
        rule.collide({ Variant = 100, Wait = 0 }, collider) == nil,
        "Challenge altered an unrelated pickup"
    )
    if info.ready == 0 then
        assert(rule.collide({ Variant = 370, Wait = 0 }, collider) == true and finish == 0)
    end
end
info.authority, info.ready, info.connected = 1, 1, 15
-- Match the endpoint, native room identity and clear status together.
for _, state in ipairs({
    { 10, 0, true, 273 },
    { 11, 1, true, 273 },
    { 11, 0, false, 273 },
    {
        11,
        0,
        true,
        102,
    },
}) do
    stage, kind, clear, enemy = table.unpack(state)
    local p = chest()
    rule.pickup(p)
    assert(p.Variant == 340)
end
stage, kind, clear, enemy = 11, 0, true, 273
local trophy = chest()
rule.pickup(trophy)
rule.pickup(trophy)
assert(morphs == 1 and trophy.Variant == 370 and trophy.Wait == 30)
rule.collide(trophy, collider)
assert(finish == 0)
trophy.Wait = 0
for _, flag in ipairs({ "ghost", "dead", "offline" }) do
    ghost, dead = flag == "ghost", flag == "dead"
    info.connected = flag == "offline" and 14 or 15
    rule.collide(trophy, collider)
    assert(finish == 0)
end
ghost, dead, info.connected = false, false, 15
for slot = 0, 3 do
    player.ControllerIndex = slot + 1
    assert(rule.collide(trophy, collider) == true)
end
assert(finish == 4) -- The native terminal request makes repeated contacts idempotent.
-- A restored trophy needs no unsaved Lua marker; rollback to combat cannot win.
local restored = { Variant = 370, Wait = 0 }
rule = coordinator({ native = native, routes = { lamb = route } })
rule.collide(restored, collider)
assert(finish == 5)
clear = false
rule.collide(restored, collider)
assert(finish == 5)
clear = true
-- Native progression is preserved; terminal chests cannot replace the trophy.
for _, source in ipairs({ 6, 8, 9, 10, 11, 12, 13 }) do
    stage, kind, enemy = source, 0, 412
    local p = chest()
    assert(rule.collide(p, collider) == nil)
    assert(stage == source and p.Variant == 340 and #transitions == 0)
    chestEnding = 6
    assert(rule.collide(p, collider) == true)
    assert(stage == source and p.Variant == 340 and #transitions == 0 and finish == 5)
    chestEnding = -1
    assert(rule.collide(p, collider) == true, "Unavailable native decision must fail closed")
    chestEnding = 0
end
enemy = 273
-- No recursive native transition inside the new-level callback.
rule = coordinator({
    native = native,
    game = function()
        return game
    end,
    routes = { lamb = route },
    maps = {
        [1001] = {
            onLayoutReady = function()
                layouts = layouts + 1
            end,
            canEnter = function(ctx)
                return ctx.slot ~= 1 or ctx.room ~= 42
            end,
        },
    },
})
for _, source in ipairs({ 10, 11 }) do
    stage, kind = source, 1
    local count, previousLayouts = #transitions, layouts
    rule.level()
    assert(#transitions == count)
    info.ready = 0
    rule.step()
    assert(#transitions == count)
    info.ready = 1
    rule.step()
    rule.step()
    assert(stage == source and kind == 1 and #transitions == count)
    assert(layouts == previousLayouts + 1)
end
assert(not rule.canEnter(1, 0, 1, 0, 42, false) and not rule.canEnter(1, 0, 1, 0, 42, true))
assert(rule.canEnter(0, 0, 1, 0, 42, false) and rule.canEnter(1, 0, 1, 0, 43, false))
-- A new run resets layout work; ordinary runs do not apply challenge maps.
local previousLayouts = layouts
info.runId = "second"
rule.step()
assert(layouts == previousLayouts + 1 and #transitions == 0)
info.challenge = 0
rule.step()
assert(layouts == previousLayouts + 1)
info.challenge = 1001
rule.step()
assert(layouts == previousLayouts + 2)
info.challengeVersion = 1
assert(not pcall(rule.step))
info.challengeVersion = 2
info.challenge = 0
assert(rule.canEnter(1, 0, 1, 0, 42, false))
-- The trophy's native room callbacks remove alternate floor exits, including
-- portals appearing after INIT. Lua grid removal commits on the next update.
local function grid(kind, variant, data)
    return {
        GetType = function()
            return kind
        end,
        GetVariant = function()
            return variant
        end,
        VarData = data,
    }
end
local function effect(kind, variant)
    return {
        Type = kind,
        Variant = variant,
        Exists = function(self)
            return not self.removed
        end,
        Remove = function(self)
            assert(not self.removed)
            self.removed = true
        end,
    }
end
local function commitRemoval()
    for index in pairs(pendingRemoval) do
        grids[index] = nil
    end
    pendingRemoval = {}
end
grids = {
    [1] = grid(17, 1, 1), -- Native Void portal.
    [2] = grid(17, 0, 0), -- Ordinary floor trapdoor.
    [3] = grid(18, 0, 0), -- Stairs/crawlspace entry.
    [4] = grid(2, 0, 0), -- Rock.
    [5] = grid(16, 0, 0), -- Room door remains usable.
    [6] = grid(7, 0, 0), -- Pit.
}
effects = { effect(1000, 39), effect(1000, 161), effect(306, 0) }
stage, kind, clear, enemy = 11, 0, true, 273
local reward = chest()
for _, state in ipairs({ { 0, 1, 1 }, { 1001, 0, 1 }, { 1001, 1, 0 } }) do
    info.challenge, info.authority, info.ready = table.unpack(state)
    rule.pickup(reward)
    assert(gridRemovals == 0 and not effects[1].removed and reward.Variant == 340)
end
info.challenge, info.authority, info.ready = 1001, 1, 1
for _, state in ipairs({
    { 10, 0, true, 273 },
    { 11, 1, true, 273 },
    { 11, 0, false, 273 },
    { 11, 0, true, 102 },
}) do
    stage, kind, clear, enemy = table.unpack(state)
    rule.pickup(reward)
    assert(gridRemovals == 0 and not effects[1].removed and reward.Variant == 340)
end
stage, kind, clear, enemy = 11, 0, true, 273
rule.pickup({ Variant = 100 })
assert(gridRemovals == 0, "Unrelated pickups must not trigger endpoint cleanup")
local beforeMorphs, beforeFinish = morphs, finish
rule.pickup(reward)
assert(morphs == beforeMorphs + 1 and reward.Variant == 370 and reward.Wait == 30)
assert(gridRemovals == 3 and pendingRemoval[1] and pendingRemoval[2] and pendingRemoval[3])
assert(effects[1].removed and not effects[2].removed and not effects[3].removed)
commitRemoval()
rule.pickup(reward)
assert(gridRemovals == 3 and morphs == beforeMorphs + 1)
assert(grids[4] and grids[5] and grids[6] and #transitions == 0 and finish == beforeFinish)
-- A later portal and a restored trophy need no run-local completion marker.
grids[7], effects[4] = grid(17, 1, 1), effect(1000, 39)
rule = coordinator({ native = native, routes = { lamb = route } })
local restoredReward = { Variant = 370, Wait = 0 }
rule.pickup(restoredReward)
assert(pendingRemoval[7] and effects[4].removed)
commitRemoval()
rule.pickup(restoredReward)
assert(gridRemovals == 4 and finish == beforeFinish and #transitions == 0)
-- Room contexts are supplied by native pickup callbacks: an uncleared or
-- unrelated room keeps its exits even when another room has a trophy.
grids[8] = grid(17, 1, 1)
clear = false
rule.pickup(restoredReward)
assert(not pendingRemoval[8] and gridRemovals == 4)
clear, enemy = true, 102
rule.pickup(restoredReward)
assert(not pendingRemoval[8] and gridRemovals == 4)
enemy = 273
rule.pickup(restoredReward)
assert(pendingRemoval[8] and gridRemovals == 5)
print(
    "PASS challenge authority, Lamb trophy/exits, all collectors, rollback/reconnect, vanilla routes and map hooks"
)
