-- Both peers must run the Repentance build of REPENTOGON in this scenario.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
assert(_VERSION == "Lua 5.4" and REPENTOGON, "Expected the active REPENTOGON Lua runtime")
local phase = native.net_phases()
local observer = RegisterMod("Isaac LAN REPENTOGON integration fixture", 1)
local hudFrames = 0
observer:AddCallback(ModCallbacks.MC_POST_HUD_RENDER, function()
    hudFrames = hudFrames + 1
end)
local frame = _IsaacLanFrame
local joined, chosen, started, finished = false, false, false, false
function _IsaacLanFrame()
    local status = frame()
    assert(status.phase ~= phase.failed, status.error)
    if status.scene == 1 and not joined then
        joined = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if status.phase == phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        config.host
        and not started
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if
        not finished
        and status.prepared
        and status.connected == 3
        and status.verified >= 120
        and hudFrames > 0
    then
        assert(Game():GetNumPlayers() == 2)
        finished = true
        Isaac.DebugString(
            "LAN_NETWORK REPENTOGON PASS verified=" .. status.verified .. " hud=" .. hudFrames
        )
    end
    return status
end
