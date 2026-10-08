local native = assert(_IsaacLan)
local owner = { Name = "Isolated current-floor reconnect regression" }
local file = assert(io.open("./lan-test-role.txt", "r"))
local host = file:read("*l") == "host"
file:close()
local renders, starts = 0, 0
local linked, chosen, finished = false, false, false
local departed = false
local confirmedArrival = false
local function report(s)
    Isaac.DebugString("LAN_NETWORK " .. s)
end
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    if not host and not departed then
        departed = true
        renders = 0
        linked = false
        chosen = false
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    starts = starts + 1
    assert(continued == (starts > 1))
    report("GAME_STARTED continued=" .. tostring(continued))
end)
local startEngine = native.net_engine_start
local readyPath = "D:/isaac-lan-lab/host-001/game/lan-test-loader-ready.txt"
if host then
    os.remove(readyPath)
end
local delayedStart
native.net_engine_start = function(...)
    if native.net_poll().firstTick > 0 then
        delayedStart = true
        report("LOADER deliberately delayed while host continues")
        return true
    end
    return startEngine(...)
end
local portFile = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = portFile:read("*l")
portFile:close()
local baseFrame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (departed and 30 or host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    if delayedStart then
        local ready = io.open(readyPath, "r")
        if ready then
            ready:close()
            delayedStart = nil
            assert(startEngine())
        end
    end
    local status = baseFrame()
    if not host and not departed and status.phase == 3 and status.verified >= 60 then
        assert(native.net_command(4))
    end
    if status.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if status.phase == 4 then
        report("FAILED " .. status.error)
    end
    if status.phase == 9 and status.error ~= "" then
        report("FAILED " .. status.error)
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if status.verified >= 900 and status.connected == 3 and not finished then
        assert(
            Game():GetLevel():GetStage() == 2,
            "Reconnect missed the host's floor transition during loading"
        )
        assert(confirmedArrival, "Current-room arrival was never observed")
        finished = true
        report("VERIFIED " .. status.verified)
        report("PASS reconnect follows floor changes during loading")
    end
    return status
end
local gate = native.net_gate
native.net_gate = function(capture, apply, collect, restore, present, beginFloor)
    local first = native.net_poll().firstTick
    if first == 0 and host then
        for i = 0, 1 do
            Isaac.GetPlayer(i):SetMinDamageCooldown(10000)
        end
        local guest = Isaac.GetPlayer(1)
        guest:AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
        guest:AddCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
        guest:AddCoins(19)
    elseif first > 0 then
        assert(first > 60 and first < 200, "Current-floor checkpoint was not captured promptly")
        report("CHECKPOINT firstTick=" .. first)
    end
    local tick = -1
    local returned = false
    return gate(
        function()
            return string.rep("\0", 34)
        end,
        function(t, n, b)
            tick = t
            apply(t, n, b)
            if t == 200 then
                assert(
                    native.rooms_connected() == 1 and Game():GetNumPlayers() == 1,
                    "Guest still affects combat"
                )
                report("HOST continued while guest waiting")
                assert(Game():GetLevel():GetStage() == 1, "Rejoin unnecessarily changed floor")
            end
            if t == 300 then
                assert(native.rooms_with_player(0, function()
                    Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
                end))
                report("HOST changed floors while guest was loading")
            end
            if t == 500 then
                assert(native.rooms_connected() == 1, "Slow loader unexpectedly stopped host time")
                report("HOST changed rooms while guest was loading")
                if host then
                    local f = assert(io.open(readyPath, "w"))
                    f:write("ready")
                    f:close()
                end
                assert(native.rooms_with_player(0, function()
                    Isaac.ExecuteCommand("goto s.devil.1")
                end))
            end
            if t == 520 then
                assert(native.rooms_with_player(0, function()
                    assert(Game():GetRoom():GetType() == RoomType.ROOM_DEVIL)
                    local e = Isaac.Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        0,
                        Game():GetRoom():GetCenterPos() + Vector(100, 60),
                        Vector.Zero,
                        nil
                    )
                    e:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                    e.HitPoints = 10000
                    e.MaxHitPoints = 10000
                    Game():GetRoom():SetClear(false)
                end))
            end
            if t > 400 and native.rooms_connected() == 3 and not returned then
                returned = true
                local positions = native.rooms_positions()
                assert(
                    positions["0"].index == positions["1"].index,
                    "Rejoin did not enter the host's current room"
                )
                local p = Isaac.GetPlayer(native.rooms_heads()["1"])
                local h = Isaac.GetPlayer(native.rooms_heads()["0"])
                assert(
                    (p.Position - h.Position):Length() < 30,
                    "Returning actor resumed at its dormant position"
                )
                confirmedArrival = true
                report(
                    "ARRIVAL host="
                        .. positions["0"].index
                        .. " guest="
                        .. positions["1"].index
                        .. " tick="
                        .. t
                )
                assert(
                    p:HasCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
                        and p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
                        and p:GetNumCoins() == 19,
                    "Rejoin lost inventory"
                )
                report("REJOIN inventory restored tick=" .. t)
            end
        end,
        collect,
        function(bytes, t, ack)
            if restore(bytes, t, ack) == false then
                return false
            end
            if first > 0 and not confirmedArrival then
                local positions = native.rooms_positions()
                assert(
                    positions["0"].index == positions["1"].index,
                    "First live rejoin view missed the host's current room"
                )
                confirmedArrival = true
                report("CLIENT_ARRIVAL room=" .. positions["1"].index .. " tick=" .. t)
            end
        end,
        present,
        beginFloor
    )
end
