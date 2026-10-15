-- One owned pair: rejoin twice without restarting either game process.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local owner = { Name = "Reconnect character cards" }
local renders, starts, departures = 0, 0, 0
local linked, chosen, leaving, finished = false, false, false, false
local lastExit, heldUntil, heldStatus
local seen = {}
local render = _IsaacLanMenuRender
function _IsaacLanMenuRender(available, visible, ...)
    -- The menu-start harness can leave the native file selector behind the
    -- overlay. Open the real LAN page explicitly for the recorded hold.
    return render(available, heldStatus ~= nil or visible, ...)
end
local function report(value)
    Isaac.DebugString("LAN_NETWORK RECONNECT_MENU " .. value)
end
local function roster(status)
    assert(status.character0 == 1 and status.character1 == 23, "Reconnect lost the run roster")
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function()
    starts = starts + 1
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    if not host then
        departures = departures + 1
        linked, chosen, leaving = false, false, false
        lastExit = renders
    end
end)
local gate = native.net_gate
native.net_gate = function(capture, apply, collect, restore, present, beginFloor)
    for i = 0, Game():GetNumPlayers() - 1 do
        Isaac.GetPlayer(i):SetMinDamageCooldown(10000)
    end
    return gate(function()
        return string.rep("\0", 34)
    end, apply, collect, restore, present, beginFloor)
end
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    -- Preserve a real received waiting/loading frame long enough to inspect
    -- its native-rendered cards. The host keeps running during this hold.
    if heldUntil and renders < heldUntil then
        return heldStatus
    end
    heldUntil, heldStatus = nil, nil
    local status = frame()
    if not linked and renders > (lastExit and lastExit + 60 or host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if status.phase == 2 then
        if not chosen then
            chosen = true
            assert(native.net_choose(host and 1 or 23, 1))
        end
        if host and status.players == 2 and status.ready0 == 1 and status.ready1 == 1 then
            _IsaacLanCommand("start", "YV039KQF:0:1:23:0:0")
        end
    end
    assert(status.phase ~= 4, status.error)
    if not host and departures > 0 and (status.phase == 9 or status.phase == 7) then
        roster(status)
        assert(status.choice0 == 0 and status.choice1 == 0, "Fresh rejoin retained lobby choices")
        local key = departures .. ":" .. status.phase
        if not seen[key] then
            seen[key] = true
            report("CARDS attempt=" .. departures .. " phase=" .. status.phase .. " roster=1,23")
            heldUntil, heldStatus = renders + 120, status
            _IsaacLanMenuOpen(true)
        end
    end
    if status.phase == 3 and status.prepared then
        roster(status)
        if status.connected == 3 and not seen["live:" .. starts] then
            for slot, id in ipairs({ 1, 23 }) do
                assert(native.rooms_with_player(slot - 1, function()
                    local player = Isaac.GetPlayer(native.rooms_heads()[tostring(slot - 1)])
                    assert(player:GetPlayerType() == id, "Rejoin changed the actual character")
                end))
            end
            seen["live:" .. starts] = true
        end
        if not host and starts <= 2 and status.verified > starts * 180 and not leaving then
            if starts > 1 then
                assert(seen[departures .. ":9"] or seen[departures .. ":7"])
                report("RESTORED attempt=" .. departures)
            end
            leaving = true
            assert(native.net_command(4))
        end
        if not finished and status.verified > 720 and status.connected == 3 then
            if not host then
                assert(starts == 3 and (seen["2:9"] or seen["2:7"]))
                report("RESTORED attempt=2")
            end
            finished = true
            Isaac.DebugString("LAN_NETWORK PASS reconnect character cards")
        end
    end
    return status
end
