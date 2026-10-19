-- The game's own menu sprites and bitmap fonts. No redistributed game assets.
local assets
local ui = {
    ip = "",
    port = "29506",
    seed = "",
    difficulty = 0,
    selection = 1,
    page = "modes",
    lastPhase = -1,
    errorText = "",
}
local Phase = _IsaacLan.net_phases()
local Command = _IsaacLan.net_commands()
local renderRestart = _IsaacLanModules["presentation/restart"]()
local renderPing = _IsaacLanModules["presentation/ping"](_IsaacLan, Phase)
-- menu_key reports Windows virtual-key codes from the native frontend.
local Key =
    { escape = 27, enter = 13, up = 38, down = 40, tab = 9, space = 32, left = 37, right = 39 }
local model = _IsaacLanModules["presentation/menu_model"](Phase, Command)
local challenges = _IsaacLan.net_challenges()
local idle = model.idle
function _IsaacLanMenuOpen(returning)
    ui.page = not returning and idle(_IsaacLanStatus().phase or Phase.idle) and "modes" or "lan"
    ui.selection, ui.editing = 1, nil
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
    local entry = characterCatalog[tostring(id)]
    return characterNames[id] or (entry and entry.name) or ("角色 " .. id)
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
    if assets then
        return
    end
    assets = { characterPortraits = {} }
    local function sprite(name, path, animation)
        local s = Sprite()
        s:Load(path, true)
        s:SetFrame(animation, 0)
        assets[name] = s
    end
    local root = "gfx/ui/main menu/"
    sprite("lobby", root .. "onlinelobby.anm2", "Background")
    sprite("cards", root .. "onlinelobby.anm2", "PlayerInfo")
    sprite("online", root .. "onlinemenu.anm2", "Idle")
    sprite("sketches", root .. "charactermenubg.anm2", "Idle")
    sprite("portraits", root .. "characterportraits.anm2", "01_Isaac")
    sprite("fill", "gfx/ui/bossoverlay_whiteout.anm2", "Fade")
    assets.fill:SetFrame("Fade", 15)
    for _, size in ipairs({ 10, 12, 16 }) do
        local font = Font()
        font:Load("font/TeamMeatEx/TeamMeatEx" .. size .. ".fnt")
        assert(font:IsLoaded(), "Cannot load the game's menu font")
        assets[size] = font
    end
    Isaac.DebugString("ISAAC_LAN NATIVE_MENU sprites=onlinelobby fonts=TeamMeatEx")
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
    networkError
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
    local function layer(sprite, id, x, y)
        sprite:RenderLayer(id, pos(x, y))
    end
    local function pointer(x, y)
        layer(assets.online, 4, x - 70, y - 68)
    end
    local function hit(x, y, w, h)
        return mouse.X >= x and mouse.X < x + w and mouse.Y >= y and mouse.Y < y + h
    end
    if phase ~= ui.lastPhase then
        if phase == Phase.running and ui.lastPhase == Phase.lobby then
            visible = false
        end
        ui.selection, ui.editing, ui.lastPhase = 1, nil, phase
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
        elseif ui.page == "challenges" then
            ui.page, ui.selection, key = "lan", 3, 0
        elseif ui.page == "lan" and idle(phase) and not status.recovering then
            ui.page = "modes"
            ui.selection = 2
            key = 0
        elseif not status.recovering then
            visible = false
        end
    end
    if not visible then
        renderPing(status, assets[10])
        renderRestart(status, assets[10])
        local banner
        if phase == Phase.waiting then
            banner = "正在当前层归队 · 队友继续游戏"
        elseif status.prepared and (status.pause or 0) > 0 then
            banner = "P"
                .. ((status.pauseOwner or 0) + 1)
                .. " 暂停了游戏，由发起者恢复"
        end
        if banner then
            assets.lobby.Scale = Vector(1, 0.4)
            layer(assets.lobby, 39, 134, -63)
            assets.lobby.Scale = Vector(1, 1)
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
    layer(assets.lobby, 9, 9 + shift, 39)
    centered(
        modes and "联机模式" or ui.page == "challenges" and "联机挑战" or "局域网联机",
        110 + shift,
        58,
        16
    )
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
    local rows, notice = model.rows(ui, status, characterChoices, challenges, {
        command = _IsaacLanCommand,
        native = _IsaacLan,
        character = character,
        accent = amber,
        hide = function()
            visible = false
        end,
    })
    if notice == "reconnecting" or notice == "reconnect_failed" then
        centered(
            notice == "reconnecting" and "正在重连…" or "重连失败，请重试",
            110,
            100,
            12
        )
    elseif notice == "unavailable" then
        centered("全员需解锁底片与里该隐", 240, 250, 10, red)
    elseif notice == "returning" then
        centered("等待队友结算结束", 110, 100, 12)
    elseif notice == "waiting" then
        centered(
            phase == Phase.waiting and "正在当前层归队" or "正在连接或加载…",
            110,
            100,
            12
        )
        centered("队友可以继续游戏", 110, 124, 10)
    end
    local yStart = (
        status.recovering
        or phase == Phase.waiting
        or phase == Phase.loading
        or phase == Phase.connecting
        or phase == Phase.returning
    )
            and 157
        or 89
    local gap = #rows > 6 and 19 or 23
    if ui.editing then
        if ui.editing == "ip" then
            ui.ip = typed:gsub("[^a-zA-Z0-9%.%-]", ""):sub(1, 253)
        elseif ui.editing == "port" then
            ui.port = typed:gsub("[^%d]", ""):sub(1, 5)
        else
            ui.seed = typed:upper():gsub("[^%w]", ""):sub(1, 8)
        end
        if key == Key.enter and (ui.editing ~= "port" or model.validPort(ui)) then
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
    for i, item in ipairs(rows) do
        local y = yStart + (i - 1) * gap
        if moved and hit(38 + shift, y - 2, 147, 22) and not ui.editing then
            ui.selection = i
        end
        if clicked and hit(38 + shift, y - 2, 147, 22) then
            ui.selection = i
            if item.enabled then
                item.action()
            end
        elseif i == ui.selection and not ui.editing and item.enabled then
            if key == Key.enter or key == Key.space then
                item.action()
            elseif item.change and (key == Key.left or key == Key.right) then
                item.change(key == Key.left and -1 or 1)
            end
        end
        local label = item.label
        if item.field and ui.editing == item.field then
            label = (item.field == "port" and "端口：" or "") .. ui[item.field] .. "_"
        end
        local size = assets[12]:GetStringWidthUTF8(label) > 138 and 10 or 12
        text(label, 49 + shift, y, size, item.color or (item.enabled and ink or faded), 138)
        if i == ui.selection then
            pointer(37 + shift, y + 5)
        end
    end
    for i = 0, (modes and -1 or 3) do
        local x, y = 224 + (i % 2) * 112, 17 + math.floor(i / 2) * 108
        layer(assets.cards, 0, x, y)
        assets.cards:SetLayerFrame(36, i)
        layer(assets.cards, 36, x, y)
        if i < count then
            local id = status[(phase == Phase.lobby and "choice" or "character") .. i] or 0
            portrait(id):Render(pos(x + 51, y + 44))
            centered(character(id), x + 51, y + 60, 10, nil, 92)
            if phase == Phase.lobby and status["ready" .. i] == 1 then
                layer(assets.cards, 5, x, y)
                centered("已准备", x + 51, y + 77, 10, ink)
            else
                centered(
                    phase == Phase.lobby and "选择中"
                        or ((status.connected or 0) & (1 << i) ~= 0 and "在线" or "等待归队"),
                    x + 51,
                    y + 77,
                    10
                )
            end
        else
            centered("等待玩家", x + 51, y + 52, 10, faded)
        end
    end
    local message = status.saveError and status.saveError ~= "" and status.saveError
        or (ui.errorText ~= "" and ui.errorText or networkError)
    local messageColor = red
    if message == "" and phase == Phase.lobby and challenge and challenge.nextBag == 1 then
        local missing = {}
        for i = 0, count - 1 do
            if status["eligible" .. i] ~= true then
                missing[#missing + 1] = "P" .. (i + 1)
            end
        end
        if #missing > 0 then
            message = table.concat(missing, "、") .. " 需解锁底片与里该隐"
        end
    end
    if message == "" and status.modMismatch == 1 then
        message = "Mod 不一致或无法核对，可能会造成未知的影响"
        messageColor = amber
    end
    local footerY = message ~= "" and 235 or 243
    if phase == Phase.lobby and ui.page ~= "challenges" then
        if not host then
            text("房主地址：" .. ui.ip, 25, footerY - 12, 10)
        end
        text("TCP 端口：" .. (host and status.port or ui.port), 25, footerY, 10)
    elseif phase == Phase.running then
        text("共同楼层 · 分头探索", 25, footerY, 10)
    else
        text(
            ui.editing and "输入后确认 · 支持粘贴"
                or status.recovering and "方向选择 · 确认进入"
                or "方向选择 · 确认进入 · 返回退出",
            25,
            footerY,
            10
        )
    end
    if message ~= "" then
        centered(message:sub(1, 100), 240, 250, 10, messageColor)
    end
    return visible
end
