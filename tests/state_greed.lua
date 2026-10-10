-- Greed/Greedier use native buttons, wave spawning, rewards and shop collision.
-- Only preparation, enemy damage and route positioning are test fixtures.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local difficulty = _IsaacLanTest.route == "greedier" and 3 or 2
local frame, gate = _IsaacLanFrame, native.net_gate
local linked, chosen, finished, renders = false, false, false, 0
local step, stepAt, main, shop, button, pressedAt = "init", 0, nil, nil, nil, nil
local lastWave, waveChanges, snapshots, splitSnapshots, floorEvents = 0, 0, 0, 0, 0
local stopWave, shopItem, initialCoins, bossSeen = nil, nil, nil, false
local function report(text)
    Isaac.DebugString("LAN_NETWORK GREED mode=" .. difficulty .. " " .. text)
end
local function mark(name, tick)
    step, stepAt = name, tick
    report("STEP " .. name .. " tick=" .. tick)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function find(kind)
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        if d.Data and d.Data.Type == kind and d.SafeGridIndex >= 0 then
            return d.SafeGridIndex
        end
    end
end
local function terminalRoom()
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        if d.Data and d.SafeGridIndex >= 0 then
            for j = 0, d.Data.SpawnCount - 1 do
                local spawn = d.Data.Spawns:Get(j)
                for k = 0, spawn.EntryCount - 1 do
                    if spawn.Entries:Get(k).Type == EntityType.ENTITY_ULTRA_GREED then
                        report("TERMINAL_ROOM index=" .. d.SafeGridIndex .. " type=" .. d.Data.Type)
                        return d.SafeGridIndex
                    end
                end
            end
        end
    end
end
local function move(slot, index)
    assert(native.rooms_move(slot, index, 0, -1))
    actor(slot, function(p)
        p.Position, p.Velocity = Vector(120, 280), Vector.Zero
    end)
end
local function press(tick)
    pressedAt = tick
    report(
        "BUTTON wave="
            .. Game():GetLevel().GreedModeWave
            .. " state="
            .. button.State
            .. " variant="
            .. button:GetVariant()
            .. " animation="
            .. button:GetSprite():GetAnimation()
    )
    actor(1, function(p)
        p.Position, p.Velocity = button.Position, Vector.Zero
    end)
end
local function enemies(slot, damage)
    local count = 0
    actor(slot, function(p)
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:IsActiveEnemy(false) then
                count = count + 1
                if damage then
                    e:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(p), 0)
                end
            end
        end
    end)
    return count
end
local function arenaClear()
    local clear
    actor(1, function()
        clear = Game():GetRoom():IsClear()
    end)
    return clear
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
        _IsaacLanCommand("start", "YV039KQF:" .. difficulty .. ":0:0:0:0")
    end
    native.test_gamepad(0)
    return status
end
local function advance(t)
    local game, level = Game(), Game():GetLevel()
    assert(
        game:IsGreedMode() and game.Difficulty == difficulty,
        "Lobby did not start the requested Greed mode"
    )
    for slot = 0, 1 do
        actor(slot, function(p)
            p:SetMinDamageCooldown(10000)
        end)
    end
    if pressedAt and t - pressedAt >= 5 then
        actor(1, function(p)
            p.Position, p.Velocity = Vector(120, 280), Vector.Zero
        end)
        pressedAt = nil
    end
    local wave = level.GreedModeWave
    if wave ~= lastWave then
        waveChanges, lastWave = waveChanges + 1, wave
        report("WAVE " .. wave .. " tick=" .. t)
    end
    if step == "init" and t >= 30 then
        assert(wave == 0 and level:GetStage() == 1)
        main, shop =
            level:GetStartingRoomIndex(), assert(find(RoomType.ROOM_SHOP), "Missing Greed shop")
        move(0, shop)
        move(1, main)
        actor(1, function()
            local room = game:GetRoom()
            for index = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(index)
                if grid and grid:GetType() == GridEntityType.GRID_PRESSURE_PLATE then
                    button = grid
                    break
                end
            end
            assert(button, "Missing native Greed button")
        end)
        press(t)
        mark("first-wave", t)
    elseif step == "first-wave" and wave >= 1 and enemies(1, false) > 0 then
        assert(
            native.rooms_positions()["0"].index ~= native.rooms_positions()["1"].index,
            "Ordinary Greed wave forced team gathering"
        )
        report("CHECK native guest button spawned enemies with host in shop")
        press(t)
        stopWave = wave
        mark("stop", t)
    elseif step == "stop" then
        enemies(1, true)
        if t - stepAt >= 90 then
            assert(wave == stopWave, "Stop button did not pause native waves")
            press(t)
            mark("waves", t)
        end
    elseif step == "waves" then
        if t % 15 == 0 then
            enemies(1, true)
        end
        local normal = difficulty == 3 and 9 or 8
        if wave >= normal and enemies(1, false) == 0 and arenaClear() then
            actor(1, function()
                assert(game:GetRoom():IsClear(), "Normal waves did not reopen the arena")
                local coins = 0
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if
                        e.Type == EntityType.ENTITY_PICKUP
                        and e.Variant == PickupVariant.PICKUP_COIN
                    then
                        coins = coins + 1
                    end
                end
                assert(coins > 0, "Native Greed waves produced no coin rewards")
                report("CHECK native wave rewards coins=" .. coins)
            end)
            mark("arm-boss", t)
        end
    elseif step == "arm-boss" and t - stepAt >= 30 then
        press(t)
        mark("boss-waves", t)
    elseif step == "boss-waves" then
        if t % 15 == 0 then
            enemies(1, true)
        end
        local bosses = difficulty == 3 and 11 or 10
        if wave >= bosses and enemies(1, false) == 0 and arenaClear() then
            mark("arm-devil", t)
        end
    elseif step == "arm-devil" and t - stepAt >= 30 then
        press(t)
        mark("devil-wave", t)
    elseif step == "devil-wave" then
        if t % 15 == 0 then
            enemies(1, true)
        end
        local final = difficulty == 3 and 12 or 11
        if wave >= final and enemies(1, false) == 0 and arenaClear() then
            assert(waveChanges >= final, "Fixture skipped native waves")
            move(1, shop)
            mark("shop-arrival", t)
        end
    elseif
        step == "shop-arrival"
        and native.rooms_positions()["1"].index == shop
        and t - stepAt >= 15
    then
        actor(1, function(p)
            p:AddCoins(30 - p:GetNumCoins())
            initialCoins = p:GetNumCoins()
            local pickup = Isaac.Spawn(
                EntityType.ENTITY_PICKUP,
                PickupVariant.PICKUP_COLLECTIBLE,
                CollectibleType.COLLECTIBLE_SAD_ONION,
                Vector(320, 280),
                Vector.Zero,
                nil
            ):ToPickup()
            pickup.Price, pickup.ShopItemId, pickup.AutoUpdatePrice = 15, 0, false
            shopItem = EntityPtr(pickup)
            p.Position = pickup.Position
        end)
        mark("shop", t)
    elseif step == "shop" then
        local purchased = false
        actor(1, function(p)
            purchased = p:HasCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
            if not purchased and shopItem.Ref and shopItem.Ref:Exists() then
                p.Position, p.Velocity = shopItem.Ref.Position, Vector.Zero
                if t % 30 == 0 then
                    report(
                        "SHOP_CONTACT tick="
                            .. t
                            .. " wait="
                            .. shopItem.Ref:ToPickup().Wait
                            .. " controls="
                            .. tostring(p:AreControlsEnabled())
                    )
                end
            end
        end)
        if not purchased then
            assert(t - stepAt < 300, "Guest could not buy the Greed shop item")
            return
        end
        actor(1, function(p)
            assert(
                p:HasCollectible(CollectibleType.COLLECTIBLE_SAD_ONION),
                "Guest could not buy the Greed shop item"
            )
            assert(
                p:GetNumCoins() == initialCoins - 15,
                "Shop purchase charged the shared pool incorrectly"
            )
        end)
        assert(not shopItem.Ref or not shopItem.Ref:Exists(), "Purchased item was not consumed")
        report("CHECK guest native Greed shop purchase charged 15 coins once")
        move(1, assert(find(RoomType.ROOM_GREED_EXIT), "Missing Greed exit room"))
        mark("exit-arrival", t)
    elseif
        step == "exit-arrival"
        and t - stepAt >= 15
        and native.rooms_positions()["1"].index == find(RoomType.ROOM_GREED_EXIT)
    then
        actor(1, function(p)
            local room = game:GetRoom()
            for i = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(i)
                if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then
                    p.Position = grid.Position
                    mark("floor", t)
                    return
                end
            end
            error("Missing native Greed trapdoor")
        end)
    elseif step == "floor" and level:GetStage() == 2 and native.rooms_ready() then
        assert(wave == 0, "New Greed floor retained its previous waves")
        local positions = native.rooms_positions()
        assert(
            positions["0"].index == positions["1"].index,
            "Greed trapdoor left a teammate on the old floor"
        )
        report("CHECK guest native trapdoor advanced the whole team")
        -- Prepare the generated terminal floor through the same reliable
        -- native transaction used by the existing ending-route fixtures.
        level:SetStage(7, 0)
        game:StartStageTransition(true, 0, Isaac.GetPlayer(assert(native.rooms_heads()["1"])))
        mark("terminal-floor", t)
    elseif step == "terminal-floor" and level:GetStage() == 7 and native.rooms_ready() then
        -- Preceding Greed minibosses can share the final arena's room type.
        -- Select the generated Ultra Greed spawn, as in the existing
        -- ending-route fixtures, instead of assuming a shop/Boss room index.
        local boss = assert(terminalRoom(), "Missing generated Ultra Greed arena")
        move(1, boss)
        mark("terminal", t)
    elseif step == "terminal" then
        actor(1, function()
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == EntityType.ENTITY_ULTRA_GREED then
                    bossSeen = true
                end
            end
        end)
        if bossSeen and t - stepAt >= 90 then
            local positions = native.rooms_positions()
            assert(
                positions["0"].index == positions["1"].index,
                "Ultra Greed did not gather the split team"
            )
            report("CHECK Ultra Greed gathers the split team")
            mark("done", t)
        end
    elseif step == "done" and t - stepAt >= 90 then
        finished = true
        report("PASS native Greed gameplay")
    end
    assert(t - stepAt < 1800, "Greed fixture stalled at " .. step)
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, b)
            before(t, n, b)
            if not finished then
                advance(t)
            end
        end,
        function(slot, t)
            local bytes = collect(slot, t)
            return string.pack(">s4", bytes) .. _IsaacLanState.encode({ step })
        end,
        function(packet, t, ack)
            local bytes, offset = string.unpack(">s4", packet)
            local phase = _IsaacLanState.decode(packet:sub(offset))[1]
            if restore(bytes, t, ack) == false then
                return false
            end
            local value = _IsaacLanState.decode(bytes)
            assert(Game():IsGreedMode() and Game().Difficulty == difficulty)
            assert(Game():GetLevel().GreedModeWave == value[18], "Replica Greed wave HUD differs")
            snapshots = snapshots + 1
            local locations = value[7]
            if #locations == 2 and locations[1][3] ~= locations[2][3] then
                splitSnapshots = splitSnapshots + 1
            end
            for _, a in ipairs(value[9]) do
                assert(
                    Isaac.GetPlayer(a[1]):GetNumCoins() == a[4][5][1],
                    "Replica Greed coins differ"
                )
            end
            assert(native.rooms_with_player(value[10], function()
                local room = Game():GetRoom()
                assert(room:IsClear() == value[11][1], "Replica Greed room-clear state differs")
                for _, grid in ipairs(value[11][4]) do
                    local actual = assert(room:GetGridEntity(grid[1]), "Replica Greed grid missing")
                    assert(
                        actual.State == grid[4] and actual.VarData == grid[6],
                        "Replica Greed button/door state differs"
                    )
                end
            end))
            assert(restore(bytes, t, ack) ~= false, "Repeated Greed state failed")
            for _, a in ipairs(value[9]) do
                assert(
                    Isaac.GetPlayer(a[1]):GetNumCoins() == a[4][5][1],
                    "Repeated Greed state changed resources"
                )
            end
            if not finished and phase == "done" then
                assert(
                    snapshots > 60 and splitSnapshots > 20 and floorEvents >= 2,
                    "Greed replica coverage incomplete"
                )
                finished = true
                report(
                    "PASS replica Greed gameplay snapshots="
                        .. snapshots
                        .. " split="
                        .. splitSnapshots
                )
            end
            return true
        end,
        present,
        function(...)
            floorEvents = floorEvents + 1
            return beginFloor(...)
        end
    )
end
