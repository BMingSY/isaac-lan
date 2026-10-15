local root = assert(arg[1])
local draws, reads = {}, 0
local width, height = 480, 270
KColor = function(r, g, b, a)
    return { r, g, b, a }
end
Isaac = {
    GetScreenWidth = function()
        return width
    end,
    GetScreenHeight = function()
        return height
    end,
}
local font = {
    GetStringWidthUTF8 = function(_, text)
        return utf8.len(text) * 6
    end,
    DrawStringScaledUTF8 = function(_, text, x, y, sx, sy, color)
        draws[#draws + 1] = { text = text, x = x, y = y, width = utf8.len(text) * 6 * sx }
        assert(sx == 0.6 and sy == 0.6 and color[1] == 1 and color[4] == 1)
    end,
}
local huds = {
    ["0"] = { x = 100, y = 20 },
    ["1"] = { x = 340, y = 25 },
    ["2"] = { x = 110, y = 230 },
    ["3"] = { x = 350, y = 235 },
}
local render = dofile(root .. "/src/bridge/presentation/ping.lua")({
    presentation_player_huds = function()
        reads = reads + 1
        return huds
    end,
})
local status = {
    prepared = true,
    phase = 3,
    players = 4,
    connected = 15,
    ping1 = 35,
    ping2 = 150,
    ping3 = 280,
}
local function draw()
    draws = {}
    render(status, font)
end
-- Each guest's measured value follows that controller's native HUD anchor.
draw()
assert(#draws == 3)
for i, slot in ipairs({ "1", "2", "3" }) do
    assert(draws[i].text == status["ping" .. slot] .. " ms")
    assert(draws[i].x == huds[slot].x + 12 and draws[i].y == huds[slot].y - 13)
end
status.players, status.connected = 2, 3
for _, ping in ipairs({ 0, 99, 100, 199, 200, 12345 }) do
    status.ping1 = ping
    draw()
    assert(#draws == 1 and draws[1].text == ping .. " ms")
end
for _, ping in ipairs({ -1, -10 }) do
    status.ping1 = ping
    draw()
    assert(draws[1].text == "—")
end
status.ping1 = nil
draw()
assert(draws[1].text == "—")
-- Local-view reordering and room/floor changes provide fresh native anchors.
huds["1"] = { x = 140.5, y = 20.5 }
draw()
assert(draws[1].x == 152 and draws[1].y == 7)
width, height = 640, 360
huds["1"] = { x = 639, y = 2 }
status.ping1 = 12345
draw()
assert(draws[1].x + draws[1].width < width and draws[1].y == 1)
status.connected = 1
draw()
assert(#draws == 0)
status.connected, huds["1"] = 3, nil
draw()
assert(#draws == 0)
local before = reads
status.prepared = false
draw()
assert(#draws == 0 and reads == before)
status.prepared, status.phase = true, 2
draw()
assert(#draws == 0 and reads == before)
print("PASS numeric ping HUD, native identity/position, resizing, disconnect and lifecycle cleanup")
