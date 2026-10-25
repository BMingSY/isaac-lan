-- Portable round policy. Native deaths/revivals are resolved by the adapter.
local rules = {
    id = 1003,
    width = 13,
    center = 84,
    momRoomVariant = 1060,
    framesPerSecond = 30,
    survivalFrames = 5 * 60 * 30,
    deathGraceFrames = 3 * 30,
    shrinkFrames = { 90 * 30, 180 * 30, 240 * 30 },
    radii = { 6, 4, 2, 0 },
    phase = {
        loading = "loading",
        survival = "survival",
        portal = "portal",
        boss = "boss",
        reward = "reward",
        trophy = "trophy",
    },
    fields = { round = 1, phase = 2, elapsed = 3, winner = 4, scores = 5, alive = 6 },
}
function rules.zone(elapsed)
    local step = 1
    for _, frame in ipairs(rules.shrinkFrames) do
        if elapsed >= frame then
            step = step + 1
        end
    end
    local radius = rules.radii[step]
    return { left = 6 - radius, top = 6 - radius, right = 6 + radius, bottom = 6 + radius }, step
end
function rules.outside(index, elapsed)
    if index < 0 or index >= rules.width * rules.width then
        return true
    end
    local zone = rules.zone(elapsed)
    local x, y = index % rules.width, index // rules.width
    return x < zone.left or x > zone.right or y < zone.top or y > zone.bottom
end
function rules.pressure(elapsed)
    local _, step = rules.zone(elapsed)
    local overtime = math.max(0, elapsed - rules.survivalFrames)
    -- Half-heart units, on a one-second cadence. Normal defenses and revivals apply.
    return step + overtime // (15 * rules.framesPerSecond)
end
function rules.new()
    local phase = rules.phase
    local state = {
        round = 0,
        phase = phase.loading,
        elapsed = 0,
        winner = -1,
        scores = { 0, 0, 0, 0 },
        alive = 0,
    }
    local function start()
        state.round = state.round + 1
        state.phase, state.elapsed, state.winner, state.alive = phase.survival, 0, -1, 0
    end
    local function step(delta, alive, reviving)
        state.alive = alive
        if state.phase == phase.loading or state.phase == phase.trophy then
            return
        end
        if reviving then
            if state.phase == phase.survival then
                state.elapsed = state.elapsed + delta
            end
            return
        end
        if alive == 0 then
            state.phase = phase.loading
            return "next"
        end
        if state.phase == phase.survival then
            state.elapsed = state.elapsed + delta
            if (alive & (alive - 1)) == 0 then
                for slot = 0, 3 do
                    if (alive & (1 << slot)) ~= 0 then
                        state.winner, state.phase = slot, phase.portal
                        return "winner"
                    end
                end
            end
        elseif state.winner >= 0 and (alive & (1 << state.winner)) == 0 then
            state.phase = phase.loading
            return "next"
        end
    end
    local function enter(slot)
        if state.phase ~= phase.portal or state.winner ~= slot then
            return false
        end
        state.phase = phase.boss
        return true
    end
    local function clear(slot)
        if state.phase ~= phase.boss or state.winner ~= slot then
            return false
        end
        state.scores[slot + 1] = state.scores[slot + 1] + 1
        state.phase = state.scores[slot + 1] >= 2 and phase.trophy or phase.reward
        return true
    end
    local function leave(slot)
        if state.phase ~= phase.reward or state.winner ~= slot then
            return false
        end
        state.phase = phase.loading
        return true
    end
    local function snapshot()
        return {
            state.round,
            state.phase,
            state.elapsed,
            state.winner,
            { table.unpack(state.scores) },
            state.alive,
        }
    end
    return {
        state = state,
        start = start,
        step = step,
        enter = enter,
        clear = clear,
        leave = leave,
        snapshot = snapshot,
    }
end
function rules.read(value)
    local f = rules.fields
    assert(type(value) == "table" and #value == 6, "Invalid battle royale state")
    local function integer(v, low, high)
        return math.type(v) == "integer" and v >= low and v <= high
    end
    assert(
        integer(value[f.round], 0, 1000000)
            and rules.phase[value[f.phase]] == value[f.phase]
            and integer(value[f.elapsed], 0, 2147483647)
            and integer(value[f.winner], -1, 3)
            and integer(value[f.alive], 0, 15)
            and type(value[f.scores]) == "table"
            and #value[f.scores] == 4,
        "Invalid battle royale fields"
    )
    for _, score in ipairs(value[f.scores]) do
        assert(integer(score, 0, 2), "Invalid battle royale score")
    end
    return {
        round = value[f.round],
        phase = value[f.phase],
        elapsed = value[f.elapsed],
        winner = value[f.winner],
        scores = { table.unpack(value[f.scores]) },
        alive = value[f.alive],
    }
end
return rules
