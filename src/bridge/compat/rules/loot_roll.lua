-- Confirmed pedestal acquisitions are rolled once on the authority.
-- Challenge and optional room rules supply their own luck policy.
return function(deps)
    local pending = {}
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
    local function roll(seats, luck)
        for _, seat in ipairs(seats) do
            seat.luck = luck and seat.player.Luck or 0
            seat.roll = assert(deps.chat.roll(seat.slot, DICE_SIDES), "Loot dice failed")
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
        assert(deps.native.rooms_with_player(seat.slot, fn, 1), "Loot recipient unavailable")
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
                "Loot grant failed"
            )
            player:AnimateCollectible(item.id)
        end)
    end
    local function itemName(id)
        return deps.native.items_collectible_name(id) or deps.config():GetCollectible(id).Name
    end
    local function acquired(info, luck)
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
                local winner = roll(seats, luck)
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
                        .. (luck and score(winner) or number(winner.roll))
                        .. "】获得了道具 "
                        .. name
                        .. "！"
                )
            end
        end
    end
    return {
        party = party,
        roll = roll,
        scoped = scoped,
        give = give,
        score = score,
        label = label,
        output = output,
        itemName = itemName,
        reset = function()
            pending = {}
        end,
        step = acquired,
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
    }
end
