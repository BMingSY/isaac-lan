local DOGMA_INTERLUDE = 25
return function(stages, stageTypes)
    return {
        id = "routes.home",
        matches = function(event)
            return event.cinematic == DOGMA_INTERLUDE
        end,
        begin = function(native)
            assert(native.rooms_begin_cinematic(), "Native Dogma interlude failed")
        end,
        reconcileFloor = function(level, stage, stageType)
            -- The native sleep marker changes Home day to night in place.
            if
                level:GetStage() == stages.STAGE8
                and stage == stages.STAGE8
                and level:GetStageType() == stageTypes.STAGETYPE_ORIGINAL
                and stageType == stageTypes.STAGETYPE_WOTL
            then
                level:SetStage(stage, stageType)
            end
        end,
    }
end
