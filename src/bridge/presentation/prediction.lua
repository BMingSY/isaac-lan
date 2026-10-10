-- Render-only movement. Authority remains responsible for all gameplay.
local prediction = {}
_IsaacLanPrediction = prediction
local methods = {}
methods.__index = methods
function prediction.new(position)
    return setmetatable({
        base = position,
        display = position,
        correction = Vector(0, 0),
        velocity = Vector(0, 0),
        pending = {},
        acknowledged = -1,
    }, methods)
end
local function target(self)
    local position = self.base
    for _, input in pairs(self.pending) do
        position = position + input.offset
    end
    return position
end
function methods:reset(position, sequence, velocity)
    self.base, self.display = position, position
    self.pending, self.correction = {}, Vector(0, 0)
    self.velocity = velocity or Vector(0, 0)
    self.acknowledged = sequence
end
function methods:confirm(position, sequence, velocity)
    if self.authority and (position - self.authority):LengthSquared() >= 96 * 96 then
        self:reset(position, sequence, velocity)
    end
    self.authority = position
    if sequence <= self.acknowledged then
        return
    end
    local expected = self.base
    for key, input in pairs(self.pending) do
        if key <= sequence then
            expected = expected + input.offset
        end
    end
    self.acknowledged = math.max(self.acknowledged, sequence)
    for key in pairs(self.pending) do
        if key <= self.acknowledged then
            self.pending[key] = nil
        end
    end
    local error = position - expected
    local tolerance = self.velocity:LengthSquared() < 1 and 0.25
        or math.max(4, math.sqrt(self.velocity:LengthSquared()) / 30)
    -- Advance our own history. Ordinary snapshot noise does not replace the
    -- local path or velocity; compare at the acknowledged input, not "now".
    self.base = expected
    if error:LengthSquared() >= 96 * 96 then
        self:reset(position, sequence, velocity)
    elseif error:LengthSquared() > tolerance * tolerance then
        self.base = position
        self.correction = self.display - target(self)
    end
end
function methods:step(direction, sequence, speed, dt)
    dt = math.max(0, math.min(dt, 0.05))
    self.sequence = sequence
    if sequence > self.acknowledged then
        local input = self.pending[sequence]
        if not input then
            input = { offset = Vector(0, 0), dt = 0 }
            self.pending[sequence] = input
        end
        local elapsed = math.min(dt, math.max(0, 0.1 - input.dt))
        input.dt = input.dt + elapsed
        -- J460 ordinary walking: velocity retains .775 per 30 Hz update;
        -- terminal speed is MoveSpeed * 4.4117647 per rendered 60 Hz frame.
        -- Split stalls into render-sized steps so acceleration is consistent.
        while elapsed > 0 do
            local step = math.min(elapsed, 1 / 60)
            local retain = 0.775 ^ (step * 30)
            self.velocity = self.velocity * retain + direction * speed * (1 - retain)
            input.offset = input.offset + self.velocity * step
            elapsed = elapsed - step
        end
    end
    -- Smooth only the error introduced by a new authoritative snapshot.
    -- Fresh local movement is added in full, independently of this decay.
    self.correction = self.correction * math.exp(-dt / 0.06)
    self.display = target(self) + self.correction
    return self.display
end
function methods:clip(position)
    local delta = position - self.display
    local input = self.pending[self.sequence]
    if input then
        input.offset = input.offset + delta
    else
        self.correction = self.correction + delta
    end
    if math.abs(delta.X) > 0.001 then
        self.velocity.X = 0
    end
    if math.abs(delta.Y) > 0.001 then
        self.velocity.Y = 0
    end
    self.display = position
end
return prediction
