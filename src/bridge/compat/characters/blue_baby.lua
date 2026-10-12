-- Queue restoration must not invoke UsePoopSpell or consume another spell.
return function(native, types)
    local blueBaby = assert(types.PLAYER_BLUEBABY_B or types.PLAYER_XXX_B)
    return {
        capture = function(p)
            if p:GetPlayerType() ~= blueBaby or p:IsCoopGhost() then
                return false
            end
            local queue = {}
            for i = 0, 5 do
                queue[#queue + 1] = p:GetPoopSpell(i)
            end
            return string.pack(">I4BBBBBB", p:GetPoopMana(), table.unpack(queue))
        end,
        apply = function(p, value)
            if value then
                assert(native.actor_poop(p:GetSprite(), value), "Cannot restore poop consumables")
            end
        end,
    }
end
