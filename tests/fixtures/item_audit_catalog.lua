-- Read the tested game's actual registry, including valid hidden/internal IDs.
return function(report)
    local config, count = Isaac.GetItemConfig(), 0
    local groups = {
        {
            "collectible",
            config:GetCollectibles(),
            "GetCollectible",
            CollectibleType,
            PickupVariant.PICKUP_COLLECTIBLE,
            1,
        },
        {
            "trinket",
            config:GetTrinkets(),
            "GetTrinket",
            TrinketType,
            PickupVariant.PICKUP_TRINKET,
            1,
        },
        { "card", config:GetCards(), "GetCard", Card, PickupVariant.PICKUP_TAROTCARD, 1 },
        {
            "pill",
            config:GetPillEffects(),
            "GetPillEffect",
            PillEffect,
            PickupVariant.PICKUP_PILL,
            0,
        },
    }
    for _, group in ipairs(groups) do
        local names = {}
        for name, id in pairs(group[4]) do
            if type(id) == "number" then
                names[id] = name
            end
        end
        for id = group[6], group[2].Size - 1 do
            local value = config[group[3]](config, id)
            if value then
                local item = {
                    key = group[1] .. ":" .. id,
                    kind = group[1],
                    id = id,
                    name = value.Name,
                    enum = names[id],
                    entity_type = EntityType.ENTITY_PICKUP,
                    entity_variant = group[5],
                }
                if group[1] == "pill" then
                    -- Subtype is a run-dependent color, NOT the pill effect ID.
                    item.entity_subtype = "color"
                else
                    item.entity_subtype = id
                end
                if group[1] == "collectible" or group[1] == "trinket" then
                    item.item_type, item.hidden = value.Type, value.Hidden
                    item.max_charges = value.MaxCharges
                end
                report("catalog", { item = item })
                count = count + 1
            end
        end
    end
    report("catalog_end", { count = count })
end
