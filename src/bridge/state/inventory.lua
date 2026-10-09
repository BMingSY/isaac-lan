-- Inventory reconciliation, using only the supplied player/config interface.
return function(env)
    local heartTypes = {
        "BrokenHearts",
        "MaxHearts",
        "BoneHearts",
        "Hearts",
        "RottenHearts",
        "EternalHearts",
        "GoldenHearts",
    }
    local function inventory(p)
        local items = {}
        local config = env.config()
        for item = 1, config:GetCollectibles().Size - 1 do
            -- J460's ghost branch dereferences the ItemConfig even for unused IDs.
            if config:GetCollectible(item) then
                local count = p:GetCollectibleNum(item, true)
                if count > 0 then
                    items[#items + 1] = { item, count }
                end
            end
        end
        local active = {}
        for slot = 0, 3 do
            active[#active + 1] =
                { p:GetActiveItem(slot), p:GetActiveCharge(slot) + p:GetBatteryCharge(slot) }
        end
        local hearts = {}
        for _, name in ipairs(heartTypes) do
            hearts[#hearts + 1] = p["Get" .. name](p)
        end
        hearts[#hearts + 1] = p:GetSoulHearts()
        hearts[#hearts + 1] = p:GetBlackHearts()
        return {
            p:GetPlayerType(),
            items,
            active,
            hearts,
            {
                p:GetNumCoins(),
                p:GetNumBombs(),
                p:GetNumKeys(),
                p:GetSoulCharge(),
                p:GetBloodCharge(),
            },
            { p:GetTrinket(0), p:GetTrinket(1) },
            { p:GetCard(0), p:GetCard(1) },
            { p:GetPill(0), p:GetPill(1) },
            p:IsCoopGhost(),
            p:GetEffects():GetNullEffectNum(env.curse),
        }
    end
    local function applyInventory(p, v, refreshItems)
        if v[9] then
            return
        end -- Native ghost conversion owns its hidden inventory.
        if p:GetPlayerType() ~= v[1] then
            p:ChangePlayerType(v[1])
        end
        local effects = p:GetEffects()
        local delta = v[10] - effects:GetNullEffectNum(env.curse)
        if delta ~= 0 then
            if delta > 0 then
                effects:AddNullEffect(env.curse, true, delta)
            else
                effects:RemoveNullEffect(env.curse, -delta)
            end
        end
        if refreshItems then
            local desired = {}
            for _, entry in ipairs(v[2]) do
                desired[entry[1]] = entry[2]
            end
            local config = env.config()
            for item = 1, config:GetCollectibles().Size - 1 do
                local itemConfig = config:GetCollectible(item)
                if itemConfig and itemConfig.Type ~= env.activeType then
                    local difference = (desired[item] or 0) - p:GetCollectibleNum(item, true)
                    for _ = 1, math.abs(difference) do
                        if difference > 0 then
                            p:AddCollectible(item, 0, false)
                        else
                            p:RemoveCollectible(item, true)
                        end
                    end
                end
            end
        end
        for i, active in ipairs(v[3]) do
            local slot = i - 1
            if p:GetActiveItem(slot) ~= active[1] then
                if p:GetActiveItem(slot) ~= 0 then
                    p:RemoveCollectible(p:GetActiveItem(slot), true, slot)
                end
                if active[1] ~= 0 then
                    if slot >= 2 then
                        p:SetPocketActiveItem(active[1], slot, true)
                    else
                        p:AddCollectible(active[1], 0, false, slot)
                    end
                end
            end
            p:SetActiveCharge(active[2], slot)
        end
        for slot = 0, 1 do
            if p:GetTrinket(slot) ~= v[6][slot + 1] then
                for i = 0, 1 do
                    local t = p:GetTrinket(i)
                    if t ~= 0 then
                        p:TryRemoveTrinket(t)
                    end
                end
                -- AddTrinket puts the newest trinket in the first slot.
                for i = 2, 1, -1 do
                    if v[6][i] ~= 0 then
                        p:AddTrinket(v[6][i], false)
                    end
                end
                break
            end
        end
        for _, pair in ipairs({ { "Coins", 1 }, { "Bombs", 2 }, { "Keys", 3 } }) do
            p["Add" .. pair[1]](p, v[5][pair[2]] - p["GetNum" .. pair[1]](p))
        end
        p:AddSoulCharge(v[5][4] - p:GetSoulCharge())
        p:AddBloodCharge(v[5][5] - p:GetBloodCharge())
        for i, name in ipairs(heartTypes) do
            local delta = v[4][i] - p["Get" .. name](p)
            if delta ~= 0 then
                p["Add" .. name](p, delta)
            end
        end
        local souls, black = v[4][8], v[4][9]
        if p:GetSoulHearts() ~= souls or p:GetBlackHearts() ~= black then
            p:AddSoulHearts(-p:GetSoulHearts())
            for offset = 0, souls - 1, 2 do
                local count = math.min(2, souls - offset)
                if (black & (1 << (offset // 2))) ~= 0 then
                    p:AddBlackHearts(count)
                else
                    p:AddSoulHearts(count)
                end
            end
        end
        for slot = 0, 1 do
            if p:GetCard(slot) ~= v[7][slot + 1] then
                p:SetCard(slot, v[7][slot + 1])
            end
            if v[7][slot + 1] == 0 and p:GetPill(slot) ~= v[8][slot + 1] then
                p:SetPill(slot, v[8][slot + 1])
            end
        end
    end
    return { capture = inventory, apply = applyInventory }
end
