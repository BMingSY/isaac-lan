-- Tainted Lazarus replaces a player allocation; changing its type in place
-- creates another backup body and leaves presentation attached to the old one.
return function(native, player)
    local function lazarus(kind)
        return kind == 29 or kind == 38
    end
    return {
        resolve = function(index, inventory, controller)
            local p = player(index)
            if not p or (controller and p.ControllerIndex ~= controller) then
                assert(lazarus(inventory[1]), "Replica actor owner differs")
                assert(
                    native.actor_form(index, inventory[1], controller),
                    "Cannot list Lazarus backup"
                )
                p = assert(player(index), "Listed backup actor is missing")
                assert(p:GetPlayerType() == inventory[1], "Listed backup actor form differs")
                assert(p.ControllerIndex == controller, "Listed backup actor owner differs")
            end
            local current, desired = p:GetPlayerType(), inventory[1]
            if
                not inventory[9]
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
                present[actor[3][1]] = true
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
