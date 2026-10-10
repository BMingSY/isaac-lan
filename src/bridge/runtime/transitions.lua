-- Reliable events enter through one epoch barrier before any native operation.
return function(native, floor, compatibility, level, resetView)
    return function(epoch, stage, stageType, animation, same, rewind, rKey, cinematic)
        if not floor.begin(epoch) then
            return false
        end
        resetView()
        local event = {
            epoch = epoch,
            stage = stage,
            stageType = stageType,
            animation = animation,
            same = same,
            rewind = rewind,
            rKey = rKey,
            cinematic = cinematic,
        }
        if compatibility.begin(native, event) then
            return true
        end
        level():SetStage(stage, stageType)
        assert(native.rooms_begin_floor(same and 1 or 0, animation), "Native floor event failed")
        return true
    end
end
