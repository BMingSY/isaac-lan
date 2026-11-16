-- Tainted Isaac selects the first entry of a rotating passive inventory.
return function(native, types)
    return function(player, value)
        if player:GetPlayerType() ~= types.PLAYER_ISAAC_B then
            assert(value == nil or value == false, "Inventory order requires Tainted Isaac")
            return false
        end
        if value == nil then
            return assert(native.actor_inventory_order(player:GetSprite()))
        end
        return assert(native.actor_inventory_order(player:GetSprite(), value))
    end
end
