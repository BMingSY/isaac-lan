return function(game, seedEffect)
    local required = { seedEffect.SEED_INVISIBLE_ISAAC, seedEffect.SEED_INVISIBLE_ENEMIES }
    local active, added = false, {}
    local function apply()
        active = true
        local seeds = game():GetSeeds()
        for _, effect in ipairs(required) do
            if not seeds:HasSeedEffect(effect) then
                seeds:AddSeedEffect(effect)
                added[effect] = true
            end
        end
    end
    local function reset()
        active = false
        if next(added) then
            local seeds = game():GetSeeds()
            for effect in pairs(added) do
                if seeds:HasSeedEffect(effect) then
                    seeds:RemoveSeedEffect(effect)
                end
            end
            added = {}
        end
    end
    return {
        active = function()
            return active
        end,
        gameStarted = apply,
        initialize = apply,
        step = apply,
        reset = reset,
        level = function() end,
        clearAward = function() end,
        collect = function() end,
    }
end
