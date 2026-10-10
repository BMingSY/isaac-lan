return {
    id = "routes.home",
    matches = function(event)
        return event.cinematic == 25
    end,
    begin = function(native)
        assert(native.rooms_begin_cinematic(), "Native Dogma interlude failed")
    end,
    reconcileFloor = function(level, stage, stageType)
        -- The native sleep marker changes Home day to night in place.
        if
            level:GetStage() == 13
            and stage == 13
            and level:GetStageType() == 0
            and stageType == 1
        then
            level:SetStage(stage, stageType)
        end
    end,
}
