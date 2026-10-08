-- Actual, unmodified Good Trip; input enters through the native XInput path.
local native = assert(_IsaacLan)
assert(ButtonAction.ACTION_MAP == 13, "J460 map action changed")
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(s)
    Isaac.DebugString("LAN_NETWORK " .. s)
end
local owner = { Name = "Isolated Good Trip interface regression" }
local frame = _IsaacLanFrame
local renders, linked, chosen, finished = 0, false, false, false
local patched, drawn, pressed, triggered, wrongView = false, 0, 0, 0, 0
local uiFrames = 0
local selection
local cursor, hostDraws, pingSeen = nil, 0, false
local function cached(name)
    for i = 1, 30 do
        local key, value = debug.getupvalue(gt.new_room, i)
        if not key then
            break
        end
        if key == name then
            return value
        end
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = frame()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "7:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "LBCD0G4M:0:7:7:7:7")
    end
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.prepared and not patched then
        patched = true
        do
            assert(gt and gt.draw_minimap, "Unmodified Good Trip did not load")
            local draw = gt.draw_minimap
            function gt:draw_minimap(...)
                drawn = drawn + 1
                if host then
                    hostDraws = hostDraws + 1
                end
                return draw(self, ...)
            end
            local teleport = gt.teleport_to_grid_index
            function gt:teleport_to_grid_index(index)
                report("GT native teleport target=" .. index)
                for i = 1, 20 do
                    local name, value = debug.getupvalue(teleport, i)
                    if not name then
                        break
                    end
                    if name == "player" then
                        report(
                            "GT cached controller="
                                .. value.ControllerIndex
                                .. " render controller="
                                .. Isaac.GetPlayer(0).ControllerIndex
                        )
                    end
                end
                return teleport(self, index)
            end
            local select = gt.get_pos_grid_index_mmp
            function gt:get_pos_grid_index_mmp(pos)
                local index = select(self, pos)
                selection = index
                if host and uiFrames >= 105 and uiFrames <= 120 then
                    if cursor then
                        assert(
                            (cursor - pos):Length() < 0.01,
                            "Remote shooting moved the host Good Trip cursor"
                        )
                    end
                    cursor = Vector(pos.X, pos.Y)
                end
                if uiFrames == 45 or uiFrames == 59 then
                    report("GT selection=" .. index .. " pos=" .. pos.X .. "," .. pos.Y)
                end
                return index
            end
        end
    end
    if s.prepared and s.verified >= 100 then
        uiFrames = uiFrames + 1
    end
    local holding = not host and uiFrames > 0 and uiFrames < 60
    local buttons = holding and (uiFrames >= 31 and selection ~= 71 and 32800 or 32) or 0
    if host and uiFrames >= 80 and uiFrames < 150 then
        buttons = 32
    end
    if not host and uiFrames >= 100 and uiFrames < 130 then
        buttons = 32768
    end
    native.test_gamepad(buttons)
    if s.ping1 and s.ping1 >= 140 and s.ping1 < 1500 then
        pingSeen = true
    end
    if uiFrames >= 20 and uiFrames < 25 then
        report("VISUAL_READY")
    end
    if s.verified >= 320 and not finished then
        local level = Game():GetLevel()
        local target = level:GetRoomByIdx(71)
        report(
            "GT room clear="
                .. tostring(target.Clear)
                .. " display="
                .. target.DisplayFlags
                .. " visits="
                .. target.VisitedCount
                .. " draws="
                .. drawn
                .. " presses="
                .. pressed
        )
        if not host then
            assert(
                pressed > 20 and triggered > 0,
                "Replica Mod did not receive native local map input"
            )
            assert(drawn > 20, "Good Trip did not render its expanded map")
        end
        assert(wrongView == 0, "Remote map input opened the host interface")
        if host then
            assert(hostDraws > 20 and cursor, "Host map/cursor isolation was not exercised")
        end
        assert(pingSeen, "Measured per-guest RTT was not exposed to the game UI")
        local pos = native.rooms_positions()
        assert(
            pos["0"].index == 84 and pos["1"].index == 71,
            "Good Trip teleport was not executed by the host"
        )
        finished = true
        report(
            "PASS local Mod map and room request draw="
                .. drawn
                .. " pressed="
                .. pressed
                .. " triggered="
                .. triggered
        )
    end
    return s
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_RENDER, function()
    local s = _IsaacLanStatus()
    if not s.prepared or not native.rooms_ready() then
        return
    end
    assert(
        Isaac.GetPlayer(0).ControllerIndex == (host and 1 or 2),
        "Mod render callback has another player first"
    )
    if Input.IsActionPressed(ButtonAction.ACTION_MAP, Isaac.GetPlayer(0).ControllerIndex) then
        if host and uiFrames > 5 and uiFrames < 55 then
            wrongView = wrongView + 1
        elseif not host then
            pressed = pressed + 1
        end
    end
    if host and uiFrames >= 105 and uiFrames <= 120 then
        assert(
            not Input.IsActionPressed(ButtonAction.ACTION_SHOOTUP, 2),
            "Remote shooting leaked into local interface queries"
        )
    end
    if s.verified >= 80 then
        assert(
            cached("crid") == Game():GetLevel():GetCurrentRoomIndex(),
            "Remote entry overwrote the local Good Trip room cache"
        )
    end
    if
        not host
        and Input.IsActionTriggered(ButtonAction.ACTION_MAP, Isaac.GetPlayer(0).ControllerIndex)
    then
        triggered = triggered + 1
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_UPDATE, function()
    local s = _IsaacLanStatus()
    if not s.prepared or not native.rooms_ready() then
        return
    end
    assert(
        Isaac.GetPlayer(0).ControllerIndex == (host and 1 or 2),
        "Global Mod update sees a remote actor first"
    )
    if host and uiFrames > 5 and uiFrames < 55 then
        assert(
            not Input.IsActionPressed(ButtonAction.ACTION_MAP, 2),
            "Remote map input leaked into the native update"
        )
    end
end)
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, b)
        before(t, n, b)
        if t == 20 then
            assert(native.rooms_move(1, 71, 0, -1))
        end
        if t == 30 then
            assert(native.rooms_with_player(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToNPC() then
                        e:Remove()
                    end
                end
                Game():GetRoom():SetClear(true)
            end))
        end
        if t == 50 then
            assert(native.rooms_move(1, 84, 0, -1))
        end
    end, collect, restore, present, beginFloor)
end
