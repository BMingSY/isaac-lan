-- Read the last accepted actor pose without using render prediction.
-- The existing motion cache owns storage and clears it at lifecycle boundaries.
return function(motion, id, controller, now)
    local value = motion[id]
    if not value or not value.actor or value.controller ~= controller or now - value.at > 0.25 then
        return nil
    end
    return {
        x = value.target.X,
        y = value.target.Y,
        vx = value.velocity.X * 60,
        vy = value.velocity.Y * 60,
    }
end
