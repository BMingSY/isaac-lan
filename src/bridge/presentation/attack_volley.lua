-- Learn deterministic ordinary multi-shot geometry from an observed launch.
-- Stored values never retain entity references or advance RNG.
return function(Vector, trajectory)
    local maximumAge, stationarySpeed, maximumOffset = 2, 0.1, 24
    local muzzleFrames = 1.5
    return function(shots, count, playerPosition, movement, shotSpeed, launch)
        if #shots ~= count then
            return
        end
        if launch then
            playerPosition, movement = launch.position, launch.velocity
        elseif movement:LengthSquared() > stationarySpeed * stationarySpeed then
            -- A moving launch needs its actual authority pose at birth. Do not
            -- guess through a turn or a lost snapshot using today's velocity.
            return
        end
        local direction = Vector(0, 0)
        local aims = {}
        for _, shot in ipairs(shots) do
            if shot.age > maximumAge or shot.velocity:LengthSquared() == 0 then
                return
            end
            local aim = trajectory.direction(shot.velocity, movement, shotSpeed)
            if not aim then
                return
            end
            aims[#aims + 1] = aim
            direction = direction + aim
        end
        if direction:LengthSquared() == 0 then
            return
        end
        direction = direction:Normalized()
        local pattern = {}
        for index, shot in ipairs(shots) do
            local aim = aims[index]
            local travel = shot.velocity:Normalized()
            local origin = shot.position - shot.velocity * shot.age
            local offset = origin - playerPosition - shot.velocity * muzzleFrames
            local eye = -offset.X * travel.Y + offset.Y * travel.X
            if math.abs(eye) > maximumOffset then
                return
            end
            pattern[#pattern + 1] = {
                along = aim:Dot(direction),
                across = aim.Y * direction.X - aim.X * direction.Y,
                eye = eye,
            }
        end
        table.sort(pattern, function(a, b)
            return a.across == b.across and a.eye < b.eye or a.across < b.across
        end)
        return pattern
    end
end
