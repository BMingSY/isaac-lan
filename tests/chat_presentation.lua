local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/presentation/chat.lua")
local layout = dofile(root .. "/src/bridge/presentation/chat_layout.lua")
local draws, loads, missing = {}, {}, false
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
        DrawStringScaledUTF8 = function() end,
    }
end
Isaac = {
    GetScreenWidth = function()
        return screenWidth
    end,
    GetScreenHeight = function()
        return screenHeight
    end,
}
local function create(image, opacity, options)
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
            api_info = function()
                return { ready = 0 }
            end,
        },
        chat = {
            revision = 1,
            messages = { { kind = "team", owner = 0, text = "你好", time = 0 } },
        },
        phase = { lobby = 2, running = 3, waiting = 8 },
        clock = function()
            return 1000
        end,
        limits = { characters = 60, commandBytes = 2048 },
        options = options or { FoundHUD = false, ExtraHUDStyle = 0, HUDOffset = 0 },
    }, layout)
    ui.input = { open = true, text = "", cursor = 0, anchor = 0, composition = "" }
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
print("PASS chat backgrounds, HUD avoidance, history dragging, input exclusion and viewport bounds")
