return function(nav, hazards)
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
    function combat.target(obs, style, previous)
        local target, best
        for _, enemy in ipairs(obs.enemies) do
            if enemy.attackable then
                local score = nav.distance(obs.actor, enemy) - (enemy.threat or 0) * 25
                if style == "aggressive" then
                    score = score - (enemy.threat or 0) * 40
                end
                if enemy.id == previous then
                    score = score - 40
                end
                if not best or score < best then
                    target, best = enemy, score
                end
            end
        end
        return target
    end
    function combat.goal(obs, target, style, available, previous)
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
                local value = nav.distance(p, goal)
                    + (distance - range) * 0.7
                    + hazards.risk(obs, goal, goal, 0, 0.35, settings)
                if goal.id == previous then
                    value = value - 20
                end
                for _, delta in ipairs({ { -40, 0 }, { 40, 0 }, { 0, -40 }, { 0, 40 } }) do
                    if
                        not nav.passable(obs.map, goal.x + delta[1], goal.y + delta[2], p.radius)
                    then
                        value = value + 25
                    end
                end
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
    function combat.kite(obs, style, memory, available)
        local count = 0
        for _, danger in ipairs(obs.dangers) do
            if danger.contact then
                count = count + 1
            end
        end
        if count < 3 then
            memory.kite = nil
            return nil
        end
        local map, p = obs.map, obs.actor
        local left, right, top, bottom = math.huge, -math.huge, math.huge, -math.huge
        for cell, walkable in ipairs(map.walk) do
            if walkable then
                local point = nav.position(map, cell)
                left, right = math.min(left, point.x), math.max(right, point.x)
                top, bottom = math.min(top, point.y), math.max(bottom, point.y)
            end
        end
        local cx, cy = (left + right) / 2, (top + bottom) / 2
        local rx, ry = (right - left) / 2 - p.radius - 14, (bottom - top) / 2 - p.radius - 14
        if rx < 60 or ry < 40 then
            memory.kite = nil
            return nil
        end
        local function point(index)
            local angle = index * math.pi / 8
            return {
                x = cx + math.cos(angle) * rx,
                y = cy + math.sin(angle) * ry,
                id = "kite:" .. index % 16,
                task = "kite",
            }
        end
        local kite = memory.kite
        if not kite then
            local nearest =
                math.floor(math.atan((p.y - cy) / ry, (p.x - cx) / rx) * 8 / math.pi + 0.5)
            local a, b = point(nearest + 1), point(nearest - 1)
            local settings = combat.styles[style]
            local function risk(goal)
                if not nav.line(map, p, goal, p.radius) or available and not available(goal.id) then
                    return math.huge
                end
                return hazards.risk(obs, p, goal, 0, 0.4, settings)
            end
            local riskA, riskB = risk(a), risk(b)
            if riskA == math.huge and riskB == math.huge then
                return nil
            end
            local sign = riskA <= riskB and 1 or -1
            kite = { index = nearest + sign, sign = sign }
            memory.kite = kite
        end
        local goal = point(kite.index)
        local arrival = 24 + p.speed * math.max(0, (obs.controlDelay or 1 / 30) - 1 / 30)
        for _ = 1, 3 do
            if nav.distance(p, goal) > arrival then
                break
            end
            kite.index = (kite.index + kite.sign) % 16
            goal = point(kite.index)
        end
        if not nav.line(map, p, goal, p.radius) or available and not available(goal.id) then
            memory.kite = nil
            return nil -- Irregular or obstructed rooms use ordinary routing.
        end
        return goal
    end
    function combat.move(obs, goal, style, previous, door, entering)
        local p, settings = obs.actor, combat.styles[style]
        local best, bestScore, evaluated = 0, math.huge, 0
        local gx, gy = goal and goal.x - p.x or 0, goal and goal.y - p.y or 0
        local contact = false
        for _, danger in ipairs(obs.dangers) do
            contact = contact or danger.contact == true
        end
        local delay = math.max(0, (obs.controlDelay or 1 / 30) - 1 / 30)
        local startX, startY, startVx, startVy = p.x, p.y, p.vx, p.vy
        local holdX = ((previous & 2) ~= 0 and 1 or 0) - ((previous & 1) ~= 0 and 1 or 0)
        local holdY = ((previous & 8) ~= 0 and 1 or 0) - ((previous & 4) ~= 0 and 1 or 0)
        local scale = holdX ~= 0 and holdY ~= 0 and 0.7071 or 1
        local elapsed = 0
        while elapsed < delay do
            local hold = previous
            for _, input in ipairs(obs.inputHistory or {}) do
                if input.at > (obs.now or 0) - delay + elapsed then
                    break
                end
                hold = input.buttons
            end
            holdX = ((hold & 2) ~= 0 and 1 or 0) - ((hold & 1) ~= 0 and 1 or 0)
            holdY = ((hold & 8) ~= 0 and 1 or 0) - ((hold & 4) ~= 0 and 1 or 0)
            scale = holdX ~= 0 and holdY ~= 0 and 0.7071 or 1
            local dt = math.min(1 / 60, delay - elapsed)
            local retain = 0.775 ^ (dt * 30)
            startVx = startVx * retain + holdX * scale * p.speed * (1 - retain)
            startVy = startVy * retain + holdY * scale * p.speed * (1 - retain)
            local nextX, nextY = startX + startVx * dt, startY + startVy * dt
            if
                nav.line(
                    obs.map,
                    { x = startX, y = startY },
                    { x = nextX, y = startY },
                    p.radius,
                    door,
                    elapsed,
                    elapsed + dt
                )
            then
                startX = nextX
            else
                startVx = 0
            end
            if
                nav.line(
                    obs.map,
                    { x = startX, y = startY },
                    { x = startX, y = nextY },
                    p.radius,
                    door,
                    elapsed,
                    elapsed + dt
                )
            then
                startY = nextY
            else
                startVy = 0
            end
            elapsed = elapsed + dt
        end
        local function trajectory(state, direction, steps)
            local x, y, vx, vy = state.x, state.y, state.vx, state.vy
            local score, arrived = state.score, state.arrived
            local progressX, progressY = state.progressX, state.progressY
            local time = state.time
            for _ = 1, steps do
                local dt, retain = 1 / 30, 0.775
                vx = vx * retain + (arrived and 0 or direction[1]) * p.speed * (1 - retain)
                vy = vy * retain + (arrived and 0 or direction[2]) * p.speed * (1 - retain)
                local nextX, nextY = x + vx * dt, y + vy * dt
                local reached = false
                if
                    goal
                    and not arrived
                    and gx * gx + gy * gy > 0.001
                    and (nextX - goal.x) * gx + (nextY - goal.y) * gy >= 0
                then
                    local along = (nextX - x) * gx + (nextY - y) * gy
                    if along > 0 then
                        local fraction = math.max(
                            0,
                            math.min(1, ((goal.x - x) * gx + (goal.y - y) * gy) / along)
                        )
                        progressX, progressY =
                            x + (nextX - x) * fraction, y + (nextY - y) * fraction
                        reached = true
                    end
                end
                if
                    not nav.line(
                        obs.map,
                        { x = x, y = y },
                        { x = nextX, y = nextY },
                        p.radius,
                        door,
                        time,
                        time + dt
                    )
                then
                    if
                        not nav.zonesAllow(
                            obs.map,
                            nextX,
                            nextY,
                            p.radius,
                            time + dt,
                            { x = x, y = y }
                        )
                    then
                        return nil
                    end
                    if contact then
                        -- Solid walls stop the blocked axis. A protected exit
                        -- or active trap above still invalidates the movement.
                        if
                            not nav.line(
                                obs.map,
                                { x = x, y = y },
                                { x = nextX, y = y },
                                p.radius,
                                door,
                                time,
                                time + dt
                            )
                        then
                            nextX, vx = x, 0
                        end
                        if
                            not nav.line(
                                obs.map,
                                { x = nextX, y = y },
                                { x = nextX, y = nextY },
                                p.radius,
                                door,
                                time,
                                time + dt
                            )
                        then
                            nextY, vy = y, 0
                        end
                        if nextX == x and nextY == y and direction[3] ~= 0 then
                            score = score + settings.risk * 0.1
                        end
                    elseif arrived then
                        nextX, nextY, vx, vy = x, y, 0, 0
                    else
                        return nil
                    end
                end
                score = score
                    + hazards.risk(
                        obs,
                        { x = x, y = y },
                        { x = nextX, y = nextY },
                        time,
                        time + dt,
                        settings
                    )
                x, y, time = nextX, nextY, time + dt
                if not arrived and not reached then
                    progressX, progressY = x, y
                end
                if
                    door
                    and not entering
                    and (x - door.x) * door.dx + (y - door.y) * door.dy >= 0
                then
                    break -- This room ends once the selected door is crossed.
                end
                if reached then
                    arrived = true
                end
            end
            return {
                x = x,
                y = y,
                vx = vx,
                vy = vy,
                score = score,
                arrived = arrived,
                progressX = progressX,
                progressY = progressY,
                time = time,
            }
        end
        local function value(state)
            local score = state.score
            if goal then
                score = score + nav.distance({ x = state.progressX, y = state.progressY }, goal) * 2
            end
            return score
        end
        local initial = {
            x = startX,
            y = startY,
            vx = startVx,
            vy = startVy,
            progressX = startX,
            progressY = startY,
            score = 0,
            arrived = false,
            time = delay,
        }
        for _, direction in ipairs(directions) do
            local predicted = trajectory(initial, direction, contact and 16 or 10)
            if predicted then
                local continuity = direction[3] ~= previous and (contact and 12 or 3) or 0
                local score = value(predicted) + continuity
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
