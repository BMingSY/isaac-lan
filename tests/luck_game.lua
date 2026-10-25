local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/compat/challenges/luck_game.lua")
local coordinator = dofile(root .. "/src/bridge/runtime/challenges.lua")
local messages, grants, takes, pills, rolls = {}, {}, {}, {}, {}
local scope, stage, kind, seed, draws = nil, 1, 0, 123, 0
local smelts = 0
local info = {
    active = 1,
    authority = 1,
    ready = 1,
    challenge = 1002,
    challengeVersion = 1,
    players = 4,
    connected = 15,
    runId = "first",
}
local configItems = {
    [1] = { Name = "洋葱", Type = 1 },
    [2] = { Name = "骰子", Type = 3 },
    [3] = { Name = "幸运脚", Type = 1 },
    [4] = { Name = "口袋主动", Type = 3 },
    [-1] = { Name = "错误道具", Type = 1 },
}
local config = {
    GetCollectibles = function()
        return { Size = 5 }
    end,
    GetCollectible = function(_, id)
        return configItems[id]
    end,
}
local players = {}
for i = 1, 4 do
    players[i] = {
        ControllerIndex = i,
        InitSeed = i + 100,
        Luck = 0,
        items = {},
        active = {},
        charge = {},
        alive = true,
        trinkets = {},
        swallowed = {},
    }
end
for _, player in ipairs(players) do
    function player:Exists()
        return true
    end
    function player:IsDead()
        return not self.alive
    end
    function player:IsCoopGhost()
        return self.ghost == true
    end
    function player:HasTrinket(id)
        if (self.swallowed[id] or 0) > 0 then
            return true
        end
        for _, held in ipairs(self.trinkets) do
            if held == id then
                return true
            end
        end
        return false
    end
    function player:GetTrinket(slot)
        return self.trinkets[slot + 1] or 0
    end
    function player:TryRemoveTrinket(id)
        for i, held in ipairs(self.trinkets) do
            if held == id then
                table.remove(self.trinkets, i)
                return true
            end
        end
        return false
    end
    function player:AddTrinket(id, first)
        assert(not first)
        table.insert(self.trinkets, 1, id)
    end
    function player:UseActiveItem(id, flags)
        assert(scope == self.ControllerIndex - 1 and id == 479 and flags == 267)
        assert(#self.trinkets == 1 and self.trinkets[1] == 88)
        self.swallowed[88] = (self.swallowed[88] or 0) + 1
        self.trinkets = {}
        smelts = smelts + 1
    end
    function player:GetActiveItem(slot)
        return self.active[slot] or 0
    end
    function player:GetSprite()
        return self
    end
    function player:FlushQueueItem() end
    function player:AnimateCollectible(id)
        self.animated = id
    end
end
local level = {
    GetStage = function()
        return stage
    end,
    GetStageType = function()
        return kind
    end,
}
local native = {
    api_info = function()
        return info
    end,
    net_challenges = function()
        return { ["1002"] = { id = 1002, version = 1, route = "mom" } }
    end,
    api_actors = function()
        local result = {}
        for i = 1, #players do
            result[i] =
                { owner = players[i].ControllerIndex, index = i - 1, role = i > 4 and 2 or 1 }
        end
        return result
    end,
    rooms_with_player = function(slot, callback, actorOnly)
        assert(scope == nil and actorOnly == 1)
        scope = slot
        callback()
        scope = nil
        return true
    end,
    items_collectible_name = function(id)
        return configItems[id].Name
    end,
    items_give_collectible = function(player, id, charge, first, data, pool)
        assert(scope == player.ControllerIndex - 1)
        grants[#grants + 1] =
            { slot = scope, id = id, charge = charge, first = first, data = data, pool = pool }
        player.items[id] = (player.items[id] or 0) + 1
        return true
    end,
    items_take_collectible = function(player, id)
        assert(scope == player.ControllerIndex - 1 and player.items[id] > 0)
        player.items[id] = player.items[id] - 1
        takes[#takes + 1] = { slot = scope, id = id }
        return player.charge[id] or 0, 17, 5
    end,
}
local deps = {
    native = native,
    player = function(index)
        return players[index + 1]
    end,
    config = function()
        return config
    end,
    items = {
        count = function(player, id)
            return player.items[id] or 0
        end,
        extraCollectibles = function()
            return { -1 }
        end,
    },
    game = function()
        return {
            GetLevel = function()
                return level
            end,
            GetSeeds = function()
                return {
                    GetStageSeed = function()
                        return seed
                    end,
                }
            end,
            GetItemPool = function()
                return {
                    ForceAddPillEffect = function(_, id)
                        assert(id == 6)
                        return 9
                    end,
                }
            end,
            GetRoom = function()
                return {
                    GetCenterPos = function()
                        return 20
                    end,
                    FindFreePickupSpawnPosition = function(_, pos)
                        assert(pos == 20)
                        return 30
                    end,
                }
            end,
        }
    end,
    zero = function()
        return 0
    end,
    spawn = function(entity, variant, color, position, velocity, spawner)
        assert(
            entity == 5
                and variant == 70
                and color == 9
                and position == 30
                and velocity == 0
                and spawner == nil
        )
        local pill = { Price = 5, AutoUpdatePrice = true, OptionsPickupIndex = 1 }
        function pill:ToPickup()
            return self
        end
        function pill:Morph(t, v, c, price, keepSeed, ignore)
            assert(t == 5 and v == 70 and c == 9 and not price and keepSeed and ignore)
        end
        pills[#pills + 1] = pill
        return pill
    end,
    enums = {
        item = { ITEM_ACTIVE = 3 },
        trinket = { TRINKET_NO = 88 },
        collectible = { COLLECTIBLE_SMELTER = 479 },
        use = { USE_NOANIM = 1, USE_NOCOSTUME = 2, USE_ALLOWNONMAIN = 8, USE_NOANNOUNCER = 256 },
        active = { SLOT_PRIMARY = 0, SLOT_SECONDARY = 1 },
        stageType = { STAGETYPE_REPENTANCE = 4 },
        pill = { PILLEFFECT_LUCK_UP = 6 },
        pickup = { PICKUP_PILL = 70 },
        entity = { ENTITY_PICKUP = 5 },
    },
    chat = {
        output = function(text, options)
            assert(options.audience == "party")
            messages[#messages + 1] = { text = text, owner = options.owner }
        end,
        roll = function(slot, sides)
            assert(sides == 100)
            draws = draws + 1
            return rolls[slot + 1] or 50
        end,
    },
    random = function(n)
        assert(n >= 1)
        return 1
    end,
}
deps.allocation = dofile(root .. "/src/bridge/compat/rules/loot_roll.lua")(deps)
local effect = factory(deps)
local function makeRule()
    return coordinator({
        native = native,
        effects = { [1002] = effect },
        game = function()
            return {
                GetLevel = function()
                    return level
                end,
            }
        end,
        routes = {
            mom = {
                pickup = function() end,
                handles = function()
                    return false
                end,
            },
        },
    })
end
local rule = makeRule()
local function pickup(owner, id, charge, touched, data, pool)
    return rule.collect(
        owner,
        players[owner + 1].InitSeed,
        id or 1,
        charge or 0,
        touched or false,
        data or 0,
        pool or 0
    )
end
-- The registered native pickup callback is the only acquisition input. Startup
-- items and inventory reconciliation do not call it; every confirmed copy does.
for _, field in ipairs({ "active", "authority", "ready", "challenge" }) do
    local previous = info[field]
    info[field] = 0
    assert(not pickup(0))
    rule.clearAward()
    rule.step()
    info[field] = previous
end
assert(draws == 0 and #grants == 0 and #pills == 0)
players[1].trinkets = { 32776, 9 }
players[5] = setmetatable(
    { ControllerIndex = 1, InitSeed = 998, trinkets = {}, swallowed = {} },
    { __index = players[1] }
)
rule.step() -- Initial floor never takes an item.
assert(smelts == 5 and players[1]:GetTrinket(0) == 32776 and players[1]:GetTrinket(1) == 9)
for _, player in ipairs(players) do
    assert(player.swallowed[88] == 1)
end
rule.step()
assert(smelts == 5, "Repeated state swallowed No! twice")
players[5] = nil
assert(not pickup(0, 2, 7), "Active pickup must use the native queue without a roll")
assert(draws == 0)
players[1].Luck, players[2].Luck, players[3].Luck, players[4].Luck = -5, 1.5, 20, -2
rolls = { 100, 99, 90, 100 }
assert(pickup(0, 1, 7, false, 11, 8))
assert(#grants == 0) -- no mutation inside native collision/room scope
rule.step()
assert(draws == 4 and #grants == 1 and grants[1].slot == 2 and grants[1].id == 1)
assert(grants[1].charge == 7 and grants[1].data == 11 and grants[1].pool == 8 and grants[1].first)
assert(messages[1].text == "P1 拾取到了野生的 洋葱！")
assert(messages[2].text == "P3【90+20=110】获得了道具 洋葱！")
rule.step()
assert(draws == 4 and #grants == 1, "Repeated authority step rerolled an acquisition")
assert(pickup(0, 1, 0, true) and pickup(0, 1, 0, true))
rule.step()
assert(#grants == 3 and not grants[2].first and not grants[3].first)
-- Offline, dead and ghost seats cannot receive inventory; linked actors do not
-- add a second roll for the same owner.
info.connected = 7
players[1].ghost, players[2].alive = true, false
assert(pickup(2))
rule.step()
assert(draws == 13 and grants[4].slot == 2)
players[1].ghost, players[2].alive, info.connected = false, true, 15
local twin = setmetatable(
    { ControllerIndex = 1, InitSeed = 999, items = {}, active = {}, charge = {} },
    { __index = players[1] }
)
players[5] = twin
local before = draws
assert(pickup(0))
rule.step()
assert(draws == before + 4)
players[5] = nil
-- Same scores still choose distinct extremes, with randomized tie order.
for _, player in ipairs(players) do
    player.Luck, player.items, player.active = 0, {}, {}
end
rolls = { 50, 50, 50, 50 }
players[2].items[1] = 2
players[2].items[4], players[2].active[2] = 1, 4
stage, seed = 2, 456
rule.level()
rule.step()
assert(#takes == 1 and takes[1].slot == 1 and takes[1].id == 1)
assert(grants[#grants].slot == 0 and not grants[#grants].first)
assert(players[2].items[1] == 1 and players[2].items[4] == 1)
local priorTakes, priorDraws = #takes, draws
rule.level()
rule.step()
rule.step()
assert(#takes == priorTakes and draws == priorDraws, "Duplicate new-level callback taxed twice")
-- Regeneration, hourglass epoch changes and ascending floors are not descents.
seed = 457
info.worldEpoch = 99
rule.level()
rule.step()
stage, seed = 1, 123
rule.level()
rule.step()
assert(#takes == priorTakes and draws == priorDraws)
-- Native active-item transfer preserves charge and per-item state; no pocket active.
for _, player in ipairs(players) do
    player.items = {}
end
players[2].items[2], players[2].active[1], players[2].charge[2] = 1, 2, 9
players[2].items[4], players[2].active[2] = 1, 4
stage, seed = 3, 789
rule.level()
rule.step()
assert(takes[#takes].id == 2 and grants[#grants].charge == 9 and grants[#grants].data == 17)
assert(grants[#grants].pool == 5 and not grants[#grants].first)
-- An empty loser does not debit a different player or reroll the party.
players[2].items, players[2].active = {}, {}
priorTakes, priorDraws = #takes, draws
stage, seed = 4, 888
rule.level()
rule.step()
assert(#takes == priorTakes and draws == priorDraws + 4)
-- Each real clear award adds exactly one independent, free Luck Up pill.
rule.clearAward()
rule.clearAward()
assert(#pills == 2)
for _, pill in ipairs(pills) do
    assert(pill.Price == 0 and not pill.AutoUpdatePrice and pill.OptionsPickupIndex == 0)
end
info.authority = 0
rule.clearAward()
rule.step()
assert(#pills == 2)
info.authority = 1
-- Exit/new-run cleanup cannot leak a pending grant or tax the first floor.
assert(pickup(0))
priorDraws = draws
local priorSmelts = smelts
rule.reset()
info.runId = "second"
for _, player in ipairs(players) do
    player.swallowed = {}
end
rule.step()
assert(draws == priorDraws and smelts == priorSmelts + 4)
assert(pickup(0))
info.challenge = 0
rule.step()
info.challenge, info.runId = 1002, "third"
rule.step()
assert(draws == priorDraws)
-- Replica initialization creates only the fixed starting effect, never rolls.
rule.reset()
info.authority = 0
players[1].swallowed = {}
priorSmelts = smelts
rule.view()
rule.view()
assert(smelts == priorSmelts + 1 and draws == priorDraws)
assert(players[1]:GetTrinket(0) == 32776 and players[1]:GetTrinket(1) == 9)
rule.reset() -- Reconnected native checkpoint already carries its swallowed copy.
rule.view()
assert(smelts == priorSmelts + 1)
print(
    "PASS luck challenge acquisition, corrections, ties, actors, floors, actives, pills and cleanup"
)

-- The same engine powers a normal room rule, without swallowing No!, luck
-- modifiers or floor transfers. Actives remain in the native pickup queue.
info.authority, info.challenge, info.roomOptions, info.worldEpoch = 1, 0, 4, 1
native.net_room_options = function()
    return {
        { key = "lootRoll", flag = 4 },
        { key = "sharedClearCharge", flag = 2 },
        { key = "specialRoomGather", flag = 8 },
    }
end
local ordinary = dofile(root .. "/src/bridge/runtime/room_rules.lua")({
    native = native,
    allocation = deps.allocation,
    gather = {
        reset = function() end,
        step = function()
            error("Gather rule is off")
        end,
    },
    charge = {
        reset = function() end,
        step = function()
            error("Charge rule is off")
        end,
    },
})
players[1].Luck, players[2].Luck = -1000, 1000
rolls = { 100, 1, 2, 3 }
local oldSmelts, oldTakes, oldGrants = smelts, #takes, #grants
assert(
    not ordinary.collect(0, players[1].InitSeed, 2, 7, true, 11, 8),
    "Active pickup must remain native"
)
assert(ordinary.collect(0, players[1].InitSeed, 1, 7, true, 11, 8))
ordinary.step()
assert(#grants == oldGrants + 1 and grants[#grants].slot == 0)
assert(grants[#grants].charge == 7 and not grants[#grants].first and grants[#grants].data == 11)
assert(messages[#messages].text:find("P1【100】", 1, true))
assert(smelts == oldSmelts and #takes == oldTakes)
ordinary.step()
assert(#grants == oldGrants + 1, "Rule rerolled an acquisition")
assert(ordinary.collect(0, players[1].InitSeed, 1, 0, false, 0, 0))
info.worldEpoch = 2
ordinary.step()
assert(#grants == oldGrants + 1, "Rewind retained a pending grant")
info.authority = 0
assert(not ordinary.collect(0, 1, 1, 0, false, 0, 0))
ordinary.step()
info.authority, info.roomOptions = 1, 0
assert(not ordinary.collect(0, 1, 1, 0, false, 0, 0))
print(
    "PASS loot rule no-luck allocation and native active pickup, authority, single grant and epoch cleanup"
)
