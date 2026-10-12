local root = assert(arg[1])
local writes, authority, ready, roomType, nativePrice, alive = 0, 1, 1, 14, -2, true
local native = {
    api_info = function()
        return { authority = authority, ready = ready }
    end,
    pickup_price = function(pickup, player)
        assert(pickup == "pickup" and player == "player")
        writes = writes + 1
        return nativePrice
    end,
}
Game = function()
    return {
        GetRoom = function()
            return {
                GetType = function()
                    return roomType
                end,
            }
        end,
    }
end
local module = dofile(root .. "/src/bridge/compat/characters/keeper.lua")(
    native,
    { ROOM_DEVIL = 14 },
    { PICKUP_COLLECTIBLE = 100 }
)
local pickup = {
    Variant = 100,
    SubType = 3,
    Exists = function()
        return alive
    end,
    Price = 15,
    AutoUpdatePrice = true,
    GetSprite = function()
        return "pickup"
    end,
}
local player = {
    GetSprite = function()
        return "player"
    end,
}
local collider = {
    ToPlayer = function()
        return player
    end,
}
module.collide(pickup, collider)
assert(pickup.Price == -2 and writes == 1)
nativePrice = 30
module.collide(pickup, collider)
assert(pickup.Price == 30 and writes == 2)
for _, mode in ipairs({ "client", "not-ready", "custom-price", "free", "shop", "removed", "empty" }) do
    authority, ready, pickup.AutoUpdatePrice, pickup.Price, roomType = 1, 1, true, 15, 14
    alive, pickup.SubType = true, 3
    if mode == "client" then
        authority = 0
    end
    if mode == "not-ready" then
        ready = 0
    end
    if mode == "custom-price" then
        pickup.AutoUpdatePrice = false
    end
    if mode == "free" then
        pickup.Price = 0
    end
    if mode == "shop" then
        roomType = 2
    end
    if mode == "removed" then
        alive = false
    end
    if mode == "empty" then
        pickup.SubType = 0
    end
    module.collide(pickup, collider)
    assert(writes == 2, "Keeper pricing escaped its authoritative Devil deal scope")
end
print("PASS per-buyer native Devil price, replica/readiness and custom-price boundaries")
Isaac = {
    GetPlayer = function(index)
        assert(index == 0)
        return player
    end,
    GetRoomEntities = function()
        return {
            {
                ToPickup = function()
                    return pickup
                end,
            },
        }
    end,
}
native.rooms_heads = function()
    return { ["1"] = 1 }
end
native.rooms_with_player = function(slot, fn, actorOnly)
    assert(slot == 1 and actorOnly == 1)
    fn()
    return true
end
authority, ready, pickup.AutoUpdatePrice, pickup.Price, roomType = 1, 1, true, -1, 14
alive, pickup.SubType = true, 3
nativePrice = -2
module.update()
assert(pickup.Price == -2 and writes == 3)
authority, nativePrice = 0, 30
module.present(1)
assert(pickup.Price == 30 and writes == 4)
module.update()
assert(writes == 4)
module.present(2)
assert(writes == 4)
print("PASS local host and guest price display scopes")
