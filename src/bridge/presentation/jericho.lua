-- Countable stone seals and shofar reliefs share the authority contact layout.
-- Native floor art and rubble retain the current stage backdrop.
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
            seals = assert(deps.native.jericho_artwork),
            rock = "gfx/grid/grid_rock.anm2",
            item = "gfx/005.100_collectible.anm2",
        }) do
            local sprite = deps.sprite()
            sprite:Load(path, true)
            assets[name] = sprite
        end
        assets.item:SetFrame("Idle", 0)
    end
    local function localActors(info)
        local result = {}
        for _, actor in ipairs(deps.native.api_actors()) do
            if actor.owner == info.slot + 1 then
                local player = deps.player(actor.index)
                if player:Exists() and not player:IsDead() and not player:IsCoopGhost() then
                    result[#result + 1] = player
                end
            end
        end
        return result
    end
    local function opacity(players, point, radius)
        for _, player in ipairs(players) do
            local offset = player.Position - point
            if offset.X ^ 2 + offset.Y ^ 2 <= radius ^ 2 then
                return 0.25
            end
        end
        return 1
    end
    local function responding(players, center, side)
        local result = {}
        for _, player in ipairs(players) do
            local offset, shot = player.Position - center, player:GetShootingInput()
            local _, firing, horn = deps.layout.contact(offset.X, offset.Y, shot.X, shot.Y, side)
            if firing then
                result[horn] = true
            end
        end
        return result
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
        local players = localActors(info)
        for index, offset in ipairs(deps.layout.plates) do
            local position = center + deps.vector(offset[1], offset[2])
            local point = screen(position)
            local alpha = opacity(players, position, deps.layout.plateRadius)
            local active = not mirror and deps.rules.plateSide(index) == side
            local lit = not mirror and index <= view[F.progress]
            local scale = active and 1.15 or 0.95
            assets.seals.Scale = deps.vector(scale, scale)
            assets.seals.Color = lit and deps.color(1, 0.86, 0.52, alpha)
                or deps.color(
                    active and 1 or 0.72,
                    active and 1 or 0.72,
                    active and 1 or 0.72,
                    mirror and 0.24 or alpha
                )
            assets.seals:SetFrame("Seals", index - 1)
            assets.seals:Render(point)
        end
        local ready = not mirror and view[F.progress] == deps.rules.sequenceLength
        local response = ready and not view[F.complete] and responding(players, center, side) or {}
        for index, offset in ipairs(deps.layout.horns) do
            local position = center + deps.vector(offset[1], offset[2])
            local point = screen(position)
            local alpha = opacity(players, position, deps.layout.hornRadius)
            local sounding = response[index]
            local lit = ready and (view[F.complete] or sounding)
            local scale = sounding and 1.4 or 1.3
            assets.seals.Scale = deps.vector(scale, scale)
            assets.seals.Color = ready and deps.color(1, 1, 1, alpha)
                or deps.color(0.65, 0.65, 0.65, mirror and 0.2 or alpha * 0.8)
            assets.seals:SetFrame("Seals", lit and 7 or 6)
            assets.seals:Render(point)
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
