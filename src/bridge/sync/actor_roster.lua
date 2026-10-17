return function(fields)
    local Actor, Entity, Inventory = fields.actor, fields.entity, fields.inventory
    return function(native)
        return function(actors)
            local byID, companions = {}, {}
            for _, actor in ipairs(actors) do
                byID[actor[Actor.entity][Entity.id]] = actor
            end
            for _, actor in ipairs(actors) do
                local entity = actor[Actor.entity]
                local parent = byID[entity[Entity.parent]]
                if parent then
                    assert(parent[Actor.index] < actor[Actor.index], "Invalid actor parent order")
                    assert(
                        parent[Actor.controller] == actor[Actor.controller],
                        "Actor owner differs"
                    )
                    companions[#companions + 1] = string.pack(
                        ">I4I1I1I1I2I2",
                        entity[Entity.id],
                        actor[Actor.index],
                        parent[Actor.index],
                        actor[Actor.controller],
                        actor[Actor.inventory][Inventory.type],
                        entity[Entity.variant]
                    )
                end
            end
            assert(
                native.actor_companions(string.pack(">I1", #companions) .. table.concat(companions))
            )
        end
    end
end
