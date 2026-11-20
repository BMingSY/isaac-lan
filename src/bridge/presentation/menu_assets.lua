-- Load only the resources declared by the selected backend. Vanilla Repentance
-- uses the common whiteout sprite for paper panels, without online DLC artwork.
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
        local paper = { 0.82, 0.77, 0.66 }
        local edge = { 0.28, 0.22, 0.17 }
        local shadow = { 0.12, 0.10, 0.08 }
        local colors = {
            KColor(0.45, 0.12, 0.10, 1),
            KColor(0.10, 0.23, 0.40, 1),
            KColor(0.40, 0.30, 0.08, 1),
            KColor(0.13, 0.32, 0.16, 1),
        }
        local function rect(origin, x, y, width, height, color)
            assets.fill.Scale = Vector(width / 480, height / 270)
            assets.fill.Color = Color(0, 0, 0, 1, color[1] - 1, color[2] - 1, color[3] - 1)
            assets.fill:Render(origin + Vector(x, y))
        end
        local function panel(origin, x, y, width, height)
            rect(origin, x + 3, y + 3, width, height, shadow)
            rect(origin, x, y, width, height, edge)
            rect(origin, x + 1, y + 1, width - 2, height - 2, paper)
        end
        function assets.panel(origin, modes)
            panel(origin, 15 + (modes and 128 or 0), 45, 185, 181)
        end
        function assets.banner(origin)
            panel(origin, 80, 19, 320, 20)
        end
        function assets.pointer(origin, x, y)
            for step = 0, 4 do
                rect(origin, x + step, y + step, 1, 9 - step * 2, edge)
            end
        end
        function assets.seat(origin, x, y, slot)
            panel(origin, x + 2, y + 4, 123, 100)
            assets[10]:DrawStringUTF8(
                "P" .. (slot + 1),
                origin.X + x + 8,
                origin.Y + y + 9,
                colors[slot + 1],
                0,
                false
            )
        end
        function assets.ready(origin, x, y)
            local green = { 0.13, 0.32, 0.16 }
            for step = 0, 2 do
                rect(origin, x + 104 + step, y + 13 + step, 2, 2, green)
            end
            for step = 0, 5 do
                rect(origin, x + 107 + step, y + 15 - step, 2, 2, green)
            end
        end
    end
    return assets
end
