-- Split complete views by update frequency. Only this module knows game fields;
-- the transport carries two opaque byte strings and an exact revision dependency.
return function(fields)
    local Actor, Room, Entity, Inventory =
        fields.actor, fields.room, fields.entity, fields.inventory
    local Location, HOST_SLOT = fields.location, 0
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
    local function share(memo, value)
        if type(value) == "table" and memo[value] == nil then
            memo[value] = false
        end
    end
    local function sharedRoom(view)
        local at
        for _, location in ipairs(view.locations) do
            if location[Location.slot] == view.slot then
                at = location
                break
            end
        end
        if not at then
            return false
        end
        for _, location in ipairs(view.locations) do
            local slot = location[Location.slot]
            if
                slot ~= HOST_SLOT
                and slot ~= view.slot
                and (view.connected & (1 << slot)) ~= 0
                and location[Location.dimension] == at[Location.dimension]
                and location[Location.index] == at[Location.index]
            then
                return true
            end
        end
        return false
    end
    local function split(view, memo)
        -- Capture owns this memo for one immutable generation. Projection copies
        -- actor/room containers, so cache their unchanged children instead. A
        -- single recipient needs no extra fragments; room data is shared only
        -- when another connected guest sees that same room and dimension.
        local guests = view.connected >> (HOST_SLOT + 1)
        if (guests & (guests - 1)) == 0 then
            memo = nil
        end
        local realtime, sharedValues, actors, room = copy(view), {}, {}, {}
        for index, name in ipairs(shared) do
            sharedValues[index], realtime[name] = view[name], false
        end
        realtime.actors = {}
        for index, actor in ipairs(view.actors) do
            if memo then
                share(memo, actor[Actor.entity])
                share(memo, actor[Actor.visuals])
            end
            local value = copy(actor)
            local stable = { actor[Actor.index], actor[Actor.entity][Entity.id] }
            value[Actor.inventory] = copy(actor[Actor.inventory])
            for _, field in ipairs(inventoryFields) do
                if memo then
                    share(memo, actor[Actor.inventory][field])
                end
                stable[#stable + 1], value[Actor.inventory][field] =
                    actor[Actor.inventory][field], false
            end
            actors[index], realtime.actors[index] = stable, value
        end
        if memo and sharedRoom(view) then
            share(memo, view.room[Room.entities])
            share(memo, view.room[Room.grids])
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
