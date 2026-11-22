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
local correctionTime, correctionSpeed = 0.06, 120
local brakingStart, maxPendingTime = 0.35, 0.5
local turnLookahead, maxTurnOffset, settledTurnOffset = 1 / 30, 8, 0.01
local stoppedDistance, contactLead = 0.05, 1
local contactAlignment = math.cos(math.rad(15))
local function zero()
    return Vector(0, 0)
end
local function dot(a, b)
    return a.X * b.X + a.Y * b.Y
end
function prediction.new(position)
    local self = setmetatable({}, methods)
    self:reset(position, -1)
    return self
end
function methods:reset(position, sequence, velocity)
    self.base, self.display, self.position = position, position, position
    self.pending, self.correction = {}, zero()
    self.pendingTime = 0
    self.previousDirection, self.turnOffset = zero(), nil
    self.confirmedDirection, self.contactNormal = nil, nil
    self.turnDirection = nil
    self.evictedTime, self.evictedSequence = 0, sequence
    self.velocity = velocity or zero()
    self.acknowledged = sequence
    self.authority, self.authorityVelocity = position, self.velocity
    self.rebuild, self.confirmedTick = false, nil
    self.teleported = true
    self.correctionStep = 0
end
-- A physical entity or a scripted obstacle can stop or deflect native walking
-- without occupying a grid. Infer the blocked direction only from acknowledged
-- input disagreeing with successive native poses under the same held direction.
local function contactNormal(self, direction, traveled, lead)
    local previous = self.confirmedDirection
    if not direction or not previous then
        return nil
    end
    local length = math.sqrt(direction:LengthSquared())
    local previousLength = math.sqrt(previous:LengthSquared())
    if
        length == 0
        or previousLength == 0
        or dot(direction, previous) < contactAlignment * length * previousLength
    then
        return nil
    end
    local normal, prior = nil, self.contactNormal
    local distance = math.sqrt(traveled:LengthSquared())
    if distance <= stoppedDistance then
        normal = prior or direction * (1 / length)
    else
        -- Preserve the tangent the host just walked, including oblique slides.
        normal = Vector(-traveled.Y / distance, traveled.X / distance)
        if dot(normal, direction) < 0 then
            normal = normal * -1
        end
    end
    if dot(normal, direction) <= 0.001 * length then
        return nil
    end
    if
        prior and dot(prior, normal) >= contactAlignment
        or lead and dot(lead, normal) > contactLead
    then
        return normal
    end
end
function methods:confirm(position, sequence, velocity, tick)
    if
        sequence < self.acknowledged or (tick and self.confirmedTick and tick <= self.confirmedTick)
    then
        return
    end
    local expected, confirmed = self.position, nil
    for i = #self.pending, 1, -1 do
        local input = self.pending[i]
        if input.sequence == sequence then
            expected = input.position
            confirmed = input
            break
        end
    end
    -- Sparse confirmations can span a long ordinary walk which is already
    -- represented by pending inputs. Only snap when the new authority also
    -- lies outside that predicted path; otherwise retain input and correction.
    if
        (position - self.authority):LengthSquared() >= teleportDistance * teleportDistance
        and (position - expected):LengthSquared() >= teleportDistance * teleportDistance
    then
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
    local direction = sequence == self.acknowledged and self.confirmedDirection or nil
    if confirmed then
        direction = not confirmed.locked and confirmed.direction or nil
    end
    -- On the first half tick a held input changes velocity before position.
    -- Compare both at the acknowledged sample, never an unacknowledged turn.
    local lead = confirmed
        and expected - position + (confirmed.velocity - velocity) * (2 / nativeRate)
    self.contactNormal = tick
            and self.confirmedTick
            and contactNormal(self, direction, position - self.authority, lead)
        or nil
    self.confirmedDirection = direction
    self.authority, self.authorityVelocity = position, velocity
    self.confirmedTick, self.acknowledged = tick, sequence
    local remaining = {}
    if sequence >= self.evictedSequence then
        self.evictedTime = 0
    end
    self.pendingTime = self.evictedTime
    for _, input in ipairs(self.pending) do
        if input.sequence > sequence then
            remaining[#remaining + 1] = input
            self.pendingTime = self.pendingTime + input.dt
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
    local along = dot(velocity, direction)
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
local function clipVelocity(self, wanted, accepted)
    local x, y = wanted.X - accepted.X, wanted.Y - accepted.Y
    local length = x * x + y * y
    if length > 0.000001 then
        local inward = (self.velocity.X * x + self.velocity.Y * y) / length
        if inward > 0 then
            self.velocity = Vector(self.velocity.X - inward * x, self.velocity.Y - inward * y)
        end
    end
end
local function advance(self, input, resolve)
    if input.locked then
        self.velocity = zero()
        return
    end
    local elapsed = input.dt
    while elapsed > 0 do
        local dt = math.min(elapsed, 1 / nativeRate)
        -- Grid/creep friction is applied before position integration and walking
        -- acceleration. MoveSpeed alone does not describe a slowed actor.
        self.velocity = self.velocity * input.friction ^ (dt * nativeRate)
        -- Native position integration precedes walking acceleration on each
        -- half tick. Integrating the new velocity advances starts and reversals
        -- too early and underestimates the distance travelled after release.
        local wanted = self.position + self.velocity * dt
        self.velocity = walkingVelocity(self.velocity, input, dt)
        local normal = self.contactNormal
        if normal then
            local inward = dot(wanted - self.authority, normal)
            if inward > 0 then
                wanted = wanted - normal * inward
                self.velocity = self.velocity - normal * math.max(0, dot(self.velocity, normal))
            end
        end
        local position, limited = wanted, false
        if resolve then
            position, limited = resolve(self.position, wanted)
            if limited then
                self.velocity = (position - self.position) * (1 / dt)
            else
                clipVelocity(self, wanted, position)
            end
        end
        self.position = position
        elapsed = elapsed - dt
    end
end
function methods:step(direction, sequence, speed, dt, locked, resolve, friction)
    dt = math.max(0, math.min(dt, 0.05))
    self.errorSquared = nil
    if self.rebuild then
        self.position, self.velocity = self.base, self.authorityVelocity
        for _, input in ipairs(self.pending) do
            advance(self, input, resolve)
            input.position, input.velocity = self.position, self.velocity
        end
        self.correction = self.display - self.position
        if self.turnOffset then
            self.correction = self.correction - self.turnOffset
        end
        self.errorSquared = self.correction:LengthSquared()
        self.rebuild = false
    end
    self.sequence = sequence
    if locked then
        self.velocity = zero()
    end
    if
        not locked
        and dot(self.previousDirection, direction) < 0
        and self.pendingTime > turnLookahead
    then
        self.turnDirection = direction * (1 / math.sqrt(direction:LengthSquared()))
        self.turnSpeed = dot(self.velocity, self.turnDirection)
    end
    self.previousDirection = direction
    if sequence > self.acknowledged then
        local elapsed = 0
        for index = #self.pending, 1, -1 do
            local input = self.pending[index]
            if input.sequence ~= sequence then
                break
            end
            elapsed = elapsed + input.dt
        end
        elapsed =
            math.min(dt, math.max(0, 0.1 - elapsed), math.max(0, maxPendingTime - self.pendingTime))
        if elapsed > 0 then
            -- The sequence acknowledges a sampled held state, not a host tick.
            -- Preserve each preview's direction and duration for approximate
            -- replay from the next authority position AND velocity.
            local input = {
                sequence = sequence,
                direction = direction
                    * math.min(
                        1,
                        math.max(
                            0,
                            (maxPendingTime - self.pendingTime) / (maxPendingTime - brakingStart)
                        )
                    ),
                speed = speed,
                dt = elapsed,
                locked = locked,
                friction = math.max(0, math.min(friction or 1, 1)),
            }
            self.pending[#self.pending + 1] = input
            self.pendingTime = self.pendingTime + elapsed
            advance(self, input, resolve)
            input.position, input.velocity = self.position, self.velocity
            if #self.pending > maxHistory then
                local evicted = table.remove(self.pending, 1)
                self.evictedTime = self.evictedTime + evicted.dt
                self.evictedSequence = evicted.sequence
            end
        end
    end
    if self.pendingTime >= maxPendingTime then
        -- Keep the bounded replay until a real acknowledgement retires it.
        -- New local sequence numbers alone cannot renew the prediction budget.
        self.velocity = zero()
    end
    local distance = math.sqrt(self.correction:LengthSquared())
    local decay = math.exp(-dt / correctionTime)
    if distance > 0 then
        -- Bound only the authority correction. Fresh movement retains its own
        -- integration, including while a late acknowledgement is catching up.
        decay = math.max(decay, 1 - correctionSpeed * dt / distance)
    end
    self.correctionStep = distance * (1 - decay)
    self.correction = self.correction * decay
    -- Show the change in velocity while a confirmed turn is still in flight.
    -- Keep the display lead out of collision integration and replay history.
    local turn = self.turnDirection
    local along = turn and dot(self.velocity, turn)
    if turn and not locked and dot(turn, direction) > 0 and along < 0 then
        local gained = math.max(0, along - self.turnSpeed)
        self.turnOffset = turn * math.min(maxTurnOffset, gained * turnLookahead)
    else
        self.turnDirection = nil
        if self.turnOffset then
            self.turnOffset = self.turnOffset * math.exp(-dt / correctionTime)
            if self.turnOffset:LengthSquared() < settledTurnOffset ^ 2 then
                self.turnOffset = nil
            end
        end
    end
    self.display = self.position + self.correction
    if self.turnOffset then
        self.display = self.display + self.turnOffset
    end
    return self.display
end
function methods:clip(position)
    local delta = position - self.display
    -- Presentation correction is also clipped, but never becomes new input
    -- history. Replay rechecks grids at the authoritative starting position.
    self.correction = self.correction + delta
    clipVelocity(self, self.display, position)
    self.display = position
end
return prediction
