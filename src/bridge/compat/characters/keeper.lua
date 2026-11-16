-- The shop is a team trait; each Devil deal uses its actual buyer's rules.
return function(native, rooms, pickups)
    local function price(pickup, player)
        if
            not pickup:Exists()
            or Game():GetRoom():GetType() ~= rooms.ROOM_DEVIL
            or pickup.Variant ~= pickups.PICKUP_COLLECTIBLE
            or pickup.SubType <= 0
            or not pickup.AutoUpdatePrice
            or pickup.Price == 0
        then
            return
        end
        local value = native.pickup_price(pickup:GetSprite(), player:GetSprite())
        assert(type(value) == "number", "Cannot calculate the buyer's Devil price")
        pickup.Price = value
    end
    local function current()
        if Game():GetRoom():GetType() ~= rooms.ROOM_DEVIL then
            return
        end
        local player = Isaac.GetPlayer(0)
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local pickup = entity:ToPickup()
            if pickup then
                price(pickup, player)
            end
        end
    end
    return {
        update = function()
            local info = native.api_info()
            if info.authority == 1 and info.ready == 1 then
                current()
            end
        end,
        collide = function(pickup, collider)
            local info = native.api_info()
            local player = collider:ToPlayer()
            if info.authority == 1 and info.ready == 1 and player then
                price(pickup, player)
            end
        end,
        present = function(slot)
            local heads = native.rooms_heads()
            if not heads[tostring(slot)] then
                return
            end
            assert(native.rooms_with_player(slot, function()
                current()
            end, 1))
        end,
    }
end
