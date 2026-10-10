-- Pure numeric, continuous collision prediction shared by aim and movement.
return function(nav)
    local hazards = {}
    local function segments(ax, ay, bx, by, cx, cy, dx, dy)
        local ux, uy, vx, vy = bx - ax, by - ay, dx - cx, dy - cy
        local cross = ux * vy - uy * vx
        if math.abs(cross) > 0.001 then
            local t = ((cx - ax) * vy - (cy - ay) * vx) / cross
            local s = ((cx - ax) * uy - (cy - ay) * ux) / cross
            if t >= 0 and t <= 1 and s >= 0 and s <= 1 then
                return 0
            end
        end
        return math.min(
            nav.segmentDistance(ax, ay, cx, cy, dx, dy),
            nav.segmentDistance(bx, by, cx, cy, dx, dy),
            nav.segmentDistance(cx, cy, ax, ay, bx, by),
            nav.segmentDistance(dx, dy, ax, ay, bx, by)
        )
    end
    function hazards.risk(obs, from, to, t0, t1, settings)
        local value, age = 0, obs.age or 0
        for _, danger in ipairs(obs.dangers) do
            local start = math.max(t0, (danger.at or 0) - age)
            if start <= t1 then
                local fraction = (start - t0) / math.max(0.001, t1 - t0)
                local x, y =
                    from.x + (to.x - from.x) * fraction, from.y + (to.y - from.y) * fraction
                local distance
                if danger.bx then
                    distance = segments(x, y, to.x, to.y, danger.x, danger.y, danger.bx, danger.by)
                else
                    local vx, vy = danger.vx or 0, danger.vy or 0
                    distance = nav.segmentDistance(
                        0,
                        0,
                        x - danger.x - vx * (start + age),
                        y - danger.y - vy * (start + age),
                        to.x - danger.x - vx * (t1 + age),
                        to.y - danger.y - vy * (t1 + age)
                    )
                end
                local radius = obs.actor.radius + danger.radius + settings.margin + age * 30
                if distance < radius then
                    value = value + settings.risk * (1 + (radius - distance) / radius)
                elseif distance < radius + 25 then
                    value = value + settings.risk * 0.04 * (1 - (distance - radius) / 25)
                end
            end
        end
        return value
    end
    return hazards
end
