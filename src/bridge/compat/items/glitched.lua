-- Glitched definitions use negative IDs, outside ItemConfig's static array.
local MAX_DEFINITIONS = 1024
return function(native)
    return {
        reader = function(player)
            local get = player.GetCollectibleNum
            -- Bind methods for this operation only; counts and generated IDs
            -- remain live, and a Mod may replace a method before the next call.
            return function(id)
                if id < 0 then
                    return assert(native.generated_item_count(player:GetSprite(), id))
                end
                return get(player, id, true)
            end
        end,
        count = function(player, id)
            if id < 0 then
                return assert(native.generated_item_count(player:GetSprite(), id))
            end
            return player:GetCollectibleNum(id, true)
        end,
        capture = function()
            return assert(native.generated_items())
        end,
        apply = function(value)
            assert(native.generated_items(value), "Cannot restore glitched item definitions")
        end,
        extraCollectibles = function(config)
            local result = {}
            for id = -1, -MAX_DEFINITIONS, -1 do
                if not config:GetCollectible(id) then
                    break
                end
                result[#result + 1] = id
            end
            return result
        end,
    }
end
