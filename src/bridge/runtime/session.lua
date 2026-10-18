-- Bridge startup owns one lifecycle. Transport phases only request launch;
-- readiness is published after native room/gate/restore have all succeeded.
return function(effects)
    for _, name in ipairs({
        "canStart",
        "start",
        "bindPlayers",
        "enableRooms",
        "gate",
        "restoreRooms",
        "close",
        "fail",
    }) do
        assert(type(effects[name]) == "function", "Missing session effect: " .. name)
    end
    local phase, generation = "idle", 0
    local function run(fn, current)
        local ok, result = pcall(fn)
        if not ok then
            if generation == current then
                phase = "failed"
                local needsExit = effects.fail(tostring(result))
                if generation == current and needsExit == false then
                    -- Rejected before native launch: no exit callback will
                    -- arrive to release this generation for retry or leaving.
                    phase = "idle"
                end
            end
            return false
        end
        return generation == current and phase ~= "failed"
    end
    return {
        active = function()
            return phase ~= "idle"
        end,
        ready = function()
            return phase == "ready"
        end,
        initializing = function()
            return phase == "initializing"
        end,
        launch = function()
            if phase ~= "idle" or not effects.canStart() then
                return false
            end
            -- Native start may synchronously invoke the game-start callback.
            phase = "starting"
            return run(effects.start, generation)
        end,
        gameStarted = function(continued)
            if phase ~= "starting" then
                return false
            end
            if continued then
                -- Continue must bind saved heads before the first native input
                -- update. Keep failures inside the same startup transaction.
                phase = "preparing"
                if
                    not run(function()
                        effects.bindPlayers(true)
                    end, generation)
                then
                    return false
                end
            end
            phase = "initializing"
            return true
        end,
        prepare = function()
            if phase ~= "initializing" then
                return false
            end
            phase = "preparing"
            local current = generation
            for _, effect in ipairs({
                effects.bindPlayers,
                effects.enableRooms,
                effects.gate,
                effects.restoreRooms,
            }) do
                if not run(effect, current) then
                    return false
                end
            end
            phase = "ready"
            return true
        end,
        close = function(preserve)
            -- Invalidate before native callbacks. A cancelled prepare cannot
            -- publish readiness or continue restoring the previous run.
            generation, phase = generation + 1, "idle"
            effects.close(preserve)
        end,
    }
end
