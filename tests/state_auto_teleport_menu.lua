-- Exercise real fonts, input and lobby propagation before gathering in the same connection.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, frame, menu = config.host, _IsaacLanFrame, _IsaacLanMenuRender
local renders, linked, chosen, began, stage, finished = 0, false, false, nil, 1, false
local queued, nextInput = {}, 0
local first, all
for _, rule in ipairs(native.net_room_options()) do
    if rule.key == "autoTeleport" then
        first, all = rule.firstRoomFlag, rule.flag
    end
end
assert(first and all)
local boss = first << (RoomType.ROOM_BOSS - RoomType.ROOM_DEFAULT)
local ultra = first << (RoomType.ROOM_ULTRASECRET - RoomType.ROOM_DEFAULT)
local expected = 1 | boss | ultra
local count, mask = 0, 0
for _, room in ipairs(_IsaacLanModules["core/room_types"]) do
    local flag = first << (assert(RoomType[room.enum]) - RoomType.ROOM_DEFAULT)
    assert(mask & flag == 0, "Duplicate room type")
    count, mask = count + 1, mask | flag
end
assert(count == 29 and mask == all, "Native room types differ from the selection contract")
assert(native.menu_room_options_save(host and 1 or 2))
local function keys(...)
    assert(#queued == 0)
    queued = { ... }
end
local function expect(status, options, scene)
    assert(status.roomOptions == options, "Auto teleport did not propagate: " .. scene)
    assert(
        native.menu_room_options() == (host and options or 2),
        "Local hosting preference changed"
    )
    Isaac.DebugString("LAN_AUTO_MENU " .. scene .. " options=" .. options)
end
local steps = {
    {
        0,
        function()
            if host then
                keys(40, 40, 40, 40, 13, 40, 40, 40, 13)
            else
                keys(40, 40, 13, 40, 40, 40, 13)
            end
        end,
    },
    {
        3500,
        function(s)
            expect(s, 1, "open")
            assert(s.ready0 == 1 and s.ready1 == 1, "Opening the submenu cleared readiness")
            if host then
                keys(40, 40, 13)
            end
        end,
    },
    {
        6000,
        function(s)
            expect(s, 1 | boss, "boss-only")
            assert(s.ready0 == 0 and s.ready1 == 0, "Type selection retained readiness")
            if host then
                keys(38, 38, 13)
            else
                keys(40, 40, 13)
            end
        end,
    },
    {
        8500,
        function(s)
            expect(s, 1 | all, "select-all")
            if host then
                keys(40, 13)
            else
                keys(13)
            end
        end,
    },
    {
        11000,
        function(s)
            expect(s, 1, "clear-preserves-friendly-fire")
            if host then
                keys(40, 13, 38, 38, 38, 38, 13)
            end
        end,
    },
    {
        14000,
        function(s)
            expect(s, expected, "selected-two-types")
            if not host then
                keys(38, 38, 38, 38, 13)
            end
        end,
    },
    {
        16500,
        function(s)
            expect(s, expected, "guest-read-only-high-bit")
            if host then
                keys(27, 27, 38, 38, 38, 13)
            else
                keys(27, 27, 38, 13)
            end
        end,
    },
}
function _IsaacLanMenuRender(available, visible, key, typed, mx, my, clicked, ...)
    if linked and _IsaacLanStatus().phase == 2 then
        visible, key, typed, mx, my, clicked = true, 0, "", -1000, -1000, false
    end
    if #queued > 0 and renders >= nextInput then
        key = table.remove(queued, 1)
        nextInput = renders + 12
    end
    return menu(available, visible, key, typed, mx, my, clicked, ...)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 420) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        _IsaacLanMenuOpen(true)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and status.players == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    local now = native.api_info().nowMs
    if not began and status.players == 2 and status.ready0 == 1 and status.ready1 == 1 then
        began = now
    end
    if began then
        if steps[stage] and now - began >= steps[stage][1] and #queued == 0 then
            steps[stage][2](status)
            stage = stage + 1
        elseif not steps[stage] and now - began >= 19500 then
            expect(status, expected, "back-and-ready")
            assert(
                status.ready0 == 1 and status.ready1 == 1,
                "Nested Back lost the lobby selection"
            )
            finished = true
            Isaac.DebugString("LAN_AUTO_MENU_PASS")
        end
    end
    return status
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        _IsaacLanFrame, _IsaacLanMenuRender = frame, menu
    end,
}
