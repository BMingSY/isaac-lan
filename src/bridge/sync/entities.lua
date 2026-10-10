-- Reconcile all identities before linking entities; allocation order is not identity.
return function(values, env)
    local currentIDs = {}
    for _, v in ipairs(values) do
        local e = env.ref(v[1])
        if e and (not e:Exists() or e.Type ~= v[2] or e.Variant ~= v[3] or e.SubType ~= v[4]) then
            env.discard(e)
            e = nil
        end
        if not e then
            -- Spawn subtype zero rolls a new collectible, even for an empty pedestal.
            local subtype = v[2] == 5 and v[3] == 100 and v[4] == 0 and 1 or v[4]
            e = env.spawn(v, env.ref(v[12]), subtype)
        end
        assert(e, "Replica spawn failed")
        e:GetData().__isaac_lan_replica = v[1]
        env.apply(e, v)
        currentIDs[v[1]] = true
    end
    for _, e in ipairs(env.entities()) do
        if e:Exists() and e.Type ~= 1 then
            local identifier = e:GetData().__isaac_lan_replica
            if not identifier or not currentIDs[identifier] then
                env.discard(e)
            end
        end
    end
    -- Native NPC spawns can allocate their own segments. Removing those extra
    -- entities unlinks their parent, so install authoritative links afterward.
    for _, v in ipairs(values) do
        local e = assert(env.ref(v[1]), "Replica identity missing")
        e.Parent = env.ref(v[11])
        e.SpawnerEntity = env.ref(v[12])
        e.Child = env.ref(v[13])
        e.Target = env.ref(v[14])
    end
end
