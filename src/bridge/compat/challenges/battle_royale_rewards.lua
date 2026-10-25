-- Use the native Chaos draw only while settling this encounter. Exploration
-- keeps its normal pools, and an already-owned Chaos copy is preserved.
return function(deps)
    local enums = deps.enums
    local ATTEMPTS, MIN_QUALITY = 128, 3
    local function draw(minimum)
        local pool, config = deps.game():GetItemPool(), deps.config()
        local fallback = enums.collectible.COLLECTIBLE_SYNTHOIL
        for _ = 1, ATTEMPTS do
            local seed = deps.random(1, 2147483646)
            local id = pool:GetCollectible(enums.pool.POOL_TREASURE, false, seed, fallback)
            local item = config:GetCollectible(id)
            if item and item.Quality >= minimum then
                id = pool:GetCollectible(enums.pool.POOL_TREASURE, true, seed, fallback)
                item = config:GetCollectible(id)
                if item and item.Quality >= minimum then
                    return id
                end
            end
        end
        assert(config:GetCollectible(fallback).Quality >= minimum)
        return fallback
    end
    return function(player)
        local chaos = enums.collectible.COLLECTIBLE_CHAOS
        player:AddCollectible(chaos, 0, false)
        local ok, reason = pcall(function()
            local pedestals = {}
            for _, entity in ipairs(deps.entities()) do
                if
                    entity.Type == enums.entity.ENTITY_PICKUP
                    and entity.Variant == enums.pickup.PICKUP_COLLECTIBLE
                then
                    pedestals[#pedestals + 1] = entity:ToPickup()
                end
            end
            table.sort(pedestals, function(a, b)
                return a.InitSeed < b.InitSeed
            end)
            if #pedestals == 0 then
                local room = deps.game():GetRoom()
                deps.spawn(
                    enums.entity.ENTITY_PICKUP,
                    enums.pickup.PICKUP_COLLECTIBLE,
                    draw(MIN_QUALITY),
                    room:FindFreePickupSpawnPosition(room:GetCenterPos(), 0, true),
                    deps.vector(0, 0),
                    nil
                )
            else
                for index, pickup in ipairs(pedestals) do
                    -- Reroll the base even when its original boss-pool item was
                    -- already quality 3. Additional rewards have no quality floor.
                    pickup:Morph(
                        enums.entity.ENTITY_PICKUP,
                        enums.pickup.PICKUP_COLLECTIBLE,
                        draw(index == 1 and MIN_QUALITY or 0),
                        true,
                        true,
                        false
                    )
                end
            end
        end)
        player:RemoveCollectible(chaos)
        if not ok then
            error(reason, 0)
        end
    end
end
