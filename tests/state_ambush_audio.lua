-- A guest starts and finishes the native challenge, then the host visits it.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local selected, origin, startTick, doneTick, nextSearch = nil, nil, nil, nil, 20
local waves, hadEnemies, observations, lastTick = 0, false, 0, -1
local observedActive, observedDone, reentered = false, false, false
local fightMusic, clearedMusic = 0, 0
local function report(message)
    Isaac.DebugString("LAN_NETWORK AMBUSH_AUDIO " .. message)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end, 1))
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
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
    if
        status.prepared
        and native.api_info().ready == 1
        and status.verified ~= lastTick
        and status.verified % 30 == 0
    then
        lastTick = status.verified
        native.api_with_local_view(function()
            local room = Game():GetRoom()
            local audible, virtual = string.unpack(">I4I4", native.audio_state())
            local mode, target = string.unpack(">BI4", native.music_state())
            report(
                string.format(
                    "STATE tick=%d room=%d type=%d active=%s done=%s audible=%d virtual=%d mode=%d target=%d",
                    lastTick,
                    Game():GetLevel():GetCurrentRoomIndex(),
                    room:GetType(),
                    tostring(room:IsAmbushActive()),
                    tostring(room:IsAmbushDone()),
                    audible,
                    virtual,
                    mode,
                    target
                )
            )
            observations = observations + 1
            if room:GetType() == RoomType.ROOM_CHALLENGE then
                local fighting = false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    fighting = fighting or e:IsActiveEnemy(false) and not e:IsDead()
                end
                observedActive = observedActive or fighting
                observedDone = observedDone or room:IsAmbushDone()
                if fighting and audible == Music.MUSIC_CHALLENGE_FIGHT then
                    fightMusic = fightMusic + 1
                end
                if room:IsAmbushDone() and audible == Music.MUSIC_BOSS_OVER then
                    clearedMusic = clearedMusic + 1
                end
            elseif observedDone then
                reentered = true
            end
        end)
    end
    if host and doneTick and status.verified >= doneTick + 900 then
        assert(waves >= 2 and observations > 10)
        assert(clearedMusic > 0, "Host reentry did not play cleared challenge music")
        finished = true
        report("PASS challenge waves and cleared-room reentry")
    elseif not host and status.prepared and native.api_info().ready == 1 then
        local positions = native.rooms_positions()
        if
            observedActive
            and observedDone
            and reentered
            and positions["0"].index == positions["1"].index
        then
            -- The authority only reunites the team after the reentry observation.
            finished = true
            assert(fightMusic > 0, "Guest challenge fight music never played")
            assert(clearedMusic > 0, "Guest challenge outro lost its following track")
            report("PASS challenge room observed through reentry")
        end
    end
    native.test_gamepad(0)
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if not native.rooms_ready() then
            return
        end
        if not selected and t >= nextSearch then
            local level = Game():GetLevel()
            origin = level:GetCurrentRoomIndex()
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                if d.Data.Type == RoomType.ROOM_CHALLENGE then
                    selected = d.SafeGridIndex
                    break
                end
            end
            if selected then
                for slot = 0, 1 do
                    actor(slot, function(p)
                        p:SetMinDamageCooldown(10000)
                    end)
                end
                assert(native.rooms_move(1, selected, 0, 0))
                startTick = t
                report("SELECTED index=" .. selected .. " floor=" .. level:GetStage())
            else
                assert(level:GetStage() < 6, "No challenge room generated")
                Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
                nextSearch = t + 300
            end
        end
        if startTick and t == startTick + 30 then
            actor(1, function(p)
                local chest = Isaac.Spawn(
                    5,
                    PickupVariant.PICKUP_CHEST,
                    0,
                    Game():GetRoom():GetCenterPos(),
                    Vector.Zero,
                    nil
                ):ToPickup()
                chest.Wait = 0
                p.Position = chest.Position
            end)
        end
        if startTick and t >= startTick + 35 and not doneTick then
            actor(1, function()
                local enemies = {}
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) and not e:IsDead() then
                        enemies[#enemies + 1] = e
                    end
                end
                if #enemies > 0 and not hadEnemies then
                    waves = waves + 1
                end
                hadEnemies = #enemies > 0
                if t >= startTick + 180 and t % 90 == 0 then
                    for _, e in ipairs(enemies) do
                        e:Kill()
                    end
                end
                if Game():GetRoom():IsAmbushDone() and waves >= 2 then
                    doneTick = t
                    report("COMPLETE waves=" .. waves .. " tick=" .. t)
                end
            end)
            assert(doneTick or t < startTick + 900, "Challenge did not complete")
        end
        if doneTick then
            if t == doneTick + 480 then
                assert(native.rooms_move(1, origin, 0, -1))
                assert(native.rooms_move(0, selected, 0, -1))
            elseif t == doneTick + 720 then
                assert(native.rooms_move(1, selected, 0, -1))
            end
        end
    end, collect, restore, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
