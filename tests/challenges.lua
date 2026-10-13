local root = assert(arg[1])
local routeFactory = dofile(root .. "/src/bridge/compat/routes/challenge_lamb.lua")
local coordinator = dofile(root .. "/src/bridge/runtime/challenges.lua")
local stage, kind, clear, enemy = 11, 0, true, 273
local finish, morphs, transitions, layouts = 0, 0, {}, 0
local enums = {
    entity = { ENTITY_PICKUP = 5, ENTITY_THE_LAMB = 273 },
    pickup = { PICKUP_BIGCHEST = 340, PICKUP_TROPHY = 370 },
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
        }
    end,
    StartStageTransition = function(_, same, animation, player)
        transitions[#transitions + 1] = { stage, kind, same, animation, player }
    end,
}
local info = {
    active = 1,
    ready = 1,
    authority = 1,
    challenge = 1001,
    challengeVersion = 1,
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
        return { ["1001"] = { version = 1, id = 1001, route = "lamb" } }
    end,
    api_info = function()
        return info
    end,
}
local route = routeFactory({
    game = function()
        return game
    end,
    enums = enums,
    finish = function()
        finish = finish + 1
        return true
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
-- Low-unlock native terminal chests continue toward the configured objective.
for _, pair in ipairs({ { 6, 7 }, { 8, 10 }, { 9, 10 }, { 10, 11 } }) do
    stage, kind = pair[1], 0
    local p = chest()
    rule.collide(p, collider)
    assert(stage == pair[2] and kind == 0 and transitions[#transitions][5] == player)
end
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
stage, kind = 10, 1
local count = #transitions
rule.level()
assert(#transitions == count)
info.ready = 0
rule.step()
assert(#transitions == count)
info.ready = 1
rule.step()
rule.step()
assert(stage == 10 and kind == 0 and #transitions == count + 1 and layouts == 1)
-- Other native endings must return to the objective, at a ready authority step.
stage, kind = 13, 1
count = #transitions
rule.routeEnding()
rule.routeEnding()
assert(#transitions == count)
info.ready = 0
rule.step()
assert(#transitions == count)
info.ready = 1
rule.step()
rule.step()
assert(stage == 11 and kind == 0 and #transitions == count + 1)
assert(not rule.canEnter(1, 0, 1, 0, 42, false) and not rule.canEnter(1, 0, 1, 0, 42, true))
assert(rule.canEnter(0, 0, 1, 0, 42, false) and rule.canEnter(1, 0, 1, 0, 43, false))
-- Pending route work cannot leak into a new challenge or ordinary run.
rule.routeEnding()
info.runId = "second"
count = #transitions
rule.step()
assert(#transitions == count)
rule.routeEnding()
info.challenge = 0
rule.step()
info.challenge = 1001
rule.step()
assert(#transitions == count)
info.challengeVersion = 2
assert(not pcall(rule.step))
info.challengeVersion = 1
info.challenge = 0
assert(rule.canEnter(1, 0, 1, 0, 42, false))
print(
    "PASS challenge authority, Lamb trophy, all collectors, rollback/reconnect, routes and map hooks"
)
