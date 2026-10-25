-- Native damage still owns shields, mitigation and death. Only a cooldown
-- produced by our own accepted hit may be suspended during a PvP query/call.
return function(deps)
    local policy, records = deps.policy, {}
    local RENDER_FRAMES_PER_UPDATE = 2
    local HALF_HEART_COOLDOWN, FULL_HEART_COOLDOWN = 60, 120
    local function health(player)
        return player:GetHearts()
            + player:GetSoulHearts()
            + player:GetBoneHearts() * 2
            + player:GetEternalHearts()
    end
    local function record(actor)
        local value = records[actor.id]
        if not value or value.room ~= actor.room then
            value = { room = actor.room, reserves = 0, protection = 0 }
            records[actor.id] = value
        end
        -- Soul/bone containers can disappear on damage. Retain the room's
        -- observed capacity so the burst limit does not shrink with each hit.
        value.reserves = math.max(
            value.reserves,
            actor.player:GetSoulHearts() + actor.player:GetBoneHearts() * 2
        )
        value.capacity = actor.player:GetMaxHearts() + value.reserves
        return value
    end
    local function ownedCooldown(value, cooldown, tick)
        local own = value.cooldown
        if not own or tick < own.at then
            return false
        end
        local remaining = own.frames - (tick - own.at) * RENDER_FRAMES_PER_UPDATE
        return cooldown > 0 and cooldown <= remaining and remaining > 0
    end
    local function scoped(actor, value, tick, fn)
        local player = actor.player
        local cooldown = player:GetDamageCooldown()
        if cooldown > 0 then
            if not ownedCooldown(value, cooldown, tick) then
                value.cooldown = nil
                return false
            end
            player:ResetDamageCooldown()
        end
        local ok, result = pcall(fn)
        if cooldown > 0 then
            player:SetMinDamageCooldown(cooldown)
        end
        if not ok then
            error(result, 0)
        end
        return result
    end
    local function immune(player)
        return player:IsInvincible() or player:HasInvincibility()
    end
    return {
        reset = function()
            records = {}
        end,
        retain = function(actors)
            local active = {}
            for _, actor in ipairs(actors) do
                active[actor.id] = record(actor)
            end
            records = active
        end,
        external = function(id)
            local value = records[id]
            if value then
                value.cooldown = nil
            end
        end,
        limit = function(actor)
            return policy.burstLimit(record(actor).capacity)
        end,
        protected = function(actor, tick)
            local value = record(actor)
            if tick < value.protection then
                return true, false
            end
            local allowed = scoped(actor, value, tick, function()
                return not immune(actor.player)
            end)
            return not allowed, not allowed
        end,
        apply = function(actor, amount, flags, source, tick)
            local value, player = record(actor), actor.player
            local before = health(player)
            local generatedCooldown
            local accepted = scoped(actor, value, tick, function()
                if immune(player) then
                    return false
                end
                deps.damage(player, amount, flags, source)
                generatedCooldown = player:GetDamageCooldown()
                return health(player) < before or player:IsDead() or player:IsCoopGhost()
            end)
            if accepted then
                local loss = before - health(player)
                local ordinary = loss >= policy.largeHit and FULL_HEART_COOLDOWN
                    or HALF_HEART_COOLDOWN
                local frames = player:GetDamageCooldown()
                value.cooldown = generatedCooldown <= ordinary and { frames = frames, at = tick }
                    or nil
                value.frameLoss = (value.at == tick and value.frameLoss or 0)
                    + before
                    - health(player)
                value.at = tick
                if value.frameLoss >= policy.largeHit then
                    value.protection = tick + policy.burstProtection
                end
            else
                -- A consumed shield or a veto keeps its native protection.
                value.cooldown = nil
            end
            return accepted
        end,
    }
end
