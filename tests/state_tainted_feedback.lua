local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local input = assert(_IsaacLanTestInput)
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local shop, origin, pickup, trial, esau, destination, entrance
local emitted, beforeCoins, beforeItems, snapshots = 0, 0, 0, 0
local failures = {}
local itemId, purchasePrice, replicaTick = 1, 0, 0
local spawnedMaterials = {}
local focusSetting, focusSamples, focusErrors = Options.PauseOnFocusLost, 0, 0
local guestShop, guestShopChecked
local walkArrived, walkChecked
local finishTick = 1140
Options.PauseOnFocusLost = not host
local owner = { Name = "Tainted character feedback regression" }
local function report(text)
    Isaac.DebugString("LAN_NETWORK TAINTED_FEEDBACK " .. text)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end, 1))
end
local function check(name, ok, detail)
    report("CHECK " .. name .. " passed=" .. tostring(ok) .. " " .. (detail or ""))
    if not ok then
        failures[#failures + 1] = name
    end
end
local function clear()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:ToPickup() or entity:IsActiveEnemy(false) then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function materials()
    local count = 0
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:ToPickup() and entity.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
            count = count + 1
        end
    end
    return count
end
local function ordinaryDoor()
    for slot = 0, 7 do
        local door = Game():GetRoom():GetDoor(slot)
        if
            door
            and Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex, 0).Data.Type
                == RoomType.ROOM_DEFAULT
        then
            return door, slot
        end
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_PICKUP_INIT, function(_, entity)
    if host and trial and entity.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
        emitted = emitted + 1
        spawnedMaterials[entity.InitSeed] = true
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, entity)
    -- Keep the newly dismantled materials on the floor while observing the
    -- purchase price and the guest view. Collectible collision stays native.
    if host and trial and spawnedMaterials[entity.InitSeed] then
        return true
    end
end)
local function setupPurchase(name, slot, kind, price, stock)
    trial, emitted, spawnedMaterials = name, 0, {}
    actor(slot, function(p)
        if not stock then
            clear()
        end
        assert(Game():GetRoom():GetType() == RoomType.ROOM_SHOP)
        p:ChangePlayerType(kind)
        p:AddCoins(99 - p:GetNumCoins())
        p:SetMinDamageCooldown(120)
        p.Position, p.Velocity = Game():GetRoom():GetCenterPos() + Vector(100, 0), Vector.Zero
        if stock then
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                local candidate = entity:ToPickup()
                if
                    candidate
                    and candidate.Variant == PickupVariant.PICKUP_COLLECTIBLE
                    and candidate.SubType > 0
                    and candidate.Price > 0
                then
                    pickup = candidate
                    break
                end
            end
            assert(pickup, "Native shop did not generate a collectible for sale")
            -- Approach the collectible from its empty aisle so the fixture
            -- does not buy a neighbouring consumable and trigger pickup delay.
            p.Position = pickup.Position + Vector(0, 60)
        else
            pickup = Isaac.Spawn(5, 100, 1, Game():GetRoom():GetCenterPos(), Vector.Zero, nil)
                :ToPickup()
            pickup.ShopItemId = price > 0 and 0 or -1
            pickup.AutoUpdatePrice, pickup.Price, pickup.Wait = false, price, 0
        end
        itemId, purchasePrice = pickup.SubType, pickup.Price
        beforeCoins, beforeItems = p:GetNumCoins(), p:GetCollectibleNum(itemId, true)
        report(
            "PURCHASE "
                .. name
                .. " slot="
                .. slot
                .. " item="
                .. itemId
                .. " price="
                .. purchasePrice
        )
    end)
end
local function finishPurchase(slot, cain)
    actor(slot, function(p)
        local consumed = not pickup:Exists() or pickup.SubType == 0
        local items = p:GetCollectibleNum(itemId, true) - beforeItems
        local spent = beforeCoins - p:GetNumCoins()
        check(
            trial,
            consumed
                and spent == purchasePrice
                and (cain and items == 0 and emitted > 0 or not cain and items == 1),
            "consumed="
                .. tostring(consumed)
                .. " spent="
                .. spent
                .. " items="
                .. items
                .. " drops="
                .. emitted
        )
    end)
    trial, pickup = nil, nil
end
local function step(t)
    if t == 30 then
        origin = Game():GetLevel():GetStartingRoomIndex()
        local rooms = Game():GetLevel():GetRooms()
        for i = 0, rooms.Size - 1 do
            local descriptor = rooms:Get(i)
            if descriptor.Data.Type == RoomType.ROOM_SHOP then
                shop = descriptor.SafeGridIndex
                break
            end
        end
        assert(shop, "Seed has no shop")
        actor(1, function(p)
            p:ChangePlayerType(PlayerType.PLAYER_CAIN_B)
        end)
        assert(native.rooms_move(1, shop, 0, -1))
    elseif t == 40 then
        Isaac.DebugString("LAN_NETWORK FOCUS_SET_REQUEST 1 client")
    elseif t == 90 then
        setupPurchase("guest-native-shop-cain", 1, PlayerType.PLAYER_CAIN_B, nil, true)
    elseif t == 100 then
        Isaac.DebugString("LAN_NETWORK FOCUS_SET_REQUEST 2 host")
    elseif t == 230 or t == 350 then
        actor(1, function(p)
            p.Position, p.Velocity = pickup.Position, Vector.Zero
        end)
    elseif t == 160 then
        finishPurchase(1, true)
    elseif t == 210 then
        setupPurchase("guest-paid-cain", 1, PlayerType.PLAYER_CAIN_B, 15)
    elseif t == 280 then
        finishPurchase(1, true)
    elseif t == 330 then
        setupPurchase("guest-paid-isaac", 1, PlayerType.PLAYER_ISAAC, 15)
    elseif t == 400 then
        finishPurchase(1, false)
        Isaac.DebugString("LAN_NETWORK FOCUS_SET_REQUEST 3 client")
        assert(native.rooms_move(0, shop, 0, -1))
    elseif t == 460 then
        actor(1, function(p)
            p.Position = Game():GetRoom():GetCenterPos() + Vector(-150, 80)
        end)
        setupPurchase("host-paid-cain", 0, PlayerType.PLAYER_CAIN_B, 15)
    elseif t == 480 then
        actor(0, function(p)
            p.Position, p.Velocity = pickup.Position, Vector.Zero
        end)
    elseif t == 530 then
        finishPurchase(0, true)
        actor(0, function(p)
            p:ChangePlayerType(PlayerType.PLAYER_ISAAC)
        end)
        assert(native.rooms_move(0, origin, 0, -1))
        assert(native.rooms_move(1, origin, 0, -1))
    elseif t == 600 then
        actor(1, function(p)
            clear()
            p:ChangePlayerType(PlayerType.PLAYER_JACOB_B)
            p.Position = Game():GetRoom():GetCenterPos()
        end)
        Isaac.DebugString("LAN_NETWORK FOCUS_SET_REQUEST 4 host")
    elseif t == 810 then
        actor(1, function(p)
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_DARK_ESAU and entity.Variant == 0 then
                    esau = entity
                end
            end
            assert(esau, "Native Tainted Jacob did not spawn Dark Esau")
            for slot = 0, 7 do
                local door = Game():GetRoom():GetDoor(slot)
                if door then
                    local descriptor = Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex, 0)
                    if descriptor.Data.Type == RoomType.ROOM_DEFAULT then
                        destination, entrance =
                            descriptor.SafeGridIndex, (slot + 2) % 4 + (slot // 4) * 4
                        break
                    end
                end
            end
            assert(destination and entrance, "Native doorway has no ordinary destination")
            esau.Position, esau.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
            p.Position = esau.Position + Vector(150, 0)
            p:ChangePlayerType(PlayerType.PLAYER_JACOB_B)
            report("ESAU before seed=" .. esau.InitSeed .. " destination=" .. destination)
        end)
        assert(native.rooms_move(1, destination, 0, entrance))
    elseif t == 811 then
        actor(1, function(p)
            assert(
                native.rooms_positions()["1"].index == destination,
                "Guest transfer did not complete"
            )
            local distance = (p.Position - esau.Position):Length()
            check(
                "guest-esau-new-room",
                distance > p.Size + esau.Size,
                "distance=" .. distance .. " kind=" .. p:GetPlayerType()
            )
            report(
                "ESAU after x="
                    .. esau.Position.X
                    .. " y="
                    .. esau.Position.Y
                    .. " actor_x="
                    .. p.Position.X
                    .. " actor_y="
                    .. p.Position.Y
            )
        end)
    elseif t == 850 then
        actor(1, function(p)
            check(
                "guest-jacob-survives-arrival",
                not p:IsDead() and p:GetPlayerType() == PlayerType.PLAYER_JACOB_B
            )
            p:SetMinDamageCooldown(300)
        end)
        assert(native.rooms_move(1, origin, 0, (entrance + 2) % 4 + (entrance // 4) * 4))
    elseif t == 851 then
        actor(1, function(p)
            assert(
                native.rooms_positions()["1"].index == origin,
                "Resident transfer did not complete"
            )
            local distance = (p.Position - esau.Position):Length()
            check(
                "guest-esau-resident-room",
                distance > p.Size + esau.Size,
                "distance=" .. distance
            )
        end)
    elseif t == 860 then
        actor(1, function(p)
            local door = assert(ordinaryDoor())
            p.Position = door.Position
                + (Game():GetRoom():GetCenterPos() - door.Position):Resized(50)
            p.Velocity = Vector.Zero
            esau.Position, esau.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
        end)
    elseif t == 870 then
        Isaac.DebugString("LAN_NETWORK FOCUS_SET_REQUEST 5 client")
    elseif t == finishTick then
        check("guest-walk-door-completed", walkChecked == true)
        report("RESULT failures=" .. #failures .. " names=" .. table.concat(failures, ","))
        assert(#failures == 0, table.concat(failures, ","))
        finished = true
        report("PASS character feedback checks completed")
    end
    if t > 870 and not walkArrived and native.rooms_positions()["1"].index == destination then
        walkArrived = t
        actor(1, function(p)
            local distance = (p.Position - esau.Position):Length()
            check(
                "guest-walk-door-distance",
                distance > p.Size + esau.Size,
                "distance=" .. distance
            )
        end)
    elseif walkArrived and not walkChecked and t >= walkArrived + 10 then
        actor(1, function(p)
            check(
                "guest-walk-door-survives",
                not p:IsDead() and p:GetPlayerType() == PlayerType.PLAYER_JACOB_B
            )
            esau:Remove()
            p:ChangePlayerType(PlayerType.PLAYER_ISAAC)
        end)
        walkChecked = true
    end
    if trial and pickup and (not pickup:Exists() or pickup.SubType == 0) then
        actor(trial == "host-paid-cain" and 0 or 1, function(p)
            p.Position = Game():GetRoom():GetCenterPos() + Vector(100, 0)
        end)
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = baseFrame()
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
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    native.test_gamepad(0)
    replicaTick = status.verified
    if not host and replicaTick >= 95 and replicaTick < 110 and not guestShop then
        actor(1, function(p)
            assert(Game():GetRoom():GetType() == RoomType.ROOM_SHOP)
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                local candidate = entity:ToPickup()
                if
                    candidate
                    and candidate.Variant == PickupVariant.PICKUP_COLLECTIBLE
                    and candidate.SubType > 0
                    and candidate.Price > 0
                then
                    guestShop = {
                        id = candidate.SubType,
                        coins = p:GetNumCoins(),
                        price = candidate.Price,
                        items = p:GetCollectibleNum(candidate.SubType, true),
                        materials = materials(),
                    }
                    report(
                        "GUEST_SHOP before item="
                            .. guestShop.id
                            .. " materials="
                            .. guestShop.materials
                    )
                    break
                end
            end
        end)
    elseif not host and replicaTick >= 175 and replicaTick < 210 and not guestShopChecked then
        assert(guestShop, "Guest missed native shop before purchase")
        actor(1, function(p)
            local spent, drops =
                guestShop.coins - p:GetNumCoins(), materials() - guestShop.materials
            assert(p:GetPlayerType() == PlayerType.PLAYER_CAIN_B)
            assert(p:GetCollectibleNum(guestShop.id, true) == guestShop.items)
            assert(
                spent == guestShop.price and drops > 0,
                "Guest did not display dismantled shop materials"
            )
            report(
                "GUEST_SHOP after item="
                    .. guestShop.id
                    .. " spent="
                    .. spent
                    .. " materials_added="
                    .. drops
            )
            guestShopChecked = true
        end)
    end
    if not host and status.verified >= finishTick and not finished then
        assert(snapshots > 100, "Guest did not receive character snapshots")
        assert(guestShopChecked, "Guest shop verification did not complete")
        report("FOCUS samples=" .. focusSamples .. " errors=" .. focusErrors)
        assert(
            focusSamples >= 300 and focusErrors == 0,
            "Guest focus loss opened a local pause menu"
        )
        assert(Options.PauseOnFocusLost, "Replica changed the user's focus setting")
        finished = true
        report("PASS guest snapshots=" .. snapshots)
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        function()
            if
                not host
                and replicaTick >= 870
                and replicaTick < 1100
                and native.rooms_positions()["1"].index
                    == Game():GetLevel():GetStartingRoomIndex()
            then
                local movement = 0
                actor(1, function(p)
                    local door = assert(ordinaryDoor())
                    local target = door.Position
                        + (door.Position - Game():GetRoom():GetCenterPos()):Resized(32)
                    local delta = target - p.Position
                    if math.abs(delta.X) > 2 then
                        movement = movement | (delta.X > 0 and 2 or 1)
                    end
                    if math.abs(delta.Y) > 2 then
                        movement = movement | (delta.Y > 0 and 8 or 4)
                    end
                end)
                return input.buttons(movement, 0)
            end
            if not host and replicaTick >= 110 and replicaTick < 160 then
                local movement = 0
                actor(1, function(p)
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        local candidate = entity:ToPickup()
                        if
                            guestShop
                            and candidate
                            and candidate.Variant == PickupVariant.PICKUP_COLLECTIBLE
                            and candidate.SubType == guestShop.id
                            and candidate.Price > 0
                        then
                            local delta = candidate.Position - p.Position
                            if math.abs(delta.X) > 2 then
                                movement = movement | (delta.X > 0 and 2 or 1)
                            end
                            if math.abs(delta.Y) > 2 then
                                movement = movement | (delta.Y > 0 and 8 or 4)
                            end
                            break
                        end
                    end
                end)
                return input.buttons(movement, 0)
            end
            return input.neutral
        end,
        function(t, n, bytes)
            before(t, n, bytes)
            if host then
                step(t)
            end
        end,
        collect,
        function(...)
            snapshots = snapshots + 1
            return restore(...)
        end,
        present,
        beginFloor
    )
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_RENDER, function()
    if not host and replicaTick >= 30 and replicaTick < finishTick then
        focusSamples = focusSamples + 1
        if native.pause_menu_state().page ~= 0 or Game():IsPaused() then
            focusErrors = focusErrors + 1
        end
    end
end)
return {
    done = function()
        return finished
    end,
    cleanup = function()
        Options.PauseOnFocusLost = focusSetting
    end,
}
