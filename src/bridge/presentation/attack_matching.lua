-- Compare launch times and positions on the local display clock. No game objects.
return function(trajectory)
    local rate, inputLookahead = 30, 1
    local alignment, maximumDistance, maximumBirthError = 0.95, 48, 0.1
    return function(previews, owner, position, velocity, age, ack, now, captured, oneWay)
        local speedSquared = velocity:LengthSquared()
        if speedSquared == 0 then
            return
        end
        local birth = captured - age / rate - oneWay
        local target = position + velocity * (math.max(0, now - captured) + oneWay) * rate
        local direction = velocity:Normalized()
        local selected, best
        for index, shot in ipairs(previews) do
            if
                shot.owner == owner
                and shot.sequence <= ack + inputLookahead
                and now - shot.at <= shot.lifetime
                and shot.velocity:Normalized():Dot(direction) > alignment
            then
                local distance = (trajectory.sample(shot, now) - target):LengthSquared()
                local time = math.abs(shot.at - birth)
                local score = distance + time * time * speedSquared * rate * rate
                if
                    distance <= maximumDistance * maximumDistance
                    and time <= maximumBirthError
                    and (not best or score < best)
                then
                    selected, best = index, score
                end
            end
        end
        return selected
    end
end
