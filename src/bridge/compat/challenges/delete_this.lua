-- Grant the original challenge's starting item once per seat. The authority
-- owns later rerolls/removal; replica views and floor changes never re-grant it.
return function(deps)
    local initialized = {}
    local function initialize(info)
        if info.authority ~= 1 then
            return
        end
        for _, seat in ipairs(deps.party(info)) do
            if not initialized[seat.slot] then
                deps.scoped(seat, function()
                    if not seat.player:HasCollectible(deps.tmtrainer) then
                        seat.player:AddCollectible(deps.tmtrainer, 0, false)
                    end
                end)
                initialized[seat.slot] = true
            end
        end
    end
    return {
        reset = function()
            initialized = {}
        end,
        initialize = initialize,
        step = initialize,
        level = function() end,
        clearAward = function() end,
        collect = function() end,
    }
end
