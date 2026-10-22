local prediction = {}
_IsaacLanPrediction = prediction
local methods = {}
methods.__index = methods
local teleportDistance = 96
local maxHistory = 120
local nativeRate = 60
local coastingRetention = math.sqrt(0.775)
local turningRetention = math.sqrt(0.8)
local inputBase, inputSpeedScale = 0.75, 0.25
local walkingAcceleration, reverseAcceleration = 0.6, 0.04
local function zero()
    return Vector(0, 0)
end
function prediction.new(position)
    local self = setmetatable({}, methods)
    self:reset(position, -1)
    return self
end
function methods:reset(position, sequence, velocity)
    self.base, self.display, self.position = position, position, position
    self.pending, self.correction = {}, zero()
    self.velocity = velocity or zero()
    self.acknowledged = sequence
    self.authority, self.authorityVelocity = position, self.velocity
    self.rebuild, self.confirmedTick = false, nil
    self.teleported = true
end
function methods:confirm(position, sequence, velocity, tick)
    if
        sequence < self.acknowledged or (tick and self.confirmedTick and tick <= self.confirmedTick)
    then
        return
    end
    if (position - self.authority):LengthSquared() >= teleportDistance * teleportDistance then
        self:reset(position, sequence, velocity)
        self.confirmedTick = tick
        return
    end
    velocity = velocity or self.velocity
    if
        not tick
        and sequence == self.acknowledged
        and (position - self.authority):LengthSquared() == 0
        and (velocity - self.authorityVelocity):LengthSquared() == 0
    then
        return
    end
    self.authority, self.authorityVelocity = position, velocity
    self.confirmedTick, self.acknowledged = tick, sequence
    local remaining = {}
    for _, input in ipairs(self.pending) do
        if input.sequence > sequence then
            remaining[#remaining + 1] = input
        end
    end
    self.pending = remaining
    self.base, self.velocity, self.rebuild = position, velocity, true
end
local function walkingVelocity(velocity, input, dt)
    local frames = dt * nativeRate
    local magnitude = math.sqrt(input.direction:LengthSquared())
    if magnitude == 0 then
        return velocity * coastingRetention ^ frames
    end
    local direction = input.direction * (1 / magnitude)
    local along = velocity.X * direction.X + velocity.Y * direction.Y
    local across = velocity - direction * along
    local strength = magnitude * (inputBase + inputSpeedScale * input.speed)
    -- Native walking projects onto the speed-scaled input before damping the
    -- remaining velocity. Consequently retention depends on MoveSpeed while
    -- holding a direction, and turning damps the perpendicular axis faster.
    local retain = coastingRetention
        * (turningRetention + (1 - turningRetention) * strength * strength)
    if along < 0 and input.speed > 0 then
        retain = retain * (1 - reverseAcceleration * strength * strength / input.speed)
    end
    local decay = retain ^ frames
    local acceleration = walkingAcceleration * nativeRate * strength * coastingRetention
    local duration = math.abs(retain - 1) < 0.000001 and frames or (1 - decay) / (1 - retain)
    return direction * (along * decay + acceleration * duration)
        + across * (coastingRetention * turningRetention) ^ frames
end
local function advance(self, input, resolve)
    if input.locked then
        self.velocity = zero()
        return
    end
    local elapsed = input.dt
    while elapsed > 0 do
        local dt = math.min(elapsed, 1 / nativeRate)
        -- Native position integration precedes walking acceleration on each
        -- half tick. Integrating the new velocity advances starts and reversals
        -- too early and underestimates the distance travelled after release.
        local wanted = self.position + self.velocity * dt
        self.velocity = walkingVelocity(self.velocity, input, dt)
        local position = resolve and resolve(self.position, wanted) or wanted
        if math.abs(position.X - wanted.X) > 0.001 then
            self.velocity.X = 0
        end
        if math.abs(position.Y - wanted.Y) > 0.001 then
            self.velocity.Y = 0
        end
        self.position = position
        elapsed = elapsed - dt
    end
end
function methods:step(direction, sequence, speed, dt, locked, resolve)
    dt = math.max(0, math.min(dt, 0.05))
    self.errorSquared = nil
    if self.rebuild then
        self.position, self.velocity = self.base, self.authorityVelocity
        for _, input in ipairs(self.pending) do
            advance(self, input, resolve)
        end
        self.correction = self.display - self.position
        self.errorSquared = self.correction:LengthSquared()
        self.rebuild = false
    end
    self.sequence = sequence
    if locked then
        self.velocity = zero()
    end
    if sequence > self.acknowledged then
        local elapsed = 0
        for index = #self.pending, 1, -1 do
            local input = self.pending[index]
            if input.sequence ~= sequence then
                break
            end
            elapsed = elapsed + input.dt
        end
        elapsed = math.min(dt, math.max(0, 0.1 - elapsed))
        if elapsed > 0 then
            -- The sequence acknowledges a sampled held state, not a host tick.
            -- Preserve each preview's direction and duration for approximate
            -- replay from the next authority position AND velocity.
            local input = {
                sequence = sequence,
                direction = direction,
                speed = speed,
                dt = elapsed,
                locked = locked,
            }
            self.pending[#self.pending + 1] = input
            advance(self, input, resolve)
            if #self.pending > maxHistory then
                table.remove(self.pending, 1)
            end
        end
    end
    self.correction = self.correction * math.exp(-dt / 0.06)
    self.display = self.position + self.correction
    return self.display
end
function methods:clip(position)
    local delta = position - self.display
    -- Presentation correction is also clipped, but never becomes new input
    -- history. Replay rechecks grids at the authoritative starting position.
    self.correction = self.correction + delta
    if math.abs(delta.X) > 0.001 then
        self.velocity.X = 0
    end
    if math.abs(delta.Y) > 0.001 then
        self.velocity.Y = 0
    end
    self.display = position
end
return prediction
