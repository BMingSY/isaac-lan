-- Learn deterministic ordinary multi-shot geometry from an observed launch.
-- Stored values never retain entity references or advance RNG.
return function(Vector)
    local maximumAge, stationarySpeed, maximumOffset = 2, 0.1, 24
    local muzzleFrames = 1.5
    return function(shots, count, playerPosition, movement)
        if #shots ~= count or movement:LengthSquared() > stationarySpeed * stationarySpeed then
            return
        end
        local direction = Vector(0, 0)
        for _, shot in ipairs(shots) do
            if shot.age > maximumAge or shot.velocity:LengthSquared() == 0 then
                return
            end
            direction = direction + shot.velocity
        end
        if direction:LengthSquared() == 0 then
            return
        end
        direction = direction:Normalized()
        local pattern = {}
        for _, shot in ipairs(shots) do
            local aim = shot.velocity:Normalized()
            local origin = shot.position - shot.velocity * shot.age
            local offset = origin - playerPosition - shot.velocity * muzzleFrames
            local eye = -offset.X * aim.Y + offset.Y * aim.X
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
