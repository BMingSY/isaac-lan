-- One LAN game: host/guest Forget Me Now, native five-pip floor, guest R Key.
local native = assert(_IsaacLan)
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local frame = _IsaacLanFrame
local renders, linked, chosen, finished = 0, false, false, false
local checked = false
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
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    native.test_gamepad(0)
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.verified >= 1400 and not finished then
        if host then
            assert(checked, "Native floor-reset checks did not finish")
        end
        finished = true
        report("PASS native Forget Me Now five-pip and R Key")
    end
    return s
end
local expected, seed, dice
local function floorSeed()
    return Game():GetSeeds():GetStageSeed(Game():GetLevel():GetStage())
end
local function clear(slot)
    assert(native.rooms_with_player(slot, function()
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:IsActiveEnemy(false) then
                e:Remove()
            end
        end
        Game():GetRoom():SetClear(true)
    end))
end
local function separate()
    local level = Game():GetLevel()
    for i = 0, level:GetRooms().Size - 1 do
        local d = level:GetRooms():Get(i)
        if
            d.Data.Type == RoomType.ROOM_DEFAULT
            and d.SafeGridIndex ~= level:GetCurrentRoomIndex()
        then
            assert(native.rooms_move(1, d.SafeGridIndex, 0, -1))
            return
        end
    end
    error("Missing separate floor-reset room")
end
local function remember()
    expected = {}
    seed = floorSeed()
    for i = 0, 1 do
        local p = Isaac.GetPlayer(i)
        expected[i + 1] =
            { p:GetHearts(), p:GetSoulHearts(), p:GetNumCoins(), p:GetNumBombs(), p:GetNumKeys() }
    end
end
local function verify(name, stage, changed)
    assert(native.rooms_ready(), "Native floor reset is still loading")
    assert(Game():GetLevel():GetStage() == stage, name .. " changed to the wrong floor")
    if changed then
        assert(floorSeed() ~= seed, name .. " did not regenerate the floor")
    end
    local positions = native.rooms_positions()
    assert(
        positions["0"].index == positions["1"].index
            and positions["0"].dimension == positions["1"].dimension,
        name .. " left teammates on separate old floors"
    )
    for i, v in ipairs(expected) do
        local p = Isaac.GetPlayer(i - 1)
        assert(
            p:GetHearts() == v[1] and p:GetSoulHearts() == v[2],
            name .. " changed retained health"
        )
        assert(
            p:GetNumCoins() == v[3] and p:GetNumBombs() == v[4] and p:GetNumKeys() == v[5],
            name .. " changed retained resources"
        )
        assert(
            p:HasCollectible(
                i == 1 and CollectibleType.COLLECTIBLE_SAD_ONION
                    or CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM
            ),
            name .. " lost retained items"
        )
        assert(p.Visible and not p:IsDead(), name .. " hid a living player")
    end
    report("CHECKED " .. name .. " stage=" .. stage .. " seed=" .. floorSeed())
end
local function use(slot, item)
    assert(native.rooms_with_player(slot, function()
        local p = Isaac.GetPlayer(0)
        p:AddCollectible(item)
        p:UseActiveItem(item, 0, -1)
    end))
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, b)
            before(t, n, b)
            if t == 30 then
                for i = 0, 1 do
                    local p = Isaac.GetPlayer(i)
                    p:AddCollectible(
                        i == 0 and CollectibleType.COLLECTIBLE_SAD_ONION
                            or CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM
                    )
                    p:AddCoins(10 + i * 7)
                    p:AddSoulHearts(2 + i * 2)
                end
                separate()
            end
            if t == 50 then
                clear(0)
                clear(1)
                remember()
            end
            if t == 60 then
                use(0, CollectibleType.COLLECTIBLE_FORGET_ME_NOW)
                report("USE host Forget Me Now")
            end
            if t == 230 then
                verify("host Forget Me Now", 1, true)
                separate()
            end
            if t == 250 then
                clear(0)
                clear(1)
                remember()
            end
            if t == 260 then
                use(1, CollectibleType.COLLECTIBLE_FORGET_ME_NOW)
                report("USE guest Forget Me Now")
            end
            if t == 430 then
                verify("guest Forget Me Now", 1, true)
                separate()
            end
            -- Room variants select layouts; the native floor independently picks
            -- its face. Keep the actor away until the five-pip fixture is ready.
            if t == 450 then
                assert(native.rooms_with_player(1, function()
                    Isaac.GetPlayer(0).Position = Vector(100, 100)
                    report("DICE command " .. Isaac.ExecuteCommand("goto s.dice.4"))
                end))
            end
            if t == 480 then
                assert(native.rooms_with_player(1, function()
                    assert(
                        Game():GetRoom():GetType() == RoomType.ROOM_DICE,
                        "Native five-pip room was not entered"
                    )
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if
                            e.Type == EntityType.ENTITY_EFFECT
                            and e.Variant == EffectVariant.DICE_FLOOR
                        then
                            e.SubType = 4
                            e:GetSprite():Play("5", true)
                            assert(
                                e.SubType == 4 and e:GetSprite():GetAnimation() == "5",
                                "Fixture is not a five-pip floor"
                            )
                            dice = EntityPtr(e)
                            report(
                                "DICE subtype="
                                    .. e.SubType
                                    .. " animation="
                                    .. e:GetSprite():GetAnimation()
                            )
                            break
                        end
                    end
                    assert(dice and dice.Ref, "Native dice floor is missing")
                end))
                remember()
            end
            if t == 520 then
                assert(native.rooms_with_player(1, function()
                    Isaac.GetPlayer(0).Position = dice.Ref.Position
                end))
                report("STEP native five-pip floor")
            end
            if t == 700 then
                verify("native five-pip floor", 1, true)
            end
            if t == 730 then
                Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
            end
            if t == 1000 then
                assert(Game():GetLevel():GetStage() == 2, "R Key fixture did not reach floor 2")
                separate()
            end
            if t == 1020 then
                clear(0)
                clear(1)
                remember()
            end
            if t == 1030 then
                use(1, CollectibleType.COLLECTIBLE_R_KEY)
                report("USE guest R Key")
            end
            if t == 1250 then
                verify("guest R Key", 1, false)
                checked = true
            end
        end,
        collect,
        function(bytes, t, ack)
            if restore(bytes, t, ack) == false then
                return false
            end
            local value = _IsaacLanState.decode(bytes)
            for _, a in ipairs(value[9]) do
                local p = Isaac.GetPlayer(a[1])
                assert(
                    p:GetHearts() == a[4][4][4] and p:GetSoulHearts() == a[4][4][8],
                    "Replica reset health differs"
                )
                assert(p:GetNumCoins() == a[4][5][1], "Replica reset resources differ")
            end
            return true
        end,
        present,
        beginFloor
    )
end
