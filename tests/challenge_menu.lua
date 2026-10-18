local root = assert(arg[1])
PlayerType = dofile(root .. "/tests/fixtures/game_enums.lua").PlayerType
local labels, commands = {}, {}
local renderedPortraits = {}
local scaledLabels = {}
local noop = function() end
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
            if self.path ~= "gfx/ui/bossoverlay_whiteout.anm2" then
                renderedPortraits[#renderedPortraits + 1] = { self.path, self.animation }
            end
        end,
        RenderLayer = noop,
        SetLayerFrame = noop,
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
        DrawStringUTF8 = function(_, text, _, _, color)
            labels[text] = color
        end,
        DrawStringScaledUTF8 = function(_, text, x, y, scale, _, color)
            labels[text] = color
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
    end
end
dofile(root .. "/src/bridge/presentation/menu.lua")
local function draw(key, visible)
    labels = {}
    renderedPortraits = {}
    scaledLabels = {}
    return _IsaacLanMenuRender(true, visible ~= false, key or 0, "", -100, -100, false, "", "")
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
        assert(width <= (label.x == 49 and 138 or 92))
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
action("离开并保留角色", { phase = 3, hosting = 0, slot = 1 })
for i = 1, 4 do
    assert(sent[i][1] == "control" and sent[i][2] == tostring(i))
end
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
