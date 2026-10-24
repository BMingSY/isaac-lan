-- Authority policy. Native pickups supply confirmed acquisitions; ordinary
-- inventory snapshots replicate the resulting grants without replaying rolls.
return function(deps)
    local initialized, lastDepth, lastFloor = {}, nil, nil
    local allocation = deps.allocation
    local party, scoped, give = allocation.party, allocation.scoped, allocation.give
    local output, label, score, itemName =
        allocation.output, allocation.label, allocation.score, allocation.itemName
    local function roll(seats)
        return allocation.roll(seats, true)
    end
    local function initialize(info)
        for _, seat in ipairs(party(info)) do
            if not initialized[seat.slot] then
                scoped(seat, function()
                    for _, player in ipairs(seat.actors) do
                        -- Smelt only No!, preserving starting trinkets and their slots.
                        local held = { player:GetTrinket(0), player:GetTrinket(1) }
                        for _, id in ipairs(held) do
                            if id ~= 0 then
                                assert(player:TryRemoveTrinket(id))
                            end
                        end
                        -- A reconnect checkpoint can already contain the swallowed
                        -- effect. Held trinkets are absent here, so this checks only
                        -- the permanent copy before initializing either peer.
                        if not player:HasTrinket(deps.enums.trinket.TRINKET_NO) then
                            player:AddTrinket(deps.enums.trinket.TRINKET_NO, false)
                            local use = deps.enums.use
                            player:UseActiveItem(
                                deps.enums.collectible.COLLECTIBLE_SMELTER,
                                use.USE_NOANIM
                                    | use.USE_NOCOSTUME
                                    | use.USE_NOANNOUNCER
                                    | use.USE_ALLOWNONMAIN
                            )
                        end
                        for i = #held, 1, -1 do
                            if held[i] ~= 0 then
                                player:AddTrinket(held[i], false)
                            end
                        end
                    end
                end)
                initialized[seat.slot] = true
            end
        end
    end
    local function inventory(seat)
        local config, result = deps.config(), {}
        local function visit(player, id, value)
            local count = deps.items.count(player, id)
            if value.Type == deps.enums.item.ITEM_ACTIVE then
                -- Pocket actives belong to the character; only carried slots
                -- participate. Native removal preserves their charge and data.
                count = 0
                for slot = deps.enums.active.SLOT_PRIMARY, deps.enums.active.SLOT_SECONDARY do
                    if player:GetActiveItem(slot) == id then
                        count = count + 1
                    end
                end
            end
            for _ = 1, count do
                result[#result + 1] = { player = player, id = id }
            end
        end
        for _, player in ipairs(seat.actors) do
            for id = 1, config:GetCollectibles().Size - 1 do
                local value = config:GetCollectible(id)
                if value then
                    visit(player, id, value)
                end
            end
            for _, id in ipairs(deps.items.extraCollectibles(config)) do
                visit(player, id, config:GetCollectible(id))
            end
        end
        return result
    end
    local function level(info, level)
        local stage, kind = level:GetStage(), level:GetStageType()
        local floor = table.concat({ stage, kind, deps.game():GetSeeds():GetStageSeed(stage) }, ":")
        local depth = stage + (kind >= deps.enums.stageType.STAGETYPE_REPENTANCE and 1 or 0)
        if floor == lastFloor then
            return
        end
        local descending = lastDepth and depth > lastDepth
        lastFloor, lastDepth = floor, depth
        if not descending then
            return
        end
        local seats = party(info)
        if #seats < 2 then
            return
        end
        local winner, loser = roll(seats)
        local owned = inventory(loser)
        if #owned == 0 then
            return
        end
        local item = owned[deps.random(#owned)]
        scoped(loser, function()
            item.charge, item.data, item.pool =
                deps.native.items_take_collectible(item.player:GetSprite(), item.id)
            assert(item.charge ~= nil, "Challenge transfer failed")
        end)
        give(winner, item, false)
        output(
            winner.slot,
            label(loser.slot)
                .. "【"
                .. score(loser)
                .. "】将 "
                .. itemName(item.id)
                .. " 交给了 "
                .. label(winner.slot)
                .. "【"
                .. score(winner)
                .. "】！"
        )
    end
    local function clearAward()
        local game = deps.game()
        local color = game:GetItemPool():ForceAddPillEffect(deps.enums.pill.PILLEFFECT_LUCK_UP)
        local room = game:GetRoom()
        local position = room:FindFreePickupSpawnPosition(room:GetCenterPos(), 0, true)
        local pill = deps.spawn(
            deps.enums.entity.ENTITY_PICKUP,
            deps.enums.pickup.PICKUP_PILL,
            color,
            position,
            deps.zero(),
            nil
        ):ToPickup()
        pill:Morph(
            deps.enums.entity.ENTITY_PICKUP,
            deps.enums.pickup.PICKUP_PILL,
            color,
            false,
            true,
            true
        )
        pill.Price, pill.AutoUpdatePrice, pill.OptionsPickupIndex = 0, false, 0
    end
    return {
        reset = function()
            initialized, lastDepth, lastFloor = {}, nil, nil
            allocation.reset()
        end,
        collect = allocation.collect,
        initialize = initialize,
        step = function(info)
            initialize(info)
            allocation.step(info, true)
        end,
        level = level,
        clearAward = clearAward,
    }
end
