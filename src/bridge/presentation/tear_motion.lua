-- Ordinary tear display kinematics. No entity creation or random numbers.
local rate, shotSpeedScale, inheritanceScale = 30, 10, 1.2
local damping, gravity, meanLaunchJitter = 0.9, 0.1, 0.1
local muzzleFrames = 1.5
local function altitude(height, falling, acceleration, frames)
    local whole = math.floor(math.max(0, frames))
    local fraction = math.max(0, frames) - whole
    local terminal = (gravity + acceleration) / (1 - damping)
    local decay = damping ^ whole
    local speed = terminal + (falling - terminal) * decay
    local nextSpeed = speed * damping + gravity + acceleration
    return height
        + terminal * whole
        + (falling - terminal) * damping * (1 - decay) / (1 - damping)
        + fraction * nextSpeed,
        speed + fraction * (nextSpeed - speed)
end
return function(Vector)
    return {
        velocity = function(direction, movement, shotSpeed)
            local inherited = movement * inheritanceScale
            local opposing = inherited:Dot(direction)
            if opposing < 0 then
                inherited = inherited - direction * opposing
            end
            return (direction * shotSpeedScale + inherited) * shotSpeed
        end,
        origin = function(position, velocity, eye)
            local direction = velocity:Normalized()
            return position + velocity * muzzleFrames + Vector(-direction.Y, direction.X) * eye
        end,
        initial = function(height, falling, acceleration)
            -- The native first update follows launch. Range has already been
            -- converted by the player cache into height/falling parameters.
            -- Use the midpoint of the native launch jitter, never advance RNG.
            local speed = (meanLaunchJitter - falling) * damping + gravity + acceleration
            return height + speed, speed
        end,
        sample = function(shot, now)
            local frames = math.max(0, now - shot.at) * rate
            local height = altitude(shot.height, shot.falling, shot.acceleration, frames)
            return shot.origin + shot.velocity * frames, height
        end,
        altitude = altitude,
    }
end
