-- Native Glowing Hourglass restores the user's pre-entry whole-team save.
local native = assert(_IsaacLan)
local host, port
if _IsaacLanTest then
    host, port = _IsaacLanTest.host, _IsaacLanTest.port
else
    local f = assert(io.open("./lan-test-role.txt", "r"))
    host = f:read("*l") == "host"
    f:close()
    f = assert(io.open("./lan-test-menu-port.txt", "r"))
    port = f:read("*l")
    f:close()
end
local consoleRewind = _IsaacLanTest and _IsaacLanTest.consoleRewind
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local frame = _IsaacLanFrame
local renders, linked, chosen, finished = 0, false, false, false
local done = false
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = frame()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.verified >= 1400 and not finished then
        if host then
            assert(done, "Hourglass restoration did not finish")
        end
        finished = true
        report("PASS native full team hourglass")
    end
    return s
end
local expected, target, stage, second = false, nil, 0, nil
local function roster()
    local result = {}
    for i = 0, 1 do
        local p = Isaac.GetPlayer(i)
        local room = native.rooms_positions()[tostring(i)]
        result[i + 1] = {
            coins = p:GetNumCoins(),
            hearts = p:GetHearts(),
            index = room.index,
            dimension = room.dimension,
            x = p.Position.X,
            y = p.Position.Y,
        }
    end
    return result
end
local function assertRoster()
    for i, v in ipairs(expected) do
        local p = Isaac.GetPlayer(i - 1)
        local room = native.rooms_positions()[tostring(i - 1)]
        report(
            "RESTORED slot="
                .. i
                .. " coins="
                .. p:GetNumCoins()
                .. " hearts="
                .. p:GetHearts()
                .. " room="
                .. room.index
                .. " pos="
                .. p.Position.X
                .. ","
                .. p.Position.Y
        )
        assert(p:GetNumCoins() == v.coins, "Team coins were not rewound")
        assert(p:GetHearts() == v.hearts, "Team health was not rewound")
        assert(
            not p:HasCollectible(CollectibleType.COLLECTIBLE_SAD_ONION),
            "Team inventory was not rewound"
        )
        assert(
            room.index == v.index and room.dimension == v.dimension,
            "Team rooms were not rewound"
        )
        assert(p.Position:Distance(Vector(v.x, v.y)) < 2, "Team position was not rewound")
    end
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, b)
            before(t, n, b)
            if t == 25 and consoleRewind then
                local seed = Game():GetSeeds():GetStartSeed()
                Isaac.ExecuteCommand("rewind")
                assert(seed ~= 0 and Game():GetSeeds():GetStartSeed() == seed)
                report("CONSOLE_REWIND_WITHOUT_CHECKPOINT")
            end
            if t == 30 then
                for i = 0, 1 do
                    local p = Isaac.GetPlayer(i)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
                    p:SetMinDamageCooldown(10000)
                    p:AddCoins(i + 2)
                    p.Position = Vector(260 + i * 80, 230)
                end
                local level = Game():GetLevel()
                local rooms = level:GetRooms()
                for i = 0, rooms.Size - 1 do
                    local d = rooms:Get(i)
                    if
                        d.Data
                        and d.Data.Type == RoomType.ROOM_DEFAULT
                        and d.SafeGridIndex ~= level:GetCurrentRoomIndex()
                    then
                        if target then
                            second = d.SafeGridIndex
                            break
                        else
                            target = d.SafeGridIndex
                        end
                    end
                end
                assert(target and second, "Hourglass fixture needs separate rooms")
                assert(native.rooms_move(1, target, 0, -1))
            end
            if t == 80 then
                for i = 0, 1 do
                    assert(native.rooms_with_player(i, function()
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e.Type ~= 1 then
                                e:Remove()
                            end
                        end
                        Game():GetRoom():SetClear(true)
                    end))
                end
            end
            if t == 100 then
                expected = roster()
                assert(native.rooms_move(0, second, 0, -1))
                report("CHECKPOINT_CAPTURE")
            end
            if t == 170 then
                for i = 0, 1 do
                    local p = Isaac.GetPlayer(i)
                    p:AddCoins(7)
                    p:AddHearts(-2)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
                end
            end
            if t == 220 then
                if consoleRewind then
                    Isaac.ExecuteCommand("rewind")
                else
                    assert(native.rooms_with_player(0, function()
                        Isaac.GetPlayer(0)
                            :UseActiveItem(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, 0, -1)
                    end))
                end
                report(consoleRewind and "CONSOLE_REWIND" or "HOURGLASS_USE")
            end
            if t == 350 then
                assertRoster()
                stage = 1
                report("FULL_TEAM_REWOUND")
            end
            if t == 390 then
                expected = roster()
                assert(native.rooms_move(1, second, 0, -1))
            end
            if t == 430 then
                for i = 0, 1 do
                    local p = Isaac.GetPlayer(i)
                    p:AddCoins(9)
                    p:AddHearts(-2)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
                end
            end
            if t == 460 then
                assert(native.rooms_with_player(1, function()
                    Isaac.GetPlayer(1)
                        :UseActiveItem(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, 0, -1)
                end))
                report("GUEST_HOURGLASS_USE")
            end
            if t == 560 then
                assertRoster()
                report("GUEST_FULL_TEAM_REWOUND")
            end
            if t == 610 then
                expected = roster()
                Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
                report("NATIVE_NEXT_FLOOR")
            end
            if t == 1000 then
                assert(Game():GetLevel():GetStage() == 2, "Native second floor did not load")
                for i = 0, 1 do
                    local p = Isaac.GetPlayer(i)
                    p:AddCoins(11)
                    p:AddHearts(-2)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
                end
                Isaac.GetPlayer(0)
                    :UseActiveItem(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, 0, -1)
                report("CROSS_FLOOR_HOURGLASS_USE")
            end
            if t == 1230 then
                assert(Game():GetLevel():GetStage() == 1, "Hourglass did not rewind floor")
                assertRoster()
                done = true
                report("FLOOR_REWOUND")
            end
        end,
        collect,
        function(bytes, t, ack)
            if restore(bytes, t, ack) == false then
                return false
            end
            local v = _IsaacLanState.decode(bytes)
            for _, a in ipairs(v[9]) do
                local p = Isaac.GetPlayer(a[1])
                assert(p:GetNumCoins() == a[4][5][1], "Replica inventory did not restore")
            end
            return true
        end,
        present,
        beginFloor
    )
end
