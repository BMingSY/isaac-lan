-- RDQV 7PSH has a 37-cent shop item, and a free pedestal that the D6 can reroll.
local native, config = _IsaacLan, _IsaacLanTest
local frame, gate, phase = _IsaacLanFrame, native.net_gate, native.net_phases()
local ordinary = config.route == "tmtrainer-pedestals"
local challenge = ordinary and 0 or 1006
local tmtrainer = CollectibleType.COLLECTIBLE_TMTRAINER
local shop, treasure, start = RoomType.ROOM_SHOP, RoomType.ROOM_TREASURE, RoomType.ROOM_DEFAULT

-- Fingerprints of the item layer in the game's native renderer for this seed.
local sale = { id = -2, price = 37, frame = 0, icon = 0x4fe9373e }
local free = { id = -3, price = 0, frame = 9, icon = 0x1e56291b }
local rerolled = { id = -4, price = 0, frame = 5, icon = 0x3961f78f }
local visits = ordinary
        and {
            { at = 45, room = shop, item = sale },
            { at = 150, room = treasure, item = free },
            { at = 235, room = treasure, item = rerolled, reroll = true },
            { at = 310, room = shop, item = sale, removeTrainer = true },
            { at = 405, room = treasure, item = rerolled },
            { at = 490, room = treasure, collect = true },
        }
    or {
        { at = 45, room = shop, item = sale },
        { at = 130, room = start },
        { at = 215, room = shop, item = sale },
    }
local renders, linked, chosen, started = 0, false, false, false
local rooms, given, acted, visit, check = {}, false, 0, 1, 1

local function player(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end

local function pickups()
    local pedestal, sack
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity:ToPickup()
        if pickup and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            pedestal = pickup
        elseif pickup and pickup.Variant == PickupVariant.PICKUP_GRAB_BAG then
            sack = pickup
        end
    end
    return pedestal, sack
end

local function icon(sprite)
    -- Sample the visible colors of the collectible layer at the reference pose.
    local hash = 0
    for y = -70, 30 do
        for x = -30, 30 do
            local c = sprite:GetTexel(Vector(x, y), Vector.Zero, 0.01, 1)
            if c.Alpha > 0 then
                local rgb = (math.floor(c.Red * 255 + 0.5) << 16)
                    | (math.floor(c.Green * 255 + 0.5) << 8)
                    | math.floor(c.Blue * 255 + 0.5)
                hash = ((hash * 33) ~ rgb) & 0xffffffff
            end
        end
    end
    return hash
end

local function advance(t)
    if t < 10 or not native.rooms_ready() then
        return
    end
    if ordinary and not given then
        given = native.rooms_with_player(0, function()
            assert(Game().Challenge == 0)
            player(0):AddCollectible(tmtrainer, 0, false)
            assert(player(0):HasCollectible(tmtrainer) and not player(1):HasCollectible(tmtrainer))
        end)
    end
    if t < visits[1].at or (ordinary and not given) then
        return
    end
    local positions = native.rooms_positions()
    if not rooms[start] then
        rooms[start] = positions["0"].index
        local descriptors = Game():GetLevel():GetRooms()
        for i = 0, descriptors.Size - 1 do
            local room = descriptors:Get(i)
            if room.Data.Type == shop or room.Data.Type == treasure then
                rooms[room.Data.Type] = room.SafeGridIndex
            end
        end
    end
    if visits[visit + 1] and t >= visits[visit + 1].at then
        visit = visit + 1
    end
    local step = visits[visit]
    local destination = assert(rooms[step.room], "Seed is missing a required room")
    if step.removeTrainer and acted ~= visit then
        if
            not native.rooms_with_player(0, function()
                player(0):RemoveCollectible(tmtrainer)
                assert(not player(0):HasCollectible(tmtrainer))
            end)
        then
            return
        end
        acted = visit
    end
    for slot = 0, 1 do
        if positions[tostring(slot)].index ~= destination then
            native.rooms_move(slot, destination, 0, -1)
        end
    end
    if step.reroll and acted ~= visit and positions["0"].index == destination then
        if
            native.rooms_with_player(0, function()
                player(0):UseActiveItem(CollectibleType.COLLECTIBLE_D6, UseFlag.USE_NOANIM)
            end)
        then
            acted = visit
        end
    elseif step.collect and positions["1"].index == destination then
        native.rooms_with_player(1, function()
            local pickup = pickups()
            if pickup and pickup.SubType == (rerolled.id & 0xffffffff) then
                player(1).Position, player(1).Velocity = pickup.Position, Vector.Zero
            end
        end)
    end
end

local function owns(playerEntity, id)
    return native.generated_item_count(playerEntity:GetSprite(), id) > 0
        or playerEntity:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == id
end

local function observe(t)
    local step = visits[check]
    if not step or t < step.at + 30 then
        return
    end
    assert(
        t < (visits[check + 1] and visits[check + 1].at or step.at + 160),
        "Missing visit " .. check
    )
    native.rooms_with_player(config.host and 0 or 1, function()
        if Game():GetRoom():GetType() ~= step.room then
            return
        end
        local pedestal, sack = pickups()
        if step.room == shop then
            assert(sack and sack.Visible and sack.Price == 7, "Missing seven-cent sack")
        end
        if step.item then
            local item = step.item
            assert(pedestal and pedestal.Visible and pedestal.Price == item.price)
            assert(pedestal.SubType == (item.id & 0xffffffff), "Wrong generated collectible")
            local sprite = pedestal:GetSprite()
            assert(sprite:GetAnimation() == (step.room == shop and "ShopIdle" or "Idle"))
            if sprite:GetFrame() ~= item.frame then
                return
            end
            local actual = icon(sprite)
            assert(actual == item.icon, ("Wrong icon for %d: %08x"):format(item.id, actual))
        elseif step.collect then
            if not owns(player(1), rerolled.id) then
                return
            end
            assert(not owns(player(0), rerolled.id), "Host received guest's collectible")
            assert(not pedestal or pedestal.SubType ~= (rerolled.id & 0xffffffff))
        end
        Isaac.DebugString("LAN_NETWORK GENERATED_PEDESTAL " .. config.route .. " visit=" .. check)
        check = check + 1
    end)
end

native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, ...)
        before(t, ...)
        advance(t)
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
    if s.phase == phase.running and s.prepared and native.rooms_ready() then
        observe(s.verified)
    end
    return s
end

return {
    done = function()
        return check > #visits
    end,
}
