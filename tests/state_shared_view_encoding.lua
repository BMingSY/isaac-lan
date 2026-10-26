-- Four owned games exercise the actual layered capture, transport and replicas.
-- Setup/byte comparisons are outside the labelled capture/encode measurements.
local native, config = assert(_IsaacLan), assert(_IsaacLanSharedViewFixture)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
assert(_IsaacLanTest.players == 4)
local modules, state = _IsaacLanModules, _IsaacLanState
local fields, codec, schema =
    modules["sync/fields"], modules["sync/codec"], modules["sync/world_schema"]
local Actor, Inventory, Item, Room, Entity, Location =
    fields.actor, fields.inventory, fields.item, fields.room, fields.entity, fields.location
local keeper = modules["compat/characters/keeper"](native, RoomType, PickupVariant)
local frame, gate, sample = _IsaacLanFrame, native.net_gate, native.diagnostics_sample
local phase, phaseAt, measuring = "setup", 0, nil
local renders, linked, chosen, done, floorFrames = 0, false, false, false, 0
local startRoom, splitRooms, roomTears = nil, {}, {}
local checked, captured = {}, {}
local function report(text)
    Isaac.DebugString("LAN_SHARED_VIEW " .. text)
end
local function actor(slot, fn)
    assert(native.api_with_owner(slot, function()
        fn(Isaac.GetPlayer(0), Game():GetRoom(), Game():GetLevel())
    end))
end
local function mark(name)
    phase, phaseAt = name, native.api_info().nowMs
    report("PHASE name=" .. name .. " now_ms=" .. phaseAt)
end
local function clear()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type ~= EntityType.ENTITY_PLAYER then
            e:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function fill(slot)
    actor(slot, function(player, room)
        clear()
        roomTears[slot] = true
        for index = 1, config.tears do
            local position = room:GetCenterPos()
                + Vector((index % 20) * 8 - 80, (index // 20) * 4 - 50)
            local tear = Isaac.Spawn(
                EntityType.ENTITY_TEAR,
                TearVariant.BLUE,
                0,
                position,
                Vector.Zero,
                player
            ):ToTear()
            tear.FallingSpeed, tear.FallingAcceleration, tear.Height = 0, 0, -20
            tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
            tear.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        end
        -- Remove() is queued until the native update finishes. Verify the
        -- captured/replicated count after warmup, not in this preparation call.
        report("LOAD slot=" .. slot .. " requested=" .. config.tears)
    end)
end
local function priceProbe(slot, devil)
    local scans, enumerate = 0, Isaac.GetRoomEntities
    local expected, pickup
    if devil then
        for _, e in ipairs(enumerate()) do
            if
                e:Exists()
                and e.Type == EntityType.ENTITY_PICKUP
                and e.Variant == PickupVariant.PICKUP_COLLECTIBLE
            then
                pickup = e:ToPickup()
                break
            end
        end
        if not pickup then
            return false
        end
        local player = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
        expected = native.pickup_price(pickup:GetSprite(), player:GetSprite())
        assert(type(expected) == "number", "Fixture buyer/pickup is not ready for native pricing")
        assert(slot % 2 == 1 and expected > 0 or slot % 2 == 0 and expected < 0)
        pickup.Price = 12345
    end
    Isaac.GetRoomEntities = function()
        scans = scans + 1
        return enumerate()
    end
    local ok, err = pcall(function()
        if host then
            keeper.update()
        else
            keeper.present(slot)
        end
    end)
    Isaac.GetRoomEntities = enumerate
    assert(ok, err)
    assert(scans == ((devil or config.baseline) and 1 or 0), "Unexpected price scan count")
    if devil then
        assert(pickup.Price == expected, "Devil price differs from the native buyer price")
    end
    report(
        "PRICE slot="
            .. slot
            .. " devil="
            .. tostring(devil)
            .. " scans="
            .. scans
            .. " value="
            .. tostring(expected)
    )
    return true
end
local function countTears(entities)
    local count = 0
    for _, e in ipairs(entities) do
        if e[Entity.type] == EntityType.ENTITY_TEAR then
            count = count + 1
        end
    end
    return count
end
local function checkView(bytes, stable, slot, replica, tick)
    if tick % 30 ~= 0 then
        return
    end
    local packed = state.decode(bytes, stable)
    local view = schema.unpack(packed, packed[2])
    local tearCount = countTears(view.room[Room.entities])
    if tearCount ~= config.tears then
        local key = "waiting:" .. phase .. ":" .. slot
        if not checked[key] then
            checked[key] = true
            report("WAIT phase=" .. phase .. " slot=" .. slot .. " tears=" .. tearCount)
        end
        return
    end
    local rooms = {}
    for _, at in ipairs(view.locations) do
        rooms[at[Location.dimension] .. ":" .. at[Location.index]] = true
    end
    local count = 0
    for _ in pairs(rooms) do
        count = count + 1
    end
    local hadSplit = replica and checked.split or checked["split:" .. slot]
    local name = count > 1 and "split" or hadSplit and "rejoined" or "same"
    local key = replica and name or name .. ":" .. slot
    if checked[key] then
        return
    end
    assert(view.slot == slot and view.connected == 15 and #view.actors == 4)
    assert(codec.encode(native.state_decode(bytes)) == bytes, "Realtime wire bytes differ")
    if stable and #stable > 0 then
        assert(codec.encode(native.state_decode(stable)) == stable, "Stable wire bytes differ")
    end
    for _, value in ipairs(view.actors) do
        local onion = 0
        for _, item in ipairs(value[Actor.inventory][Inventory.items]) do
            if item[Item.id] == CollectibleType.COLLECTIBLE_SAD_ONION then
                onion = item[Item.count]
            end
        end
        assert(onion == value[Actor.controller], "Per-actor inventory was lost or mixed")
    end
    if replica then
        local actual = 0
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:Exists() and e.Type == EntityType.ENTITY_TEAR then
                actual = actual + 1
            end
        end
        if actual ~= config.tears then
            return -- A just-replaced room can still contain deferred removals.
        end
        assert(
            Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
                :GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION)
                == slot + 1
        )
    end
    checked[key] = true
    report(
        "VIEW name=" .. name .. " slot=" .. slot .. " tears=" .. config.tears .. " rooms=" .. count
    )
end
local function advance()
    if not native.rooms_ready() or native.api_info().ready ~= 1 or done then
        return
    end
    local now = native.api_info().nowMs
    for slot in pairs(roomTears) do
        actor(slot, function()
            local alive = 0
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                local tear = e:Exists() and e:ToTear()
                if tear then
                    alive = alive + 1
                    tear.FallingSpeed, tear.FallingAcceleration, tear.Height = 0, 0, -20
                    tear.Velocity = Vector.Zero
                end
            end
            if phase == "same" or phase == "split" then
                assert(
                    alive == config.tears,
                    "Measured room load changed: slot=" .. slot .. " tears=" .. alive
                )
            end
        end)
    end
    if phase == "setup" then
        local level = Game():GetLevel()
        startRoom = level:GetStartingRoomIndex()
        local rooms = level:GetRooms()
        for index = 0, rooms.Size - 1 do
            local d = rooms:Get(index)
            if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= startRoom then
                splitRooms[#splitRooms + 1] = d.SafeGridIndex
            end
        end
        assert(#splitRooms >= 2)
        for slot = 0, 3 do
            actor(slot, function(player, room)
                player:ChangePlayerType(
                    slot % 2 == 1 and PlayerType.PLAYER_KEEPER or PlayerType.PLAYER_ISAAC
                )
                for _ = 0, slot do
                    player:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
                end
                player.Position = room:GetCenterPos() + Vector(slot * 30 - 45, 100)
                player:SetMinDamageCooldown(10000)
            end)
        end
        assert(priceProbe(0, false))
        fill(0)
        mark("warm_same")
    elseif phase == "warm_same" and now - phaseAt >= 3000 then
        for slot = 1, 3 do
            assert(checked["same:" .. slot], "Same-room warmup did not reach the expected load")
        end
        mark("same")
    elseif phase == "same" and now - phaseAt >= config.seconds * 1000 then
        for slot = 2, 3 do
            assert(native.rooms_move(slot, splitRooms[slot - 1], 0, -1))
        end
        mark("move_split")
    elseif phase == "move_split" and now - phaseAt >= 2000 then
        for slot = 2, 3 do
            assert(native.rooms_positions()[tostring(slot)].index == splitRooms[slot - 1])
            fill(slot)
        end
        mark("warm_split")
    elseif phase == "warm_split" and now - phaseAt >= 3000 then
        for slot = 1, 3 do
            assert(checked["split:" .. slot], "Split-room warmup did not reach the expected load")
        end
        mark("split")
    elseif phase == "split" and now - phaseAt >= config.seconds * 1000 then
        for slot = 2, 3 do
            actor(slot, clear)
            assert(native.rooms_move(slot, startRoom, 0, -1))
        end
        roomTears[2], roomTears[3] = nil, nil
        mark("move_rejoin")
    elseif phase == "move_rejoin" and now - phaseAt >= 2000 then
        fill(0)
        mark("warm_rejoin")
    elseif phase == "warm_rejoin" and now - phaseAt >= 3000 then
        mark("rejoined")
    elseif phase == "rejoined" and now - phaseAt >= 6000 then
        actor(0, function(_, _, level)
            clear()
            level:InitializeDevilAngelRoom(false, false)
        end)
        for slot = 0, 3 do
            assert(native.rooms_move(slot, GridRooms.ROOM_DEVIL_IDX, 0, -1))
        end
        mark("move_devil")
    elseif phase == "move_devil" and now - phaseAt >= 2000 then
        actor(0, function(_, room)
            assert(room:GetType() == RoomType.ROOM_DEVIL)
            clear()
            local pickup = Isaac.Spawn(
                EntityType.ENTITY_PICKUP,
                PickupVariant.PICKUP_COLLECTIBLE,
                CollectibleType.COLLECTIBLE_SAD_ONION,
                room:GetCenterPos() + Vector(100, -50),
                Vector.Zero,
                nil
            ):ToPickup()
            pickup.ShopItemId, pickup.AutoUpdatePrice, pickup.Price = 0, true, -1
        end)
        roomTears = {}
        mark("warm_devil")
    elseif phase == "warm_devil" and now - phaseAt >= 2000 then
        actor(0, function()
            assert(priceProbe(0, true))
        end)
        mark("devil")
    elseif phase == "devil" and now - phaseAt >= 6000 then
        actor(0, clear)
        for slot = 0, 3 do
            assert(native.rooms_move(slot, startRoom, 0, -1))
        end
        mark("return")
    elseif phase == "return" and now - phaseAt >= 3000 then
        actor(0, function(player)
            Game():StartStageTransition(false, RoomTransitionAnim.FADE, player)
        end)
        mark("floor")
    end
end
native.diagnostics_sample = function(name, value)
    sample(name, value)
    if measuring and name == "encode" then
        sample("fixture.encode." .. measuring, value)
    end
end
native.net_gate = function(capture, before, collect, restore, present, floor)
    return gate(capture, function(...)
        before(...)
        if host then
            advance()
        end
    end, function(slot, tick)
        measuring = (phase == "same" or phase == "split") and phase or nil
        local started = Isaac.GetTime()
        local bytes, stable = collect(slot, tick)
        if measuring then
            sample("fixture.capture." .. measuring, Isaac.GetTime() - started)
            captured[measuring] = (captured[measuring] or 0) + 1
        end
        measuring = nil
        if phase == "warm_same" or phase == "warm_split" or phase == "rejoined" then
            checkView(bytes, stable, slot, false, tick)
        end
        return bytes, stable
    end, function(bytes, tick, ack, between, stable)
        local result = restore(bytes, tick, ack, between, stable)
        if result and not host then
            local slot = _IsaacLanStatus().slot
            checkView(bytes, stable, slot, true, tick)
            local devil = Game():GetRoom():GetType() == RoomType.ROOM_DEVIL
            local key = devil and "price_devil" or "price_ordinary"
            if not checked[key] and (devil or checked.same) then
                checked[key] = priceProbe(slot, devil)
            end
        end
        return result
    end, present, floor)
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
        and status.players == 4
        and status.ready0 == 1
        and status.ready1 == 1
        and status.ready2 == 1
        and status.ready3 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    native.test_gamepad(0)
    if
        status.prepared
        and native.rooms_ready()
        and native.api_info().ready == 1
        and Game():GetLevel():GetStage() == 2
    then
        floorFrames = floorFrames + 1
        if not done and floorFrames >= 120 then
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                assert(e.Type ~= EntityType.ENTITY_TEAR, "Previous floor's tears survived cleanup")
            end
            local slot = status.slot
            local player = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
            assert(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION) == slot + 1)
            if host then
                assert((captured.same or 0) >= 30 and (captured.split or 0) >= 30)
                for recipient = 1, 3 do
                    assert(
                        checked["same:" .. recipient]
                            and checked["split:" .. recipient]
                            and checked["rejoined:" .. recipient],
                        "Missing authoritative view checks"
                    )
                end
            else
                assert(
                    checked.same
                        and checked.split
                        and checked.rejoined
                        and checked.price_ordinary
                        and checked.price_devil,
                    "Missing replica/price checks"
                )
            end
            done = true
            report("PASS native shared encoding and prices")
        end
    end
    return status
end
