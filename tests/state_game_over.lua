-- Embedded by run_game_over.py. Reuse both processes across completed runs.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local role = host and "host" or "client"
local Phase = native.net_phases()
local owner = { Name = "LAN game over regression" }
local cases = {
    { source = "soul", survivor = 0, linger = 25000 },
    { source = "soul", survivor = 1 },
    { source = "berserk", survivor = 0 },
    { source = "berserk", survivor = 1 },
    { source = "tainted", survivor = 0 },
    { source = "tainted", survivor = 1 },
    { source = "normal", survivor = 1 },
    { source = "soul", survivor = 0, revive = true },
}
local current, case, linked, chosen, started, menuDone = 0, nil, false, false, false, false
local renders, startAt, endAt, exitAt, exitPulse, lastHeartbeat = 0, 0, nil, nil, nil, 0
local ends, snapshots, lastTick, complete = 0, 0, 0, false
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
local GAMEPAD_BACK = 0x2000
local function read(name)
    local file = io.open(gameOverCoordination .. "/" .. name, "r")
    if not file then
        return nil
    end
    local value = file:read("*a")
    file:close()
    return value
end
local function write(name, value)
    local file = assert(io.open(gameOverCoordination .. "/" .. name, "w"))
    file:write(value)
    file:close()
end
local function report(message)
    Isaac.DebugString("LAN_NETWORK GAME_OVER case=" .. current .. " " .. message)
end
local function player(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(player(slot))
    end))
end
local function hit(p)
    p:ResetDamageCooldown()
    p:TakeDamage(2, DamageFlag.DAMAGE_INVINCIBLE, EntityRef(nil), 0)
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_END, function(_, gameOver)
    assert(case and started and gameOver and ends == 0, "Unexpected or repeated game over")
    ends, endAt = ends + 1, Isaac.GetTime()
    report(
        "NATIVE_END tick=" .. lastTick .. " source=" .. case.source .. " survivor=" .. case.survivor
    )
    write("ended-" .. current .. "-" .. role, "done")
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    assert(ends == 1, "Exited before native game over")
    exitAt = Isaac.GetTime()
    report("NATIVE_EXIT")
end)
function _IsaacLanFrame()
    renders = renders + 1
    local status, now = baseFrame(), Isaac.GetTime()
    native.test_gamepad(0)
    if renders == 60 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local requested = tonumber(read("case.txt"))
    if requested and requested > #cases then
        if not complete then
            complete = true
            Isaac.DebugString("LAN_NETWORK PASS game over and native exit")
        end
        return status
    end
    if
        requested
        and requested ~= current
        and status.phase == Phase.idle
        and status.scene == 1
        and not status.prepared
    then
        current, case = requested, assert(cases[requested])
        linked, chosen, started, menuDone = false, false, false, false
        startAt = now + (current == 1 and 8000 or 2000)
        endAt, exitAt, exitPulse = nil, nil, nil
        ends, snapshots, lastTick = 0, 0, 0
        report("BEGIN source=" .. case.source .. " survivor=" .. case.survivor)
    end
    if not case then
        return status
    end
    if status.phase == Phase.failed then
        Isaac.DebugString("LAN_NETWORK FAILED " .. status.error)
        return status
    end
    if not linked and status.scene == 1 and now >= startAt + (host and 0 or 900) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
    end
    if status.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and not started
        and status.phase == Phase.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    elseif not host and status.prepared then
        started = true
    end
    if endAt and not exitAt then
        assert(ends == 1 and (host or snapshots > 50), "Incomplete native ending")
        local both = read("ended-" .. current .. "-host") and read("ended-" .. current .. "-client")
        if both and now - endAt > (case.linger or 3000) then
            exitPulse = exitPulse or renders
            if renders - exitPulse < 4 then
                native.test_gamepad(GAMEPAD_BACK)
            end
            assert(renders - exitPulse < 600, "Native game-over Exit did not respond")
        end
    end
    if
        exitAt
        and not menuDone
        and status.phase == Phase.idle
        and status.scene == 1
        and not status.prepared
        and now - exitAt > 2000
    then
        menuDone = true
        report("PASS native_exit=true snapshots=" .. snapshots)
        write("done-" .. current .. "-" .. role, "done")
    end
    if host and menuDone and read("done-" .. current .. "-client") then
        write("case.txt", tostring(current + 1))
    end
    if now - lastHeartbeat > 10000 then
        lastHeartbeat = now
        report("HEARTBEAT phase=" .. status.phase .. " tick=" .. lastTick .. " ends=" .. ends)
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        function()
            return string.rep("\0", 34)
        end,
        function(t, n, bytes)
            before(t, n, bytes)
            lastTick = t
            if t == 40 then
                for slot = 0, 1 do
                    actor(slot, function(p)
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e.Type ~= EntityType.ENTITY_PLAYER then
                                e:Remove()
                            end
                        end
                        Game():GetRoom():SetClear(true)
                        if slot == case.survivor and case.source == "tainted" then
                            p:ChangePlayerType(PlayerType.PLAYER_SAMSON_B)
                        end
                        p:AddHearts(1 - p:GetHearts())
                        if slot ~= case.survivor then
                            hit(p)
                        end
                    end)
                end
            elseif t == 160 then
                assert(player(1 - case.survivor):IsCoopGhost(), "Teammate must already be dead")
                actor(case.survivor, function(p)
                    if case.revive then
                        p:AddCollectible(CollectibleType.COLLECTIBLE_1UP, 0, false)
                    end
                    if case.source == "soul" then
                        p:UseCard(Card.CARD_SOUL_SAMSON, UseFlag.USE_NOANIM)
                    elseif case.source ~= "normal" then
                        p:UseActiveItem(CollectibleType.COLLECTIBLE_BERSERK, UseFlag.USE_NOANIM)
                    end
                    if case.source ~= "normal" then
                        assert(
                            p:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_BERSERK)
                        )
                    end
                end)
            elseif t == 180 then
                actor(case.survivor, function(p)
                    hit(p)
                    assert(p:GetHearts() == 0, "Lethal hit did not remove the last heart")
                    if case.source ~= "normal" then
                        assert(not p:IsDead() and ends == 0, "Berserk deferred death ended early")
                    end
                end)
                report("LETHAL_HIT")
            elseif t == 720 and case.revive then
                actor(case.survivor, function(p)
                    assert(
                        ends == 0 and not p:IsDead() and not p:IsCoopGhost() and p:GetHearts() > 0,
                        "Extra life was replaced by game over"
                    )
                    report("REVIVED_WITHOUT_GAME_OVER")
                    p:AddHearts(1 - p:GetHearts())
                    hit(p)
                end)
            end
            assert(t < 1200, "Last survivor's death did not reach native game over")
        end,
        collect,
        function(bytes, tick, ack, between, stable)
            lastTick, snapshots = tick, snapshots + 1
            return restore(bytes, tick, ack, between, stable)
        end,
        present,
        beginFloor
    )
end
