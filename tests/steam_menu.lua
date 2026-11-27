local root = assert(arg[1])
local phase = dofile(root .. "/tests/fixtures/net_phases.lua")
local model = dofile(root .. "/src/bridge/presentation/menu_model.lua")(
    phase,
    dofile(root .. "/tests/fixtures/net_commands.lua"),
    dofile(root .. "/src/bridge/core/endpoint.lua"),
    dofile(root .. "/src/bridge/presentation/menu_characters.lua")(),
    string.format
)
local ui = { page = "modes", port = "30220", ip = "", errorText = "" }
local status = { phase = phase.idle, steamAvailable = true }
local room = { id = "109775243000000001", name = "Room", players = 3, limit = 4, pingMs = 50 }
local other = { id = "109775243000000002", name = "Other", players = 1, limit = 4 }
local rooms = { room, other }
local action, value
local deps = {
    native = {
        menu_official = function() end,
        net_steam_list = function()
            return rooms
        end,
    },
    command = function(name, arg)
        action, value = name, arg
    end,
    hide = function() end,
}
local function byLabel()
    local result = {}
    for _, row in ipairs(model.rows(ui, status, {}, {}, deps)) do
        result[row.label] = row
    end
    return result
end
local menu = byLabel()
assert(menu["官方联机"] and menu["局域网联机"] and menu["Steam 联机"])
menu["Steam 联机"].action()
byLabel()["创建私人房间"].action()
assert(action == "steam_create")
byLabel()["公开房间"].action()
assert(action == "steam_browse" and ui.page == "steamList")
menu = byLabel()
assert(menu["Other  1/4  --ms"].roomSummary == "1/4  --ms")
assert(menu["Room  3/4  50ms"].roomName == "Room")
ui.selection = 2
other.pingMs = 0
rooms = { other, room }
local sorted = model.rows(ui, status, {}, {}, deps)
assert(sorted[2].label == "Other  1/4  0ms" and ui.selection == 3)
sorted[ui.selection].action()
assert(action == "steam_join" and value == room.id)
rooms = { other }
assert(byLabel()["刷新"] and ui.selection == 1)
ui.selection = 3
rooms = { other, room }
assert(byLabel()["返回"] and ui.selection == 4)
status.steamBusy = true
assert(not byLabel()["Room  3/4  50ms"].enabled)
byLabel()["返回"].action()
assert(action == "steam_cancel" and ui.page == "steam")
ui.page, status.phase, status.hosting, status.transport = "steamOptions", phase.lobby, 1, "steam"
byLabel()["可见性：私人"].action()
assert(action == "steam_visibility")
status.hosting = 0
assert(not byLabel()["可见性：私人"])
byLabel()["邀请 Steam 好友"].action()
assert(action == "steam_invite")
ui.page, status.phase, status.transport, status.steamBusy = "steamInvite", phase.idle, "udp", false
byLabel()["忽略邀请"].action()
assert(action == "steam_dismiss" and ui.page == "modes")
status.steamAvailable = false
assert(not byLabel()["Steam 联机"] and byLabel()["局域网联机"])
