-- Native floor art, pressure plates, horn and collectible sprites. Glyphs are
-- small engraved city walls with countable battlements, never numeral labels.
return function(deps)
    local assets, previewItem, rockSheet, rockSheets
    local F = deps.rules.fields
    local function load()
        if assets then
            return
        end
        assets, rockSheets = {}, {}
        for name, texture in pairs({
            BASEMENT = "basement",
            CELLAR = "cellar",
            BURNT_BASEMENT = "burningbasement",
            CAVES = "caves",
            CATACOMBS = "catacombs",
            FLOODED_CAVES = "drownedcaves",
            DEPTHS = "depths",
            NECROPOLIS = "depths",
            DANK_DEPTHS = "depths",
            WOMB = "womb",
            UTERO = "utero",
            SCARRED_WOMB = "scarredwomb",
            BLUE_WOMB = "bluewomb",
            SHEOL = "sheol",
            CATHEDRAL = "cathedral",
            DARKROOM = "sheol",
            CHEST = "basement",
            DOWNPOUR = "downpour",
            DROSS = "dross",
            MINES = "secretroom",
            ASHPIT = "ashpit",
            MAUSOLEUM = "mausoleum",
            MAUSOLEUM2 = "mausoleum",
            MAUSOLEUM3 = "mausoleum",
            MAUSOLEUM4 = "mausoleum",
            GEHENNA = "gehenna",
            CORPSE = "corpse",
            CORPSE2 = "corpse2",
            CORPSE3 = "corpse3",
        }) do
            rockSheets[deps.backdrop[name]] = "gfx/grid/rocks_" .. texture .. ".png"
        end
        for name, path in pairs({
            plate = "gfx/grid/grid_pressureplate.anm2",
            rock = "gfx/grid/grid_rock.anm2",
            horn = "gfx/005.350_trinket.anm2",
            item = "gfx/005.100_collectible.anm2",
            fill = "gfx/ui/bossoverlay_whiteout.anm2",
        }) do
            local sprite = deps.sprite()
            sprite:Load(path, true)
            assets[name] = sprite
        end
        assets.fill:SetFrame("Fade", 15)
        assets.horn:ReplaceSpritesheet(0, "gfx/items/trinkets/trinket_035_curvedhorn.png")
        assets.horn:LoadGraphics()
        assets.horn:SetFrame("Idle", 0)
        assets.item:SetFrame("Idle", 0)
    end
    local function rect(x, y, w, h, color)
        assets.fill.Scale = deps.vector(w / 480, h / 270)
        assets.fill.Color =
            deps.color(0, 0, 0, color[4] or 1, color[1] - 1, color[2] - 1, color[3] - 1)
        assets.fill:Render(deps.vector(math.floor(x), math.floor(y)))
    end
    local function glyph(point, count, lit, faded)
        local dark = { 0.17, 0.13, 0.11, faded and 0.3 or 0.9 }
        local light = lit and { 0.94, 0.79, 0.39, 1 } or { 0.63, 0.59, 0.48, faded and 0.25 or 0.9 }
        local x, y = point.X - 11, point.Y - 6
        rect(x, y + 5, 22, 8, dark)
        rect(x + 1, y + 5, 20, 6, light)
        rect(x + 9, y + 7, 4, 6, dark)
        -- Evenly spaced towers: one to six; their shape stays recognisable on
        -- damp, bloody and dark backgrounds without replacing those backgrounds.
        local start = point.X - (count * 4 - 1) / 2
        for tower = 0, count - 1 do
            rect(start + tower * 4, y, 3, 6, dark)
            rect(start + tower * 4 + 1, y + 1, 1, 4, light)
        end
    end
    local function render()
        local info = deps.native.api_info()
        if info.active ~= 1 or info.ready ~= 1 or info.challenge ~= 0 then
            return
        end
        local view = deps.view()
        if not view then
            return
        end
        local game, level = deps.game(), deps.game():GetLevel()
        local desc = level:GetCurrentRoomDesc()
        local side = deps.rules.side(view, desc.SafeGridIndex)
        if not side then
            return
        end
        local main = level:GetRoomByIdx(desc.SafeGridIndex, 0)
        local mirror = not main or main.ListIndex ~= desc.ListIndex
        local reflected = level:GetRoomByIdx(desc.SafeGridIndex, 1)
        if mirror and (not reflected or reflected.ListIndex ~= desc.ListIndex) then
            return
        end
        load()
        local room = game:GetRoom()
        local function screen(position)
            local point = deps.screen(position)
            if room:IsMirrorWorld() then
                point = deps.vector(deps.width() - point.X, point.Y)
            end
            return point
        end
        local center = room:GetCenterPos()
        for index, offset in ipairs(deps.layout.plates) do
            local point = screen(center + deps.vector(offset[1], offset[2]))
            local active = not mirror and deps.rules.plateSide(index) == side
            local lit = not mirror and index <= view[F.progress]
            assets.plate.Scale = deps.vector(active and 1.15 or 0.95, active and 1.15 or 0.8)
            assets.plate.Color =
                deps.color(0.8, 0.78, 0.7, mirror and 0.28 or (active and 1 or 0.55))
            assets.plate:SetFrame(active and not lit and "Off" or "On", 0)
            assets.plate:Render(point)
            glyph(point, index, lit, mirror)
        end
        for _, offset in ipairs(deps.layout.horns) do
            local point = screen(center + deps.vector(offset[1], offset[2]))
            local lit = not mirror and view[F.progress] == deps.rules.sequenceLength
            assets.plate.Scale = deps.vector(1.4, 1.05)
            assets.plate.Color = deps.color(0.65, 0.61, 0.5, mirror and 0.2 or 0.65)
            assets.plate:SetFrame(lit and "Off" or "On", 0)
            assets.plate:Render(point)
            assets.horn.Color = deps.color(
                lit and 1 or 0.48,
                lit and 0.9 or 0.46,
                lit and 0.6 or 0.4,
                mirror and 0.18 or 0.9
            )
            assets.horn.Scale = deps.vector(0.9, 0.9)
            assets.horn:Render(point + deps.vector(0, 7))
        end
        if mirror or view[F.complete] then
            local path = rockSheets[room:GetBackdropType()] or "gfx/grid/rocks_basement.png"
            if path ~= rockSheet then
                assets.rock:ReplaceSpritesheet(0, path)
                assets.rock:LoadGraphics()
                rockSheet = path
            end
            assets.rock.Color = deps.color(0.6, 0.57, 0.5, mirror and 0.5 or 0.65)
            for index, offset in ipairs(deps.layout.walls) do
                assets.rock:SetFrame("rubble", (index - 1) % 4)
                assets.rock:Render(screen(center + deps.vector(offset[1], offset[2])))
            end
        else
            local item = side == 1 and view[F.firstItem] or view[F.secondItem]
            if previewItem ~= item then
                local config = deps.config():GetCollectible(item)
                if not config then
                    return
                end
                assets.item:ReplaceSpritesheet(1, config.GfxFileName)
                assets.item:LoadGraphics()
                previewItem = item
            end
            assets.item.Color = deps.color(0.8, 0.88, 1, 0.35)
            assets.item:Render(
                screen(center + deps.vector(0, -4 + math.sin(game:GetFrameCount() / 12) * 2))
            )
        end
    end
    return {
        render = render,
        reset = function()
            assets, previewItem, rockSheet, rockSheets = nil, nil, nil, nil
        end,
    }
end
