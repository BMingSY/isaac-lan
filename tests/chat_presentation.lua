local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/presentation/chat.lua")
local layout = dofile(root .. "/src/bridge/presentation/chat_layout.lua")
local draws, loads, missing = {}, {}, false
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
        Render = function(self)
            draws[#draws + 1] = { path = self.path, color = self.Color, scale = self.Scale }
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
        return 640
    end,
    GetScreenHeight = function()
        return 360
    end,
}
local function create()
    local ui = factory({
        native = {
            chat_style = {
                opacity = 45,
                background = 0x231b18,
                border = 0x79604c,
                text = 0xe8dfcb,
                image = "custom.anm2",
                image_width = 420,
                image_height = 192,
            },
            chat_ui_caret = function() end,
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
    }, layout)
    ui.input = { open = true, text = "", cursor = 0, anchor = 0, composition = "" }
    return ui
end
local ui = create()
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
create().render({ phase = 2 })
assert(#draws > 0)
for _, draw in ipairs(draws) do
    assert(draw.path ~= "custom.anm2", "Failed image was rendered instead of the fallback")
end
print(
    "PASS chat image scaling, opacity, cached rendering, recent messages and missing-image fallback"
)
