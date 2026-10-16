-- The game's own menu sprites and bitmap fonts. No redistributed game assets.
local assets
local renderPing = _IsaacLanModules["presentation/ping"](_IsaacLan)
local ip, port, seed, difficulty = "", "29506", "", 0
local selection, editing, lastPhase = 1, nil, -1
local page = "modes"
local challenges = _IsaacLan.net_challenges()
local function idle(phase)
    return phase == 0 or phase == 4 or phase == 5
end
function _IsaacLanMenuOpen(returning)
    page = not returning and idle(_IsaacLanStatus().phase or 0) and "modes" or "lan"
    selection, editing = 1, nil
    _IsaacLan.menu_text_end()
end
local previousMouse = Vector(-1000, -1000)
local errorText = ""
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
    local phase = status.phase or 0
    if not visible and not available and not status.prepared and phase ~= 9 then
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
    if phase ~= lastPhase then
        if phase == 3 and lastPhase == 2 then
            visible = false
        end
        selection, editing, lastPhase = 1, nil, phase
        _IsaacLan.menu_text_end()
    end
    if key == 27 then
        if editing then
            editing = nil
            _IsaacLan.menu_text_end()
            key = 0
        elseif page == "challenges" then
            page, selection, key = "lan", 3, 0
        elseif page == "lan" and idle(phase) then
            page = "modes"
            selection = 2
            key = 0
        else
            visible = false
        end
    end
    if not visible then
        renderPing(status, assets[10])
        local banner
        if phase == 9 then
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
    local modes = page == "modes"
    local shift = modes and 128 or 0
    layer(assets.lobby, 9, 9 + shift, 39)
    centered(
        modes and "联机模式" or page == "challenges" and "联机挑战" or "局域网联机",
        110 + shift,
        58,
        16
    )
    local rows = {}
    local function row(label, action, enabled, change, field, color)
        rows[#rows + 1] = {
            label = label,
            action = action,
            enabled = enabled ~= false,
            change = change,
            field = field,
            color = color,
        }
    end
    local function command(action, value)
        local ok, reason = pcall(_IsaacLanCommand, action, value or "")
        errorText = ok and "" or tostring(reason):gsub("^.-:%d+: ", "")
        return ok
    end
    local function validPort()
        local number = tonumber(port)
        if number and number >= 1 and number <= 65535 then
            port = tostring(number)
            errorText = ""
            return true
        end
        errorText = "端口范围：1–65535"
        return false
    end
    local localSlot = status.slot or 0
    -- No seat exists until the host has accepted the connection. Default
    -- session values must not appear as a joined P1 after a failed attempt.
    local count = (phase == 2 or phase == 3 or phase == 7 or phase == 9) and (status.players or 0)
        or 0
    local host = status.hosting == 1
    local ready = status["ready" .. localSlot] == 1
    local choice = status["choice" .. localSlot] or 0
    if modes then
        row("官方联机", function()
            if command("close") then
                _IsaacLan.menu_official()
                visible = false
            end
        end)
        row("局域网联机", function()
            page = "lan"
            selection = 1
        end)
        row("返回", function()
            visible = false
        end)
    elseif idle(phase) then
        row("创建房间", function()
            if validPort() then
                command("host", port)
            end
        end)
        row(ip == "" and "输入房主的 IP" or ip, function()
            editing = "ip"
            _IsaacLan.menu_text_begin(ip, "ip")
        end, true, nil, "ip")
        row("端口：" .. port, function()
            editing = "port"
            _IsaacLan.menu_text_begin(port, "port")
        end, true, nil, "port")
        row("加入房间", function()
            if validPort() then
                command("join", ip .. ":" .. port)
            end
        end, ip ~= "")
        row("返回", function()
            page = "modes"
            selection = 2
        end)
    elseif phase == 2 and page == "challenges" and host then
        local ids = {}
        for id in pairs(challenges) do
            ids[#ids + 1] = tonumber(id)
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local definition = challenges[tostring(id)]
            row(id .. " " .. definition.name, function()
                if command("challenge", tostring(id)) then
                    difficulty = definition.difficulty
                    page, selection = "lan", 3
                end
            end, definition.team_available, nil, nil, amber)
        end
        row("返回", function()
            page, selection = "lan", 3
        end)
        local preview = challenges[tostring(ids[selection] or ids[1])]
        if preview and not preview.team_available then
            centered("全员需解锁底片与里该隐", 240, 250, 10, red)
        end
    elseif phase == 2 then
        local choices = characterChoices
        local function cycle(delta)
            if #choices == 0 then
                return
            end
            local index = 1
            for i, v in ipairs(choices) do
                if v == choice then
                    index = i
                    break
                end
            end
            command("choose", choices[(index - 1 + delta) % #choices + 1] .. ":0")
        end
        row(character(choice), function()
            cycle(1)
        end, not ready and not challenge and #choices > 0, cycle)
        row(ready and "取消准备" or "准备", function()
            command("choose", choice .. (ready and ":0" or ":1"))
        end, ready or status["eligible" .. localSlot] == true)
        if host then
            local function changeMode(delta)
                local nextMode = ((challenge and 4 or difficulty) + delta) % 5
                if nextMode == 4 then
                    page, selection = "challenges", 1
                elseif command("challenge", "0") then
                    difficulty = nextMode
                end
            end
            row(
                challenge and ("挑战：" .. challenge.id .. " " .. challenge.name)
                    or ({ "普通", "困难", "贪婪", "贪婪加强" })[difficulty + 1],
                function()
                    if challenge then
                        page, selection = "challenges", 1
                    else
                        changeMode(1)
                    end
                end,
                true,
                changeMode,
                nil,
                challenge and amber
            )
            row(seed == "" and "种子：随机" or seed, function()
                editing = "seed"
                _IsaacLan.menu_text_begin(seed, "seed")
            end, true, nil, "seed")
            local allReady = count >= 2
            for i = 0, count - 1 do
                allReady = allReady
                    and status["ready" .. i] == 1
                    and status["eligible" .. i] == true
            end
            row("开始游戏", function()
                local settings = (seed == "" and "RANDOM" or seed)
                    .. ":"
                    .. (challenge and challenge.difficulty or difficulty)
                for i = 0, 3 do
                    settings = settings .. ":" .. (status["choice" .. i] or 0)
                end
                if command("start", settings) then
                    visible = false
                end
            end, allReady)
            if not challenge and (status.savedPlayers or 0) >= 2 then
                row("继续上次联机", function()
                    if command("resume") then
                        visible = false
                    end
                end, allReady and count == status.savedPlayers)
            end
        end
        if not host and challenge then
            row(
                "挑战：" .. challenge.id .. " " .. challenge.name,
                function() end,
                false,
                nil,
                nil,
                amber
            )
        end
        row("离开房间", function()
            command("close")
        end)
    elseif phase == 3 then
        if (status.pause or 0) == 0 then
            row("暂停全队", function()
                command("control", "1")
            end)
        else
            row("恢复游戏", function()
                if command("control", "2") then
                    visible = false
                end
            end, localSlot == status.pauseOwner)
        end
        if host then
            row(challenge and "结束挑战（不保存）" or "保存并结束联机", function()
                command("control", "3")
            end)
        else
            row("离开并保留角色", function()
                command("control", "4")
            end)
        end
        row("返回游戏", function()
            visible = false
        end)
    else
        centered(phase == 9 and "正在当前层归队" or "正在连接或加载…", 110, 100, 12)
        centered("队友可以继续游戏", 110, 124, 10)
        if not status.prepared then
            row("离开房间", function()
                command("close")
            end)
        end
    end
    local yStart = (phase == 9 or phase == 7 or phase == 1) and 157 or 89
    local gap = #rows > 6 and 19 or 23
    if editing then
        if editing == "ip" then
            ip = typed:gsub("[^a-zA-Z0-9%.%-]", ""):sub(1, 253)
        elseif editing == "port" then
            port = typed:gsub("[^%d]", ""):sub(1, 5)
        else
            seed = typed:upper():gsub("[^%w]", ""):sub(1, 8)
        end
        if key == 13 and (editing ~= "port" or validPort()) then
            editing = nil
            _IsaacLan.menu_text_end()
        end
        key = 0
    elseif #rows > 0 then
        if key == 38 then
            selection = (selection - 2) % #rows + 1
        elseif key == 40 or key == 9 then
            selection = selection % #rows + 1
        end
        selection = math.min(selection, #rows)
    end
    for i, item in ipairs(rows) do
        local y = yStart + (i - 1) * gap
        if moved and hit(38 + shift, y - 2, 147, 22) and not editing then
            selection = i
        end
        if clicked and hit(38 + shift, y - 2, 147, 22) then
            selection = i
            if item.enabled then
                item.action()
            end
        elseif i == selection and not editing and item.enabled then
            if key == 13 or key == 32 then
                item.action()
            elseif item.change and (key == 37 or key == 39) then
                item.change(key == 37 and -1 or 1)
            end
        end
        local label = item.label
        if item.field and editing == item.field then
            label = (item.field == "port" and "端口：" or "")
                .. ({ ip = ip, port = port, seed = seed })[item.field]
                .. "_"
        end
        local size = assets[12]:GetStringWidthUTF8(label) > 138 and 10 or 12
        text(label, 49 + shift, y, size, item.color or (item.enabled and ink or faded), 138)
        if i == selection then
            pointer(37 + shift, y + 5)
        end
    end
    for i = 0, (modes and -1 or 3) do
        local x, y = 224 + (i % 2) * 112, 17 + math.floor(i / 2) * 108
        layer(assets.cards, 0, x, y)
        assets.cards:SetLayerFrame(36, i)
        layer(assets.cards, 36, x, y)
        if i < count then
            local id = status[(phase == 2 and "choice" or "character") .. i] or 0
            portrait(id):Render(pos(x + 51, y + 44))
            centered(character(id), x + 51, y + 60, 10, nil, 92)
            if phase == 2 and status["ready" .. i] == 1 then
                layer(assets.cards, 5, x, y)
                centered("已准备", x + 51, y + 77, 10, ink)
            else
                centered(
                    phase == 2 and "选择中"
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
    local message = errorText ~= "" and errorText or networkError
    local messageColor = red
    if message == "" and phase == 2 and challenge then
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
    if phase == 2 and page ~= "challenges" then
        if not host then
            text("房主地址：" .. ip, 25, footerY - 12, 10)
        end
        text("TCP 端口：" .. (host and status.port or port), 25, footerY, 10)
    elseif phase == 3 then
        text("共同楼层 · 分头探索", 25, footerY, 10)
    else
        text(
            editing and "输入后确认 · 支持粘贴"
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
