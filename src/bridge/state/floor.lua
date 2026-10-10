-- Reliable native floor events own transitions. A world snapshot can overtake
-- that event; it must wait, never regenerate a floor with stale route flags.
return function(native)
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
            -- Home's sleep marker changes day to night in place, without a
            -- floor transition. Replicas display that authoritative change.
            if currentStage == 13 and stage == 13 and currentType == 0 and stageType == 1 then
                level:SetStage(stage, stageType)
                currentType = stageType
            end
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
