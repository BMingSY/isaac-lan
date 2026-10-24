-- One run-scoped coordinator; individual routes/effects stay in compat/.
return function(deps)
    local native, definitions = deps.native, deps.native.net_challenges()
    local pendingLayout, lastRun = true, nil
    local routes, effects = deps.routes, deps.effects or {}
    local function reset()
        for _, effect in pairs(effects) do
            effect.reset()
        end
        lastRun = nil
    end
    local function current()
        local info = native.api_info()
        if info.active ~= 1 or not info.challenge or info.challenge == 0 then
            if lastRun then
                reset()
            end
            return
        end
        local definition = assert(definitions[tostring(info.challenge)], "Unknown LAN challenge")
        assert(definition.version == info.challengeVersion, "LAN challenge version mismatch")
        if lastRun ~= info.runId then
            reset()
            lastRun, pendingLayout = info.runId, true
        end
        return definition, info
    end
    local function authority()
        local definition, info = current()
        if definition and info.authority == 1 and info.ready == 1 then
            return definition, info
        end
    end
    local function view()
        local definition, info = current()
        local effect = definition and effects[definition.id]
        if effect and info.ready == 1 and info.authority ~= 1 then
            effect.initialize(info)
        end
    end
    local function pickup(p)
        local definition = authority()
        if definition then
            routes[definition.route].pickup(p)
        end
    end
    local function collide(p, collider)
        local definition, info = current()
        if not definition then
            return
        end
        local route = routes[definition.route]
        if not route.handles(p) then
            return
        end
        local player = collider:ToPlayer()
        if not player then
            return
        end
        if info.authority ~= 1 or info.ready ~= 1 then
            return true
        end
        local slot = player.ControllerIndex - 1
        if slot < 0 or slot >= info.players or (info.connected & (1 << slot)) == 0 then
            return true
        end
        return route.collide(p, player)
    end
    local function level()
        pendingLayout = true
    end
    local function step()
        local definition, info = authority()
        if not definition then
            return
        end
        local effect = effects[definition.id]
        if effect then
            effect.step(info)
        end
        if not pendingLayout then
            return
        end
        pendingLayout = false
        if effect then
            effect.level(info, deps.game():GetLevel())
        end
        -- Deferred until the native floor is usable, before this authority
        -- step releases player input. A callback never recursively loads a floor.
        local map = deps.maps and deps.maps[definition.id]
        if map and map.onLayoutReady then
            map.onLayoutReady(info, deps.game():GetLevel())
        end
    end
    local function canEnter(slot, fromDimension, fromRoom, dimension, room, teleport)
        local definition, info = authority()
        if not definition then
            return true
        end
        local map = deps.maps and deps.maps[definition.id]
        if not map or not map.canEnter then
            return true
        end
        return map.canEnter({
            slot = slot,
            fromDimension = fromDimension,
            fromRoom = fromRoom,
            dimension = dimension,
            room = room,
            teleport = teleport,
            info = info,
        }) == true
    end
    local function clearAward()
        local definition, info = authority()
        if definition then
            local route, effect = routes[definition.route], effects[definition.id]
            if route.clearAward then
                route.clearAward()
            end
            if effect then
                effect.clearAward(info)
            end
        end
    end
    local function collect(owner, ...)
        local definition, info = authority()
        local effect = definition and effects[definition.id]
        if
            effect
            and owner >= 0
            and owner < info.players
            and (info.connected & (1 << owner)) ~= 0
        then
            return effect.collect(owner, ...)
        end
        return nil
    end
    return {
        reset = reset,
        view = view,
        collect = collect,
        clearAward = clearAward,
        pickup = pickup,
        collide = collide,
        level = level,
        step = step,
        canEnter = canEnter,
    }
end
