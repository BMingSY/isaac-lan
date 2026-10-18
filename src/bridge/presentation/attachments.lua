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
                    return { parent = parent }
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
        local function present(motion, ref)
            local resolved, visiting = {}, {}
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
                if model.actor then
                    value = model.display - model.target
                elseif model.attachment and model.attachment.parent ~= 0 then
                    value = offset(model.attachment.parent)
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
                if attachment then
                    local entity = ref(identifier)
                    if entity then
                        local translation = offset(identifier)
                        if translation then
                            model.display = model.target + translation
                            entity.Position = model.display
                        end
                        if attachment.path then
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
