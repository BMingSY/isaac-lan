-- The tainted skeleton is moved by carrying/throwing, not directional input.
-- GetMovementInput returns the owner's input for both bodies in J460.
return function(types, native)
    local function paired(kind)
        return kind == types.PLAYER_THEFORGOTTEN or kind == types.PLAYER_THESOUL
    end
    return {
        restoreForm = function(player, desired)
            if not paired(player:GetPlayerType()) or not paired(desired) then
                return false
            end
            -- ChangePlayerType does not exchange the hidden body's health/type.
            -- Keep both native allocations and restore their active roles first.
            assert(
                native.actor_forgotten_form(player:GetSprite(), desired),
                "Cannot restore Forgotten form"
            )
            return true
        end,
        subplayer = function(player)
            if paired(player:GetPlayerType()) then
                return player:GetSubPlayer()
            end
        end,
        predictMovement = function(player)
            return player:GetPlayerType() ~= types.PLAYER_THEFORGOTTEN_B
        end,
    }
end
