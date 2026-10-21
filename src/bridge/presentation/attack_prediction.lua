-- Reconcile display-only weapon clocks against accepted input sequences.
local rate, maxHistory, maxPendingTime = 30, 120, 0.25
return function(policy)
    local methods = {}
    methods.__index = methods
    local function copy(weapons)
        local result = {}
        for slot, weapon in pairs(weapons) do
            result[slot] = {
                kind = weapon.kind,
                delay = weapon.delay,
                maximum = weapon.maximum,
                charge = weapon.charge,
                untilShot = math.max(0, math.floor(weapon.delay) + 1),
            }
        end
        return result
    end
    local function advance(weapons, input, emit)
        local frames = input.dt * rate
        for slot, weapon in pairs(weapons) do
            local mode = policy.mode(weapon)
            if mode.charge then
                if not input.firing then
                    weapon.charge = 0
                elseif weapon.delay <= 0 then
                    weapon.charge = math.min(mode.charge, weapon.charge + frames)
                end
                weapon.delay = math.max(-1, weapon.delay - frames)
            elseif mode.tears then
                local remaining = frames
                if input.firing then
                    while remaining >= weapon.untilShot do
                        local wait = weapon.untilShot
                        remaining = remaining - wait
                        if emit and input.tears then
                            emit(slot)
                        end
                        -- Native shooting checks once per simulation tick and
                        -- adds the interval to the residual (possibly fractional)
                        -- cooldown. Do not replace that remainder with maximum.
                        weapon.delay = math.max(-1, weapon.delay - wait)
                            + math.max(0, weapon.maximum)
                            + 1
                        weapon.untilShot = math.floor(weapon.delay) + 1
                    end
                end
                weapon.delay = math.max(-1, weapon.delay - remaining)
                weapon.untilShot = math.max(0, weapon.untilShot - remaining)
            end
        end
    end
    function methods:confirm(weapons, sequence, tick)
        if self.tick and (tick <= self.tick or sequence < self.ack) then
            return false
        end
        self.tick, self.ack, self.weapons = tick, sequence, copy(weapons)
        local pending = {}
        for _, input in ipairs(self.pending) do
            if input.sequence > sequence then
                pending[#pending + 1] = input
                advance(self.weapons, input)
            end
        end
        self.pending = pending
        return true
    end
    function methods:step(sequence, dt, firing, tears, emit)
        local input = {
            sequence = sequence,
            dt = math.max(0, math.min(dt, 0.05)),
            firing = firing,
            tears = tears,
        }
        local total = input.dt
        for _, pending in ipairs(self.pending) do
            total = total + pending.dt
        end
        if #self.pending >= maxHistory or total > maxPendingTime then
            return nil
        end
        self.pending[#self.pending + 1] = input
        advance(self.weapons, input, emit)
        return self.weapons
    end
    return {
        new = function(weapons, sequence, tick)
            return setmetatable(
                { weapons = copy(weapons), ack = sequence, tick = tick, pending = {} },
                methods
            )
        end,
    }
end
