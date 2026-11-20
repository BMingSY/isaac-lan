-- Start a real encounter inside an open Devil Room, with the guest at its exit.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, phase = config.host, native.net_phases()
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local devil, boss = GridRooms.ROOM_DEVIL_IDX
local closed, reopened, escaped, direction, observedOpen
local function report(message)
    Isaac.DebugString("LAN_NETWORK DEVIL_COMBAT " .. message)
end
local function exitDoor()
    local room = Game():GetRoom()
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door then
            return door
        end
    end
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, ...)
        before(t, ...)
        if t == 35 then
            local rooms = Game():GetLevel():GetRooms()
            for i = 0, rooms.Size - 1 do
                local d = rooms:Get(i)
                if d.Data.Type == RoomType.ROOM_BOSS then
                    boss = d.SafeGridIndex
                    break
                end
            end
            assert(native.rooms_move(1, assert(boss), 0, -1))
        elseif t == 200 then
            assert(native.rooms_with_player(1, function()
                local room = Game():GetRoom()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Remove()
                    end
                end
                room:SetClear(true)
                room:TrySpawnDevilRoomDoor(false, true)
                local entrance
                for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                    local door = room:GetDoor(slot)
                    if door and door.TargetRoomType == RoomType.ROOM_DEVIL then
                        entrance = door
                    end
                end
                assert(entrance, "No native entrance to the Devil Room")
                direction = (entrance.Slot + 2) % 4
            end))
        elseif t == 220 then
            assert(native.rooms_move(1, devil, 0, direction))
        elseif t == 300 then
            assert(native.rooms_with_player(1, function()
                local room, door = Game():GetRoom(), assert(exitDoor(), "Devil Room has no exit")
                assert(
                    room:GetType() == RoomType.ROOM_DEVIL and door:IsOpen(),
                    "Missing open Devil Room"
                )
                local p = Isaac.GetPlayer(native.rooms_heads()["1"])
                p:SetMinDamageCooldown(10000)
                p.Position = door.Position + (room:GetCenterPos() - door.Position):Resized(45)
                Isaac.Spawn(EntityType.ENTITY_FALLEN, 1, 0, room:GetCenterPos(), Vector.Zero, nil)
                room:SetClear(false)
                report("spawned Krampus with open exit")
            end))
        elseif t == 390 or t == 440 then
            assert(native.rooms_positions()["1"].index == devil, "Guest passed the combat door")
            assert(native.rooms_with_player(1, function()
                local room, door = Game():GetRoom(), assert(exitDoor())
                report(
                    "during clear="
                        .. tostring(room:IsClear())
                        .. " open="
                        .. tostring(door:IsOpen())
                        .. " pose="
                        .. door:GetSprite():GetAnimation()
                )
                assert(
                    not room:IsClear() and not door:IsOpen(),
                    "Devil Room exit remained open in combat"
                )
                closed = true
            end))
        elseif t >= 460 and t <= 545 and t % 8 == 0 then
            assert(native.rooms_with_player(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) and not e:IsDead() then
                        e:TakeDamage(
                            100000,
                            DamageFlag.DAMAGE_IGNORE_ARMOR,
                            EntityRef(Isaac.GetPlayer(0)),
                            0
                        )
                    end
                end
                local door = exitDoor()
                if Game():GetRoom():IsClear() and door and door:IsOpen() then
                    reopened = true
                end
            end))
        end
    end, collect, restore, present, beginFloor)
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
    local s = frame()
    assert(s.phase ~= phase.failed, s.error)
    if s.phase == phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == phase.lobby and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "EFF834F4:0:0:0:0:0")
    end
    local buttons = 0
    if not host and s.prepared and native.rooms_ready() then
        local room = Game():GetRoom()
        if room:GetType() == RoomType.ROOM_DEVIL then
            local door = exitDoor()
            if door then
                if s.verified > 255 and s.verified < 290 and door:IsOpen() then
                    observedOpen = true
                end
                if
                    s.verified > 345
                    and s.verified < 450
                    and not room:IsClear()
                    and not door:IsOpen()
                then
                    closed = true
                end
                if s.verified > 470 and room:IsClear() and door:IsOpen() then
                    reopened = true
                end
                if s.verified > 365 and s.verified < 445 or s.verified >= 550 then
                    local p = Isaac.GetPlayer(native.rooms_heads()["1"])
                    local delta = door.Position - p.Position
                    buttons = math.abs(delta.X) > math.abs(delta.Y) and (delta.X > 0 and 8 or 4)
                        or (delta.Y > 0 and 2 or 1)
                end
            end
        elseif reopened and room:GetType() == RoomType.ROOM_BOSS then
            escaped = true
        end
    end
    native.test_gamepad(buttons)
    if s.verified >= 680 and not finished then
        assert(closed and reopened, "Missing observed combat closure or post-clear opening")
        if not host then
            assert(
                observedOpen and escaped,
                "Guest did not walk back out of the cleared Devil Room"
            )
        end
        finished = true
        report("PASS combat bars the exit and clearing restores traversal")
    end
    return s
end
return {
    done = function()
        return finished
    end,
}
