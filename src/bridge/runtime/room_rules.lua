-- Authority lifecycle for optional rule effects. Network state carries options
-- and ordinary gameplay state; pending rule effects never run remotely.
return function(deps)
    local native, allocation, charge = deps.native, deps.allocation, deps.charge
    local gather = deps.gather
    local flags = {}
    for _, rule in ipairs(native.net_room_options()) do
        flags[rule.key] = rule.flag
    end
    local run, epoch
    local function reset()
        run, epoch = nil, nil
        allocation.reset()
        charge.reset()
        gather.reset()
    end
    local function current()
        local info = native.api_info()
        if info.active ~= 1 or info.authority ~= 1 or info.ready ~= 1 then
            reset()
            return
        end
        if info.runId ~= run or info.worldEpoch ~= epoch then
            reset()
            run, epoch = info.runId, info.worldEpoch
        end
        return info
    end
    local function enabled(info, key)
        return info
            and (info.roomOptions & assert(flags[key])) ~= 0
            and (not deps.allow or deps.allow(key))
    end
    return {
        reset = reset,
        collect = function(owner, ...)
            local info = current()
            if
                enabled(info, "lootRoll")
                and owner >= 0
                and owner < info.players
                and (info.connected & (1 << owner)) ~= 0
            then
                return allocation.collect(owner, ...)
            end
            return false
        end,
        cleared = function(...)
            local info = current()
            if enabled(info, "sharedClearCharge") then
                charge.record(...)
            end
        end,
        step = function()
            local info = current()
            if not info then
                return
            end
            if enabled(info, "lootRoll") then
                allocation.step(info, false)
            end
            if enabled(info, "sharedClearCharge") then
                charge.step(info)
            end
            if enabled(info, "specialRoomGather") then
                gather.step(info)
            else
                gather.reset()
            end
        end,
    }
end
