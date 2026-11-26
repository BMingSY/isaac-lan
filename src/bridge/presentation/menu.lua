-- The game's own menu sprites and bitmap fonts. No redistributed game assets.
local assets
local resources = _IsaacLan.presentation_assets
local menuLocale = _IsaacLanModules["presentation/menu_locale"]
-- Options.Language is valid once the game presents a menu.
local translate = menuLocale(true)
local function message(value, ...)
    return translate(value, ...)
end
local savedAddress, savedPort = _IsaacLan.menu_connection()
local ui = {
    ip = savedAddress,
    port = tostring(savedPort),
    seed = "",
    difficulty = 0,
    selection = 1,
    page = _IsaacLan.menu_official and "modes" or "lan",
    lastPhase = -1,
    errorText = "",
}
local Phase = _IsaacLan.net_phases()
local Command = _IsaacLan.net_commands()
local drawVote = _IsaacLanModules["presentation/vote_progress"](_IsaacLan.max_players)
local renderRestart = _IsaacLanModules["presentation/restart"](drawVote)
local renderSkip = _IsaacLanModules["presentation/animation_skip"](drawVote)
local renderPing = _IsaacLanModules["presentation/ping"](_IsaacLan, Phase)
-- menu_key reports Windows virtual-key codes from the native frontend.
local Key = {
    escape = 27,
    enter = 13,
    up = 38,
    down = 40,
    tab = 9,
    space = 32,
    left = 37,
    right = 39,
    toggle = 69,
}
local renderUpdateNotice = _IsaacLanModules["presentation/update_notice"](Key, _IsaacLan)
local characters = _IsaacLanModules["presentation/menu_characters"]()
local endpoint = _IsaacLanModules["core/endpoint"]
local model =
    _IsaacLanModules["presentation/menu_model"](Phase, Command, endpoint, characters, message)
local LIST_ROWS, LIST_TOP, LIST_GAP, LIST_BACK_Y = 6, 100, 17, 214
local CHARACTER_SWAP_ICON_LAYER, CHARACTER_SWAP_KEY_LAYER = 1, 2
local challenges = _IsaacLan.net_challenges()
local roomOptions = _IsaacLan.net_room_options()
local idle = model.idle
function _IsaacLanMenuOpen(returning)
    ui.page = not returning
            and _IsaacLan.menu_official
            and idle(_IsaacLanStatus().phase or Phase.idle)
            and "modes"
        or "lan"
    ui.selection, ui.editing = 1, nil
    ui.ruleReturn, ui.listScroll = nil, nil
    ui.autoReturn, ui.autoScroll = nil, nil
    _IsaacLan.menu_text_end()
end
local previousMouse = Vector(-1000, -1000)
local characterChoices, characterCatalog = {}, {}
local characterNames = {
    [PlayerType.PLAYER_ISAAC] = "以撒",
    [PlayerType.PLAYER_MAGDALENE] = "抹大拉",
    [PlayerType.PLAYER_CAIN] = "该隐",
    [PlayerType.PLAYER_JUDAS] = "犹大",
    [PlayerType.PLAYER_BLUEBABY] = "???",
    [PlayerType.PLAYER_EVE] = "夏娃",
    [PlayerType.PLAYER_SAMSON] = "参孙",
    [PlayerType.PLAYER_AZAZEL] = "阿撒泻勒",
    [PlayerType.PLAYER_LAZARUS] = "拉撒路",
    [PlayerType.PLAYER_EDEN] = "伊甸",
    [PlayerType.PLAYER_THELOST] = "游魂",
    [PlayerType.PLAYER_LAZARUS2] = "拉撒路",
    [PlayerType.PLAYER_BLACKJUDAS] = "犹大",
    [PlayerType.PLAYER_LILITH] = "莉莉丝",
    [PlayerType.PLAYER_KEEPER] = "店长",
    [PlayerType.PLAYER_APOLLYON] = "亚玻伦",
    [PlayerType.PLAYER_THEFORGOTTEN] = "遗骸",
    [PlayerType.PLAYER_THESOUL] = "灵魂",
    [PlayerType.PLAYER_BETHANY] = "伯大尼",
    [PlayerType.PLAYER_JACOB] = "雅各与以扫",
    [PlayerType.PLAYER_ESAU] = "以扫",
    [PlayerType.PLAYER_ISAAC_B] = "里·以撒",
    [PlayerType.PLAYER_MAGDALENE_B] = "里·抹大拉",
    [PlayerType.PLAYER_CAIN_B] = "里·该隐",
    [PlayerType.PLAYER_JUDAS_B] = "里·犹大",
    [PlayerType.PLAYER_BLUEBABY_B] = "里·???",
    [PlayerType.PLAYER_EVE_B] = "里·夏娃",
    [PlayerType.PLAYER_SAMSON_B] = "里·参孙",
    [PlayerType.PLAYER_AZAZEL_B] = "里·阿撒泻勒",
    [PlayerType.PLAYER_LAZARUS_B] = "里·拉撒路",
    [PlayerType.PLAYER_EDEN_B] = "里·伊甸",
    [PlayerType.PLAYER_THELOST_B] = "里·游魂",
    [PlayerType.PLAYER_LILITH_B] = "里·莉莉丝",
    [PlayerType.PLAYER_KEEPER_B] = "里·店长",
    [PlayerType.PLAYER_APOLLYON_B] = "里·亚玻伦",
    [PlayerType.PLAYER_THEFORGOTTEN_B] = "里·遗骸",
    [PlayerType.PLAYER_BETHANY_B] = "里·伯大尼",
    [PlayerType.PLAYER_JACOB_B] = "里·雅各",
    [PlayerType.PLAYER_LAZARUS2_B] = "里·拉撒路",
    [PlayerType.PLAYER_JACOB2_B] = "里·雅各",
    [PlayerType.PLAYER_THESOUL_B] = "里·灵魂",
}
local function character(id)
    if id == characters.random then
        return "?"
    end
    local entry = characterCatalog[tostring(id)]
    local name = characterNames[id]
    if not name then
        return (entry and entry.name) or message("角色 %d", id)
    end
    local tainted = name:match("^里·(.+)")
    return tainted and message("里·%s", message(tainted)) or message(name)
end
local function portrait(id)
    local entry = characterCatalog[tostring(id)]
    if entry and entry.portraitAnm2Path ~= "" and entry.animation ~= "" then
        local path = entry.portraitAnm2Path
        local sprite = assets.characterPortraits[path]
        if not sprite then
            sprite = Sprite()
            sprite:Load(path, true)
            assets.characterPortraits[path] = sprite
        end
        sprite:Play(entry.animation, true)
        if sprite:GetAnimation() == entry.animation then
            sprite:SetFrame(entry.animation, 0)
            return sprite
        end
    end
    assets.portraits:SetFrame("00_Random", 0)
    return assets.portraits
end
local ink = KColor(0.18, 0.14, 0.14, 1)
local faded = KColor(0.47, 0.42, 0.41, 1)
local red = KColor(0.44, 0.06, 0.06, 1)
local amber = KColor(0.45, 0.27, 0.06, 1)
local function load()
    local language = not resources.native_lobby and Options.Language
    local locale = menuLocale(resources.native_lobby, language)
    if assets and translate == locale then
        return
    end
    translate = locale
    assets = _IsaacLanModules["presentation/menu_assets"](
        resources,
        _IsaacLanModules["presentation/fonts"],
        language
    )
end
function _IsaacLanMainMenuEntry(x, y)
    load()
    if assets.mainEntry then
        assets.mainEntry(x, y, Options and Options.Language)
    end
end
function _IsaacLanMenuRender(
    available,
    visible,
    key,
    typed,
    mx,
    my,
    clicked,
    addresses,
    networkError,
    updateVersion,
    updateReleased
)
    local status = _IsaacLanStatus()
    local phase = status.phase or Phase.idle
    local playing = phase == Phase.running and status.prepared and not status.recovering
    if playing and not ui.wasPlaying then
        visible = false
    end
    ui.wasPlaying = playing
    if
        not visible
        and not available
        and not status.prepared
        and not status.recovering
        and phase ~= Phase.waiting
    then
        return false
    end
    load()
    local width, height = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    local origin = Vector((width - 480) / 2, (height - 270) / 2)
    local mouse = Vector(mx - origin.X, my - origin.Y)
    local moved = (mouse - previousMouse):LengthSquared() > 1
    previousMouse = mouse
    local function pos(x, y)
        return origin + Vector(x, y)
    end
    local function text(value, x, y, size, color, maxWidth)
        local font = assets[size or 12]
        value = tostring(value)
        local width = font:GetStringWidthUTF8(value)
        if maxWidth and width > maxWidth then
            local scale = maxWidth / width
            font:DrawStringScaledUTF8(
                value,
                origin.X + x,
                origin.Y + y,
                scale,
                scale,
                color or ink,
                0,
                false
            )
            return
        end
        font:DrawStringUTF8(value, origin.X + x, origin.Y + y, color or ink, 0, false)
    end
    local function centered(value, x, y, size, color, maxWidth)
        local font = assets[size or 12]
        local width = font:GetStringWidthUTF8(value)
        text(value, x - math.min(width, maxWidth or width) / 2, y, size, color, maxWidth)
    end
    local function pointer(x, y)
        assets.pointer(origin, x, y)
    end
    local function hit(x, y, w, h)
        return mouse.X >= x and mouse.X < x + w and mouse.Y >= y and mouse.Y < y + h
    end
    if available and updateVersion and updateVersion ~= "" then
        renderUpdateNotice(
            { key = key, clicked = clicked, moved = moved, released = updateReleased },
            {
                assets = assets,
                width = width,
                height = height,
                centered = function(value, ...)
                    centered(message(value), ...)
                end,
                panel = function()
                    assets.panel(origin, true)
                end,
                pointer = pointer,
                hit = hit,
            }
        )
        return false
    end
    if phase ~= ui.lastPhase then
        if phase == Phase.running and ui.lastPhase == Phase.lobby then
            visible = false
        end
        ui.selection, ui.editing, ui.lastPhase = 1, nil, phase
        if
            phase ~= Phase.lobby
            and (ui.page == "rules" or ui.page == "autoTeleport" or ui.page == "challenges")
        then
            ui.page, ui.ruleReturn, ui.listScroll = "lan", nil, nil
            ui.autoReturn, ui.autoScroll = nil, nil
        end
        _IsaacLan.menu_text_end()
    end
    if status.recovering then
        visible = true
        ui.page = "lan"
    end
    if key == Key.escape then
        if ui.editing then
            ui.editing = nil
            _IsaacLan.menu_text_end()
            key = 0
        elseif model.back(ui) then
            key = 0
        elseif
            _IsaacLan.menu_official
            and ui.page == "lan"
            and idle(phase)
            and not status.recovering
        then
            ui.page = "modes"
            ui.selection = 2
            key = 0
        elseif not status.recovering then
            visible = false
        end
    end
    if not visible then
        renderPing(status, assets[10])
        if (status.skipVotes or 0) ~= 0 then
            renderSkip(status, assets[10], message)
        else
            renderRestart(status, assets[10])
        end
        local banner
        if phase == Phase.waiting then
            banner = message("正在重连…")
        elseif status.prepared and (status.pause or 0) > 0 then
            banner =
                message("P%d 暂停了游戏，由发起者恢复", (status.pauseOwner or 0) + 1)
        end
        if banner then
            assets.banner(origin)
            centered(banner, 240, 24, 10)
        end
        return false
    end
    characterChoices, characterCatalog = _IsaacLan.net_characters()
    characterCatalog = characterCatalog or {}
    challenges = _IsaacLan.net_challenges()
    local challenge = challenges[tostring(status.challenge or 0)]
    assets.fill.Scale = Vector(width / 480, height / 270)
    assets.fill.Color = Color(0, 0, 0, 1, -0.20, -0.25, -0.26)
    assets.fill:Render(Vector.Zero)
    assets.sketches:RenderLayer(0, origin)
    local modes = ui.page == "modes"
    local shift = modes and 128 or 0
    assets.panel(origin, modes)
    local localSlot = status.slot or 0
    -- No seat exists until the host has accepted the connection. Default
    -- session values must not appear as a joined P1 after a failed attempt.
    local count = (
        phase == Phase.lobby
        or phase == Phase.running
        or phase == Phase.loading
        or phase == Phase.waiting
        or phase == Phase.returning
    )
            and (status.players or 0)
        or 0
    local host = status.hosting == 1
    local ready = status["ready" .. localSlot] == 1
    local choice = status["choice" .. localSlot] or 0
    local rows, notice, ruleCount = model.rows(ui, status, characterChoices, challenges, {
        command = _IsaacLanCommand,
        native = _IsaacLan,
        character = character,
        catalog = characterCatalog,
        accent = amber,
        options = roomOptions,
        hide = function()
            visible = false
        end,
    })
    local rulesPage = ruleCount ~= nil
    local listPage = rulesPage or ui.page == "challenges"
    local heading = message(
        modes and "联机模式"
            or ui.page == "autoTeleport" and "自动传送"
            or rulesPage and "房间规则"
            or ui.page == "challenges" and "联机挑战"
            or "局域网联机"
    )
    if resources.native_lobby then
        centered(heading, 110 + shift, 58, 16)
    end
    if rulesPage then
        centered(
            message(ui.page == "autoTeleport" and "已选 %d 类" or "已启用 %d 项", ruleCount)
                .. (
                    host and not (challenge and challenge.roomOptionsLocked) and ""
                    or message(" · 只读")
                ),
            110,
            82,
            10,
            faded
        )
    end
    if notice == "reconnecting" or notice == "reconnect_failed" then
        centered(
            message(notice == "reconnecting" and "正在重连…" or "重连失败，请重试"),
            110,
            100,
            12
        )
    elseif notice == "returning" then
        centered(message("队友结算中"), 110, 100, 12)
    elseif notice == "waiting" then
        centered(message("正在连接..."), 110, 100, 12)
    end
    local yStart = (
        status.recovering
        or phase == Phase.waiting
        or phase == Phase.loading
        or phase == Phase.connecting
        or phase == Phase.returning
    )
            and 157
        or (#rows > 7 and 82 or 89)
    local gap = #rows > 7 and 17 or (#rows > 6 and 19 or 23)
    if ui.editing then
        if ui.editing == "ip" then
            ui.ip = typed -- The native editor filters and bounds both typing and paste.
            if key == Key.enter then
                local host, port = endpoint.parse(typed)
                if host then
                    ui.ip, ui.port = host, tostring(port)
                end
            end
        elseif ui.editing == "port" then
            ui.port = typed:gsub("[^%d]", ""):sub(1, 5)
        else
            ui.seed = typed:upper():gsub("[^%w]", ""):sub(1, 8)
        end
        if key == Key.enter and (ui.editing ~= "port" or model.validPort(ui)) then
            if ui.editing ~= "seed" then
                model.remember(ui, _IsaacLan)
            end
            ui.editing = nil
            _IsaacLan.menu_text_end()
        end
        key = 0
    elseif #rows > 0 then
        if key == Key.up then
            ui.selection = (ui.selection - 2) % #rows + 1
        elseif key == Key.down or key == Key.tab then
            ui.selection = ui.selection % #rows + 1
        end
        ui.selection = math.min(ui.selection, #rows)
    end
    local activated = false
    local function renderRow(i, item, y, height)
        if moved and hit(38 + shift, y - 2, 147, height) and not ui.editing then
            ui.selection = i
        end
        if clicked and hit(38 + shift, y - 2, 147, height) then
            ui.selection = i
            if item.enabled and not activated then
                activated = true
                if item.toggle and hit(160 + shift, y - 3, 24, 18) then
                    if item.canToggle then
                        item.toggle()
                    end
                else
                    item.action()
                end
            end
        elseif i == ui.selection and not ui.editing and item.enabled and not activated then
            if key == Key.enter or key == Key.space then
                activated = true
                item.action()
            elseif item.change and (key == Key.left or key == Key.right) then
                activated = true
                item.change(key == Key.left and -1 or 1)
            elseif item.toggle and key == Key.toggle then
                activated = true
                item.toggle()
            end
        end
        local label = item.label
        if item.checked ~= nil then
            label = (item.checked and "[x] " or "[ ] ") .. label
        end
        if item.field and ui.editing == item.field then
            label = (item.field == "port" and message("端口：%s", ui.port) or ui[item.field])
                .. "_"
        end
        local labelX, maxWidth = 49 + shift, 138
        if item.toggle then
            maxWidth = 105
            assets.characterSwap.Color = Color(0.65, 0.65, 0.65, item.canToggle and 0.65 or 0.3)
            local hint = pos(173 + shift, y + 6)
            assets.characterSwap:RenderLayer(CHARACTER_SWAP_ICON_LAYER, hint)
            assets.characterSwap:RenderLayer(CHARACTER_SWAP_KEY_LAYER, hint)
        end
        local size = assets[12]:GetStringWidthUTF8(label) > maxWidth and 10 or 12
        text(label, labelX, y, size, item.color or (item.enabled and ink or faded), maxWidth)
        if i == ui.selection then
            pointer(37 + shift, y + 5)
        end
    end
    if listPage then
        local total = #rows - 1
        local maxFirst = math.max(1, total - LIST_ROWS + 1)
        local first = math.min(ui.listScroll or 1, maxFirst)
        if ui.selection <= total then
            first = math.min(first, ui.selection)
            first = math.max(first, ui.selection - LIST_ROWS + 1)
        end
        if total > LIST_ROWS then
            local function scroll(x, delta, label, enabled)
                text(label, x, 198, 10, enabled and ink or faded)
                if clicked and enabled and hit(x - 3, 195, 18, 16) then
                    first = math.max(1, math.min(maxFirst, first + delta))
                    ui.selection = first
                end
            end
            scroll(156, -LIST_ROWS, "↑", first > 1)
            scroll(177, LIST_ROWS, "↓", first < maxFirst)
            text(
                first .. "-" .. math.min(total, first + LIST_ROWS - 1) .. " / " .. total,
                49,
                198,
                10,
                faded
            )
        end
        ui.listScroll = first
        for i = first, math.min(total, first + LIST_ROWS - 1) do
            renderRow(i, rows[i], LIST_TOP + (i - first) * LIST_GAP, LIST_GAP)
        end
        renderRow(#rows, rows[#rows], LIST_BACK_Y, 22)
    else
        for i, item in ipairs(rows) do
            renderRow(i, item, yStart + (i - 1) * gap, math.min(gap, 22))
        end
    end
    if not modes and count > 4 then
        for i = 0, count - 1 do
            local x, y = 198 + (i % 2) * 132, 30 + (i // 2) * 50
            local id = status[(phase == Phase.lobby and "choice" or "character") .. i] or 0
            if phase == Phase.lobby and status["random" .. i] then
                id = characters.random
            end
            local label = phase == Phase.lobby
                    and (status["ready" .. i] == 1 and "已准备" or "选择中")
                or ((status.connected or 0) & (1 << i) ~= 0 and "在线" or "等待归队")
            text(
                "P" .. (i + 1) .. "  " .. character(id),
                x,
                y,
                12,
                i == localSlot and amber or ink,
                122
            )
            text(message(label), x, y + 16, 10, faded)
        end
    else
        for i = 0, ((modes or count == 0) and -1 or 3) do
            local x, y = 198 + (i % 2) * 132, 17 + math.floor(i / 2) * 108
            assets.seat(origin, x, y, i)
            if i < count then
                local id = status[(phase == Phase.lobby and "choice" or "character") .. i] or 0
                local marks = phase == Phase.lobby and status["marks" .. i] or nil
                if phase == Phase.lobby and status["random" .. i] then
                    id, marks = characters.random, nil
                end
                local portraitX = x + (marks and 34 or 63)
                portrait(id):Render(pos(portraitX, y + 45))
                if id ~= characters.random then
                    centered(character(id), portraitX, y + 66, 10, nil, marks and 60 or 110)
                end
                if marks then
                    assets.marks.Scale = Vector(0.65, 0.65)
                    for layerId, state in ipairs(marks) do
                        assets.marks:SetLayerFrame(layerId - 1, state)
                    end
                    assets.marks:Render(pos(x + 65, y + 26))
                end
                if phase == Phase.lobby and status["ready" .. i] == 1 then
                    assets.ready(origin, x, y)
                    centered(message("已准备"), x + 63, y + 78, 10, ink)
                else
                    centered(
                        message(
                            phase == Phase.lobby and "选择中"
                                or (
                                    (status.connected or 0) & (1 << i) ~= 0 and "在线"
                                    or "等待归队"
                                )
                        ),
                        x + 63,
                        y + 78,
                        10
                    )
                end
            else
                centered(message("等待玩家"), x + 63, y + 52, 10, faded)
            end
        end
    end
    local errorText = status.saveError and status.saveError ~= "" and status.saveError
        or (ui.errorText ~= "" and ui.errorText or networkError)
    local compatibilityLines = (not status.saveError or status.saveError == "")
        and ui.errorText == ""
        and model.compatibilityError(status)
    local messageColor = red
    local selected = rows[ui.selection]
    if errorText == "" and ui.page == "challenges" and selected and selected.unlockHint then
        errorText = message(selected.unlockHint)
    end
    if
        errorText == ""
        and ui.page == "lan"
        and phase == Phase.lobby
        and challenge
        and challenge.nextBag == 1
    then
        local missing = {}
        for i = 0, count - 1 do
            if status["eligible" .. i] ~= true then
                missing[#missing + 1] = "P" .. (i + 1)
            end
        end
        if #missing > 0 then
            errorText =
                message("%s 需解锁底片与里该隐", table.concat(missing, message("、")))
        end
    end
    if errorText == "" and status.modMismatch == 1 then
        errorText = message("Mod 不一致或无法核对，可能会造成未知的影响")
        messageColor = amber
    end
    local footerY = compatibilityLines and 206 or (errorText ~= "" and 235 or 243)
    if not listPage and phase == Phase.lobby then
        if not host then
            text(message("房主地址：%s", ui.ip), 25, footerY - 12, 10)
        end
        text(
            message("%s 端口：%s", status.transport:upper(), host and status.port or ui.port),
            25,
            footerY,
            10
        )
    end
    if compatibilityLines then
        for i, line in ipairs(compatibilityLines) do
            centered(line, 240, 212 + i * 12, 10, red, 430)
        end
    elseif errorText ~= "" then
        if resources.native_lobby then
            centered(errorText:sub(1, 100), 240, 250, 10, messageColor)
        else
            centered(message(errorText), 240, 250, 10, messageColor, 430)
        end
    end
    -- Repentance queues font quads. Draw its heading after the cursor and cards
    -- so their native sprite submissions cannot overwrite its glyph vertices.
    if not resources.native_lobby then
        centered(heading, 110 + shift, 58, 16, nil, 146)
    end
    return visible
end
