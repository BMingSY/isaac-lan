-- Native R Key artwork inside the shared consent ring.
return function(drawProgress)
    local icon
    local itemLayer, itemLift = 1, 22
    return function(status, font)
        local votes, members = status.restartVotes or 0, status.restartMembers or 0
        if votes == 0 or members == 0 then
            return
        end
        if not icon then
            icon = Sprite()
            icon:Load("gfx/005.100_collectible.anm2", true)
            icon:ReplaceSpritesheet(
                itemLayer,
                Isaac.GetItemConfig():GetCollectible(CollectibleType.COLLECTIBLE_R_KEY).GfxFileName
            )
            icon:LoadGraphics()
            icon:SetFrame("Idle", 0)
        end
        drawProgress(votes, members, font, function(cx, cy)
            icon:RenderLayer(itemLayer, Vector(cx, cy + itemLift))
        end)
    end
end
