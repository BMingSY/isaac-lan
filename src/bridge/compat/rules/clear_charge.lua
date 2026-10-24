-- Share only the charging part of native clear events. Replaying TriggerRoomClear
-- would also flip Lazarus, heal, spawn rewards and run other unrelated effects.
return function(deps)
    local native, enums = deps.native, deps.enums
    local pending, byRoom = {}, {}
    local function reset()
        pending, byRoom = {}, {}
    end
    local function record(owner, dimension, index)
        local game = deps.game()
        local key = table.concat({ game:GetFrameCount(), dimension, index }, ":")
        local event = byRoom[key]
        if not event then
            local room = game:GetRoom()
            local shape = room:GetRoomShape()
            local large = shape >= enums.shape.ROOMSHAPE_2x2 and shape <= enums.shape.ROOMSHAPE_LBR
            event = {
                charged = {},
                amount = room:GetType() ~= enums.room.ROOM_BOSSRUSH and large and 2 or 1,
            }
            byRoom[key] = event
            pending[#pending + 1] = event
        end
        -- Native may call once for each body or include the complete roster.
        -- Each recipient already covered by the engine is excluded from sharing.
        event.charged[owner] = true
    end
    local function charge(player, amount)
        if
            player:HasTrinket(enums.trinket.TRINKET_OLD_CAPACITOR)
            or player:HasCollectible(enums.collectible.COLLECTIBLE_4_5_VOLT)
        then
            return
        end
        for slot = enums.active.SLOT_PRIMARY, enums.active.SLOT_POCKET2 do
            if player:GetActiveItem(slot) ~= 0 then
                local kind, maximum = native.items_active_charge(player:GetSprite(), slot)
                assert(kind, "Active charge unavailable")
                if kind == enums.charge.CHARGE_NORMAL then
                    local grant = amount
                    local watch = player:GetTrinketMultiplier(enums.trinket.TRINKET_WATCH_BATTERY)
                    for _ = 1, math.min(watch, 16) do
                        if
                            player:GetTrinketRNG(enums.trinket.TRINKET_WATCH_BATTERY):RandomInt(20)
                            == 0
                        then
                            grant = grant + watch
                        end
                    end
                    local aaa =
                        math.min(player:GetTrinketMultiplier(enums.trinket.TRINKET_AAA_BATTERY), 3)
                    if player:GetActiveCharge(slot) + grant >= maximum - aaa then
                        grant = grant + aaa
                    end
                    assert(
                        native.items_add_active_charge(player:GetSprite(), slot, grant),
                        "Clear charge failed"
                    )
                elseif kind == enums.charge.CHARGE_TIMED then
                    player:FullCharge(slot, false)
                end
            end
        end
    end
    local function step(info)
        local events = pending
        pending, byRoom = {}, {}
        for _, event in ipairs(events) do
            for _, seat in ipairs(deps.party(info)) do
                if not event.charged[seat.slot] then
                    deps.scoped(seat, function()
                        for _, player in ipairs(seat.actors) do
                            charge(player, event.amount)
                        end
                    end)
                end
            end
        end
    end
    return { reset = reset, record = record, step = step }
end
