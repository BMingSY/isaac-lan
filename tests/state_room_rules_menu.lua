-- Native menu-only acceptance: drive the production render/input path while
-- retaining one host/client connection. Gameplay is never started.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local frame, menu = _IsaacLanFrame, _IsaacLanMenuRender
local json = require("json")
local renders, linked, chosen, began, stage = 0, false, false, nil, 1
local queued, nextInput = {}, 0
local function keys(...)
    assert(#queued == 0, "Previous menu input did not finish")
    queued = { ... }
end
local function report(scene, s)
    Isaac.DebugString("LAN_RULES_MENU " .. json.encode({
        role = config.host and "host" or "client",
        scene = scene,
        frame = renders,
        nowMs = native.api_info().nowMs,
        options = s.roomOptions,
        ready0 = s.ready0,
        ready1 = s.ready1,
    }))
end
local function expect(s, options)
    assert(s.roomOptions == options, "Menu rule edit did not reach this peer")
end
local steps = config.host
        and {
            {
                0,
                function()
                    keys(40, 40, 40, 40, 13)
                end,
            },
            {
                2500,
                function(s)
                    expect(s, 0)
                    assert(s.ready0 == 1 and s.ready1 == 1, "Opening rules cleared readiness")
                    report("host-submenu-off", s)
                end,
            },
            {
                3000,
                function()
                    keys(13)
                end,
            },
            {
                4500,
                function(s)
                    expect(s, 1)
                    assert(s.ready0 == 0 and s.ready1 == 0, "Changing rules retained readiness")
                    report("host-submenu-on", s)
                end,
            },
            {
                5500,
                function()
                    keys(13)
                end,
            },
            {
                7000,
                function(s)
                    expect(s, 0)
                    report("host-submenu-off-again", s)
                end,
            },
            {
                7500,
                function()
                    keys(13)
                end,
            },
            {
                9000,
                function(s)
                    expect(s, 1)
                    keys(27)
                end,
            },
            {
                10500,
                function(s)
                    report("host-summary", s)
                    keys(13) -- Escape must have returned to the rules entry.
                end,
            },
            {
                12000,
                function(s)
                    expect(s, 1)
                    report("host-submenu-reopened", s)
                    keys({ x = 70, y = 217 }) -- Fixed Back row.
                end,
            },
            {
                13500,
                function()
                    keys(38, 38, 38, 13) -- Rules entry -> Ready, with no gameplay start.
                end,
            },
        }
    or {
        {
            0,
            function()
                keys(40, 40, 13)
            end,
        },
        {
            2500,
            function(s)
                expect(s, 0)
                report("guest-submenu-off", s)
            end,
        },
        {
            4000,
            function(s)
                expect(s, 1)
                keys(13) -- Read-only checkbox must ignore confirmation.
            end,
        },
        {
            5000,
            function(s)
                expect(s, 1)
                report("guest-submenu-read-only", s)
            end,
        },
        {
            7000,
            function(s)
                expect(s, 0)
                report("guest-live-update", s)
            end,
        },
        {
            9000,
            function(s)
                expect(s, 1)
                keys(32) -- Space is also read-only.
            end,
        },
        {
            10000,
            function(s)
                expect(s, 1)
                keys(27)
            end,
        },
        {
            11000,
            function(s)
                report("guest-summary", s)
                keys(13)
            end,
        },
        {
            12000,
            function()
                keys({ x = 70, y = 105 }) -- Mouse confirmation is read-only as well.
            end,
        },
        {
            13000,
            function(s)
                expect(s, 1)
                report("guest-submenu-reopened", s)
                keys({ x = 70, y = 217 })
            end,
        },
        {
            14500,
            function()
                keys(38, 13)
            end,
        },
    }
function _IsaacLanMenuRender(available, visible, key, typed, mx, my, clicked, ...)
    if linked and _IsaacLanStatus().phase == 2 then
        visible = true
        key, typed, mx, my, clicked = 0, "", -1000, -1000, false
    end
    if #queued > 0 and renders >= nextInput then
        local input = table.remove(queued, 1)
        nextInput = renders + 12
        if type(input) == "table" then
            mx = (Isaac.GetScreenWidth() - 480) / 2 + input.x
            my = (Isaac.GetScreenHeight() - 270) / 2 + input.y
            clicked = true
        else
            key = input
        end
    end
    return menu(available, visible, key, typed, mx, my, clicked, ...)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (config.host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        _IsaacLanMenuOpen(true)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    local now = native.api_info().nowMs
    if not began and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        began = now
    end
    if began then
        if steps[stage] and now - began >= steps[stage][1] and #queued == 0 then
            steps[stage][2](s)
            stage = stage + 1
        elseif not steps[stage] and now - began >= 16500 then
            expect(s, 1)
            assert(s.ready0 == 1 and s.ready1 == 1, "Back did not restore the lobby selection")
            report("completed", s)
            Isaac.DebugString("LAN_RULES_MENU_PASS")
            _IsaacLanFrame, _IsaacLanMenuRender = frame, menu
        end
    end
    return s
end
