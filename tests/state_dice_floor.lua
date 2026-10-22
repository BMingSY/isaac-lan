-- Use the seeded map's real dice room so its descriptor survives departure.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local requested, placed, departed, returned = false, false, false, false
local origin, diceRoom, enteredAt, activatedAt, returnedAt
local sawUsed, sawDarkness, leftRoom = false, false, false
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(native.rooms_heads()[tostring(slot)]), Game():GetRoom())
    end, 1))
end
local function inspect(t)
    local room = Game():GetRoom()
    if room:GetType() ~= RoomType.ROOM_DICE then
        leftRoom = leftRoom or sawUsed
        return
    end
    local used = room:IsSacrificeDone()
    sawUsed = sawUsed or used
    sawDarkness = sawDarkness or Game():GetDarknessModifier() > 0.1
    if leftRoom then
        assert(used, "Returning to a used dice floor lost its state")
        assert(Game():GetDarknessModifier() < 0.01, "Room re-entry replayed dice presentation")
        returnedAt = returnedAt or t
    end
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
        _IsaacLanCommand("start", "1XJTX49A:0:0:0:0:0")
    end
    local buttons = 0
    if status.prepared and native.api_info().ready == 1 and not status.recovering then
        if not host then
            actor(1, function(_, room)
                if room:GetType() == RoomType.ROOM_DICE and not room:IsSacrificeDone() then
                    buttons = 1
                end
            end)
        end
        if returnedAt and status.verified > returnedAt + 30 and not finished then
            assert(sawUsed and sawDarkness, "Dice activation or screen effects were not observed")
            finished = true
            Isaac.DebugString(
                "LAN_NETWORK DICE_FLOOR PASS activation presentation and used-room re-entry"
            )
        end
        assert(status.verified < 2000 or finished, "Dice-floor scenario timed out")
    end
    native.test_gamepad(buttons)
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, bytes)
            before(t, n, bytes)
            if t == 30 then
                for slot = 0, 1 do
                    actor(slot, function(p)
                        p:AddKeys(10)
                    end)
                end
                Game():GetLevel():SetStage(4, StageType.STAGETYPE_ORIGINAL)
                Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
            end
            if not native.rooms_ready() or Game():GetLevel():GetStage() ~= 4 then
                return
            end
            if not requested and t > 180 then
                origin = native.rooms_positions()["0"].index
                local rooms = Game():GetLevel():GetRooms()
                for i = 0, rooms.Size - 1 do
                    local d = rooms:Get(i)
                    if d.Data.Type == RoomType.ROOM_DICE then
                        diceRoom = d.SafeGridIndex
                        break
                    end
                end
                assert(diceRoom, "Seeded Caves II dice room was not generated")
                requested, enteredAt = true, t
                for slot = 0, 1 do
                    assert(native.rooms_move(slot, diceRoom, 0, -1))
                end
            elseif enteredAt and t > enteredAt + 15 and not placed then
                placed = true
                actor(0, function(p, room)
                    assert(room:GetType() == RoomType.ROOM_DICE, "Native dice-room entry failed")
                    p.Position, p.Velocity = Vector(100, 380), Vector.Zero
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if
                            e.Type == EntityType.ENTITY_EFFECT
                            and e.Variant == EffectVariant.DICE_FLOOR
                        then
                            e.SubType = 2
                            e:GetSprite():Play("3", true)
                        end
                    end
                end)
                actor(1, function(p, room)
                    p.Position, p.Velocity = room:GetCenterPos() + Vector(0, 80), Vector.Zero
                end)
            end
            actor(0, function(_, room)
                inspect(t)
                if placed and room:GetType() == RoomType.ROOM_DICE and room:IsSacrificeDone() then
                    activatedAt = activatedAt or t
                end
            end)
            if activatedAt and t > activatedAt + 90 and not departed then
                departed = true
                for slot = 0, 1 do
                    assert(native.rooms_move(slot, origin, 0, -1))
                end
            elseif departed and t > activatedAt + 150 and not returned then
                returned = true
                for slot = 0, 1 do
                    assert(native.rooms_move(slot, diceRoom, 0, -1))
                end
            end
        end,
        collect,
        function(bytes, t, ...)
            local applied = restore(bytes, t, ...)
            if applied ~= false then
                actor(1, function()
                    inspect(t)
                end)
            end
            return applied
        end,
        present,
        beginFloor
    )
end
return {
    done = function()
        return finished
    end,
}
