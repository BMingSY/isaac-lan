return function(fields)
    local Inventory, Item, Active = fields.inventory, fields.item, fields.active
    local Resource, Heart = fields.resources, fields.hearts
    local LAST_ACTIVE_SLOT, FIRST_POCKET_ACTIVE_SLOT, LAST_POCKET_SLOT = 3, 2, 1
    -- Inventory reconciliation, using only the supplied player/config interface.
    return function(env)
        local count = env.collectibleCount
            or function(p, item)
                return p:GetCollectibleNum(item, true)
            end
        local function eachCollectible(config, visit)
            for item = 1, config:GetCollectibles().Size - 1 do
                local value = config:GetCollectible(item)
                if value then
                    visit(item, value)
                end
            end
            for _, item in ipairs(env.extraCollectibles and env.extraCollectibles(config) or {}) do
                visit(item, assert(config:GetCollectible(item)))
            end
        end
        local heartTypes = {
            { field = Heart.broken, name = "BrokenHearts" },
            { field = Heart.max, name = "MaxHearts" },
            { field = Heart.bone, name = "BoneHearts" },
            { field = Heart.red, name = "Hearts" },
            { field = Heart.rotten, name = "RottenHearts" },
            { field = Heart.eternal, name = "EternalHearts" },
            { field = Heart.golden, name = "GoldenHearts" },
        }
        local sharedResources = {
            { name = "Coins", field = Resource.coins },
            { name = "Bombs", field = Resource.bombs },
            { name = "Keys", field = Resource.keys },
        }
        local sharedFlags = {
            { name = "GoldenBomb", field = Resource.goldenBomb },
            { name = "GoldenKey", field = Resource.goldenKey },
        }
        local function inventory(p)
            local items = {}
            local config = env.config()
            eachCollectible(config, function(item)
                local owned = count(p, item)
                if owned > 0 then
                    items[#items + 1] = { item, owned } -- Item.id, Item.count
                end
            end)
            local active = {}
            for slot = 0, LAST_ACTIVE_SLOT do
                active[#active + 1] = {
                    p:GetActiveItem(slot), -- Active.id
                    p:GetActiveCharge(slot) + p:GetBatteryCharge(slot), -- Active.charge
                }
            end
            local hearts = {}
            for _, heart in ipairs(heartTypes) do
                hearts[heart.field] = p["Get" .. heart.name](p)
            end
            hearts[Heart.soul] = p:GetSoulHearts()
            hearts[Heart.black] = p:GetBlackHearts()
            return {
                [Inventory.type] = p:GetPlayerType(),
                [Inventory.items] = items,
                [Inventory.active] = active,
                [Inventory.hearts] = hearts,
                [Inventory.resources] = {
                    p:GetNumCoins(), -- Resource.coins
                    p:GetNumBombs(), -- Resource.bombs
                    p:GetNumKeys(), -- Resource.keys
                    p:GetSoulCharge(), -- Resource.soulCharge
                    p:GetBloodCharge(), -- Resource.bloodCharge
                    p:HasGoldenBomb(), -- Resource.goldenBomb
                    p:HasGoldenKey(), -- Resource.goldenKey
                },
                [Inventory.trinkets] = { p:GetTrinket(0), p:GetTrinket(1) },
                [Inventory.cards] = { p:GetCard(0), p:GetCard(1) },
                [Inventory.pills] = { p:GetPill(0), p:GetPill(1) },
                [Inventory.ghost] = p:IsCoopGhost(),
                [Inventory.curse] = p:GetEffects():GetNullEffectNum(env.curse),
                [Inventory.pockets] = env.pockets and env.pockets(p) or false,
            }
        end
        local function applyResources(p, v)
            -- Resources are shared by native co-op, including its hidden ghost
            -- inventory. Conversion alone cannot restore a newer authority value.
            for _, pair in ipairs(sharedResources) do
                p["Add" .. pair.name](
                    p,
                    v[Inventory.resources][pair.field] - p["GetNum" .. pair.name](p)
                )
            end
            for _, flag in ipairs(sharedFlags) do
                local desired = v[Inventory.resources][flag.field]
                if p["Has" .. flag.name](p) ~= desired then
                    p[(desired and "Add" or "Remove") .. flag.name](p)
                end
            end
        end
        local function applyInventory(p, v, refreshItems)
            if v[Inventory.ghost] then
                applyResources(p, v)
                return
            end -- Native ghost conversion owns its hidden inventory.
            if p:GetPlayerType() ~= v[Inventory.type] then
                p:ChangePlayerType(v[Inventory.type])
            end
            local effects = p:GetEffects()
            local delta = v[Inventory.curse] - effects:GetNullEffectNum(env.curse)
            if delta ~= 0 then
                if delta > 0 then
                    effects:AddNullEffect(env.curse, true, delta)
                else
                    effects:RemoveNullEffect(env.curse, -delta)
                end
            end
            if refreshItems then
                local desired = {}
                for _, entry in ipairs(v[Inventory.items]) do
                    desired[entry[Item.id]] = entry[Item.count]
                end
                local config = env.config()
                eachCollectible(config, function(item, itemConfig)
                    if itemConfig.Type ~= env.activeType then
                        local difference = (desired[item] or 0) - count(p, item)
                        for _ = 1, math.abs(difference) do
                            if difference > 0 then
                                p:AddCollectible(item, 0, false)
                            else
                                p:RemoveCollectible(item, true)
                            end
                        end
                    end
                end)
            end
            for i, active in ipairs(v[Inventory.active]) do
                local slot = i - 1
                if p:GetActiveItem(slot) ~= active[Active.id] then
                    if p:GetActiveItem(slot) ~= 0 then
                        p:RemoveCollectible(p:GetActiveItem(slot), true, slot)
                    end
                    if active[Active.id] ~= 0 then
                        if slot >= FIRST_POCKET_ACTIVE_SLOT then
                            p:SetPocketActiveItem(active[Active.id], slot, true)
                        else
                            p:AddCollectible(active[Active.id], 0, false, slot)
                        end
                    end
                end
                p:SetActiveCharge(active[Active.charge], slot)
            end
            for slot = 0, LAST_POCKET_SLOT do
                if p:GetTrinket(slot) ~= v[Inventory.trinkets][slot + 1] then
                    for i = 0, LAST_POCKET_SLOT do
                        local t = p:GetTrinket(i)
                        if t ~= 0 then
                            p:TryRemoveTrinket(t)
                        end
                    end
                    -- AddTrinket puts the newest trinket in the first slot.
                    for i = LAST_POCKET_SLOT + 1, 1, -1 do
                        if v[Inventory.trinkets][i] ~= 0 then
                            p:AddTrinket(v[Inventory.trinkets][i], false)
                        end
                    end
                    break
                end
            end
            applyResources(p, v)
            p:AddSoulCharge(v[Inventory.resources][Resource.soulCharge] - p:GetSoulCharge())
            p:AddBloodCharge(v[Inventory.resources][Resource.bloodCharge] - p:GetBloodCharge())
            for _, heart in ipairs(heartTypes) do
                local delta = v[Inventory.hearts][heart.field] - p["Get" .. heart.name](p)
                if delta ~= 0 then
                    p["Add" .. heart.name](p, delta)
                end
            end
            local souls, black = v[Inventory.hearts][Heart.soul], v[Inventory.hearts][Heart.black]
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
            for slot = 0, LAST_POCKET_SLOT do
                if p:GetCard(slot) ~= v[Inventory.cards][slot + 1] then
                    p:SetCard(slot, v[Inventory.cards][slot + 1])
                end
                if
                    v[Inventory.cards][slot + 1] == 0
                    and p:GetPill(slot) ~= v[Inventory.pills][slot + 1]
                then
                    p:SetPill(slot, v[Inventory.pills][slot + 1])
                end
            end
            if v[Inventory.pockets] then
                assert(
                    env.pockets and env.pockets(p, v[Inventory.pockets]),
                    "Cannot restore ordered pocket items"
                )
            end
        end
        return { capture = inventory, apply = applyInventory }
    end
end
