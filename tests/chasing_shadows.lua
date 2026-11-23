local root = assert(arg[1])
local coordinator = dofile(root .. "/src/bridge/runtime/challenges.lua")
local shadows = dofile(root .. "/src/bridge/compat/challenges/chasing_shadows.lua")
local effects = dofile(root .. "/tests/fixtures/game_enums.lua").SeedEffect
local player, enemies = effects.SEED_INVISIBLE_ISAAC, effects.SEED_INVISIBLE_ENEMIES
for _, authority in ipairs({ 0, 1 }) do
    local info = {
        active = 1,
        ready = 0,
        authority = authority,
        challenge = 1007,
        challengeVersion = 1,
        runId = "first",
    }
    local active, writes = { unrelated = true }, 0
    local seeds = {
        HasSeedEffect = function(_, id)
            return active[id] == true
        end,
        AddSeedEffect = function(_, id)
            assert(not active[id], "Duplicate seed effect")
            active[id], writes = true, writes + 1
        end,
        RemoveSeedEffect = function(_, id)
            assert(active[id], "Removed an unrelated or missing seed effect")
            active[id], writes = nil, writes + 1
        end,
    }
    local game = function()
        return {
            GetSeeds = function()
                return seeds
            end,
            GetLevel = function()
                return {}
            end,
        }
    end
    local effect = shadows(game, effects)
    local challenge = coordinator({
        native = {
            api_info = function()
                return info
            end,
            net_challenges = function()
                return { ["1007"] = { id = 1007, version = 1 } }
            end,
        },
        game = game,
        effects = { [1007] = effect },
    })
    local update = authority == 1 and challenge.step or challenge.view
    update()
    assert(writes == 0 and not effect.active())
    challenge.gameStarted()
    assert(active[player] and active[enemies] and writes == 2 and effect.active())
    info.ready = 1
    update()
    challenge.level()
    update()
    assert(active[player] and active[enemies] and writes == 2)

    -- A rewound or reloaded game can lose a seed flag while retaining its run ID.
    active[enemies] = nil
    update()
    assert(active[enemies] and writes == 3)
    info.challenge = 0
    update()
    challenge.reset()
    assert(not active[player] and not active[enemies] and active.unrelated and writes == 5)
    assert(not effect.active())

    -- Rejoin a run with an existing player effect. The challenge owns only its addition.
    active[player] = true
    info.challenge, info.runId = 1007, "rejoined"
    update()
    assert(active[enemies] and writes == 6)
    challenge.reset()
    assert(active[player] and not active[enemies] and active.unrelated and writes == 7)
end
