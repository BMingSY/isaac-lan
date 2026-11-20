-- Each game supplies its own menu paper, pointer and typography.
return function(resources, font)
    local assets = { characterPortraits = {} }
    local function sprite(path, animation, frame)
        local value = Sprite()
        value:Load(path, true)
        value:SetFrame(animation, frame or 0)
        return value
    end
    local root = "gfx/ui/main menu/"
    assets.sketches = sprite(root .. "charactermenubg.anm2", "Idle")
    assets.portraits = sprite(root .. "characterportraits.anm2", "01_Isaac")
    assets.characterSwap = sprite(root .. "pageswapwidget.anm2", "Idle")
    assets.characterSwap.Scale = Vector(0.4, 0.4)
    assets.marks = sprite("gfx/ui/completion_widget.anm2", "Idle")
    assets.fill = sprite("gfx/ui/bossoverlay_whiteout.anm2", "Fade", 15)
    assets[10], assets[12], assets[16] = font("small"), font("normal"), font("heading")
    if resources.native_lobby then
        local lobby = sprite(root .. "onlinelobby.anm2", "Background")
        local cards = sprite(root .. "onlinelobby.anm2", "PlayerInfo")
        local online = sprite(root .. "onlinemenu.anm2", "Idle")
        function assets.panel(origin, modes)
            lobby:RenderLayer(9, origin + Vector(9 + (modes and 128 or 0), 39))
        end
        function assets.banner(origin)
            lobby.Scale = Vector(1, 0.4)
            lobby:RenderLayer(39, origin + Vector(134, -63))
            lobby.Scale = Vector(1, 1)
        end
        function assets.pointer(origin, x, y)
            online:RenderLayer(4, origin + Vector(x - 70, y - 68))
        end
        function assets.seat(origin, x, y, slot)
            cards.Scale = Vector(1.25, 1)
            cards:RenderLayer(0, origin + Vector(x, y))
            cards:SetLayerFrame(36, slot)
            cards:RenderLayer(36, origin + Vector(x, y))
        end
        function assets.ready(origin, x, y)
            cards:RenderLayer(5, origin + Vector(x, y))
        end
    else
        -- The original challenge sheet is a pinned menu paper. Its seventh paper
        -- starts far down the scrolling challenge list, so anchor its visible art here.
        local paper = sprite(root .. "challengemenu.anm2", "Idle")
        local pinPaperLayer = 29
        local note = sprite(root .. "seedunlockpaper.anm2", "Idle")
        local cursor = sprite(root .. "gamemenu.anm2", "Idle")
        local cursorLayer = 6
        local check = sprite(root .. "seedsmenu.anm2", "Checkmark", 1)
        local checkLayer = 10
        local ink = KColor(0.18, 0.14, 0.14, 1)
        local title
        if resources.main_title then
            title = Sprite()
            title:Load(resources.main_title, false)
            if title:IsLoaded() then
                -- Layers use the two pages of Repentance's own Chinese menu font.
                local pages = { 1, 0, 0, 1, 1, 1, 1, 1, 1, 1 }
                for index, page in ipairs(pages) do
                    title:ReplaceSpritesheet(
                        index - 1,
                        "resources-dlc3.zh/font/TeamMeatFontExtended16Bold_" .. page .. ".png"
                    )
                end
                title:LoadGraphics()
                title.Rotation = -15
                title.Color = Color(0.18, 0.14, 0.14, 1, 0, 0, 0)
            else
                title = nil
            end
        end
        local animation
        function assets.mainEntry(x, y, language)
            if title then
                local nextAnimation = language == "zh" and "Chinese" or "English"
                if animation ~= nextAnimation then
                    animation = nextAnimation
                    title:SetFrame(animation, 0)
                end
                title:Render(Vector(x, y))
            else
                assets[16]:DrawStringUTF8(
                    language == "zh" and "联机模式" or "ONLINE",
                    x,
                    y,
                    ink,
                    0,
                    false
                )
            end
        end
        function assets.panel(origin, modes)
            paper.Scale = Vector(0.70, 0.80)
            paper:RenderLayer(pinPaperLayer, origin + Vector(-65 + (modes and 128 or 0), -624))
        end
        function assets.banner(origin)
            note.Scale = Vector(0.70, 0.22)
            note:RenderLayer(0, origin + Vector(240, 30))
        end
        function assets.pointer(origin, x, y)
            cursor:RenderLayer(cursorLayer, origin + Vector(x - 169, y - 69))
        end
        function assets.seat(origin, x, y, slot)
            note.Scale = Vector(0.46, 0.82)
            note:RenderLayer(0, origin + Vector(x + 68, y + 54))
            local font = assets[12]
            local label = "P" .. (slot + 1)
            font:DrawStringUTF8(
                label,
                origin.X + x + 68 - font:GetStringWidthUTF8(label) / 2,
                origin.Y + y + 8,
                ink,
                0,
                false
            )
        end
        function assets.ready(origin, x, y)
            check:RenderLayer(checkLayer, origin + Vector(x + 105, y + 18))
        end
    end
    return assets
end
