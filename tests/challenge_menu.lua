local root = assert(arg[1])
local labels, commands = {}, {}
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
    return { Load = noop, SetFrame = noop, Render = noop, RenderLayer = noop, SetLayerFrame = noop }
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
        DrawStringScaledUTF8 = function(_, text)
            labels[text] = true
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
_IsaacLanStatus = function()
    return status
end
_IsaacLan = {
    menu_text_end = noop,
    net_characters = function()
        return characters
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
draw(39)
assert(status.choice0 == 0)
characters = { 0 }
draw(39)
assert(status.choice0 == 0)
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
print("PASS challenge list, colored selection, role lock, guest view, clean HUD and transient exit")
