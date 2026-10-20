local prediction = {}
_IsaacLanPrediction = prediction
local methods = {}
methods.__index = methods
local teleportDistance = 96
local maxHistory = 120
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
local function advance(self, input, resolve)
    if input.locked then
        self.velocity = zero()
        return
    end
    local elapsed = input.dt
    while elapsed > 0 do
        local dt = math.min(elapsed, 1 / 60)
        local retain = 0.775 ^ (dt * 30)
        self.velocity = self.velocity * retain + input.direction * (input.speed * (1 - retain))
        local wanted = self.position + self.velocity * dt
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
