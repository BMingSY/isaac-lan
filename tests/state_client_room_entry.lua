-- Guest native room APIs must resolve the entrance of a resident room.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local stage, stageAt, previous, enteredAt, requestedAt, floorQueued
local phase, arrivals, checks = "out", 0, 0
local starting, right
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end, 1))
end
local function advance(s)
    if not s.prepared or not native.rooms_ready() or finished then
        return
    end
    local level, tick = Game():GetLevel(), s.verified
    if stage ~= level:GetStage() then
        stage, stageAt = level:GetStage(), tick
        phase, arrivals, previous, enteredAt, requestedAt = "out", 0, nil, nil, nil
        starting = level:GetStartingRoomIndex()
        actor(host and 0 or 1, function(_, room)
            right =
                level:GetRoomByIdx(assert(room:GetDoor(DoorSlot.RIGHT0)).TargetRoomIndex, 0).SafeGridIndex
        end)
    end
    assert(tick - stageAt < 1200, "Guest room request did not complete")
    local locations = native.rooms_positions()
    assert(locations["0"].index == starting, "Resident host was moved by a guest request")
    local own = locations["1"].index
    if previous ~= own then
        if previous == right and own == starting then
            enteredAt = tick
        end
        previous = own
    end
    if enteredAt and tick >= enteredAt + 10 then
        actor(1, function(p, room)
            local door = assert(room:GetDoor(DoorSlot.RIGHT0))
            assert(
                p.Position:Distance(door.Position + Vector(-40, 0)) < 5,
                "Guest return kept the source room's left-side coordinates"
            )
        end)
        checks, arrivals, enteredAt = checks + 1, arrivals + 1, nil
        phase, requestedAt = "out", tick
        Isaac.DebugString("LAN_NETWORK CLIENT_ROOM_ENTRY CHECK " .. checks)
    end
    if checks == 4 then
        finished = true
        Isaac.DebugString("LAN_NETWORK CLIENT_ROOM_ENTRY PASS resident entry across floors")
    elseif not host and arrivals < 2 and tick - (requestedAt or stageAt) >= 30 then
        if phase == "out" and own == starting then
            actor(1, function(p)
                if arrivals == 0 then
                    Game():StartRoomTransition(
                        right,
                        Direction.RIGHT,
                        RoomTransitionAnim.WALK,
                        p,
                        0
                    )
                else
                    Game():ChangeRoom(right, 0)
                end
            end)
            phase, requestedAt = "back", tick
        elseif phase == "back" and own == right then
            actor(1, function(p)
                if arrivals == 0 then
                    Game():StartRoomTransition(
                        starting,
                        Direction.LEFT,
                        RoomTransitionAnim.WALK,
                        p,
                        0
                    )
                else
                    Game():ChangeRoom(starting, 0)
                end
            end)
            phase, requestedAt = "wait", tick
        end
    elseif host and arrivals == 2 and stage == 1 and tick - requestedAt >= 30 then
        floorQueued = true
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
        _IsaacLanCommand("start", "XBS3S2KX:0:0:0:0:0")
    end
    native.test_gamepad(0)
    advance(s)
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if host then
            actor(1, function(p, room)
                p:SetMinDamageCooldown(10000)
                p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToNPC() then
                        e:Remove()
                    end
                end
                room:SetClear(true)
            end)
            if floorQueued then
                floorQueued = nil
                actor(0, function(p)
                    Game():StartStageTransition(false, RoomTransitionAnim.FADE, p)
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
