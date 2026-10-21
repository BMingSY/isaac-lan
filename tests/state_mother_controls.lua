-- Enter Mother through Corpse II's native hole, then use ordinary guest input.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local entrant = _IsaacLanTest.motherEntrant or 0
local together = _IsaacLanTest.motherTogether
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local prepared, entered, arenaAt, phaseTwoAt, stagedHole
local movement, movementStart = {}, {}
local minimumFreeTravel = 200
local lastObservation = -1
local staleCooldown, recoveredCooldown = false, false
local moveLeft, moveRight, shootUp = 0x0004, 0x0008, 0x8000
local function report(message)
    Isaac.DebugString("LAN_NETWORK MOTHER_CONTROLS " .. message)
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
        _IsaacLanCommand("choose", host and "0:1" or "2:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "MBHM9FSV:0:0:2:0:0")
    end
    local buttons = 0
    if status.prepared and native.api_info().ready == 1 then
        if together and not arenaAt and status.verified > 230 then
            native.api_with_local_view(function()
                if
                    Game():GetLevel():GetStage() == 8
                    and Game():GetRoom():GetType() == RoomType.ROOM_BOSS
                then
                    buttons = 1
                end
            end)
        end
        local location = native.rooms_positions()["1"]
        if location and location.index == -10 then
            arenaAt = arenaAt or status.verified
            local age = status.verified - arenaAt
            if not host and age >= 180 then
                buttons = (math.floor(age / 60) % 2 == 0 and moveLeft or moveRight) | shootUp
            end
            if not host and age >= 420 and age < 450 then
                native.chat_ui_open(true)
            elseif not host and age >= 450 and age < 480 then
                native.chat_ui_open(false)
            end
            if not host and age >= 300 and not staleCooldown then
                staleCooldown = true
                actor(1, function(p)
                    p.ControlsCooldown = 90
                end)
                report("STALE_COOLDOWN injected=90")
            elseif not host and age >= 330 and not recoveredCooldown then
                actor(1, function(p)
                    assert(p.ControlsCooldown == 0, "Replica retained a stale control cooldown")
                end)
                recoveredCooldown = true
                report("STALE_COOLDOWN recovered=0")
            end
            if age >= 180 then
                actor(1, function(p)
                    local interval = math.floor(age / 60)
                    movementStart[interval] = movementStart[interval] or p.Position.X
                    local direction = interval % 2 == 0 and -1 or 1
                    movement[interval] = math.max(
                        movement[interval] or 0,
                        (p.Position.X - movementStart[interval]) * direction
                    )
                end)
            end
            if age % 30 == 0 and age ~= lastObservation then
                lastObservation = age
                actor(1, function(p)
                    report(
                        string.format(
                            "STATE tick=%d age=%d enabled=%s controls=%s finished=%s body=%s x=%.2f y=%.2f vx=%.2f cooldown=%d",
                            status.verified,
                            age,
                            tostring(p.ControlsEnabled),
                            tostring(p:AreControlsEnabled()),
                            tostring(p:IsExtraAnimationFinished()),
                            p:GetSprite():GetAnimation(),
                            p.Position.X,
                            p.Position.Y,
                            p.Velocity.X,
                            p.ControlsCooldown
                        )
                    )
                end)
            end
            if age >= 750 and not finished then
                finished = true
                if host then
                    assert(phaseTwoAt, "Mother phase two was not exercised")
                else
                    assert(recoveredCooldown, "Stale control cooldown was not exercised")
                end
                -- The first interval starts at the arbitrary landing point;
                -- subsequent sweeps start at opposite edges of the arena.
                for _, interval in ipairs({ 4, 5, 10, 11 }) do
                    assert(
                        movement[interval] and movement[interval] > minimumFreeTravel,
                        "Guest could not cross the Mother arena in interval "
                            .. interval
                            .. ": travel="
                            .. tostring(movement[interval])
                    )
                end
                report("PASS native hole, gathering, chat close and phase two movement")
            end
        end
    end
    assert(status.verified < 1800 or finished, "Mother entry or control trial timed out")
    native.test_gamepad(buttons)
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if not native.rooms_ready() then
            return
        end
        if t >= 30 and not prepared then
            prepared = true
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:SetMinDamageCooldown(10000)
                    p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                end)
            end
            Game():GetLevel():SetStage(8, StageType.STAGETYPE_REPENTANCE)
            Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
        elseif t > 180 and Game():GetLevel():GetStage() == 8 and not entered then
            local rooms = Game():GetLevel():GetRooms()
            for i = 0, rooms.Size - 1 do
                local descriptor = rooms:Get(i)
                if descriptor.Data.Type == RoomType.ROOM_BOSS and descriptor.SafeGridIndex >= 0 then
                    assert(native.rooms_move(entrant, descriptor.SafeGridIndex, 0, -1))
                    if together then
                        assert(native.rooms_move(1 - entrant, descriptor.SafeGridIndex, 0, -1))
                    end
                    entered = t
                    report("HOLE_ROOM index=" .. descriptor.SafeGridIndex)
                    break
                end
            end
            assert(entered, "Corpse II hole room is missing")
        end
        if entered and not arenaAt and t > entered + 45 then
            if together then
                if not stagedHole then
                    stagedHole = true
                    for slot = 0, 1 do
                        actor(slot, function(p)
                            -- One actor is already being drawn into the hole
                            -- when the other starts the room transfer.
                            p.Position = Game():GetRoom():GetCenterPos()
                                + (slot == entrant and Vector(-20, 70) or Vector(55, -15))
                            p.Velocity = Vector.Zero
                        end)
                    end
                end
            else
                actor(entrant, function(p)
                    p.Position, p.Velocity = Game():GetRoom():GetCenterPos(), Vector(1, 0)
                end)
            end
        end
        if arenaAt then
            local age = t - arenaAt
            if age >= 360 then
                actor(0, function(p)
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if
                            e.Type == EntityType.ENTITY_MOTHER
                            and e.Variant == 0
                            and not phaseTwoAt
                        then
                            e:TakeDamage(100000, 0, EntityRef(p), 0)
                        elseif e.Type == EntityType.ENTITY_MOTHER and e.Variant == 10 then
                            phaseTwoAt = phaseTwoAt or t
                        end
                    end
                end)
            end
        end
    end, collect, restore, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
