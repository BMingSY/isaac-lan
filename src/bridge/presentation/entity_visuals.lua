-- Bounded, display-only progress between snapshots. Never call Entity/ Sprite.Update.
return function(fields)
    local E, S = fields.entity, fields.sprite
    local rate, maximumAge, correctionTime, groundHeight = 30, 0.1, 0.06, -5
    local locomotion = {
        Idle = true,
        Walk = true,
        WalkUp = true,
        WalkDown = true,
        WalkLeft = true,
        WalkRight = true,
        Fly = true,
        Float = true,
        Swim = true,
    }
    return function(native, trajectory, tearType, variants, normalFlags)
        local function height(value, now)
            local elapsed = math.min(maximumAge, math.max(0, now - value.at))
            return math.min(
                groundHeight,
                trajectory.altitude(value.height, value.falling, value.acceleration, elapsed * rate)
                    + value.correction
                        * math.exp(-math.max(0, now - value.received) / correctionTime)
            )
        end
        local function observe(prior, entity, value, now, captured)
            local visual = { at = captured or now, received = now }
            local sprite = value[E.sprite]
            if
                sprite
                and (
                    locomotion[sprite[S.animation]] or sprite[S.animation]:match("^RegularTear%d+$")
                )
            then
                visual.animation, visual.frame = sprite[S.animation], sprite[S.frame]
                visual.path = sprite[S.path]
                local same = prior
                    and prior.animation == visual.animation
                    and prior.path == visual.path
                visual.length = same and prior.length
                    or native.sprite_animation_length(entity:GetSprite())
                visual.speed = entity:GetSprite().PlaybackSpeed
            end
            local tear = value[E.type] == tearType and entity:ToTear()
            if
                tear
                and (value[E.variant] == variants.BLUE or value[E.variant] == variants.BLOOD)
                and tear.TearFlags == normalFlags
                and tear.WaitFrames == 0
                and tear.Height < groundHeight
            then
                visual.height, visual.falling, visual.acceleration =
                    tear.Height, tear.FallingSpeed, tear.FallingAcceleration
                visual.correction = 0
                if prior and prior.height then
                    visual.correction = height(prior, now) - height(visual, now)
                end
            end
            return visual
        end
        return {
            observe = observe,
            present = function(visual, entity, now)
                if not visual then
                    return
                end
                if visual.animation and visual.length > 0 then
                    local sprite = entity:GetSprite()
                    if sprite:GetAnimation() == visual.animation then
                        local age = math.min(maximumAge, math.max(0, now - visual.at))
                        -- Never cross an unconfirmed animation boundary or invent an event.
                        local frame =
                            math.min(visual.length - 1, visual.frame + age * rate * visual.speed)
                        sprite:SetFrame(visual.animation, math.floor(frame))
                    end
                end
                if visual.height then
                    visual.presentedHeight = height(visual, now)
                    entity:ToTear().Height = visual.presentedHeight
                end
            end,
        }
    end
end
