-- Native artwork and geometric progress only; no gameplay decisions or labels.
return function(deps)
    local assets, animationFrame
    local function load()
        if assets then
            return
        end
        assets = {}
        for name, path in pairs({
            fill = "gfx/ui/bossoverlay_whiteout.anm2",
            trophy = "gfx/005.370_trophy.anm2",
            portal = "gfx/1000.161_portal teleport.anm2",
        }) do
            local sprite = deps.sprite()
            sprite:Load(path, true)
            sprite:Play(sprite:GetDefaultAnimation(), true)
            assets[name] = sprite
        end
        assets.fill:SetFrame("Fade", 15)
        assets.trophy:SetFrame("Idle", 0)
        assets.trophy.Scale = deps.vector(0.45, 0.45)
    end
    local function rect(x, y, w, h, r, g, b, alpha)
        assets.fill.Scale = deps.vector(w / 480, h / 270)
        assets.fill.Color = deps.color(0, 0, 0, alpha or 1, r - 1, g - 1, b - 1)
        assets.fill:Render(deps.vector(x, y))
    end
    local function render()
        local info = deps.native.api_info()
        if info.active ~= 1 or info.ready ~= 1 or info.challenge ~= deps.rules.id then
            return
        end
        local view = deps.view()
        if not view then
            return
        end
        load()
        for key, hud in pairs(deps.native.presentation_player_huds()) do
            local slot = tonumber(key)
            local wins = view.scores[slot + 1]
            -- Ping owns the row immediately above hearts; progress sits above it.
            local x = math.max(2, math.min(deps.width() - 45, hud.x + 12))
            local y = math.max(3, hud.y - 23)
            rect(x - 1, y - 1, 34, 7, 0.12, 0.08, 0.06)
            for point = 1, 2 do
                local filled = wins >= point
                rect(
                    x + (point - 1) * 17,
                    y,
                    15,
                    5,
                    filled and 0.91 or 0.32,
                    filled and 0.72 or 0.26,
                    filled and 0.21 or 0.22
                )
            end
            if wins >= 1 then
                assets.trophy:Render(deps.vector(x + 39, y + 12))
            end
        end
        -- A compact discovered-map-independent zone diagram keeps the shrinking
        -- safe area readable without revealing opponents or unexplored rooms.
        local zone = deps.rules.zone(view.elapsed)
        local size, scale = 13, 2
        local x, y = deps.width() - 35, deps.height() - 39
        rect(x - 2, y - 2, size * scale + 4, size * scale + 4, 0.10, 0.07, 0.06, 0.85)
        rect(x, y, size * scale, size * scale, 0.45, 0.12, 0.12, 0.8)
        rect(
            x + zone.left * scale,
            y + zone.top * scale,
            (zone.right - zone.left + 1) * scale,
            (zone.bottom - zone.top + 1) * scale,
            0.32,
            0.61,
            0.34,
            0.9
        )
        local at = deps.native.rooms_positions()[tostring(info.slot)]
        if at and at.dimension == 0 and at.index >= 0 and at.index < 169 then
            rect(
                x + (at.index % size) * scale,
                y + (at.index // size) * scale,
                scale,
                scale,
                1,
                0.92,
                0.62
            )
        end
        local remaining = math.max(0, 1 - view.elapsed / deps.rules.survivalFrames)
        rect(x, y + size * scale + 2, size * scale * remaining, 2, 0.91, 0.72, 0.21)
        local portal = view.portal
        if portal and at and portal.room == at.index and portal.dimension == at.dimension then
            local frame = deps.game():GetFrameCount()
            if frame ~= animationFrame then
                assets.portal:Update()
                if assets.portal:IsFinished(assets.portal:GetAnimation()) then
                    assets.portal:Play(assets.portal:GetDefaultAnimation(), true)
                end
                animationFrame = frame
            end
            assets.portal:Render(deps.screen(deps.vector(portal.x, portal.y)))
        end
    end
    return { render = render }
end
