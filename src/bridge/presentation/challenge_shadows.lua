-- Native invisibility clears the generic ground shadow. Some sprites (e.g. Monstro)
-- carry an animated shadow layer of their own, which the game still draws.
return function(active, hasShadowLayer)
    local shadow
    local shadowLayer, frameRadius = 1, 33
    return function(_, entity, offset)
        if not active() or (entity.Type ~= EntityType.ENTITY_PLAYER and not entity:IsEnemy()) then
            return
        end
        local game = Game()
        local room = game:GetRoom()
        if
            room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
            or hasShadowLayer(entity:GetSprite())
        then
            return
        end
        if not shadow then
            shadow = Sprite()
            -- Idle layer 1 is the game's centered 66-pixel-wide ground shadow.
            shadow:Load("gfx/005.390_moms chest.anm2", true)
            shadow:SetFrame("Idle", 0)
            shadow.Color = Color(1, 1, 1, 0.24)
        end
        local scale = math.max(6, entity.Size * 0.85) / frameRadius
        shadow.Scale = Vector(scale, scale)
        local ground = Isaac.WorldToScreen(entity.Position)
            + offset
            - room:GetRenderScrollOffset()
            - game.ScreenShakeOffset
        shadow:RenderLayer(shadowLayer, ground)
    end
end
