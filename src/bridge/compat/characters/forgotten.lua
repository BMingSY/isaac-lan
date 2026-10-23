-- The tainted skeleton is moved by carrying/throwing, not directional input.
-- GetMovementInput returns the owner's input for both bodies in J460.
return function(types)
    return {
        subplayer = function(player)
            local kind = player:GetPlayerType()
            if kind == types.PLAYER_THEFORGOTTEN or kind == types.PLAYER_THESOUL then
                return player:GetSubPlayer()
            end
        end,
        predictMovement = function(player)
            return player:GetPlayerType() ~= types.PLAYER_THEFORGOTTEN_B
        end,
    }
end
