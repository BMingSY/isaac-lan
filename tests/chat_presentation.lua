local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/presentation/chat.lua")
local layout = dofile(root .. "/src/bridge/presentation/chat_layout.lua")
local draws, loads, missing = {}, {}, false
local texts, availability, controlsPolled, sceneReady = {}, {}, 0, false
local mouse = { x = -1000, y = -1000, down = false }
local screenWidth, screenHeight = 640, 360
function Vector(x, y)
    return { X = x, Y = y }
end
function Color(r, g, b, a)
    return { R = r, G = g, B = b, A = a }
end
KColor = Color
function Sprite()
    return {
        Load = function(self, path)
            loads[path] = (loads[path] or 0) + 1
            if missing and path == "custom.anm2" then
                error("missing cached image")
            end
            self.path = path
        end,
        SetFrame = function() end,
        IsLoaded = function(self)
            return self.path ~= nil
        end,
        Render = function(self, position)
            draws[#draws + 1] =
                { path = self.path, color = self.Color, scale = self.Scale, position = position }
        end,
    }
end
function Font()
    return {
        Load = function() end,
        GetStringWidthUTF8 = function(_, value)
            return (utf8.len(value) or 0) * 5
        end,
        DrawStringScaledUTF8 = function(_, value, x, y, _, _, color)
            texts[#texts + 1] = { text = value, color = color, x = x, y = y }
        end,
    }
end
Isaac = {
    GetScreenWidth = function()
        return screenWidth
    end,
    GetScreenHeight = function()
        return screenHeight
    end,
    GetPlayer = function(index)
        return { Position = Vector(140 + index * 100, 150) }
    end,
    WorldToScreen = function(position)
        return position
    end,
}
local function create(image, opacity, options, messages)
    local input = { open = true, text = "", cursor = 0, anchor = 0, composition = "", scroll = 0 }
    local bubbles = {}
    for _, message in ipairs(messages or {}) do
        if message.bubble then
            bubbles[message.owner] = message
        end
    end
    local ui = factory({
        native = {
            chat_style = {
                opacity = opacity or 70,
                background = 0x231b18,
                border = 0x79604c,
                text = 0xe8dfcb,
                image = image or "",
                image_width = 420,
                image_height = 192,
            },
            chat_ui_caret = function() end,
            chat_ui_pointer = function()
                return mouse
            end,
            chat_ui_available = function(value)
                availability[#availability + 1] = value
                if not value then
                    input.open = false
                end
            end,
            chat_ui_state = function()
                return input
            end,
            chat_controls = function()
                controlsPolled = controlsPolled + 1
                return {}
            end,
            chat_ui_modal = function() end,
            emote_poll = function()
                return { open = false, selected = 0 }
            end,
            api_info = function()
                return { ready = sceneReady and 1 or 0 }
            end,
            rooms_positions = function()
                local positions = {}
                for owner = 0, 3 do
                    positions[tostring(owner)] = { index = 84, dimension = 0 }
                end
                return positions
            end,
            api_actors = function()
                local actors = {}
                for owner = 0, 3 do
                    actors[#actors + 1] = { index = owner, owner = owner + 1, role = 1 }
                end
                return actors
            end,
            api_with_local_view = function(callback)
                callback()
            end,
        },
        chat = {
            revision = 1,
            messages = messages or { { kind = "team", owner = 0, text = "你好", time = 0 } },
            bubbles = bubbles,
            emotes = {},
        },
        phase = { lobby = 2, running = 3, waiting = 9 },
        clock = function()
            return 1000
        end,
        limits = { characters = 60, commandBytes = 2048 },
        options = options or { FoundHUD = false, ExtraHUDStyle = 0, HUDOffset = 0 },
    }, layout)
    ui.input = input
    return ui
end
local ui = create()
ui.render({ phase = 2 })
assert(loads["custom.anm2"] == nil, "Solid default loaded a background image")
assert(draws[5].path == "gfx/ui/bossoverlay_whiteout.anm2" and draws[5].color.A == 0.7)
draws = {}
ui.input.open = false
ui.render({ phase = 2 })
assert(draws[5].color.A == 0.7, "Recent messages lost their translucent solid background")
draws = {}
ui = create("custom.anm2", 45)
ui.render({ phase = 2 })
assert(draws[1].path == "custom.anm2" and draws[1].color.A == 0.45)
assert(
    draws[1].color.R == 1 and draws[1].scale.X * 420 >= 210,
    "Image was tinted or incorrectly fitted"
)
ui.render({ phase = 2 })
assert(loads["custom.anm2"] == 1, "Image was reloaded every frame")
draws = {}
ui.input.open = false
ui.render({ phase = 2 })
assert(draws[1].path == "custom.anm2", "Recent messages lost their image background")
missing, draws = true, {}
create("custom.anm2", 45).render({ phase = 2 })
assert(#draws > 0)
assert(draws[5].color.A == 0.45, "Image fallback lost configured opacity")
for _, draw in ipairs(draws) do
    assert(draw.path ~= "custom.anm2", "Failed image was rendered instead of the fallback")
end
missing, draws = false, {}
local options = { FoundHUD = true, ExtraHUDStyle = 1, HUDOffset = 1 }
local status = { phase = 3, prepared = true }
ui = create(nil, nil, options)
ui.render(status)
local initial = draws[5].position
assert(initial.X >= 96, "Chat overlaps the stat HUD at maximum HUD offset")
mouse = { x = initial.X + 30, y = initial.Y + 20, down = true }
ui.render(status)
mouse.x, mouse.y = mouse.x + 80, mouse.y - 20
draws = {}
ui.render(status)
assert(
    draws[5].position.X == initial.X + 80 and draws[5].position.Y == initial.Y - 20,
    "Dragging the history did not move the panel"
)
mouse.down, draws = false, {}
ui.input.open = false
ui.render(status)
assert(draws[5].position.X == initial.X + 80, "Closing input lost the chosen position")
ui.input.open, draws = true, {}
ui.render(status)
assert(draws[5].position.Y == initial.Y - 20, "Reopening input lost the chosen position")
screenWidth, screenHeight, draws = 480, 270, {}
ui.render(status)
local resized = draws[5]
assert(
    resized.position.X >= 96 and resized.position.X + resized.scale.X * 480 <= 396,
    "Resized panel overlaps the stats or inventory HUD"
)
assert(
    resized.position.Y >= 68 and resized.position.Y + resized.scale.Y * 270 <= 254,
    "Resized panel left the screen"
)
mouse = {
    x = resized.position.X + 30,
    y = resized.position.Y + resized.scale.Y * 270 - 10,
    down = true,
}
ui.render(status)
mouse.x, draws = mouse.x - 70, {}
ui.render(status)
assert(draws[5].position.X == resized.position.X, "Clicking the input line started a drag")
-- Only LAN lobby/game/waiting may capture input or draw the chat interface.
ui = create()
for _, phase in ipairs({ 2, 3, 9 }) do
    ui.step({ phase = phase })
    assert(availability[#availability], "LAN chat did not enable input")
end
local polled = controlsPolled
for _, phase in ipairs({ 0, 1, 4, 5, 6, 7, 8 }) do
    draws, texts = {}, {}
    ui.step({ phase = phase })
    ui.render({ phase = phase })
    assert(not availability[#availability] and not ui.input.open, "Offline chat retained input")
    assert(controlsPolled == polled, "Offline chat polled chat controls")
    assert(#draws == 0 and #texts == 0, "Offline chat was rendered")
end
screenWidth, screenHeight, texts, draws = 640, 360, {}, {}
local messages = {}
for owner = 0, 3 do
    messages[#messages + 1] = {
        kind = "team",
        owner = owner,
        text = "发言" .. owner + 1,
        time = 0,
        bubble = true,
    }
end
messages[#messages + 1] = {
    kind = "system",
    owner = 0,
    text = "/c g c333",
    time = 0,
    command = true,
}
messages[#messages + 1] = {
    kind = "system",
    owner = 0,
    text = "1P掷出 D6 : 4",
    time = 0,
    bubble = true,
}
sceneReady = true
ui = create(nil, nil, nil, messages)
ui.render({ phase = 3, prepared = true, slot = 0, connected = 15 })
local function drawn(value)
    for _, item in ipairs(texts) do
        if item.text == value then
            return item.color
        end
    end
    error("Missing rendered text: " .. value)
end
local function colorKey(color)
    return color.R .. ":" .. color.G .. ":" .. color.B
end
local colors, bubbleColors = {}, {}
for owner = 0, 3 do
    local color = drawn(owner + 1 .. "P：发言" .. owner + 1)
    local key = colorKey(color)
    assert(not colors[key], "Players share a chat text color")
    assert(math.max(color.R, color.G, color.B) > 0.8, "Chat text is too dark for its panel")
    colors[key] = true
    local bubble = drawn(owner == 0 and "1P掷出 D6 : 4" or "发言" .. owner + 1)
    key = colorKey(bubble)
    assert(not bubbleColors[key], "Players share a bubble text color")
    assert(
        math.max(bubble.R, bubble.G, bubble.B) < 0.5,
        "Bubble text is too light for its background"
    )
    bubbleColors[key] = true
end
local commandColor = drawn("system: /c g c333")
assert(
    commandColor.R == 0xe8 / 255 and commandColor.G == 0xdf / 255 and commandColor.B == 0xcb / 255
)
local diceRows = {}
for _, item in ipairs(texts) do
    if item.text == "1P掷出 D6 : 4" then
        diceRows[#diceRows + 1] = item.color
    end
end
assert(
    #diceRows == 2 and colorKey(diceRows[2]) == colorKey(drawn("1P：发言1")),
    "Dice history lost its owner color"
)
sceneReady, texts = false, {}
ui = create("custom.anm2", 70, nil, messages)
ui.render({ phase = 2 })
local customRows = {}
for _, item in ipairs(texts) do
    if item.text == "1P：发言1" then
        customRows[#customRows + 1] = item
    end
end
assert(#customRows == 2, "Custom background text has no contrast shadow")
local shadow, label = customRows[1], customRows[2]
assert(shadow.x == label.x + 1 and shadow.y == label.y + 1)
assert(
    shadow.color.R < label.color.R
        and shadow.color.G < label.color.G
        and shadow.color.B < label.color.B
)
print(
    "PASS chat appearance, private history prefix, player colors, LAN-only input, HUD avoidance and dragging"
)
