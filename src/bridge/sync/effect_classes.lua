-- Bits name the engine effects eligible for a per-peer drawing budget.
local bloodParticle, bloodGib, bloodExplosion = 1, 2, 4
local classes = { all = bloodParticle | bloodGib | bloodExplosion }
function classes.mask(variants, variant, subtype)
    if variant == variants.BLOOD_PARTICLE then
        if subtype == nil then
            return bloodParticle | bloodGib
        end
        return subtype == 0 and bloodParticle or subtype == 99 and bloodGib or 0
    elseif variant == variants.BLOOD_EXPLOSION and (subtype == nil or subtype == 2) then
        return bloodExplosion
    end
    return 0
end
return classes
