-- Measure two real rooms together, then check the same channels with the party split.
local native, config = _IsaacLan, _IsaacLanTest
local host, frame, gate = config.host, _IsaacLanFrame, native.net_gate
local phases, water = native.net_phases(), SoundEffect.SOUND_WATER_FLOW_LOOP
local downpour, dross = StageType.STAGETYPE_REPENTANCE, StageType.STAGETYPE_REPENTANCE_B
local floors = { [downpour] = {}, [dross] = {} }
local arrangements = { { "dry", "wet" }, { "wet", "wet" }, { "wet", "dry" }, { "dry", "dry" } }
local renders, linked, chosen, started, requested, finished = 0, false, false, false, false, false
local floorAt, nextMove, hostFloor = 0, 1, nil
local checked, observed, since, baseline = {}, nil, 0, nil
local probes, probe = {}, 1
local referenceRoom, referenceSince
local fire = SoundEffect.SOUND_FIRE_BURN
local fireStage = LevelStage.STAGE2_1
local fireSteps = {
    { true, true, false }, -- Both in the unlit starting room.
    { false, true, true }, -- Guest alone by the fire.
    { true, true, true }, -- Host joins the guest.
    { true, false, true }, -- Guest leaves; host stays by the fire.
    { true, true, true }, -- Guest comes back while it is still lit.
    { true, true, false }, -- Both see the host extinguish it.
    { true, false, false }, -- Guest leaves the ashes.
    { true, true, false }, -- Guest returns to the extinguished fire.
}
local firePeriod, extinguishStep = 80, 6
local fireStart, hearth, quiet, flame
local fireChecks, fireSince, fireBaseline, lastFireStarts = 0, nil, nil, nil

local function changeFloor(stage, kind)
    assert(native.rooms_with_player(0, function()
        Game():GetLevel():SetStage(stage, kind)
        Game():StartStageTransition(true, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
    end))
end

local function observeFire(tick, level)
    local index = fireChecks + 1
    local step = fireSteps[index]
    if not step then
        return
    end
    local origin, positions = level:GetStartingRoomIndex(), native.rooms_positions()
    local atFire = level:GetCurrentRoomIndex() == origin
    -- Each client may finish the native floor transition on a different frame.
    -- Observe the actual party and replicated fireplace before checking its channel.
    local ready = atFire == step[host and 1 or 2]
        and (positions["0"].index == origin) == step[1]
        and (positions["1"].index == origin) == step[2]
    if ready and atFire then
        local lit, ashes = false, false
        for _, source in ipairs(Isaac.FindByType(EntityType.ENTITY_FIREPLACE)) do
            lit = lit or source.HitPoints > 1
            ashes = ashes or source.HitPoints <= 1
        end
        ready = lit == step[3] and (index < extinguishStep or ashes)
    end
    if not ready then
        fireSince, fireBaseline = nil, nil
        return
    end
    fireSince = fireSince or tick
    if tick - fireSince < 12 then
        return
    end
    local playing = SFXManager():IsPlaying(fire)
    assert(playing == (atFire and step[3]), "Wrong fire channel in arrangement " .. index)
    local starts = string.unpack(">I4", native.audio_state(fire), 21)
    fireBaseline = fireBaseline or starts
    assert(starts == fireBaseline, "Fire crackle restarted in arrangement " .. index)
    if tick - fireSince < 28 then
        return
    end
    local previous = fireSteps[index - 1]
    if previous and previous[host and 1 or 2] and previous[3] and atFire and step[3] then
        assert(starts == lastFireStarts, "Another player crossing the door restarted the fire")
    end
    Isaac.DebugString(
        "LAN_NETWORK SIDE room-ambience fire="
            .. index
            .. " playing="
            .. tostring(playing)
            .. " starts="
            .. starts
    )
    fireChecks, lastFireStarts, fireSince, fireBaseline = index, starts, nil, nil
    if index == #fireSteps then
        for kind in pairs(floors) do
            for i = 1, #arrangements do
                assert(checked[kind .. ":" .. i], "Missing water arrangement " .. kind .. ":" .. i)
            end
        end
        finished = true
    end
end

local function observe(tick)
    local level = Game():GetLevel()
    if level:GetStage() == fireStage then
        observeFire(tick, level)
        return
    end
    local kind = level:GetStageType()
    local floor = floors[kind]
    if not floor then
        return
    end
    local positions = native.rooms_positions()
    if not floor.dry or not floor.wet then
        local index = positions["0"].index
        if positions["1"].index == index then
            local key = kind .. ":" .. index
            if referenceRoom ~= key then
                referenceRoom, referenceSince = key, tick
            elseif tick - referenceSince >= 24 then
                local name = SFXManager():IsPlaying(water) and "wet" or "dry"
                if not floor[name] then
                    floor[name] = index
                    Isaac.DebugString(
                        "LAN_NETWORK SIDE room-ambience reference stage="
                            .. kind
                            .. " "
                            .. name
                            .. "="
                            .. index
                    )
                end
            end
        end
        return
    end
    for i, pair in ipairs(arrangements) do
        if positions["0"].index == floor[pair[1]] and positions["1"].index == floor[pair[2]] then
            local key = kind .. ":" .. i
            if observed ~= key then
                observed, since, baseline = key, tick, nil
            elseif tick - since >= 12 then
                local wet = pair[host and 1 or 2] == "wet"
                local context = "stage=" .. kind .. " host=" .. pair[1] .. " guest=" .. pair[2]
                assert(SFXManager():IsPlaying(water) == wet, "Incorrect water channel: " .. context)
                local starts = string.unpack(">I4", native.audio_state(water), 21)
                if baseline then
                    assert(starts == baseline, "Steady water restarted: " .. context)
                else
                    baseline = starts
                end
                if tick - since >= 32 and not checked[key] then
                    checked[key] = true
                    Isaac.DebugString(
                        "LAN_NETWORK SIDE room-ambience " .. context .. " starts=" .. starts
                    )
                end
            end
            return
        end
    end
    observed = nil
end

function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= phases.failed, status.error)
    if status.phase == phases.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and not started
        and status.phase == phases.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if status.prepared and native.api_info().ready == 1 and native.rooms_ready() then
        assert(native.api_with_local_view(function()
            observe(status.verified)
        end))
        assert(
            status.verified < 2400,
            "Room ambience arrangements did not finish, fire=" .. fireChecks
        )
    end
    return status
end

local function moveRooms(hostRoom, guestRoom)
    local positions = native.rooms_positions()
    for slot, target in ipairs({ hostRoom, guestRoom }) do
        if positions[tostring(slot - 1)].index ~= target then
            assert(native.rooms_move(slot - 1, target, 0, -1))
        end
    end
end

local function driveFire(t, level)
    if not fireStart then
        fireStart, hearth = t, level:GetStartingRoomIndex()
        local list = level:GetRooms()
        for i = 0, list.Size - 1 do
            local room = list:Get(i)
            if
                room.Data
                and room.Data.Type == RoomType.ROOM_DEFAULT
                and room.SafeGridIndex ~= hearth
            then
                quiet = room.SafeGridIndex
                break
            end
        end
        assert(quiet, "Missing second fire room")
    end
    local elapsed = t - fireStart
    local index = math.floor(elapsed / firePeriod) + 1
    local age, step = elapsed % firePeriod, fireSteps[index]
    if not step then
        return
    end
    if age == 0 then
        moveRooms(step[1] and hearth or quiet, step[2] and hearth or quiet)
    elseif age == 4 then
        for slot = 0, 1 do
            assert(native.rooms_with_player(slot, function()
                local p = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
                p:SetMinDamageCooldown(10000)
                p.Position, p.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
                for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_FIREPLACE)) do
                    if not flame or not flame.Ref or GetPtrHash(e) ~= GetPtrHash(flame.Ref) then
                        e:Remove()
                    end
                end
                if index == 2 and slot == 1 then
                    flame = EntityPtr(
                        Isaac.Spawn(
                            EntityType.ENTITY_FIREPLACE,
                            0,
                            0,
                            p.Position + Vector(48, 0),
                            Vector.Zero,
                            nil
                        )
                    )
                end
            end))
        end
    elseif index == extinguishStep and age >= 5 and age < 44 and age % 3 == 0 then
        assert(native.rooms_with_player(0, function()
            local source = assert(flame and flame.Ref, "Missing lit fireplace")
            if source.HitPoints > 1 then
                local p = Isaac.GetPlayer(assert(native.rooms_heads()["0"]))
                local tear = p:FireTear(
                    p.Position,
                    (source.Position - p.Position):Resized(14),
                    false,
                    true,
                    false,
                    p
                )
                tear.CollisionDamage = 100
            end
        end))
    end
end

native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if not native.rooms_ready() then
            return
        end
        if not requested and t >= 30 then
            requested = true
            changeFloor(LevelStage.STAGE1_1, downpour)
            return
        end
        local level = Game():GetLevel()
        if level:GetStage() == fireStage then
            driveFire(t, level)
            return
        end
        local kind = level:GetStageType()
        local floor = floors[kind]
        if not floor then
            return
        end
        if hostFloor ~= kind then
            hostFloor, floorAt, nextMove = kind, t, 1
            probes, probe = {}, 1
            local list = level:GetRooms()
            for i = 0, list.Size - 1 do
                local room = list:Get(i)
                if
                    room.Data
                    and room.Data.Type == RoomType.ROOM_DEFAULT
                    and room.SafeGridIndex ~= level:GetStartingRoomIndex()
                then
                    probes[#probes + 1] = room.SafeGridIndex
                end
            end
            for slot = 0, 1 do
                assert(native.rooms_with_player(slot, function()
                    Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
                        :SetMinDamageCooldown(10000)
                end))
            end
        end
        if not floor.dry or not floor.wet then
            if t - floorAt >= 65 then
                local index = assert(probes[probe], "Missing dry/wet reference on floor " .. kind)
                moveRooms(index, index)
                probe, floorAt = probe + 1, t
            end
            return
        end
        if t - floorAt >= nextMove * 65 then
            local pair = arrangements[nextMove]
            if pair then
                moveRooms(floor[pair[1]], floor[pair[2]])
            elseif kind == downpour then
                changeFloor(LevelStage.STAGE1_2, dross)
            else
                changeFloor(fireStage, StageType.STAGETYPE_ORIGINAL)
            end
            nextMove = nextMove + 1
        end
    end, collect, restore, present, beginFloor)
end

return {
    done = function()
        return finished
    end,
}
