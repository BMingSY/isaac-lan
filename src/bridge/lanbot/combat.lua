return function(nav)
    local combat = {}
    combat.styles = {
        aggressive = { risk = 1900, margin = 5, distance = 0.55 },
        balanced = { risk = 2800, margin = 10, distance = 0.7 },
        cautious = { risk = 4200, margin = 18, distance = 0.8 },
    }
    local directions = {
        { 0, 0, 0 },
        { -1, 0, 1 },
        { 1, 0, 2 },
        { 0, -1, 4 },
        { 0, 1, 8 },
        { -0.7071, -0.7071, 5 },
        { 0.7071, -0.7071, 6 },
        { -0.7071, 0.7071, 9 },
        { 0.7071, 0.7071, 10 },
    }
    function combat.target(obs, style)
        local target, best
        for _, enemy in ipairs(obs.enemies) do
            if enemy.attackable then
                local score = nav.distance(obs.actor, enemy) - (enemy.threat or 0) * 25
                if style == "aggressive" then
                    score = score - (enemy.threat or 0) * 40
                end
                if not best or score < best then
                    target, best = enemy, score
                end
            end
        end
        return target
    end
    function combat.goal(obs, target, style, available)
        local p, settings = obs.actor, combat.styles[style]
        local distance = math.max(p.radius + target.radius + 18, p.range * settings.distance)
        local best, score
        -- Try all four firing lanes and shorter lanes near walls. A preferred
        -- range outside the room must not prevent approaching a corner enemy.
        for i, direction in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
            for j, scale in ipairs({ 1, 0.65, 0.4 }) do
                local range = math.max(p.radius + target.radius + 18, distance * scale)
                local goal = {
                    x = target.x + direction[1] * range,
                    y = target.y + direction[2] * range,
                    id = "aim:" .. target.id .. ":" .. i .. ":" .. j,
                }
                local value = nav.distance(p, goal) + (distance - range) * 0.7
                if
                    (not available or available(goal.id))
                    and nav.passable(obs.map, goal.x, goal.y, p.radius)
                    and obs.shotLine(goal, target)
                    and (not score or value < score)
                then
                    best, score = goal, value
                end
            end
        end
        return best
    end
    local function risk(obs, x, y, t, settings)
        local value = 0
        for _, danger in ipairs(obs.dangers) do
            if not danger.at or t >= danger.at then
                local distance
                if danger.bx then
                    distance = nav.segmentDistance(x, y, danger.x, danger.y, danger.bx, danger.by)
                else
                    distance = math.sqrt(
                        (x - danger.x - (danger.vx or 0) * t) ^ 2
                            + (y - danger.y - (danger.vy or 0) * t) ^ 2
                    )
                end
                local radius = obs.actor.radius
                    + danger.radius
                    + settings.margin
                    + (obs.age or 0) * 30
                if distance < radius then
                    value = value + settings.risk * (1 + (radius - distance) / radius)
                elseif distance < radius + 25 then
                    value = value + settings.risk * 0.04 * (1 - (distance - radius) / 25)
                end
            end
        end
        return value
    end
    function combat.move(obs, goal, style, previous, door)
        local p, settings = obs.actor, combat.styles[style]
        local best, bestScore, evaluated = 0, math.huge, 0
        for _, direction in ipairs(directions) do
            local x, y, vx, vy = p.x, p.y, p.vx, p.vy
            local score, valid, distance, steps = 0, true, 0, 0
            for step = 1, 10 do
                local dt, retain = 1 / 30, 0.775
                vx = vx * retain + direction[1] * p.speed * (1 - retain)
                vy = vy * retain + direction[2] * p.speed * (1 - retain)
                local nextX, nextY = x + vx * dt, y + vy * dt
                if
                    not nav.line(
                        obs.map,
                        { x = x, y = y },
                        { x = nextX, y = nextY },
                        p.radius,
                        door
                    )
                then
                    valid = false
                    break
                end
                x, y = nextX, nextY
                score = score + risk(obs, x, y, step * dt, settings)
                if goal then
                    distance, steps = distance + nav.distance({ x = x, y = y }, goal), steps + 1
                end
                if door and (x - door.x) * door.dx + (y - door.y) * door.dy >= 0 then
                    break -- Crossing commits a room transfer; this room ends here.
                end
            end
            if valid then
                if goal then
                    -- Score progress along the trajectory. A final point past
                    -- a nearby waypoint must not make standing still optimal.
                    score = score + distance / math.max(1, steps) * 2
                end
                -- Prefer continuity, not a fixed left/right tie break every frame.
                if direction[3] ~= previous then
                    score = score + 3
                end
                if score < bestScore then
                    best, bestScore = direction[3], score
                end
            end
            evaluated = evaluated + 1
        end
        return best, bestScore, evaluated
    end
    function combat.shoot(obs, target, memory)
        if not target or not target.attackable then
            memory.charging, memory.releasing = nil, nil
            return 0
        end
        local p = obs.actor
        local dx, dy = target.x - p.x, target.y - p.y
        local horizontal = math.abs(dx) >= math.abs(dy)
        local across = math.abs(horizontal and dy or dx)
        local distance = nav.distance(p, target)
        local clear = obs.shotLine(p, target)
        local aimed = across < target.radius + 16 and distance <= p.range + target.radius and clear
        local button = horizontal and (dx < 0 and 16 or 32) or (dy < 0 and 64 or 128)
        if not p.charge then
            memory.charging, memory.releasing = nil, nil
            return aimed and button or 0
        end
        if memory.releasing and obs.frame < memory.releasing then
            return 0
        end
        memory.releasing = nil
        if not memory.charging then
            memory.charging = obs.frame
        end
        if obs.frame - memory.charging >= p.charge and aimed then
            memory.charging = nil
            memory.releasing = obs.frame + 3
            return 0 -- Span a 30 Hz capture; a one-render release can be lost.
        end
        return button
    end
    return combat
end
