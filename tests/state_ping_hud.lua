-- Concentrated two-peer visual acceptance; uses one game per peer throughout.
local native = assert(_IsaacLan)
local file = assert(io.open("./lan-test-role.txt", "r"))
local host = file:read("*l") == "host"
file:close()
file = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = file:read("*l")
file:close()
local function report(message)
    Isaac.DebugString("LAN_NETWORK " .. message)
end
local frame, menu, getStatus = _IsaacLanFrame, _IsaacLanMenuRender, _IsaacLanStatus
local frames, linked, chosen, done = 0, false, false, false
local uiFrames, lastPhase, seen = 0, -1, {}
local initialOffset
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if status.phase == 4 or status.phase == 9 then
        report("FAILED " .. status.error)
    end
    return status
end
function _IsaacLanMenuRender(available, visible, ...)
    local status = getStatus()
    if not status.prepared or status.phase ~= 3 or status.verified < 40 then
        return menu(available, visible, ...)
    end
    uiFrames = uiFrames + 1
    initialOffset = initialOffset or Options.HUDOffset
    local phase = math.min(8, math.floor((uiFrames - 1) / 90))
    local hud = Game():GetHUD()
    Options.HUDOffset = phase == 1 and 1 or initialOffset
    hud:SetVisible(phase ~= 5)
    local overrides = { [2] = 150, [3] = 280, [4] = -1 }
    if overrides[phase] then
        status.ping1 = overrides[phase]
    end
    -- Only the display reads synthetic values; transport RTT stays intact.
    _IsaacLanStatus = function()
        return status
    end
    local ok, result = pcall(menu, available, phase == 6, ...)
    _IsaacLanStatus = getStatus
    assert(ok, result)
    local huds = native.presentation_player_huds()
    if phase == 5 then
        assert(next(huds) == nil, "Hidden HUD retained ping anchors")
    end
    if phase ~= lastPhase and (phase == 5 or huds["0"] and huds["1"]) then
        lastPhase, seen[phase] = phase, true
        local function rectangle(slot)
            local value = huds[tostring(slot)]
            return value and string.format("%.1f,%.1f,layout=%d", value.x, value.y, value.layout)
                or "hidden"
        end
        report(
            "PING_HUD phase="
                .. phase
                .. " host="
                .. rectangle(0)
                .. " guest="
                .. rectangle(1)
                .. " rtt="
                .. (status.ping1 or -1)
        )
        if phase == 0 then
            report("VISUAL_READY")
        end
    end
    if phase == 8 and status.verified >= 650 and not done then
        for index = 0, 8 do
            assert(seen[index], "HUD acceptance phase missing: " .. index)
        end
        assert(Game():GetLevel():GetStage() == 2, "Floor transition did not finish")
        assert((getStatus().ping1 or -1) >= 0, "No measured RTT reached the display")
        assert(huds["0"] and huds["1"], "Player HUD identity lost across floor")
        Options.HUDOffset = initialOffset
        done = true
        report("PASS ping HUD anchors, values, offset, hide, menu, room and floor")
    end
    return phase == 6 and false or result
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(function()
        return string.rep("\0", 43)
    end, function(t, n, buttons)
        before(t, n, buttons)
        for index = 0, Game():GetNumPlayers() - 1 do
            Isaac.GetPlayer(index):SetMinDamageCooldown(60)
        end
        if t == 200 then
            local origin = native.rooms_positions()["1"].index
            local rooms = Game():GetLevel():GetRooms()
            for index = 0, rooms.Size - 1 do
                local room = rooms:Get(index)
                if room.SafeGridIndex ~= origin and room.Data.Type == RoomType.ROOM_DEFAULT then
                    assert(native.rooms_move(1, room.SafeGridIndex, 0, 0))
                    report("PING_HUD remote room changed")
                    break
                end
            end
        end
        if t == 420 then
            assert(native.rooms_with_player(0, function()
                Game():GetRoom():SetClear(true)
                Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
            end))
            report("PING_HUD floor transition")
        end
    end, collect, restore, present, beginFloor)
end
