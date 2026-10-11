-- Item metadata and budgets only; collection and effects stay native.
local items = {}
function items.score(meta, actor)
    if meta.active or meta.quest or meta.maxHearts < 0 then
        return nil
    end
    local value = meta.quality * 20 + (meta.damage and 30 or 0) + (meta.fireRate and 20 or 0)
    value = value + math.max(0, meta.maxHearts) * 8
    if actor.needsHeal then
        value = value + math.max(0, meta.hearts + meta.soulHearts) * 8
    end
    local owned = actor.owned
    if owned == nil then
        owned = meta.owned
    end
    if owned then
        value = value * ((meta.damage or meta.fireRate or meta.maxHearts > 0) and 0.5 or 0.25)
    end
    return value > 0 and value or nil
end
function items.recipient(meta, party, price)
    local best, bestValue, bestRank
    for _, actor in ipairs(party) do
        local value = actor.available ~= false and items.score(meta, actor) or nil
        if value and (price <= 0 or items.affordable(value, price, actor)) then
            -- Balance equipment while retaining item-specific value: healing
            -- and redundant items can benefit otherwise equal actors differently.
            local rank = value / (5 + math.max(0, actor.items or 0))
            if not bestRank or rank > bestRank or rank == bestRank and actor.id < best.id then
                best, bestValue, bestRank = actor, value, rank
            end
        end
    end
    return best, bestValue
end
function items.reserve(actor)
    return (actor.keys < 1 and 5 or 0)
        + (
            actor.needsHeal
                and math.min(12, math.max(3, math.ceil((actor.redDeficit or 1) / 2) * 3))
            or 0
        )
end
function items.affordable(value, price, actor)
    return value ~= nil
        and value >= 40
        and price > 0
        and value / price >= 2.5
        and price <= (actor.coins or 0) - items.reserve(actor)
end
return items
