-- Swept circles in relative motion. Returns the first contact along a frame,
-- so fast projectiles cannot skip a small target or hit through a nearer one.
return function(ax, ay, bx, by, radius)
    local dx, dy = bx - ax, by - ay
    local c = ax * ax + ay * ay - radius * radius
    if c <= 0 then
        return 0
    end
    local a = dx * dx + dy * dy
    if a == 0 then
        return nil
    end
    local b = 2 * (ax * dx + ay * dy)
    local discriminant = b * b - 4 * a * c
    if discriminant < 0 then
        return nil
    end
    local t = (-b - math.sqrt(discriminant)) / (2 * a)
    return t >= 0 and t <= 1 and t or nil
end
