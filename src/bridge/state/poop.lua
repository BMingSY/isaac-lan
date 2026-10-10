-- Queue restoration must not invoke UsePoopSpell or consume another spell.
return function(native)
    return {
        capture = function(p)
            if p:GetPlayerType() ~= 25 or p:IsCoopGhost() then
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
