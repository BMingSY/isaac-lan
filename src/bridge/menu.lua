-- The game's own menu sprites and bitmap fonts. No redistributed game assets.
local assets
local ip, port, seed, difficulty = "", "29506", "", 0
local selection, editing, lastPhase = 1, nil, -1
local page = "modes"
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
local choices = {
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    13,
    14,
    15,
    16,
    18,
    19,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
}
local names = {
    "以撒",
    "抹大拉",
    "该隐",
    "犹大",
    "小蓝人",
    "夏娃",
    "参孙",
    "阿撒泻勒",
    "拉撒路",
    "伊甸",
    "游魂",
    "莉莉丝",
    "店主",
    "亚玻伦",
    "遗骸",
    "伯大尼",
    "雅各与以扫",
}
local portraits = {
    "01_Isaac",
    "02_Magdalene",
    "03_Cain",
    "04_Judas",
    "06_Bluebaby",
    "05_Eve",
    "07_Samson",
    "08_Azazel",
    "09_Lazarus",
    "10_Eden",
    "11_TheLost",
    "12_Lilith",
    "13_Keeper",
    "15_Apollyon",
    "16_TheForgotten",
    "17_Bethany",
    "18_JacobEsau",
}
local function character(id)
    for i, v in ipairs(choices) do
        if id == v then
            return (i > 17 and "里·" or "") .. names[(i - 1) % 17 + 1],
                portraits[(i - 1) % 17 + 1],
                i > 17
        end
    end
    return "自定义角色", "00_Random", false
end
local ink = KColor(0.18, 0.14, 0.14, 1)
local faded = KColor(0.47, 0.42, 0.41, 1)
local red = KColor(0.44, 0.06, 0.06, 1)
local amber = KColor(0.45, 0.27, 0.06, 1)
local function load()
    if assets then
        return
    end
    assets = {}
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
    sprite("altPortraits", root .. "characterportraitsalt.anm2", "01_Isaac")
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
    local function text(value, x, y, size, color)
        assets[size or 12]:DrawStringUTF8(
            tostring(value),
            origin.X + x,
            origin.Y + y,
            color or ink,
            0,
            false
        )
    end
    local function centered(value, x, y, size, color)
        local font = assets[size or 12]
        text(value, x - font:GetStringWidthUTF8(value) / 2, y, size, color)
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
        elseif page == "lan" and idle(phase) then
            page = "modes"
            selection = 2
            key = 0
        else
            visible = false
        end
    end
    if not visible then
        if status.prepared and phase == 3 then
            local white = KColor(1, 1, 1, 1)
            local line = 0
            for slot = 1, (status.players or 1) - 1 do
                if ((status.connected or 0) & (1 << slot)) ~= 0 then
                    local ping = status["ping" .. slot] or -1
                    assets[10]:DrawStringScaledUTF8(
                        "P" .. (slot + 1) .. " " .. (ping < 0 and "—" or ping .. " ms"),
                        origin.X + 320,
                        origin.Y + 62 + line * 8,
                        0.6,
                        0.6,
                        white,
                        0,
                        false
                    )
                    line = line + 1
                end
            end
        end
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
    assets.fill.Scale = Vector(width / 480, height / 270)
    assets.fill.Color = Color(0, 0, 0, 1, -0.20, -0.25, -0.26)
    assets.fill:Render(Vector.Zero)
    assets.sketches:RenderLayer(0, origin)
    local modes = page == "modes"
    local shift = modes and 128 or 0
    layer(assets.lobby, 9, 9 + shift, 39)
    centered(modes and "联机模式" or "局域网联机", 110 + shift, 58, 16)
    local rows = {}
    local function row(label, action, enabled, change, field)
        rows[#rows + 1] = {
            label = label,
            action = action,
            enabled = enabled ~= false,
            change = change,
            field = field,
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
        row(ip == "" and "输入房主 IP" or ip, function()
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
    elseif phase == 2 then
        local function cycle(delta)
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
        end, not ready, cycle)
        row(ready and "取消准备" or "准备", function()
            command("choose", choice .. (ready and ":0" or ":1"))
        end)
        if host then
            row(
                ({ "普通", "困难", "贪婪", "贪婪加强" })[difficulty + 1],
                function()
                    difficulty = (difficulty + 1) % 4
                end,
                true,
                function(d)
                    difficulty = (difficulty + d) % 4
                end
            )
            row(seed == "" and "种子：随机" or seed, function()
                editing = "seed"
                _IsaacLan.menu_text_begin(seed, "seed")
            end, true, nil, "seed")
            local allReady = count >= 2
            for i = 0, count - 1 do
                allReady = allReady and status["ready" .. i] == 1
            end
            row("开始游戏", function()
                local settings = (seed == "" and "RANDOM" or seed) .. ":" .. difficulty
                for i = 0, 3 do
                    settings = settings .. ":" .. (status["choice" .. i] or 0)
                end
                if command("start", settings) then
                    visible = false
                end
            end, allReady)
            if (status.savedPlayers or 0) >= 2 then
                row("继续上次联机", function()
                    if command("resume") then
                        visible = false
                    end
                end, allReady and count == status.savedPlayers)
            end
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
            row("保存并结束联机", function()
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
            ip = typed:gsub("[^%d%.]", ""):sub(1, 15)
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
        text(label, 49 + shift, y, size, item.enabled and ink or faded)
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
            local name, animation, alt = character(status["choice" .. i] or 0)
            local portrait = alt and assets.altPortraits or assets.portraits
            portrait:SetFrame(animation, 0)
            portrait:Render(pos(x + 51, y + 44))
            centered(name, x + 51, y + 60, 10)
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
    if message == "" and status.modMismatch == 1 then
        message = "Mod 不一致或无法核对，可能会造成未知的影响"
        messageColor = amber
    end
    local footerY = message ~= "" and 235 or 243
    if phase == 2 then
        text(host and ("房主 IP：" .. addresses) or ("房主 IP：" .. ip), 25, footerY - 12, 10)
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
