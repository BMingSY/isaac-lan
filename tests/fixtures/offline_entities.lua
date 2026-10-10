-- Allocations differ from authoritative IDs; only selected-room entities are enumerated.
return function(root)
    local reconcile = dofile(root .. "/src/bridge/sync/entities.lua")
    local fixture, allocations, refs, spawned, removed, room = {}, {}, {}, 0, 0, "0:1"
    local function new(id, kind, variant, subtype, selectedRoom)
        local e = {
            Type = kind,
            Variant = variant,
            SubType = subtype,
            room = selectedRoom,
            data = { __isaac_lan_replica = id },
            alive = true,
        }
        function e:Exists()
            return self.alive
        end
        function e:GetData()
            return self.data
        end
        allocations[#allocations + 1] = e
        return e
    end
    local function ref(id)
        local e = refs[id]
        return e and e.alive and e or nil
    end
    local function identifier(e)
        return e and e.data.__isaac_lan_replica or 0
    end
    function fixture.reset()
        allocations, refs, spawned, removed, room = {}, {}, 0, 0, "0:1"
        -- An unrelated player and a second room must survive reconciliation.
        new(-1, 1, 0, 0, room)
        refs[900] = new(900, 10, 0, 0, "0:2")
    end
    function fixture.apply(selectedRoom, values, implicitSegments)
        room = selectedRoom
        reconcile(values, {
            ref = ref,
            spawn = function(v, _, subtype)
                spawned = spawned + 1
                local e = new(v[1], v[2], v[3], subtype, room)
                e.spawnSubtype = subtype
                if implicitSegments and v[2] == 62 and subtype == 0 then
                    local child = new(nil, 62, v[3], 1, room)
                    child.Parent, e.Child = e, child
                end
                return e
            end,
            discard = function(e)
                if e.Parent then
                    e.Parent.Child = nil
                end
                e.alive = false
                removed = removed + 1
            end,
            apply = function(e, v)
                e.Variant, e.SubType, e.room = v[3], v[4], room
                refs[v[1]] = e
            end,
            entities = function()
                local values = {}
                for _, e in ipairs(allocations) do
                    if e.room == room and e.alive then
                        values[#values + 1] = e
                    end
                end
                return values
            end,
        })
        return fixture.read()
    end
    function fixture.read()
        local values = {}
        for _, e in ipairs(allocations) do
            if e.alive then
                values[#values + 1] = {
                    identifier(e),
                    e.Type,
                    e.Variant,
                    e.SubType,
                    identifier(e.Parent),
                    identifier(e.SpawnerEntity),
                    identifier(e.Child),
                    identifier(e.Target),
                    e.room,
                    e.spawnSubtype or 0,
                }
            end
        end
        table.sort(values, function(a, b)
            return a[1] < b[1]
        end)
        return { values, spawned, removed }
    end
    fixture.reset()
    return fixture
end
