-- The guest's controlled ring must travel with its owner and survive reunions.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local ringSubtype = 1
local checks, secondFloorAt, cleanupAt = {}, nil, nil
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end, 1))
end
local function report(message)
    Isaac.DebugString("LAN_NETWORK LUDOVICO_ROOMS " .. message)
end
local function inspect(t)
    local stage = Game():GetLevel():GetStage()
    local checkpoint
    if stage == LevelStage.STAGE1_1 then
        if t >= 80 and t <= 110 then
            checkpoint = "initial"
        elseif t >= 180 and t <= 210 then
            checkpoint = "new-room"
        elseif t >= 280 and t <= 310 then
            checkpoint = "resident-joins-owner"
        elseif t >= 400 and t <= 430 then
            checkpoint = "loaded-room"
        elseif t >= 520 and t <= 550 then
            checkpoint = "owner-joins-resident"
        elseif t >= 640 and t <= 670 then
            checkpoint = "resident-leaves-owner"
        end
    elseif stage == LevelStage.STAGE1_2 then
        secondFloorAt = secondFloorAt or t
        if t >= secondFloorAt + 60 and not cleanupAt then
            checkpoint = "floor"
        elseif cleanupAt and t >= cleanupAt + 60 then
            checkpoint = "cleanup"
        end
    end
    if not checkpoint then
        return
    end
    local locations = native.rooms_positions()
    local sameRoom = locations["0"].index == locations["1"].index
        and locations["0"].dimension == locations["1"].dimension
    local separated = checkpoint == "new-room"
        or checkpoint == "loaded-room"
        or checkpoint == "resident-leaves-owner"
        or checkpoint == "cleanup"
    assert(sameRoom ~= separated, "Room separation/reunion did not complete: " .. checkpoint)
    for slot = host and 0 or 1, 1 do
        actor(slot, function(_, room)
            local count = 0
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == EntityType.ENTITY_LASER and e.SubType == ringSubtype then
                    count = count + 1
                    local parent = assert(e.Parent, "Controlled ring lost its owner")
                    assert(
                        parent:ToPlayer() and parent:ToPlayer().ControllerIndex == 2,
                        "Controlled ring belongs to the wrong player"
                    )
                    assert(e.CollisionDamage > 0, "Controlled ring lost its damage")
                    assert(
                        e:GetData()[host and "__isaac_lan_entity" or "__isaac_lan_replica"],
                        "Controlled ring has no synchronized identity"
                    )
                    assert(
                        room:IsPositionInRoom(e.Position, 0),
                        "Controlled ring is outside its room"
                    )
                end
            end
            local expected = checkpoint ~= "cleanup" and (slot == 1 or sameRoom) and 1 or 0
            assert(count == expected, checkpoint .. " ring count=" .. count .. " slot=" .. slot)
        end)
    end
    if not checks[checkpoint] then
        checks[checkpoint] = true
        report("CHECK " .. checkpoint)
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "1XJTX49A:0:0:0:0:0")
    end
    native.test_gamepad(0)
    if checks.cleanup and not finished then
        for _, checkpoint in ipairs({
            "initial",
            "new-room",
            "resident-joins-owner",
            "loaded-room",
            "owner-joins-resident",
            "resident-leaves-owner",
            "floor",
        }) do
            assert(checks[checkpoint], "Missing controlled-ring check: " .. checkpoint)
        end
        finished = true
        report("PASS split/reunion/repeated-entry/floor/cleanup")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        for slot = 0, 1 do
            actor(slot, function(p, room)
                p:SetMinDamageCooldown(10000)
                -- A non-door fixture transfer can land at the return door.
                -- Keep neutral actors inside after entry without moving lasers.
                if
                    t == 130
                    or t == 250
                    or t == 370
                    or t == 490
                    or t == 610
                    or cleanupAt and t == cleanupAt + 10
                then
                    p.Position, p.Velocity = room:GetCenterPos(), Vector.Zero
                end
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Remove()
                    end
                end
                room:SetClear(true)
            end)
        end
        if Game():GetLevel():GetStage() == LevelStage.STAGE1_1 then
            if t == 30 then
                actor(1, function(p)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
                end)
            elseif t == 120 or t == 480 then
                assert(native.rooms_move(1, 71, 0, -1))
            elseif t == 240 then
                assert(native.rooms_move(0, 71, 0, -1))
            elseif t == 360 then
                assert(native.rooms_move(1, 84, 0, -1))
            elseif t == 600 then
                assert(native.rooms_move(0, 84, 0, -1))
            elseif t == 720 then
                actor(0, function(p)
                    Game():StartStageTransition(false, RoomTransitionAnim.FADE, p)
                end)
            end
        elseif checks.floor and not cleanupAt and t >= secondFloorAt + 150 then
            cleanupAt = t
            local destination
            actor(1, function(p)
                p:RemoveCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE)
                assert(not p:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE))
                -- Existing attacks can outlive a removed item until room entry.
                for door = 0, 7 do
                    local exit = Game():GetRoom():GetDoor(door)
                    if exit then
                        destination =
                            Game():GetLevel():GetRoomByIdx(exit.TargetRoomIndex, 0).SafeGridIndex
                        break
                    end
                end
            end)
            assert(native.rooms_move(1, assert(destination, "Missing cleanup room"), 0, -1))
        end
    end, function(slot, t)
        if slot == 1 then
            inspect(t)
        end
        return collect(slot, t)
    end, function(bytes, t, ...)
        local applied = restore(bytes, t, ...)
        if applied ~= false then
            if Game():GetLevel():GetStage() == LevelStage.STAGE1_2 and checks.floor then
                local locations = native.rooms_positions()
                if locations["0"].index ~= locations["1"].index then
                    cleanupAt = cleanupAt or t
                end
            end
            inspect(t)
        end
        return applied
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
