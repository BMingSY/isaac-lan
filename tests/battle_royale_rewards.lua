local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/compat/challenges/battle_royale_rewards.lua")
local chaos, pool, config = 0, {}, {}
local player = {
    AddCollectible = function(_, id, charge, first)
        assert(id == 402 and charge == 0 and not first)
        chaos = chaos + 1
    end,
    RemoveCollectible = function(_, id)
        assert(id == 402)
        chaos = chaos - 1
    end,
}
local entities, rolls, commits, draws, failure = {}, { 1, 100, 2 }, {}, 0
local function pedestal(id, seed)
    return {
        Type = 5,
        Variant = 100,
        SubType = id,
        InitSeed = seed,
        ToPickup = function(self)
            return self
        end,
        Morph = function(self, _, _, value)
            if failure == "morph" then
                error("morph failed")
            end
            self.SubType = value
        end,
    }
end
function config:GetCollectible(id)
    return { Quality = id == 100 and 4 or id == 345 and 3 or 0 }
end
function pool:GetCollectible(kind, decrease, seed)
    assert(kind == 0 and chaos > 0, "Native draw must observe Chaos")
    if failure == "draw" then
        error("draw failed")
    end
    if decrease then
        commits[#commits + 1] = seed
    end
    return rolls[seed]
end
local reward = factory({
    enums = {
        collectible = { COLLECTIBLE_CHAOS = 402, COLLECTIBLE_SYNTHOIL = 345 },
        pool = { POOL_TREASURE = 0 },
        entity = { ENTITY_PICKUP = 5 },
        pickup = { PICKUP_COLLECTIBLE = 100 },
    },
    game = function()
        return {
            GetItemPool = function()
                return pool
            end,
            GetRoom = function()
                return {
                    GetCenterPos = function()
                        return {}
                    end,
                    FindFreePickupSpawnPosition = function(_, pos)
                        return pos
                    end,
                }
            end,
        }
    end,
    config = function()
        return config
    end,
    random = function()
        draws = draws + 1
        return draws
    end,
    entities = function()
        return entities
    end,
    vector = function()
        return {}
    end,
    spawn = function(_, _, id)
        if failure == "spawn" then
            error("spawn failed")
        end
        entities[#entities + 1] = pedestal(id, 1)
    end,
})
-- Even an already high-quality boss reward is rerolled across pools; extra
-- rewards may remain low quality. Non-collectible resources are untouched.
local base, extra, coin =
    pedestal(345, 1), pedestal(345, 2), { Type = 5, Variant = 20, SubType = 1 }
entities = { extra, coin, base }
reward(player)
assert(base.SubType == 100 and extra.SubType == 2 and coin.SubType == 1)
assert(
    #commits == 2 and commits[1] == 2 and commits[2] == 3,
    "Rejected draws must not consume weight"
)
assert(chaos == 0)
chaos, entities, draws = 1, {}, 0
reward(player)
assert(#entities == 1 and entities[1].SubType == 100 and chaos == 1)
for _, stage in ipairs({ "draw", "morph", "spawn" }) do
    failure, draws = stage, 0
    entities = stage == "spawn" and {} or { pedestal(345, 1) }
    local ok = pcall(reward, player)
    assert(not ok and chaos == 1, "A failed reward must preserve only the original Chaos")
end
print("PASS Chaos rewards, base quality, unrestricted extras and failure cleanup")
