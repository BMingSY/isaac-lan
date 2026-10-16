-- Explicit synthetic load, not an assertion about every item combination.
return function(report)
    local captured
    local function reset()
        captured = { render = {}, capture = {}, apply = {}, raw_bytes = {} }
    end
    reset()
    local function record(name, value)
        captured[name][#captured[name] + 1] = value
    end
    local function finish()
        local values = {}
        for name, samples in pairs(captured) do
            if #samples > 0 then
                table.sort(samples)
                local sum, over33, over50 = 0, 0, 0
                for _, value in ipairs(samples) do
                    sum = sum + value
                    over33 = over33 + (value > 1000 / 30 and 1 or 0)
                    over50 = over50 + (value > 50 and 1 or 0)
                end
                values[name] = {
                    count = #samples,
                    mean = sum / #samples,
                    p50 = samples[math.ceil(#samples * 0.5)],
                    p95 = samples[math.ceil(#samples * 0.95)],
                    p99 = samples[math.ceil(#samples * 0.99)],
                    max = samples[#samples],
                    over33 = over33,
                    over50 = over50,
                }
            end
        end
        report("metrics", values)
        reset()
    end
    local function prepare(case, p, room)
        local began = Isaac.GetTime()
        for _, id in ipairs(case.loadout or {}) do
            p:AddCollectible(id, 0, true)
        end
        for _ = 1, case.copies or 0 do
            p:AddCollectible(CollectibleType.COLLECTIBLE_BREAKFAST, 0, true)
        end
        -- Capacity probe: keep native entities alive without ending the run.
        p:SetMinDamageCooldown(100000)
        for i = 1, (case.tears or 0) + (case.projectiles or 0) do
            local position = room:GetCenterPos()
                + Vector((i % 29 - 14) * 14, (math.floor(i / 29) % 17 - 8) * 12)
            local entity
            if i <= (case.tears or 0) then
                entity = p:FireTear(position, Vector.Zero, false, true, false, p, 1)
                entity.FallingAcceleration = -0.1
            else
                entity = Isaac.Spawn(EntityType.ENTITY_PROJECTILE, 0, 0, position, Vector.Zero, nil)
                    :ToProjectile()
                entity.FallingAccel = -0.1
            end
            entity.Height, entity.FallingSpeed = -30, 0
            entity.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
            entity.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        end
        report("stress_prepared", {
            duration_ms = Isaac.GetTime() - began,
            inventory = p:GetCollectibleCount(),
            distinct = #(case.loadout or {}),
            tears = case.tears or 0,
            projectiles = case.projectiles or 0,
        })
    end
    return { prepare = prepare, record = record, finish = finish }
end
