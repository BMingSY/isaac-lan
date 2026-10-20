-- Split complete views by update frequency. Only this module knows game fields;
-- the transport carries two opaque byte strings and an exact revision dependency.
return function(fields)
    local Actor, Room, Entity, Inventory =
        fields.actor, fields.room, fields.entity, fields.inventory
    local shared = { "map", "progress", "curses", "deals", "pills", "glitched" }
    local inventoryFields = { Inventory.items, Inventory.trinkets }
    local roomFields = { Room.layout, Room.rails, Room.crawlspace }
    local function copy(value)
        local result = {}
        for key, field in pairs(value) do
            result[key] = field
        end
        return result
    end
    local function split(view)
        local realtime, sharedValues, actors, room = copy(view), {}, {}, {}
        for index, name in ipairs(shared) do
            sharedValues[index], realtime[name] = view[name], false
        end
        realtime.actors = {}
        for index, actor in ipairs(view.actors) do
            local value = copy(actor)
            local stable = { actor[Actor.index], actor[Actor.entity][Entity.id] }
            value[Actor.inventory] = copy(actor[Actor.inventory])
            for _, field in ipairs(inventoryFields) do
                stable[#stable + 1], value[Actor.inventory][field] =
                    actor[Actor.inventory][field], false
            end
            actors[index], realtime.actors[index] = stable, value
        end
        realtime.room = copy(view.room)
        for index, field in ipairs(roomFields) do
            room[index], realtime.room[field] = view.room[field], false
        end
        return realtime, { sharedValues, actors, room }
    end
    local function join(view, stable)
        assert(
            type(stable) == "table"
                and #stable == 3
                and #stable[1] == #shared
                and #stable[2] == #view.actors
                and #stable[3] == #roomFields,
            "Invalid view dependency"
        )
        for index, name in ipairs(shared) do
            assert(view[name] == false, "Duplicate view field")
            view[name] = stable[1][index]
        end
        for index, actor in ipairs(view.actors) do
            local saved = stable[2][index]
            assert(
                #saved == #inventoryFields + 2
                    and saved[1] == actor[Actor.index]
                    and saved[2] == actor[Actor.entity][Entity.id],
                "View actor dependency mismatch"
            )
            for offset, field in ipairs(inventoryFields) do
                assert(actor[Actor.inventory][field] == false, "Duplicate inventory field")
                actor[Actor.inventory][field] = saved[offset + 2]
            end
        end
        for index, field in ipairs(roomFields) do
            assert(view.room[field] == false, "Duplicate room field")
            view.room[field] = stable[3][index]
        end
        return view
    end
    return { split = split, join = join }
end
