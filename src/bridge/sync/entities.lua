return function(fields)
    local Entity = fields.entity
    -- Reconcile all identities before linking entities; allocation order is not identity.
    local COLLECTIBLE_SPAWN_PLACEHOLDER = 1
    return function(types, pickups)
        return function(values, env)
            local currentObjects = {}
            local removed = false
            -- Native entity pools are bounded. Free obsolete allocations before
            -- spawning replacements, or the factory can overwrite a retained one.
            for _, v in ipairs(values) do
                local e = env.ref(v[Entity.id])
                if
                    e
                    and e:Exists()
                    and e.Type == v[Entity.type]
                    and e.Variant == v[Entity.variant]
                    and e.SubType == v[Entity.subtype]
                then
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
                local e = env.ref(v[Entity.id])
                if
                    e
                    and (
                        not e:Exists()
                        or e.Type ~= v[Entity.type]
                        or e.Variant ~= v[Entity.variant]
                        or e.SubType ~= v[Entity.subtype]
                    )
                then
                    env.discard(e)
                    e = nil
                end
                if not e then
                    -- Spawn subtype zero rolls a new collectible, even for an empty pedestal.
                    local subtype = v[Entity.type] == types.ENTITY_PICKUP
                            and v[Entity.variant] == pickups.PICKUP_COLLECTIBLE
                            and v[Entity.subtype] == 0
                            and COLLECTIBLE_SPAWN_PLACEHOLDER
                        or v[Entity.subtype]
                    e = env.spawn(v, env.ref(v[Entity.spawner]), subtype)
                end
                assert(e, "Replica spawn failed")
                e:GetData().__isaac_lan_replica = v[Entity.id]
                env.apply(e, v)
                currentObjects[env.key(e)] = true
            end
            for _, e in ipairs(env.entities()) do
                if e:Exists() and e.Type ~= types.ENTITY_PLAYER then
                    -- Remove implicit native segments before applying links.
                    -- Membership uses allocations, independently of Mod GetData.
                    if
                        not currentObjects[env.key(e)]
                        and not (env.localEffect and env.localEffect(e))
                    then
                        env.discard(e)
                    end
                end
            end
            -- Native NPC spawns can allocate their own segments. Removing those extra
            -- entities unlinks their parent, so install authoritative links afterward.
            for _, v in ipairs(values) do
                local e = env.ref(v[Entity.id])
                if e then
                    e.Parent = env.ref(v[Entity.parent])
                    e.SpawnerEntity = env.ref(v[Entity.spawner])
                    e.Child = env.ref(v[Entity.child])
                    e.Target = env.ref(v[Entity.target])
                    if env.link then
                        env.link(e, v, env.ref)
                    end
                else
                    -- Native initialization can create poofs in the effect pool
                    -- and retire an older effect while this view is installed.
                    -- The next view recreates it if it remains authoritative.
                    assert(
                        v[Entity.type] == types.ENTITY_EFFECT,
                        "Replica identity missing: "
                            .. v[Entity.id]
                            .. " type="
                            .. v[Entity.type]
                            .. ":"
                            .. v[Entity.variant]
                    )
                end
            end
        end
    end
end
