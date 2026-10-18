-- The tainted skeleton is moved by carrying/throwing, not directional input.
-- GetMovementInput returns the owner's input for both bodies in J460.
return function(types)
    return {
        predictMovement = function(player)
            return player:GetPlayerType() ~= types.PLAYER_THEFORGOTTEN_B
        end,
    }
end
