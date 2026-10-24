local root = assert(arg[1])
PlayerType = dofile(root .. "/tests/fixtures/game_enums.lua").PlayerType
local labels, commands = {}, {}
local renderedPortraits = {}
local scaledLabels, renderedMarks = {}, {}
local labelPositions = {}
local options = { { flag = 1, key = "friendlyFire", name = "队友伤害", shortName = "友伤" } }
local noop = function() end
local remembered = { "", 29506 }
local savedCount = 0
local vector = {}
vector.__index = vector
local function vec(x, y)
    return setmetatable({ X = x, Y = y }, vector)
end
vector.__add = function(a, b)
    return vec(a.X + b.X, a.Y + b.Y)
end
vector.__sub = function(a, b)
    return vec(a.X - b.X, a.Y - b.Y)
end
vector.LengthSquared = function(v)
    return v.X * v.X + v.Y * v.Y
end
Vector = setmetatable({ Zero = vec(0, 0) }, {
    __call = function(_, x, y)
        return vec(x, y)
    end,
})
KColor = function(r, g, b, a)
    return { r, g, b, a }
end
Color = KColor
Sprite = function()
    return {
        Load = function(self, path)
            self.path = path
        end,
        Play = function(self, animation)
            if animation ~= "missing" then
                self.animation = animation
            end
        end,
        GetAnimation = function(self)
            return self.animation
        end,
        SetFrame = function(self, animation)
            self.animation = animation
        end,
        Render = function(self)
            if self.path == "gfx/ui/completion_widget.anm2" then
                renderedMarks[#renderedMarks + 1] = { table.unpack(self.layers) }
            elseif self.path ~= "gfx/ui/bossoverlay_whiteout.anm2" then
                renderedPortraits[#renderedPortraits + 1] = { self.path, self.animation }
            end
        end,
        RenderLayer = noop,
        SetLayerFrame = function(self, layer, frame)
            self.layers = self.layers or {}
            self.layers[layer + 1] = frame
        end,
    }
end
Font = function()
    return {
        Load = noop,
        IsLoaded = function()
            return true
        end,
        GetStringWidthUTF8 = function(_, value)
            return utf8.len(value) * 8
        end,
        DrawStringUTF8 = function(_, text, x, y, color)
            labels[text] = color
            labelPositions[text] = { x = x, y = y }
        end,
        DrawStringScaledUTF8 = function(_, text, x, y, scale, _, color)
            labels[text] = color
            labelPositions[text] = { x = x, y = y }
            scaledLabels[#scaledLabels + 1] = { text = text, x = x, y = y, scale = scale }
        end,
    }
end
Isaac = {
    DebugString = noop,
    GetScreenWidth = function()
        return 480
    end,
    GetScreenHeight = function()
        return 270
    end,
}
local status = {
    phase = 2,
    hosting = 1,
    players = 2,
    slot = 0,
    choice0 = 0,
    choice1 = 0,
    ready0 = 0,
    ready1 = 0,
    connected = 3,
    port = 29506,
    transport = "udp",
    savedPlayers = 2,
    eligible0 = true,
    eligible1 = true,
}
local available = true
local characters = { 0, 23 }
local catalog = {
    ["0"] = {
        name = "Isaac",
        animation = "01_Isaac",
        portraitAnm2Path = "native-normal.anm2",
        tainted = false,
    },
    ["23"] = {
        name = "Cain",
        animation = "03_Cain",
        portraitAnm2Path = "native-tainted.anm2",
        tainted = true,
    },
}
_IsaacLanStatus = function()
    return status
end
_IsaacLan = {
    net_room_options = function()
        return options
    end,
    net_phases = function()
        return dofile(root .. "/tests/fixtures/net_phases.lua")
    end,
    net_commands = function()
        return dofile(root .. "/tests/fixtures/net_commands.lua")
    end,
    presentation_player_huds = function()
        return {}
    end,
    menu_text_end = noop,
    menu_connection = function()
        return table.unpack(remembered)
    end,
    menu_connection_save = function(address, port)
        remembered, savedCount = { address, port }, savedCount + 1
    end,
    menu_text_begin = noop,
    net_characters = function()
        return characters, catalog
    end,
    net_challenges = function()
        return {
            ["1001"] = {
                id = 1001,
                name = "恶魔形态",
                character = 23,
                difficulty = 0,
                nextBag = 1,
                available = available,
                team_available = available,
            },
        }
    end,
}
_IsaacLanModules = {
    ["presentation/restart"] = dofile(root .. "/src/bridge/presentation/restart.lua"),
    ["presentation/menu_model"] = dofile(root .. "/src/bridge/presentation/menu_model.lua"),
    ["presentation/ping"] = dofile(root .. "/src/bridge/presentation/ping.lua"),
}
_IsaacLanCommand = function(name, value)
    commands[#commands + 1] = { name, value }
    if name == "challenge" then
        status.challenge = tonumber(value)
        status.ready0, status.ready1 = 0, 0
        if status.challenge ~= 0 then
            status.choice0, status.choice1 = 23, 23
        end
    elseif name == "choose" then
        local character, ready = value:match("^(%d+):(%d+)$")
        status["choice" .. status.slot], status["ready" .. status.slot] =
            tonumber(character), tonumber(ready)
    elseif name == "room_options" then
        status.roomOptions = tonumber(value)
        status.ready0, status.ready1 = 0, 0
    end
end
dofile(root .. "/src/bridge/presentation/menu.lua")
local function draw(key, visible, mx, my, clicked)
    labels = {}
    renderedPortraits = {}
    scaledLabels = {}
    renderedMarks = {}
    labelPositions = {}
    return _IsaacLanMenuRender(
        true,
        visible ~= false,
        key or 0,
        "",
        mx or -100,
        my or -100,
        clicked or false,
        "",
        ""
    )
end
_IsaacLanMenuOpen(true)
draw()
draw(40)
draw(40) -- Mode row.
for _ = 1, 4 do
    draw(39)
end
draw()
assert(labels["1001 恶魔形态"] and labels["返回"])
draw(13)
draw()
assert(status.challenge == 1001 and status.choice0 == 23 and status.ready0 == 0)
local accent = assert(labels["挑战：1001 恶魔形态"])
assert(accent[1] == 0.45 and not labels["继续上次联机"])
-- Character row is locked, even when unready; mode row can return to normal.
draw(38)
draw(38)
local count = #commands
draw(39)
assert(#commands == count)
draw(40)
draw(40)
draw(39)
draw()
assert(status.challenge == 0 and labels["普通"] and labels["继续上次联机"])
-- Ordinary character cycling uses the personal save's list, with catalog names.
_IsaacLanMenuOpen(true)
status.choice0 = 0
draw(39)
draw()
assert(status.choice0 == 23 and labels["里·该隐"])
assert(renderedPortraits[1][1] == "native-tainted.anm2" and renderedPortraits[1][2] == "03_Cain")
draw(39)
assert(status.choice0 == 0)
draw()
assert(labels["以撒"] and not labels["Isaac"])
characters = { 0 }
draw(39)
assert(status.choice0 == 0)
characters = { 0, 23 }
-- Native metadata and ordering include dynamically registered Mod roles.
local longName = "LAN Extremely Long Mod Character Name"
catalog["4096"] = {
    name = longName,
    animation = "目录角色",
    portraitAnm2Path = "mod-menu.anm2",
    tainted = false,
}
catalog["41"] = {
    name = "无菜单画像",
    animation = "missing",
    portraitAnm2Path = "mod-menu.anm2",
    tainted = true,
}
characters = { 0, 4096, 23, 41 }
draw(39)
draw()
assert(status.choice0 == 4096 and labels[longName])
local nameRenders = 0
for _, label in ipairs(scaledLabels) do
    if label.text == longName then
        nameRenders = nameRenders + 1
        local width = utf8.len(longName) * 8 * label.scale
        assert(label.scale > 0 and label.scale < 1)
        assert(width <= (label.x == 49 and 138 or 110))
    end
end
assert(nameRenders == 2, "Long Mod name did not fit both the row and player card")
assert(renderedPortraits[1][1] == "mod-menu.anm2" and renderedPortraits[1][2] == "目录角色")
draw(39)
assert(status.choice0 == 23)
draw(39)
draw()
assert(status.choice0 == 41 and labels["无菜单画像"])
assert(renderedPortraits[1][2] == "00_Random")
draw(39)
assert(status.choice0 == 0)
-- Mod names remain untouched even when they match a vanilla English name.
catalog["42"] = {
    name = "Isaac",
    animation = "ModIsaac",
    portraitAnm2Path = "mod-menu.anm2",
    tainted = false,
}
characters, status.choice0 = { 42 }, 42
draw()
assert(labels["Isaac"] and not labels["以撒"])
for _, role in ipairs({
    { 1, "Magdalene", false, "抹大拉" },
    { 4, "???", false, "???" },
    { 19, "Jacob", false, "雅各与以扫" },
    { 21, "Isaac", true, "里·以撒" },
    { 25, "???", true, "里·???" },
    { 37, "Jacob", true, "里·雅各" },
}) do
    catalog[tostring(role[1])] = {
        name = role[2],
        animation = "",
        portraitAnm2Path = "",
        tainted = role[3],
    }
    characters, status.choice0 = { role[1] }, role[1]
    draw()
    assert(labels[role[4]])
end
status.choice0 = 0
characters = {}
count = #commands
draw(39)
assert(#commands == count)
characters = { 0, 23 }
-- An unavailable challenge stays visible and cannot be selected.
available = false
draw(40)
draw(40)
for _ = 1, 4 do
    draw(39)
end
draw()
count = #commands
draw(13)
assert(#commands == count and status.challenge == 0)
available = true
-- Guest sees selected rules but has no mode-changing action.
status.challenge, status.hosting, status.slot = 1001, 0, 1
_IsaacLanMenuOpen(true)
draw()
assert(labels["挑战：1001 恶魔形态"])
status.eligible1 = false
draw(40)
count = #commands
draw(13)
assert(#commands == count and labels["P2 需解锁底片与里该隐"])
status.eligible1 = true
_IsaacLanMenuOpen(true)
draw()
count = #commands
draw(39)
assert(#commands == count)
-- Gameplay has no challenge title or next-seat text overlay.
status.phase, status.prepared = 3, true
for n = 2, 4 do
    status.players, status.connected = n, (1 << n) - 1
    for slot = 0, n - 1 do
        status.slot = slot
        draw(0, false)
        for label in pairs(labels) do
            assert(not label:find("挑战") and not label:find("百宝袋"))
        end
    end
end
status.hosting, status.slot = 1, 0
draw()
assert(labels["结束挑战（不保存）"] and not labels["保存并结束联机"])
status.challenge = 0
draw()
assert(labels["保存并结束联机"])
local actions = dofile(root .. "/src/bridge/presentation/menu_model.lua")(
    _IsaacLan.net_phases(),
    _IsaacLan.net_commands()
)
local sent, hidden = {}, 0
local deps = {
    native = _IsaacLan,
    command = function(action, value)
        sent[#sent + 1] = { action, value }
    end,
    hide = function()
        hidden = hidden + 1
    end,
}
local ui = { page = "lan" }
local function action(label, running)
    local rows = actions.rows(ui, running, {}, {}, deps)
    for _, row in ipairs(rows) do
        if row.label == label then
            assert(row.enabled)
            row.action()
            return
        end
    end
    error("Missing action: " .. label)
end
action("暂停全队", { phase = 3, hosting = 1, slot = 0, pause = 0 })
action("恢复游戏", { phase = 3, hosting = 1, slot = 0, pause = 1, pauseOwner = 0 })
action("保存并结束联机", { phase = 3, hosting = 1, slot = 0 })
action("重连游戏", { phase = 3, hosting = 0, slot = 1 })
action("离开游戏", { phase = 3, hosting = 0, slot = 1 })
for i = 1, 3 do
    assert(sent[i][1] == "control" and sent[i][2] == tostring(i))
end
assert(sent[4][1] == "reconnect" and sent[5][1] == "leave")
for _, phase in ipairs({ 1, 7, 9, 3, 4 }) do
    local recovering = { phase = phase, hosting = 0, slot = 1, recovering = true }
    local rows, notice = actions.rows(ui, recovering, {}, {}, deps)
    assert(#rows == 2 and rows[1].label == "重连游戏" and rows[2].label == "离开游戏")
    assert(rows[1].enabled == (phase == 4) and rows[2].enabled)
    assert(notice == (phase == 4 and "reconnect_failed" or "reconnecting"))
end
status.hosting, status.recovering, status.prepared = 0, true, false
for _, phase in ipairs({ 1, 7, 9, 4 }) do
    status.phase = phase
    labels = {}
    assert(_IsaacLanMenuRender(false, false, 0, "", -1000, -1000, false, "", ""))
    assert(labels[phase == 4 and "重连失败，请重试" or "正在重连…"])
    assert(labels["重连游戏"] and labels["离开游戏"] and not labels["暂停全队"])
    assert(not labels["方向选择 · 确认进入 · 返回退出"])
end
status.hosting, status.recovering, status.prepared, status.phase = 0, false, true, 3
assert(
    not _IsaacLanMenuRender(false, true, 0, "", -1000, -1000, false, "", ""),
    "Recovered game kept capturing input"
)
assert(
    _IsaacLanMenuRender(false, true, 0, "", -1000, -1000, false, "", ""),
    "A later manual menu open was hidden"
)
status.hosting, status.prepared = 1, false
assert(hidden == 1)
-- Reconnect/loading/game cards use the run roster, even when lobby choices
-- were never selected (fresh rejoin) or differ from a resumed save.
catalog["1"].animation = "02_Magdalene"
catalog["1"].portraitAnm2Path = "native-normal.anm2"
local roster = { 1, 23, 4096, 41 }
for slot, id in ipairs(roster) do
    status["character" .. (slot - 1)] = id
    status["choice" .. (slot - 1)] = 0
end
for _, phase in ipairs({ 9, 7, 3, 9 }) do
    status.phase = phase
    for n = 2, 4 do
        status.players = n
        draw()
        assert(labels["抹大拉"] and labels["里·该隐"] and not labels["以撒"])
        for slot = 1, n do
            local entry = catalog[tostring(roster[slot])]
            local expected = entry.animation == "missing" and "00_Random" or entry.animation
            assert(renderedPortraits[slot][2] == expected, "Run card used a lobby portrait")
        end
        assert(n < 3 or labels[longName])
        assert(n < 4 or labels["无菜单画像"])
    end
end
-- A new lobby returns to its own selections rather than retaining the run.
status.phase, status.prepared = 10, false
_IsaacLanMenuOpen(true)
draw()
assert(labels["等待队友结算结束"] and labels["离开房间"])
assert(not labels["开始游戏"] and not labels["队友可以继续游戏"])
status.phase, status.players = 2, 2
draw()
assert(labels["以撒"] and not labels["里·该隐"])
assert(labels["准备"] and labels["开始游戏"] and not labels["等待队友结算结束"])
assert(renderedPortraits[1][2] == "01_Isaac" and renderedPortraits[2][2] == "01_Isaac")
-- Native MainMenu can remain behind the returning LAN page. Two Back presses
-- close the LAN/mode overlay without invoking a lobby action.
status.phase, status.prepared = 0, false
_IsaacLanMenuOpen(true)
count = #commands
assert(draw(27))
assert(not draw(27))
assert(#commands == count)
print("PASS challenge selection, role cards, reconnect roster, clean HUD and transient exit")

status.pendingSave, status.saveError = 1, "联机存档保存失败，请重试保存"
_IsaacLanMenuOpen(true)
draw()
assert(labels["重试保存联机存档"] and labels[status.saveError])
assert(not labels["创建房间"] and not labels["加入房间"])
draw(13)
assert(commands[#commands][1] == "retry_save", "Pending snapshot offered no retry action")
status.pendingSave, status.saveError = 0, ""
draw()
assert(labels["创建房间"] and not labels["重试保存联机存档"])

-- An unrestricted challenge keeps ordinary character cycling on both peers.
local phaseValues = dofile(root .. "/tests/fixtures/net_phases.lua")
local model = dofile(root .. "/src/bridge/presentation/menu_model.lua")(
    phaseValues,
    dofile(root .. "/tests/fixtures/net_commands.lua")
)
for _, host in ipairs({ 0, 1 }) do
    local selected
    local rows = model.rows(
        { page = "lan", difficulty = 0, seed = "" },
        {
            phase = phaseValues.lobby,
            hosting = host,
            players = 2,
            slot = 0,
            challenge = 1002,
            choice0 = 0,
            ready0 = 0,
        },
        { 0, 1, 23 },
        { ["1002"] = { id = 1002, name = "运气游戏", character = 65535, difficulty = 0 } },
        {
            character = tostring,
            command = function(action, value)
                selected = { action, value }
            end,
            connected = function()
                return true
            end,
        }
    )
    assert(rows[1].enabled and rows[1].label == "0")
    rows[1].change(1)
    assert(selected[1] == "choose" and selected[2] == "1:0")
end

-- Save on confirmed edits/connection attempts and reconstruct a fresh menu VM.
status = { phase = 0, hosting = 0, players = 0 }
remembered = { "room.example.com", 31234 }
dofile(root .. "/src/bridge/presentation/menu.lua")
_IsaacLanMenuOpen(true)
draw()
assert(labels["room.example.com"] and labels["端口：31234"])
draw(40) -- Address.
draw(13)
_IsaacLanMenuRender(true, true, 13, "192.168.1.42", -100, -100, false, "", "")
assert(remembered[1] == "192.168.1.42" and remembered[2] == 31234)
draw(40) -- Port.
draw(13)
local beforeSave = savedCount
_IsaacLanMenuRender(true, true, 13, "0", -100, -100, false, "", "")
assert(savedCount == beforeSave and remembered[2] == 31234)
_IsaacLanMenuRender(true, true, 13, "32123", -100, -100, false, "", "")
assert(remembered[2] == 32123)
dofile(root .. "/src/bridge/presentation/menu.lua")
_IsaacLanMenuOpen(true)
draw()
assert(labels["192.168.1.42"] and labels["端口：32123"])
for _, port in ipairs({ "", "0", "65536", "123.5" }) do
    local prefs = { page = "lan", ip = "room.example.com", port = port }
    local count = savedCount
    local rows = actions.rows(prefs, status, {}, {}, deps)
    rows[1].action()
    rows[4].action()
    assert(savedCount == count, "Invalid port overwrote saved preferences")
end
local prefs = { page = "lan", ip = "host.example.com", port = "01234" }
local rows = actions.rows(prefs, status, {}, {}, deps)
rows[4].action()
assert(remembered[1] == prefs.ip and remembered[2] == 1234)
assert(sent[#sent][1] == "join" and sent[#sent][2] == "host.example.com:1234")

-- Each card renders its owner's twelve native single-player layers.
status = {
    phase = 2,
    hosting = 1,
    players = 2,
    slot = 0,
    choice0 = 0,
    choice1 = 23,
    ready0 = 1,
    ready1 = 1,
    connected = 3,
    roomOptions = 0,
    savedPlayers = 2,
    savedOptions = 1,
    transport = "udp",
    port = 29506,
    marks0 = { 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2 },
    marks1 = { 2, 1, 0, 2, 1, 0, 2, 1, 0, 2, 1, 0 },
}
_IsaacLanMenuOpen(true)
draw()
assert(#renderedMarks == 2 and renderedMarks[1][1] == 0 and renderedMarks[2][1] == 2)
assert(
    labels["房间规则：无 >"]
        and not labels["[ ] 队友伤害"]
        and labels["载入上次规则"]
)
for _ = 1, 4 do
    draw(40)
end
draw(13)
draw()
assert(labels["房间规则"] and labels["已启用 0 项"] and labels["[ ] 队友伤害"])
assert(status.roomOptions == 0, "Opening rules changed their state")
draw(13)
draw()
assert(status.roomOptions == 1 and status.ready0 == 0 and status.ready1 == 0)
assert(labels["[x] 队友伤害"] and labels["已启用 1 项"] and labels["返回"])
draw(27)
draw()
assert(labels["房间规则：友伤 >"] and labels["继续上次联机"])
draw(13) -- Back restored the rules entry, rather than the character row.
draw()
assert(labels["房间规则"])
draw(27)
status.hosting, status.slot = 0, 1
_IsaacLanMenuOpen(true)
draw()
draw(40)
draw(40)
local previousCommands = #commands
draw(13)
draw()
assert(labels["已启用 1 项 · 只读"] and labels["[x] 队友伤害"])
draw(13)
assert(#commands == previousCommands and status.roomOptions == 1, "guest edited room rules")
status.roomOptions = 0 -- Host changes while the guest's list remains open.
draw()
assert(labels["已启用 0 项 · 只读"] and labels["[ ] 队友伤害"])
draw(27)
draw()
assert(labels["房间规则：无"])
draw(13)
draw()
assert(labels["已启用 0 项 · 只读"], "Guest Back did not restore the rules entry")
status.phase = phaseValues.waiting
draw()
assert(#renderedMarks == 0, "Loading a saved character displayed unrelated lobby-choice marks")
assert(not labels["房间规则"], "Rules page survived a lobby lifecycle change")

-- Future independent checkboxes retain other flags when toggled.
local selected
local rows = model.rows(
    { page = "rules", difficulty = 0, seed = "" },
    { phase = 2, hosting = 1, players = 2, slot = 0, roomOptions = 3 },
    { 0 },
    {},
    {
        character = tostring,
        connected = function()
            return true
        end,
        command = function(action, value)
            selected = { action, value }
        end,
        options = { { flag = 1, name = "first" }, { flag = 2, name = "second" } },
    }
)
for _, row in ipairs(rows) do
    if row.label == "first" then
        assert(row.checked)
        row.action()
        assert(selected[1] == "room_options" and selected[2] == "2")
    end
end
-- Overflow remains a six-row viewport with an independently positioned Back.
for i = 1, 11 do
    options[#options + 1] = { flag = 1 << i, name = "规则 " .. i, shortName = "规" .. i }
end
status.phase, status.hosting, status.slot, status.savedPlayers = 2, 1, 0, 0
status.roomOptions = 1 | (1 << 2) | (1 << 10)
_IsaacLanMenuOpen(true)
draw()
assert(labels["房间规则：友伤 +2 >"] and not labels["[x] 队友伤害"])
for _ = 1, 4 do
    draw(40)
end
draw(13)
draw()
local function visibleRules()
    local count = 0
    for label, point in pairs(labelPositions) do
        if label:match("^%[[ x]%]") then
            count = count + 1
            assert(point.y >= 100 and point.y <= 185, "Rule escaped its viewport")
        end
    end
    assert(count == 6 and labelPositions["返回"].y == 214)
end
visibleRules()
assert(labels["1–6 / 12"] and labels["[ ] 规则 5"] and not labels["[ ] 规则 6"])
for _ = 1, 6 do
    draw(40)
end
draw()
visibleRules()
assert(labels["2–7 / 12"] and not labels["[x] 队友伤害"] and labels["[ ] 规则 6"])
local previousMask = status.roomOptions
draw(13)
draw()
assert(status.roomOptions == (previousMask | (1 << 6)) and labels["已启用 4 项"])
for _ = 1, 6 do
    draw(40)
end
draw()
visibleRules()
assert(labels["7–12 / 12"] and labels["[ ] 规则 11"])
draw(13) -- Back stays accessible after the final rule.
draw()
assert(labels["房间规则：友伤 +3 >"])
draw(13)
draw()
assert(labels["1–6 / 12"], "Reopening rules retained an unrelated scroll offset")
previousCommands = #commands
draw(0, true, 180, 202, true) -- Mouse page-down control.
draw()
visibleRules()
assert(labels["7–12 / 12"] and #commands == previousCommands)
draw(0, true, 159, 202, true) -- Mouse page-up control.
draw()
assert(labels["1–6 / 12"])
previousMask = status.roomOptions
draw(0, true, 70, 117, true) -- Adjacent hitboxes must not toggle two rules.
assert(#commands == previousCommands + 1 and status.roomOptions == (previousMask ~ 2))
draw()
assert(labels["[x] 规则 1"] and labels["[x] 队友伤害"])
draw(0, true, 70, 217, true) -- Fixed Back also works with the mouse.
draw()
assert(labels["房间规则：友伤 +4 >"])
-- A challenge adds a guest status row; Back still selects the actual rules entry.
status.hosting, status.slot, status.challenge = 0, 1, 1001
_IsaacLanMenuOpen(true)
draw()
for _ = 1, 3 do
    draw(40)
end
draw(13)
draw()
assert(labels["已启用 5 项 · 只读"])
previousCommands = #commands
draw(0, true, 70, 117, true)
assert(#commands == previousCommands, "Read-only mouse click sent a mutation")
draw(27)
draw(13)
draw()
assert(labels["已启用 5 项 · 只读"], "Challenge guest returned to the wrong row")
for i = #options, 2, -1 do
    options[i] = nil
end
print("PASS personal completion layers, host-only independent rules and resume selection")
print("PASS rules submenu, summaries, scrolling, read-only updates and keyboard/mouse navigation")
