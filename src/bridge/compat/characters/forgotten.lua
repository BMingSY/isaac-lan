-- The tainted skeleton is moved by carrying/throwing, not directional input.
-- GetMovementInput returns the owner's input for both bodies in J510.
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
        departTrapdoor = function(player, room)
            if
                player:GetPlayerType() ~= types.PLAYER_THESOUL_B
                or player:IsCoopGhost()
                or not player:GetSprite():IsPlaying("Trapdoor")
            then
                return
            end
            local skeleton = player:GetOtherTwin()
            if
                skeleton
                and skeleton:GetPlayerType() == types.PLAYER_THEFORGOTTEN_B
                and not skeleton:IsCoopGhost()
                and room:GetGridIndex(skeleton.Position) == room:GetGridIndex(player.Position)
                and not skeleton:GetSprite():IsPlaying("Trapdoor")
            then
                -- Picking the skeleton up can replace the soul's exit pose on the next
                -- player update. Let the body at the same exit complete the native jump.
                skeleton:AnimateTrapdoor()
            end
        end,
        predictMovement = function(player)
            return player:GetPlayerType() ~= types.PLAYER_THEFORGOTTEN_B
        end,
    }
end
