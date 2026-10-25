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
    local function minimap(view)
        if view.phase ~= deps.rules.phase.survival or not view.zones then
            return
        end
        local zone, step = deps.rules.zone(view)
        local nextZone = step < #view.zones and deps.rules.bounds(view.zones, step + 1)
        local deadline = deps.rules.shrinkFrames[step] or deps.rules.survivalFrames
        local start = deps.rules.shrinkFrames[step - 1] or 0
        local remaining = math.max(0, (deadline - view.elapsed) / (deadline - start))
        for _, map in pairs(deps.native.presentation_minimap()) do
            if map.dimension == 0 and map.alpha > 0 then
                local function clipped(x, y, w, h, r, g, b, alpha)
                    local right, bottom = math.min(map.right, x + w), math.min(map.bottom, y + h)
                    x, y = math.max(map.left, x), math.max(map.top, y)
                    if right > x and bottom > y then
                        rect(x, y, right - x, bottom - y, r, g, b, alpha * map.alpha)
                    end
                end
                local function bounds(area)
                    return map.x + (area.left - 0.5) * map.cellWidth,
                        map.y + (area.top - 0.5) * map.cellHeight,
                        map.x + (area.right + 0.5) * map.cellWidth,
                        map.y + (area.bottom + 0.5) * map.cellHeight
                end
                local function outline(area, dashed, r, g, b)
                    local left, top, right, bottom = bounds(area)
                    local stride = dashed and 5 or math.max(right - left, bottom - top)
                    local length = dashed and 3 or stride
                    for x = left, right - 1, stride do
                        clipped(x, top, math.min(length, right - x), 1, r, g, b, 0.9)
                        clipped(x, bottom - 1, math.min(length, right - x), 1, r, g, b, 0.9)
                    end
                    for y = top, bottom - 1, stride do
                        clipped(left, y, 1, math.min(length, bottom - y), r, g, b, 0.9)
                        clipped(right - 1, y, 1, math.min(length, bottom - y), r, g, b, 0.9)
                    end
                end
                -- Tint only the unsafe part of the existing map's viewport.
                -- Room icons, discovery, zoom, placement and opacity stay native.
                local left, top, right, bottom = bounds(zone)
                clipped(
                    map.left,
                    map.top,
                    map.right - map.left,
                    top - map.top,
                    0.65,
                    0.16,
                    0.13,
                    0.2
                )
                clipped(
                    map.left,
                    bottom,
                    map.right - map.left,
                    map.bottom - bottom,
                    0.65,
                    0.16,
                    0.13,
                    0.2
                )
                clipped(map.left, top, left - map.left, bottom - top, 0.65, 0.16, 0.13, 0.2)
                clipped(right, top, map.right - right, bottom - top, 0.65, 0.16, 0.13, 0.2)
                outline(zone, false, 0.9, 0.85, 0.69)
                if nextZone then
                    outline(nextZone, true, 0.95, 0.67, 0.25)
                end
                local width = math.min(70, map.right - map.left)
                rect(map.right - width, map.bottom + 2, width, 2, 0.18, 0.13, 0.1, map.alpha * 0.8)
                rect(
                    map.right - width,
                    map.bottom + 2,
                    width * remaining,
                    2,
                    0.95,
                    0.67,
                    0.25,
                    map.alpha
                )
            end
        end
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
        local at = deps.native.rooms_positions()[tostring(info.slot)]
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
    local function renderMap()
        local info = deps.native.api_info()
        if info.active ~= 1 or info.ready ~= 1 or info.challenge ~= deps.rules.id then
            return
        end
        local view = deps.view()
        if view then
            load()
            minimap(view)
        end
    end
    return { render = render, renderMap = renderMap }
end
