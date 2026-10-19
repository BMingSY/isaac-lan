-- Authority policy. Native pickups supply confirmed acquisitions; ordinary
-- inventory snapshots replicate the resulting grants without replaying rolls.
return function(deps)
    local pending, initialized, lastDepth, lastFloor = {}, {}, nil, nil
    local DICE_SIDES = 100
    local function label(slot)
        return "P" .. (slot + 1)
    end
    local function output(slot, text)
        deps.chat.output(text, { owner = slot, audience = "party" })
    end
    local function number(value)
        return string.format("%g", value)
    end
    local function score(entry)
        return number(entry.roll)
            .. (entry.luck < 0 and "" or "+")
            .. number(entry.luck)
            .. "="
            .. number(entry.total)
    end
    local function party(info)
        local seats = {}
        for _, actor in ipairs(deps.native.api_actors()) do
            local slot = actor.owner - 1
            local player = deps.player(actor.index)
            if
                slot >= 0
                and slot < info.players
                and (info.connected & (1 << slot)) ~= 0
                and player:Exists()
                and not player:IsDead()
                and not player:IsCoopGhost()
            then
                local seat = seats[slot]
                if not seat then
                    seat = { slot = slot, player = player, actors = {} }
                    seats[slot] = seat
                end
                seat.actors[#seat.actors + 1] = player
            end
        end
        local result = {}
        for slot = 0, info.players - 1 do
            if seats[slot] then
                result[#result + 1] = seats[slot]
            end
        end
        return result
    end
    local function roll(seats)
        for _, seat in ipairs(seats) do
            seat.luck = seat.player.Luck
            seat.roll = assert(deps.chat.roll(seat.slot, DICE_SIDES), "Challenge dice failed")
            seat.total = seat.roll + seat.luck
        end
        -- Shuffle before a stable score ordering: every tied seat has the same
        -- chance, and the highest/lowest remain distinct when all scores tie.
        for i = #seats, 2, -1 do
            local j = deps.random(i)
            seats[i], seats[j] = seats[j], seats[i]
        end
        for i = 2, #seats do
            local value, j = seats[i], i
            while j > 1 and seats[j - 1].total > value.total do
                seats[j] = seats[j - 1]
                j = j - 1
            end
            seats[j] = value
        end
        return seats[#seats], seats[1]
    end
    local function scoped(seat, fn)
        assert(deps.native.rooms_with_player(seat.slot, fn, 1), "Challenge actor unavailable")
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
    local function give(seat, item, first, sourceSeed)
        local player = seat.player
        for _, actor in ipairs(seat.actors) do
            if actor.InitSeed == sourceSeed then
                player = actor
                break
            end
        end
        scoped(seat, function()
            player:FlushQueueItem()
            assert(
                deps.native.items_give_collectible(
                    player:GetSprite(),
                    item.id,
                    item.charge,
                    first,
                    item.data,
                    item.pool
                ),
                "Challenge grant failed"
            )
            player:AnimateCollectible(item.id)
        end)
    end
    local function itemName(id)
        return deps.native.items_collectible_name(id) or deps.config():GetCollectible(id).Name
    end
    local function acquired(info)
        local queue = pending
        pending = {}
        for _, item in ipairs(queue) do
            local seats = party(info)
            if #seats == 0 then
                -- Keep the acquisition until a live recipient is available.
                pending[#pending + 1] = item
            else
                local name = itemName(item.id)
                output(item.owner, label(item.owner) .. " 拾取到了野生的 " .. name .. "！")
                local winner = roll(seats)
                give(
                    winner,
                    item,
                    not item.touched,
                    winner.slot == item.owner and item.actorSeed or nil
                )
                output(
                    winner.slot,
                    label(winner.slot)
                        .. "【"
                        .. score(winner)
                        .. "】获得了道具 "
                        .. name
                        .. "！"
                )
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
            pending, initialized, lastDepth, lastFloor = {}, {}, nil, nil
        end,
        collect = function(owner, actorSeed, id, charge, touched, data, pool)
            local config = deps.config():GetCollectible(id)
            if not config or config.Type == deps.enums.item.ITEM_ACTIVE then
                return false
            end
            pending[#pending + 1] = {
                owner = owner,
                actorSeed = actorSeed,
                id = id,
                charge = charge,
                touched = touched,
                data = data,
                pool = pool,
            }
            return true
        end,
        initialize = initialize,
        step = function(info)
            initialize(info)
            acquired(info)
        end,
        level = level,
        clearAward = clearAward,
    }
end
