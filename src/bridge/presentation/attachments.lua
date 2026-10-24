-- Render offsets belong to the current view, never to authoritative simulation.
return function(fields)
    local Entity = fields.entity
    local KnifeSubtype = { projectile = 1 }
    local LaserSubtype = { linear = 0, followingRing = 3 }
    return function(native, Vector, types, effects)
        local function capture(entity, value)
            local parent = value[Entity.parent]
            if entity.Type == types.ENTITY_KNIFE then
                -- Native returning knives retain their parent even in flight.
                -- Synergy projectiles use a distinct subtype and travel freely.
                if parent ~= 0 and entity.SubType ~= KnifeSubtype.projectile then
                    return { parent = parent, trajectory = true }
                end
            elseif entity.Type == types.ENTITY_LASER then
                local follows = not entity:ToLaser().DisableFollowParent
                    and (
                        entity.SubType == LaserSubtype.linear
                        or entity.SubType == LaserSubtype.followingRing
                    )
                return {
                    parent = follows and parent or 0,
                    path = value[Entity.laserPath],
                    endpoint = value[Entity.laserEndPoint],
                }
            elseif
                entity.Type == types.ENTITY_EFFECT
                and entity.Variant == effects.LASER_IMPACT
                and parent ~= 0
            then
                return { parent = parent }
            end
        end
        local function present(motion, ref, now, track, sample)
            local resolved, visiting = {}, {}
            local holders = {}
            for identifier, model in pairs(motion) do
                if model.held and model.held ~= 0 and ref(identifier) then
                    holders[model.held] = identifier
                end
            end
            local function offset(identifier)
                if resolved[identifier] ~= nil then
                    return resolved[identifier]
                end
                local model = motion[identifier]
                if not model or not ref(identifier) or visiting[identifier] then
                    return false
                end
                visiting[identifier] = true
                local value = false
                if holders[identifier] then
                    value = offset(holders[identifier])
                elseif model.actor then
                    value = model.display - model.target
                elseif model.attachment and model.attachment.parent ~= 0 then
                    value = offset(model.attachment.parent)
                    local parent = motion[model.attachment.parent]
                    if value and model.attachment.trajectory and model.track and now then
                        -- Returning weapons have zero native velocity in flight.
                        -- Follow their observed path in the parent's frame, then
                        -- compose it with that parent's current rendered position.
                        local relative = model.target - parent.target
                        local prior = model.relative
                        if model.relativeParent ~= model.attachment.parent then
                            prior = nil
                        end
                        local tick = model.track.tick
                        local velocity = Vector(0, 0)
                        if prior and tick > prior.tick then
                            local interval = tick - prior.tick
                            velocity = Vector(
                                (relative.X - prior.x) / interval,
                                (relative.Y - prior.y) / interval
                            )
                        end
                        model.relative = track(prior, relative, velocity, now, tick, 30)
                        model.relativeParent = model.attachment.parent
                        value = value + sample(model.relative, now) - relative
                    elseif not value then
                        model.relative, model.relativeParent = nil, nil
                    end
                end
                if not value and model.attachment and model.attachment.path then
                    -- A free laser keeps its own trajectory; its impact still
                    -- shares that laser's display offset.
                    value = model.display - model.target
                end
                visiting[identifier], resolved[identifier] = nil, value
                return value
            end
            -- Actors have already been predicted. Resolve links independently
            -- of hash-table order, including a laser's attached impact effect.
            for identifier, model in pairs(motion) do
                local attachment = model.attachment
                if not attachment or not attachment.trajectory then
                    model.relative, model.relativeParent = nil, nil
                end
                if attachment or holders[identifier] then
                    local entity = ref(identifier)
                    if entity then
                        local translation = offset(identifier)
                        if translation then
                            model.display = model.target + translation
                            entity.Position = model.display
                        end
                        if attachment and attachment.path then
                            local delta = model.display - model.target
                            if attachment.x ~= delta.X or attachment.y ~= delta.Y then
                                -- Rebuild from the accepted bytes, not the last
                                -- translated path; repeated renders cannot drift.
                                assert(
                                    native.laser_path(
                                        entity:GetSprite(),
                                        attachment.path,
                                        delta.X,
                                        delta.Y
                                    )
                                )
                                entity:ToLaser().EndPoint = Vector(
                                    attachment.endpoint[1],
                                    attachment.endpoint[2]
                                ) + delta
                                attachment.x, attachment.y = delta.X, delta.Y
                            end
                        end
                    end
                end
            end
        end
        return { capture = capture, present = present }
    end
end
