-- Run after state_shared_rules in the same protected profiles. This deliberately
-- requires a process restart to exercise the real preference-file startup path.
local native, host, port = _IsaacLan, _IsaacLanTest.host, _IsaacLanTest.port
local frame = _IsaacLanFrame
local renders, linked, finished = 0, false, false
assert(native.menu_room_options() == (host and 6 or 1), "Restart lost local rule selection")
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 420) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    if
        not finished
        and s.phase == native.net_phases().lobby
        and s.players == 2
        and s.roomOptions == 6
    then
        assert(
            native.menu_room_options() == (host and 6 or 1),
            "Joined rules overwrote saved hosting preferences"
        )
        if not host then
            assert(not native.net_configure_options(0), "Guest changed room rules")
        end
        finished = true
        Isaac.DebugString("LAN_PREFERENCES_PASS")
    end
    return s
end
return {
    done = function()
        return finished
    end,
}
