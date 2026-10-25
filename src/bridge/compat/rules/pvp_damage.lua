-- PvP tuning in half-heart units. Inputs are values, never game objects.
local M = {
    updatesPerSecond = 30,
    accumulationGap = 30,
    continuousInterval = 2,
    burstProtection = 10,
    largeHit = 2,
    roundingEpsilon = 1e-6,
}
local BASE_DAMAGE, BASE_INTERVAL = 3.5, 11
local BASE_DPS = BASE_DAMAGE * M.updatesPerSecond / BASE_INTERVAL
local BASE_HALF_HEARTS_PER_SECOND = 6 / 4.5
local MAX_HALF_HEARTS_PER_SECOND = 6 / 2.4
local DIMINISHING_KNEE = 3

function M.positive(value)
    return type(value) == "number" and value > 0 and value < math.huge
end

function M.scale(dps)
    if not M.positive(dps) then
        return 0
    end
    if dps <= BASE_DPS then
        return BASE_HALF_HEARTS_PER_SECOND / BASE_DPS
    end
    local excess = dps / BASE_DPS - 1
    local rate = BASE_HALF_HEARTS_PER_SECOND
        + (MAX_HALF_HEARTS_PER_SECOND - BASE_HALF_HEARTS_PER_SECOND)
            * excess
            / (excess + DIMINISHING_KNEE)
    return rate / dps
end

function M.burstLimit(capacity)
    return math.max(1, math.floor(capacity / 2))
end

return M
