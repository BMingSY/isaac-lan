-- Reconcile all identities before linking entities; allocation order is not identity.
local COLLECTIBLE_SPAWN_PLACEHOLDER = 1
return function(types, pickups)
    return function(values, env)
        local currentObjects = {}
        local removed = false
        -- Native entity pools are bounded. Free obsolete allocations before
        -- spawning replacements, or the factory can overwrite a retained one.
        for _, v in ipairs(values) do
            local e = env.ref(v[1])
            if e and e:Exists() and e.Type == v[2] and e.Variant == v[3] and e.SubType == v[4] then
                currentObjects[env.key(e)] = true
            end
        end
        for _, e in ipairs(env.entities()) do
            if
                e:Exists()
                and e.Type ~= types.ENTITY_PLAYER
                and not currentObjects[env.key(e)]
                and not (env.localEffect and env.localEffect(e))
            then
                env.discard(e)
                removed = true
            end
        end
        if removed then
            env.reclaim()
        end
        for _, v in ipairs(values) do
            local e = env.ref(v[1])
            if
                e and (not e:Exists() or e.Type ~= v[2] or e.Variant ~= v[3] or e.SubType ~= v[4])
            then
                env.discard(e)
                e = nil
            end
            if not e then
                -- Spawn subtype zero rolls a new collectible, even for an empty pedestal.
                local subtype = v[2] == types.ENTITY_PICKUP
                        and v[3] == pickups.PICKUP_COLLECTIBLE
                        and v[4] == 0
                        and COLLECTIBLE_SPAWN_PLACEHOLDER
                    or v[4]
                e = env.spawn(v, env.ref(v[12]), subtype)
            end
            assert(e, "Replica spawn failed")
            e:GetData().__isaac_lan_replica = v[1]
            env.apply(e, v)
            currentObjects[env.key(e)] = true
        end
        for _, e in ipairs(env.entities()) do
            if e:Exists() and e.Type ~= types.ENTITY_PLAYER then
                -- Remove implicit native segments before applying links.
                -- Membership uses allocations, independently of Mod GetData.
                if
                    not currentObjects[env.key(e)] and not (env.localEffect and env.localEffect(e))
                then
                    env.discard(e)
                end
            end
        end
        -- Native NPC spawns can allocate their own segments. Removing those extra
        -- entities unlinks their parent, so install authoritative links afterward.
        for _, v in ipairs(values) do
            local e = env.ref(v[1])
            if e then
                e.Parent = env.ref(v[11])
                e.SpawnerEntity = env.ref(v[12])
                e.Child = env.ref(v[13])
                e.Target = env.ref(v[14])
                if env.link then
                    env.link(e, v, env.ref)
                end
            else
                -- Native initialization can create poofs in the effect pool
                -- and retire an older effect while this view is installed.
                -- The next view recreates it if it remains authoritative.
                assert(
                    v[2] == types.ENTITY_EFFECT,
                    "Replica identity missing: " .. v[1] .. " type=" .. v[2] .. ":" .. v[3]
                )
            end
        end
    end
end
