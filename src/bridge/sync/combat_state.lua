-- Authority facts used for speculative contact. Replica collision classes are
-- disabled, and a Mod may change a tear independently of its owner's stats.
return function(fields, variants, tearFlags, entityFlags)
    local C = fields.combat
    return function(entity)
        if entity:ToNPC() then
            return entity:IsVulnerableEnemy()
                    and not entity:HasEntityFlags(entityFlags.FLAG_NO_FLASH_ON_DAMAGE)
                    and C.target
                or C.none
        end
        local tear = entity:ToTear()
        if
            tear
            and tear.TearFlags == tearFlags.TEAR_NORMAL
            and tear.WaitFrames <= 0
            and (entity.Variant == variants.BLUE or entity.Variant == variants.BLOOD)
        then
            return C.projectile
        end
        return C.none
    end
end
