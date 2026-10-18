-- Native R Key artwork, with a pixel ring split between the connected players.
return function()
    local fill, icon
    local rings = {}
    local radius, thickness, iconScale = 17, 2, 1
    local itemLayer, itemLift = 1, 22 -- Visible R Key center in collectible Idle's head layer.
    local function ring(count)
        if rings[count] then
            return rings[count]
        end
        local spans, sector = {}, 2 * math.pi / count
        for y = -radius, radius do
            local start, previous
            for x = -radius, radius + 1 do
                local distance = math.sqrt(x * x + y * y)
                local angle = (math.atan(y, x) + math.pi / 2) % (2 * math.pi)
                local within = angle % sector
                local part = distance >= radius - thickness
                        and distance <= radius
                        and within > 0.06
                        and within < sector - 0.06
                        and math.floor(angle / sector) + 1
                    or nil
                if part ~= previous then
                    if previous then
                        spans[#spans + 1] = { x = start, y = y, width = x - start, part = previous }
                    end
                    start, previous = x, part
                end
            end
        end
        rings[count] = spans
        return spans
    end
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
            icon.Scale = Vector(iconScale, iconScale)
            fill = Sprite()
            fill:Load("gfx/ui/bossoverlay_whiteout.anm2", true)
            fill:SetFrame("Fade", 15)
        end
        local agreed, accepted = {}, 0
        for slot = 0, 3 do
            if (members & (1 << slot)) ~= 0 then
                local voted = (votes & (1 << slot)) ~= 0
                agreed[#agreed + 1] = voted
                accepted = accepted + (voted and 1 or 0)
            end
        end
        local cx, cy = math.floor(Isaac.GetScreenWidth() / 2), Isaac.GetScreenHeight() - 34
        local function rect(x, y, w, h, r, g, b)
            fill.Scale = Vector(w / 480, h / 270)
            fill.Color = Color(0, 0, 0, 0.92, r - 1, g - 1, b - 1)
            fill:Render(Vector(cx + x, cy + y))
        end
        local spans = ring(#agreed)
        for _, span in ipairs(spans) do
            rect(span.x - 1, span.y - 1, span.width + 2, 3, 0.10, 0.08, 0.07)
        end
        for _, span in ipairs(spans) do
            local lit = agreed[span.part]
            rect(
                span.x,
                span.y,
                span.width,
                1,
                lit and 0.88 or 0.35,
                lit and 0.80 or 0.30,
                lit and 0.62 or 0.25
            )
        end
        icon:RenderLayer(itemLayer, Vector(cx, cy + itemLift * iconScale))
        local label, scale = accepted .. "/" .. #agreed, 0.8
        local x, y = math.floor(cx - font:GetStringWidthUTF8(label) * scale / 2), cy + radius + 3
        font:DrawStringScaledUTF8(
            label,
            x + 1,
            y + 1,
            scale,
            scale,
            KColor(0.08, 0.06, 0.05, 0.9),
            0,
            false
        )
        font:DrawStringScaledUTF8(label, x, y, scale, scale, KColor(0.91, 0.87, 0.78, 1), 0, false)
    end
end
