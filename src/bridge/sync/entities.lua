return function(fields)
    local Entity = fields.entity
    -- Reconcile all identities before linking entities; allocation order is not identity.
    local COLLECTIBLE_SPAWN_PLACEHOLDER = 1
    return function(types, pickups)
        return function(values, env)
            local function optionalTear(v)
                if v[Entity.type] ~= types.ENTITY_TEAR then
                    return false
                end
                -- Only player-owned tears may disappear under allocation pressure.
                -- Hostile projectiles and entities with native links remain required.
                if (v[Entity.child] or 0) ~= 0 or (v[Entity.minecart] or 0) ~= 0 then
                    return false
                end
                local parent = env.ref(v[Entity.parent])
                local spawner = env.ref(v[Entity.spawner])
                return (parent and parent.Type == types.ENTITY_PLAYER)
                    or (spawner and spawner.Type == types.ENTITY_PLAYER)
            end
            local currentObjects, retained = {}, {}
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
                    retained[v[Entity.id]] = e
                end
            end
            for _, e in ipairs(env.entities()) do
                if
                    not currentObjects[env.key(e)]
                    and e:Exists()
                    and e.Type ~= types.ENTITY_PLAYER
                    and not (env.localEffect and env.localEffect(e))
                then
                    env.discard(e)
                    removed = true
                end
            end
            if removed then
                retained = nil
                env.reclaim()
            end
            local spawned = false
            for _, v in ipairs(values) do
                local cached = retained and retained[v[Entity.id]]
                local e = cached or env.ref(v[Entity.id])
                if
                    e
                    and not cached
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
                local registered = e ~= nil
                if not e then
                    -- Factory calls can retire retained allocations in bounded
                    -- native pools. Never reuse borrowed refs across that boundary.
                    retained, spawned = nil, true
                    -- Spawn subtype zero rolls a new collectible, even for an empty pedestal.
                    local collectible = v[Entity.type] == types.ENTITY_PICKUP
                        and v[Entity.variant] == pickups.PICKUP_COLLECTIBLE
                    local subtype = collectible
                            and v[Entity.subtype] == 0
                            and COLLECTIBLE_SPAWN_PLACEHOLDER
                        or v[Entity.subtype]
                    e = env.spawn(v, env.ref(v[Entity.spawner]), subtype)
                    if
                        e
                        and collectible
                        and e.SubType ~= v[Entity.subtype]
                        and env.restorePedestal
                    then
                        env.restorePedestal(e, v[Entity.subtype])
                    end
                end
                if e then
                    local data = e:GetData()
                    if data then
                        data.__isaac_lan_replica = v[Entity.id]
                    end
                    env.apply(e, v, registered)
                    currentObjects[env.key(e)] = true
                else
                    assert(optionalTear(v), "Replica spawn failed")
                end
            end
            if spawned then
                for _, e in ipairs(env.entities()) do
                    if
                        not currentObjects[env.key(e)]
                        and e:Exists()
                        and e.Type ~= types.ENTITY_PLAYER
                    then
                        -- Remove implicit native segments before applying links.
                        -- Membership uses allocations, independently of Mod GetData.
                        if not (env.localEffect and env.localEffect(e)) then
                            env.discard(e)
                        end
                    end
                end
            end
            local missingTears = 0
            -- The allocation/cleanup phase is complete. Resolve shared targets
            -- once for this linking pass; nothing survives into the next view.
            local linked, keys = {}, {}
            local function ref(identifier)
                if not identifier or identifier == 0 then
                    return nil
                end
                if linked[identifier] == nil then
                    linked[identifier] = env.ref(identifier) or false
                end
                return linked[identifier] or nil
            end
            local function link(e, name, identifier)
                local target = ref(identifier)
                local current = e[name]
                if current and target then
                    keys[identifier] = keys[identifier] or env.key(target)
                    if env.key(current) == keys[identifier] then
                        return
                    end
                end
                if current or target then
                    e[name] = target
                end
            end
            -- Native NPC spawns can allocate their own segments. Removing those extra
            -- entities unlinks their parent, so install authoritative links afterward.
            for _, v in ipairs(values) do
                local e = ref(v[Entity.id])
                if e then
                    link(e, "Parent", v[Entity.parent])
                    link(e, "SpawnerEntity", v[Entity.spawner])
                    link(e, "Child", v[Entity.child])
                    link(e, "Target", v[Entity.target])
                    if env.link then
                        env.link(e, v, ref)
                    end
                else
                    -- Native initialization can create poofs in the effect pool
                    -- and retire an older effect while this view is installed.
                    -- The next view recreates it if it remains authoritative.
                    assert(
                        v[Entity.type] == types.ENTITY_EFFECT or optionalTear(v),
                        "Replica identity missing: "
                            .. v[Entity.id]
                            .. " type="
                            .. v[Entity.type]
                            .. ":"
                            .. v[Entity.variant]
                    )
                    if v[Entity.type] == types.ENTITY_TEAR then
                        missingTears = missingTears + 1
                    end
                end
            end
            return missingTears
        end
    end
end
