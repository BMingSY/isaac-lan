-- Predicted presentation is a transaction: confirm without replay, reject or
-- expire without changing gameplay. IDs are authority-assigned entity IDs.
return function()
    local pending, effects, seen, hidden, history = {}, {}, 0, {}, {}
    local timeout, retention = 0.35, 3
    local counts = { predicted = 0, confirmed = 0, rejected = 0, expired = 0, played = 0 }
    local function key(source, target)
        return source .. ":" .. target
    end
    local function predict(source, target, now, duration)
        local id = key(source, target)
        if pending[id] or hidden[source] then
            return false
        end
        local value = { source = source, target = target, at = now, untilTime = now + duration }
        pending[id], effects[id], hidden[source], history[id] = value, value, now + timeout, value
        counts.predicted = counts.predicted + 1
        return true
    end
    local function confirm(event, now, age)
        if event.serial <= seen then
            return false
        end
        seen = event.serial
        local id = key(event.source, event.target)
        -- A consumable projectile can be confirmed against another target.
        -- Cancel that incorrect contact before presenting the authority event.
        for other, prediction in pairs(pending) do
            if prediction.source == event.source and other ~= id then
                pending[other], effects[other], hidden[event.source], history[other] =
                    nil, nil, nil, nil
                counts.rejected = counts.rejected + 1
            end
        end
        -- Keep a short tombstone after timeout: a delayed confirmation must
        -- not turn a finished, cancelled prediction into another visual event.
        local value = pending[id] or history[id]
        pending[id], history[id] = nil, nil
        if not event.accepted then
            effects[id], hidden[event.source] = nil, nil
            counts.rejected = counts.rejected + (value and 1 or 0)
            return false
        end
        if value then
            -- Keep the original presentation clock even when it has finished.
            value.untilTime = math.min(value.untilTime, value.at + event.duration)
            effects[id] = value
            counts.confirmed = counts.confirmed + 1
        elseif age < event.duration then
            local at = now - math.max(0, age)
            effects["event:" .. event.serial] = {
                target = event.target,
                at = at,
                untilTime = at + event.duration,
            }
            counts.played = counts.played + 1
        end
        return true
    end
    local function sample(now)
        for id, value in pairs(pending) do
            if now - value.at >= timeout then
                pending[id], effects[id], hidden[value.source] = nil, nil, nil
                counts.expired = counts.expired + 1
            end
        end
        local targets = {}
        for id, value in pairs(effects) do
            if now < value.untilTime then
                targets[value.target] = true
            elseif now - value.at > retention then
                effects[id] = nil
            end
        end
        for source, untilTime in pairs(hidden) do
            if now >= untilTime then
                hidden[source] = nil
            end
        end
        for id, value in pairs(history) do
            if now - value.at > retention then
                history[id] = nil
            end
        end
        return targets, hidden
    end
    return {
        predict = predict,
        confirm = confirm,
        sample = sample,
        observe = function(serial)
            seen = math.max(seen, serial)
        end,
        counts = counts,
        clear = function(resetSequence)
            pending, effects, hidden, history = {}, {}, {}, {}
            if resetSequence then
                seen = 0
            end
        end,
    }
end
