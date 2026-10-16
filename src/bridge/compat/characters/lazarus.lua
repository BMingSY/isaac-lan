return function(fields)
    local Actor = fields.actor
    local Inventory = fields.inventory
    local Entity = fields.entity
    -- Tainted Lazarus replaces a player allocation; changing its type in place
    -- creates another backup body and leaves presentation attached to the old one.
    return function(native, player, types)
        local function lazarus(kind)
            return kind == types.PLAYER_LAZARUS_B or kind == types.PLAYER_LAZARUS2_B
        end
        return {
            resolve = function(index, inventory, controller)
                local p = player(index)
                if not p or (controller and p.ControllerIndex ~= controller) then
                    assert(lazarus(inventory[Inventory.type]), "Replica actor owner differs")
                    assert(
                        native.actor_form(index, inventory[Inventory.type], controller),
                        "Cannot list Lazarus backup"
                    )
                    p = assert(player(index), "Listed backup actor is missing")
                    assert(
                        p:GetPlayerType() == inventory[Inventory.type],
                        "Listed backup actor form differs"
                    )
                    assert(p.ControllerIndex == controller, "Listed backup actor owner differs")
                end
                local current, desired = p:GetPlayerType(), inventory[Inventory.type]
                if
                    not inventory[Inventory.ghost]
                    and current ~= desired
                    and lazarus(current)
                    and lazarus(desired)
                then
                    assert(
                        native.actor_form(index, desired, controller),
                        "Cannot replace Tainted Lazarus form"
                    )
                    p = assert(player(index), "Replacement actor is missing")
                    assert(p:GetPlayerType() == desired, "Replacement actor form differs")
                end
                return p
            end,
            prune = function(replicas, motion, inventories, actors)
                local present = {}
                for _, actor in ipairs(actors) do
                    present[actor[Actor.entity][Entity.id]] = true
                end
                for identifier, value in pairs(motion) do
                    if value.actor and not present[identifier] then
                        -- Native replacement redirects EntityPtr to the new body.
                        -- Its previous identity must not keep moving that body to
                        -- the last position recorded before Flip.
                        replicas[identifier], motion[identifier], inventories[identifier] =
                            nil, nil, nil
                    end
                end
            end,
        }
    end
end
