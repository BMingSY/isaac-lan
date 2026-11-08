local root = assert(arg[1])
local create = dofile(root .. "/src/bridge/presentation/update_notice.lua")
local keys =
    { escape = 27, enter = 13, up = 38, down = 40, tab = 9, space = 32, left = 37, right = 39 }
Vector = setmetatable({ Zero = {} }, {
    __call = function()
        return {}
    end,
})
Color = function()
    return {}
end
local function fixture()
    local result = { exits = 0, continues = 0, success = true, labels = {} }
    local render = create(keys, {
        update_continue = function()
            result.continues = result.continues + 1
        end,
        update_exit = function()
            result.exits = result.exits + 1
            return result.success
        end,
    })
    function result.draw(key, clicked, moved, hovered, held)
        result.labels = {}
        render({ key = key or 0, clicked = clicked, moved = moved, released = not held }, {
            assets = { fill = { Render = function() end }, lobby = {} },
            width = 480,
            height = 270,
            layer = function() end,
            centered = function(text)
                result.labels[text] = true
            end,
            pointer = function(_, y)
                result.selection = y == 181 and 1 or 2
            end,
            hit = function(_, y)
                return hovered == (y == 171 and 1 or 2)
            end,
        })
    end
    function result.arm()
        result.draw()
        result.draw()
    end
    return result
end
local ui = fixture()
ui.draw(keys.enter, true, true, 2)
assert(
    ui.selection == 1 and ui.exits == 0 and ui.continues == 0,
    "Opening key/click must not activate or change the default Exit selection"
)
ui.draw(keys.enter)
assert(ui.exits == 0, "Wait for a neutral input frame")
ui.draw(0, false, false, nil, true)
ui.draw(keys.enter, false, false, nil, true)
assert(ui.exits == 0, "Held keyboard/controller confirmation cannot arm the default Exit")
ui.draw()
ui.draw(keys.enter)
assert(ui.exits == 1 and ui.continues == 0)
assert(ui.labels["新版 Isaac LAN 已下载"] and ui.labels["退出后重新启动游戏，"])
for _, key in ipairs({ keys.up, keys.down, keys.left, keys.right, keys.tab }) do
    ui = fixture()
    ui.arm()
    ui.draw(key)
    ui.draw(keys.enter)
    assert(ui.selection == 2 and ui.continues == 1 and ui.exits == 0)
end
ui = fixture()
ui.arm()
ui.draw(keys.escape)
assert(ui.continues == 1 and ui.exits == 0, "Back continues safely")
ui = fixture()
ui.arm()
ui.draw(0, false, false, 2)
assert(ui.selection == 1, "An idle pointer does not replace the keyboard/controller default")
ui.draw(0, true, false, 2)
assert(ui.continues == 1 and ui.exits == 0, "Mouse can choose Continue")
ui = fixture()
ui.arm()
ui.draw(0, true, false, nil)
assert(ui.exits == 0 and ui.continues == 0, "Background clicks do nothing")
ui.draw(0, true, false, 1)
assert(ui.exits == 1, "Mouse can choose Exit")
ui = fixture()
ui.arm()
ui.success = false
ui.draw(keys.space)
assert(ui.exits == 1 and ui.labels["退出失败，请重试"])
ui.draw(keys.down)
ui.draw(keys.enter)
assert(ui.continues == 1, "A failed close request still allows Continue")
print("PASS update dialog default, input arming, keyboard/controller mapping, mouse and failure")
