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
function methods:confirm(position, sequence)
    self.acknowledged = math.max(self.acknowledged, sequence)
    for key in pairs(self.pending) do
        if key <= self.acknowledged then
            self.pending[key] = nil
        end
    end
    self.base = position
    self.correction = self.display - target(self)
    if self.correction:LengthSquared() >= 160 * 160 then
        -- Teleports must not carry movement from the old position along.
        self.pending = {}
        self.correction = Vector(0, 0)
        self.display = position
    end
end
function methods:step(direction, sequence, speed, dt)
    dt = math.max(0, math.min(dt, 0.05))
    if sequence > self.acknowledged then
        local input = self.pending[sequence]
        if not input then
            input = { offset = Vector(0, 0), dt = 0 }
            self.pending[sequence] = input
        end
        local elapsed = math.min(dt, math.max(0, 0.1 - input.dt))
        input.dt = input.dt + elapsed
        -- Accumulate each render's actual intent. A turn or release within
        -- one 30 Hz interval must never reuse that interval's first direction.
        input.offset = input.offset + direction * speed * elapsed
    end
    -- Smooth only the error introduced by a new authoritative snapshot.
    -- Fresh local movement is added in full, independently of this decay.
    self.correction = self.correction * math.exp(-dt / 0.12)
    self.display = target(self) + self.correction
    return self.display
end
function methods:clip(position)
    self.correction = self.correction + position - self.display
    self.display = position
end
return prediction
