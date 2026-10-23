local native = assert(_IsaacLan)
local Phase = native.net_phases()
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame = _IsaacLanFrame
local initialized, renders, joined, chosen, started = Isaac.GetTime(), 0, false, false, false
local run, startSeed, endFrame, readyFrame, seenVote = 0, nil, nil, nil, false
local lastTick, exits = 0, 0
local complete = false
local GAMEPAD_CONFIRM, GAMEPAD_RESTART = 0x1000, 0x3c0
local function report(text)
    Isaac.DebugString("LAN_NETWORK RESTART " .. text)
end
local function player(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
Isaac.AddCallback({}, ModCallbacks.MC_POST_GAME_STARTED, function()
    run = run + 1
    local seed = Game():GetSeeds():GetStartSeedString()
    assert(seed ~= startSeed, "Restart reused the old seed")
    startSeed, endFrame, readyFrame, seenVote = seed, nil, nil, false
    report("START run=" .. run .. " seed=" .. seed)
end)
Isaac.AddCallback({}, ModCallbacks.MC_POST_GAME_END, function(_, over)
    assert(over, "Expected a death result")
    endFrame = renders
    report("GAME_OVER run=" .. run)
end)
Isaac.AddCallback({}, ModCallbacks.MC_PRE_GAME_EXIT, function()
    exits = exits + 1
    report("EXIT run=" .. run)
end)
function _IsaacLanFrame()
    renders = renders + 1
    if renders == 1 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    if complete then
        native.test_gamepad(0)
        return s
    end
    if not joined and Isaac.GetTime() - initialized > 15000 then
        joined = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
    end
    if s.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and not started
        and s.phase == Phase.lobby
        and s.players == 2
        and s.ready0 == 1
        and s.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    assert(s.phase ~= Phase.failed, s.error)
    local buttons = 0
    if s.prepared and run > 0 then
        readyFrame = readyFrame or renders
        assert(
            s.phase == Phase.running and s.players == 2 and s.connected == 3,
            "Room lost on restart"
        )
        if (s.restartVotes or 0) ~= 0 and not seenVote then
            seenVote = true
            report("VOTE run=" .. run .. " mask=" .. s.restartVotes)
        end
        local age = renders - (endFrame or readyFrame)
        local death = run == 1 or run == 3
        local first = (run == 1 or run == 4 or run == 5) == host
        local trigger = first and 180 or 420
        if
            (death or run == 4 or run == 6)
            and (not death or endFrame)
            and age >= trigger
            and age < trigger + (death and 4 or 90)
        then
            buttons = death and GAMEPAD_CONFIRM or GAMEPAD_RESTART
        end
        if (run == 2 or run == 5) and age == trigger then
            report("KEYBOARD_READY run=" .. run)
        end
        if run <= 6 and age == 400 and (not death or endFrame) then
            assert(seenVote, "First player's approval did not display a vote")
            report("INCOMPLETE_STILL_RUNNING run=" .. run)
        end
        if run == 7 and renders - readyFrame > 180 then
            assert(
                exits == 6 and not endFrame and (s.restartVotes or 0) == 0,
                "Stale restart state"
            )
            report("PASS six unanimous restarts, same room and native input")
            complete = true
        end
        if renders % 120 == 0 then
            report(
                "FRAME run="
                    .. run
                    .. " age="
                    .. age
                    .. " tick="
                    .. lastTick
                    .. " votes="
                    .. (s.restartVotes or 0)
            )
        end
    end
    native.test_gamepad(buttons)
    return s
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        function()
            return string.rep("\0", 43)
        end,
        function(t, n, b)
            before(t, n, b)
            lastTick = t
            if t == 20 then
                for slot = 0, 1 do
                    assert(native.rooms_with_player(slot, function()
                        local p = player(slot)
                        assert(not p:HasCollectible(333), "Old inventory survived a fresh restart")
                        assert(
                            p:GetPlayerType() == PlayerType.PLAYER_ISAAC,
                            "Restart changed character selection"
                        )
                        p:AddCollectible(333)
                        for _, entity in ipairs(Isaac.GetRoomEntities()) do
                            if entity.Type ~= EntityType.ENTITY_PLAYER then
                                entity:Remove()
                            end
                        end
                        Game():GetRoom():SetClear(true)
                    end))
                end
                report("FRESH_ROSTER run=" .. run)
            end
            if (run == 1 or run == 3) and (t == 60 or t == 150) then
                local slot = t == 60 and 1 or 0
                assert(native.rooms_with_player(slot, function()
                    local p = player(slot)
                    p:AddSoulHearts(-p:GetSoulHearts())
                    p:AddHearts(1 - p:GetHearts())
                    p:ResetDamageCooldown()
                    p:TakeDamage(2, DamageFlag.DAMAGE_INVINCIBLE, EntityRef(nil), 0)
                end))
            end
        end,
        collect,
        function(bytes, t, ack, between, stable)
            lastTick = t
            return restore(bytes, t, ack, between, stable)
        end,
        present,
        beginFloor
    )
end
