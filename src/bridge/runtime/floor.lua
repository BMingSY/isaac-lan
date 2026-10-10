-- Reliable native floor events own transitions. A world snapshot can overtake
-- that event; it must wait, never regenerate a floor with stale route flags.
return function(native, home)
    local epoch, awaiting = nil, false
    return {
        reset = function()
            epoch, awaiting = nil, false
        end,
        begin = function(nextEpoch)
            if epoch and nextEpoch <= epoch then
                return false
            end
            epoch, awaiting = nextEpoch, true
            return true
        end,
        ready = function(level, nextEpoch, stage, stageType)
            if not native.rooms_ready() then
                return false
            end
            local currentStage, currentType = level:GetStage(), level:GetStageType()
            if epoch == nil and currentStage == stage and currentType == stageType then
                epoch = nextEpoch
            end
            if nextEpoch ~= epoch then
                return false
            end
            awaiting = false
            home.reconcileFloor(level, stage, stageType)
            currentType = level:GetStageType()
            assert(
                currentStage == stage and currentType == stageType,
                "Replica floor initialization failed"
            )
            return true
        end,
        waiting = function()
            return awaiting and not native.rooms_ready()
        end,
    }
end
