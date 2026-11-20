-- The first shop for RDQV 7PSH sells a generated collectible next to a grab bag.
local native, config = _IsaacLan, _IsaacLanTest
local frame, gate, phase = _IsaacLanFrame, native.net_gate, native.net_phases()
local challenge, collectibleLayer = 1006, 1
local renders, linked, chosen, started = 0, false, false, false
local origin, shop, destination, movedAt
local visits, inShop, sampledAt, done = 0, false, 0, false

local function checkShop()
    local collectible, sack
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity:ToPickup()
        if pickup and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            collectible = pickup
        elseif pickup and pickup.Variant == PickupVariant.PICKUP_GRAB_BAG then
            sack = pickup
        end
    end
    assert(sack and sack.Visible and sack.Price == 7, "Missing seven-cent sack")
    assert(collectible and collectible.Visible and collectible.Price == 37, "Missing shop item")
    assert(collectible.SubType == (-2 & 0xffffffff))
    local sprite = collectible:GetSprite()
    assert(sprite:GetAnimation() == "ShopIdle")
    local opaque = 0
    for y = -30, 12, 2 do
        for x = -12, 12, 2 do
            if sprite:GetTexel(Vector(x, y), Vector.Zero, 0.01, collectibleLayer).Alpha > 0 then
                opaque = opaque + 1
            end
        end
    end
    assert(opaque == 67, "Wrong generated shop icon: " .. opaque .. " opaque samples")
end

native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, ...)
        before(t, ...)
        if t < 45 or not native.rooms_ready() then
            return
        end
        local positions = native.rooms_positions()
        if not shop then
            origin = positions["0"].index
            local rooms = Game():GetLevel():GetRooms()
            for i = 0, rooms.Size - 1 do
                local room = rooms:Get(i)
                if room.Data.Type == RoomType.ROOM_SHOP then
                    shop, destination = room.SafeGridIndex, room.SafeGridIndex
                    break
                end
            end
            assert(shop, "Seed has no shop")
        end
        if positions["0"].index ~= destination or positions["1"].index ~= destination then
            for slot = 0, 1 do
                if positions[tostring(slot)].index ~= destination then
                    native.rooms_move(slot, destination, 0, -1)
                end
            end
            movedAt = t
        elseif t - movedAt >= 60 and visits < 2 then
            destination = destination == shop and origin or shop
        end
    end, collect, restore, present, beginFloor)
end

function _IsaacLanFrame()
    renders = renders + 1
    local s = frame()
    assert(s.phase ~= phase.failed, s.error)
    if not linked and renders >= (config.host and 260 or 320) then
        linked = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if s.phase == phase.lobby and not started then
        if config.host and s.challenge ~= challenge then
            _IsaacLanCommand("challenge", tostring(challenge))
        elseif s.challenge == challenge and not chosen then
            chosen = true
            _IsaacLanCommand("choose", "0:1")
        end
        if
            config.host
            and s.challenge == challenge
            and s.players == 2
            and s.ready0 == 1
            and s.ready1 == 1
        then
            started = true
            _IsaacLanCommand("start", "RDQV7PSH:0:0:0:0:0")
        end
    end
    if s.phase == phase.running and s.prepared and native.rooms_ready() and not done then
        -- A transfer can temporarily leave the local player without a room scope.
        native.rooms_with_player(config.host and 0 or 1, function()
            local here = Game():GetRoom():GetType() == RoomType.ROOM_SHOP
            if here and (not inShop or s.verified >= sampledAt + 12) then
                checkShop()
                sampledAt = s.verified
                if not inShop then
                    visits = visits + 1
                    Isaac.DebugString("LAN_NETWORK CHALLENGE45 shop icon visit=" .. visits)
                elseif visits == 2 then
                    done = true
                end
            end
            inShop = here
        end)
        assert(s.verified < 600 or done, "Shop re-entry missing")
    end
    return s
end

return {
    done = function()
        return done
    end,
}
