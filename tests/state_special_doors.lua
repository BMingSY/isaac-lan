local native = assert(_IsaacLan)
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(s)
    Isaac.DebugString("LAN_NETWORK " .. s)
end
local original = _IsaacLanFrame
local renders, linked, chosen, done = 0, false, false, false
local boss, origin, entered, seen
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = original()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "7:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "LBCD0G4M:0:7:7:7:7")
    end
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    local buttons = 0
    if not host and s.prepared and s.verified >= 100 and s.verified < 500 then
        local room = Game():GetRoom()
        local p = Isaac.GetPlayer(native.rooms_heads()["1"])
        if room:GetType() == RoomType.ROOM_BOSS then
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door.TargetRoomType == RoomType.ROOM_DEVIL then
                    seen = true
                    local delta = door.Position - p.Position
                    if math.abs(delta.X) > 8 then
                        buttons = delta.X > 0 and 8 or 4
                    else
                        buttons = delta.Y > 0 and 2 or 1
                    end
                end
            end
        elseif room:GetType() == RoomType.ROOM_DEVIL then
            entered = true
        end
    end
    native.test_gamepad(buttons)
    if s.verified >= 510 and not done then
        if not host then
            assert(seen, "Native Devil door slot was never registered")
            assert(entered, "Raw input never entered native Devil door")
        end
        assert(Game():GetLevel():GetStage() == 1, "Door traversal unexpectedly changed floor")
        done = true
        report("PASS special door slots and raw-input Devil entry")
    end
    return s
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    origin = Game():GetLevel():GetCurrentRoomIndex()
    for i = 0, Game():GetLevel():GetRooms().Size - 1 do
        local d = Game():GetLevel():GetRooms():Get(i)
        if d.Data.Type == RoomType.ROOM_BOSS then
            boss = d.SafeGridIndex
        end
    end
    assert(boss)
    return gate(
        capture,
        function(t, n, b)
            before(t, n, b)
            if t == 30 then
                assert(native.rooms_move(1, boss, 0, -1))
            end
            if t == 50 then
                assert(native.rooms_with_player(1, function()
                    local room = Game():GetRoom()
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsActiveEnemy(false) then
                            e:Remove()
                        end
                    end
                    room:SetClear(true)
                    assert(
                        room:TrySpawnDevilRoomDoor(false, true),
                        "Native Devil door fixture failed"
                    )
                    for slot = 0, 7 do
                        local door = room:GetDoor(slot)
                        if door then
                            report(
                                "HOST door slot="
                                    .. slot
                                    .. " target="
                                    .. door.TargetRoomIndex
                                    .. " type="
                                    .. door.TargetRoomType
                            )
                        end
                    end
                end))
            end
            if t == 90 then
                report("VISUAL_READY")
            end
        end,
        collect,
        function(bytes, t, ack)
            if restore(bytes, t, ack) == false then
                return false
            end
            if t >= 70 and t < 90 then
                local value = _IsaacLanState.decode(bytes)
                for _, grid in ipairs(value[11][4]) do
                    if grid[9] and grid[9][4] == RoomType.ROOM_DEVIL then
                        local door = Game():GetRoom():GetDoor(grid[9][1])
                        assert(
                            door and door.TargetRoomIndex == grid[9][2],
                            "Snapshot grid door is absent from native door slots: slot="
                                .. grid[9][1]
                                .. " expected="
                                .. grid[9][2]
                                .. " actual="
                                .. tostring(door and door.TargetRoomIndex)
                                .. " room="
                                .. Game():GetLevel():GetCurrentRoomIndex()
                        )
                    end
                end
            end
        end,
        present,
        beginFloor
    )
end
