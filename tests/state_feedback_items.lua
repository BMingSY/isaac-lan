-- Native regressions for Soul of the Forgotten, Tainted Isaac and Blue Key.
local native, input, config = _IsaacLan, _IsaacLanTestInput, _IsaacLanTest
local fields, schema = _IsaacLanModules["sync/fields"], _IsaacLanModules["sync/world_schema"]
local host, frame, gate = config.host, _IsaacLanFrame, native.net_gate
local Phase = native.net_phases()
local renders, linked, chosen, finished, snapshots = 0, false, false, false, 0
local origin, other, treasure, source, pickupSeed
local resourceChecks, orderChecks, heldChecks, blueChecks = 0, 0, 0, 0
local items = {
    CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM,
    CollectibleType.COLLECTIBLE_SAD_ONION,
    CollectibleType.COLLECTIBLE_WIRE_COAT_HANGER,
    CollectibleType.COLLECTIBLE_LUNCH,
    CollectibleType.COLLECTIBLE_GROWTH_HORMONES,
    CollectibleType.COLLECTIBLE_SPOON_BENDER,
    CollectibleType.COLLECTIBLE_TOOTH_PICKS,
    CollectibleType.COLLECTIBLE_ODD_MUSHROOM_THIN,
}
local replacement = CollectibleType.COLLECTIBLE_PENTAGRAM
local function report(text)
    Isaac.DebugString("LAN_NETWORK FEEDBACK_ITEMS " .. text)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end))
end
local function clear(room)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:IsActiveEnemy(false) then
            e:Kill()
        end
    end
    room:SetClear(true)
end
local function resources()
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        assert(
            p:GetNumCoins() == 17 and p:GetNumBombs() == 3 and p:GetNumKeys() == 5,
            "Temporary body changed shared coins/bombs/keys"
        )
    end
    resourceChecks = resourceChecks + 1
end
local function checkOrder(t)
    actor(1, function(p)
        local packed = assert(native.actor_inventory_order(p:GetSprite()))
        if t < 720 then
            local cycles = t >= 680 and 3 or t >= 650 and 2 or t >= 620 and 1 or 0
            for i = 1, 8 do
                assert(
                    string.unpack(">i4", packed, (i - 1) * 4 + 1) == items[(i + cycles - 1) % 8 + 1],
                    "Tainted Isaac selected the wrong item after Drop"
                )
            end
        elseif t >= 810 then
            assert(
                p:HasCollectible(replacement) and not p:HasCollectible(items[4]),
                "Native pickup did not replace the selected passive"
            )
            local found = 0
            for i = 1, 16 do
                local id = string.unpack(">i4", packed, (i - 1) * 4 + 1)
                assert(id ~= items[4], "Replaced item remained in the inventory display")
                if id == replacement then
                    found = found + 1
                end
            end
            assert(found == 1, "Replacement icon was missing or duplicated")
        end
        orderChecks = orderChecks + 1
    end)
end
local function doorTo(room, target)
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door and door.TargetRoomIndex == target then
            return door
        end
    end
    error("Missing expected door to " .. target)
end
local function approach(p, room, target)
    local door = doorTo(room, target)
    p.Position = door.Position - (door.Position - room:GetCenterPos()):Normalized() * 25
    p.Velocity = Vector.Zero
    return door
end
local function bluePlan()
    local level = Game():GetLevel()
    for i = 0, level:GetRooms().Size - 1 do
        local desc = level:GetRooms():Get(i)
        if desc.Data.Type == RoomType.ROOM_TREASURE then
            treasure = desc.SafeGridIndex
            break
        end
    end
    assert(treasure)
    for _, delta in ipairs({ -1, -13, 1, 13 }) do
        local desc = level:GetRoomByIdx(treasure + delta, 0)
        if desc and desc.Data and desc.Data.Type == RoomType.ROOM_DEFAULT then
            source = desc.SafeGridIndex
            break
        end
    end
    assert(source)
end
local function checkBlue(t)
    if not source then
        bluePlan()
    end
    actor(1, function(_, room)
        local at = Game():GetLevel():GetCurrentRoomIndex()
        if t == 1600 then
            assert(at == GridRooms.ROOM_BLUE_ROOM_IDX, "Locked door skipped the Blue Key corridor")
            doorTo(room, source)
            doorTo(room, treasure)
            assert(
                Game():GetLevel():GetRoomByIdx(treasure).Flags & RoomDescriptor.FLAG_BLUE_REDIRECT
                    == 0,
                "Source door retained its Blue Key redirect"
            )
        elseif t == 1740 then
            assert(at == treasure, "Opposite Blue Key exit did not reach the treasure room")
        elseif t == 1990 then
            assert(at == treasure, "Revisiting without Blue Key entered a stale corridor")
        end
        blueChecks = blueChecks + 1
        report("BLUE tick=" .. t .. " room=" .. at)
    end)
end
local function skeleton(hold)
    actor(1, function(p, room)
        clear(room)
        local soul = assert(p:GetOtherTwin())
        if hold then
            p.Position, p.Velocity = room:GetCenterPos(), Vector.Zero
            soul.Position, soul.Velocity = p.Position + Vector(16, 0), Vector.Zero
            if native.actor_held_entity(soul:GetSprite()) == -1 then
                assert(soul:TryHoldEntity(p), "Could not carry the skeleton")
            end
        else
            assert(soul:ThrowHeldEntity(Vector(-12, 0)), "Could not throw the skeleton")
        end
    end)
end
local function checkHeld(expected)
    actor(1, function(p)
        local soul = assert(p:GetOtherTwin())
        assert(
            native.actor_held_entity(soul:GetSprite()) == (expected and p.Index or -1),
            "Split-room skeleton holding link differs from authority"
        )
        assert(not p:IsDead() and soul.Visible, "Split-room skeleton or soul disappeared")
        heldChecks = heldChecks + 1
    end)
end
Isaac.AddCallback({ Name = "Item feedback regression" }, ModCallbacks.MC_ENTITY_TAKE_DMG, function()
    if host then
        return false
    end
end, EntityType.ENTITY_PLAYER)
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
    local status = frame()
    if status.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == Phase.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if status.phase == Phase.failed then
        Isaac.DebugString("LAN_NETWORK FAILED " .. status.error)
    end
    if status.verified >= 2500 and not finished then
        assert(
            resourceChecks >= 6 and orderChecks >= 5 and heldChecks >= 4 and blueChecks == 3,
            "Missing item observations"
        )
        assert(host or snapshots > 500, "Missing replica observations")
        finished = true
        report(
            "PASS soul resources, selected/replaced passive, Blue Key exits and split-room holding"
        )
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local previousMask, inputWindow, inputRoom = 0, nil, nil
    local function captureInput()
        if host then
            return input.neutral
        end
        local t, mask = _IsaacLanStatus().verified, 0
        if (t >= 610 and t < 613) or (t >= 640 and t < 643) or (t >= 670 and t < 673) then
            mask = 1 << ButtonAction.ACTION_DROP
        end
        local window = (t > 1450 and t < 1510) and 1
            or (t > 1650 and t < 1710) and 2
            or (t > 1850 and t < 1910) and 3
        if window then
            actor(1, function(p, room)
                local at = Game():GetLevel():GetCurrentRoomIndex()
                if inputWindow ~= window then
                    inputWindow, inputRoom = window, at
                end
                if at ~= inputRoom then
                    return
                end
                local door, distance
                for slot = 0, 7 do
                    local candidate = room:GetDoor(slot)
                    if candidate then
                        local d = p.Position:Distance(candidate.Position)
                        if not distance or d < distance then
                            door, distance = candidate, d
                        end
                    end
                end
                assert(door)
                local direction = (door.Position - room:GetCenterPos()):Normalized()
                mask = math.abs(direction.X) > math.abs(direction.Y)
                        and (1 << (direction.X < 0 and ButtonAction.ACTION_LEFT or ButtonAction.ACTION_RIGHT))
                    or (
                        1
                        << (direction.Y < 0 and ButtonAction.ACTION_UP or ButtonAction.ACTION_DOWN)
                    )
            end)
        end
        local result = input.buttons(mask, mask & ~previousMask)
        previousMask = mask
        return result
    end
    local samples = {}
    local function sample(t)
        local function once(at, fn, value)
            if t >= at and t <= at + 5 and not samples[at] then
                if value == nil then
                    value = at
                end
                fn(value)
                samples[at] = true
            end
        end
        for _, at in ipairs({ 120, 160, 240, 360, 400, 480 }) do
            once(at, resources)
        end
        for _, at in ipairs({ 580, 620, 650, 680, 810, 850, 1300 }) do
            once(at, checkOrder)
        end
        for _, at in ipairs({ 1600, 1740, 1990 }) do
            once(at, checkBlue)
        end
        for _, at in ipairs({ 2090, 2230, 2330, 2450 }) do
            once(at, checkHeld, true)
        end
        -- Observe the released body before a normal door crossing can make
        -- the soul carry it again on arrival.
        once(2125, checkHeld, false)
    end
    return gate(
        captureInput,
        function(t, n, buttons)
            before(t, n, buttons)
            if not host then
                return
            end
            if t == 20 then
                origin = Game():GetLevel():GetCurrentRoomIndex()
                for i = 0, Game():GetLevel():GetRooms().Size - 1 do
                    local desc = Game():GetLevel():GetRooms():Get(i)
                    if desc.Data.Type == RoomType.ROOM_DEFAULT and desc.SafeGridIndex ~= origin then
                        other = desc.SafeGridIndex
                        break
                    end
                end
                assert(other)
                actor(0, function(p)
                    p:AddCoins(17 - p:GetNumCoins())
                    p:AddBombs(3 - p:GetNumBombs())
                    p:AddKeys(5 - p:GetNumKeys())
                end)
            elseif t == 60 or t == 300 then
                resources()
                actor(t == 60 and 1 or 0, function(p)
                    p:UseCard(Card.CARD_SOUL_FORGOTTEN, UseFlag.USE_NOANIM)
                end)
                resources()
                report("SOUL owner=" .. (t == 60 and 1 or 0))
            elseif t == 180 then
                assert(native.rooms_move(1, other, 0, -1))
            elseif t == 420 then
                assert(native.rooms_move(0, other, 0, -1))
            elseif t == 540 then
                actor(1, function(p, room)
                    clear(room)
                    p:ChangePlayerType(PlayerType.PLAYER_ISAAC_B)
                    for _, id in ipairs(items) do
                        p:AddCollectible(id, 0, true)
                    end
                end)
            elseif t == 720 then
                actor(1, function(p, room)
                    p.Position, p.Velocity = room:GetCenterPos(), Vector.Zero
                    local pickup = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        replacement,
                        p.Position,
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    pickup.Wait, pickupSeed = 0, pickup.InitSeed
                end)
            elseif t == 900 then
                Game():GetLevel():SetStage(2, StageType.STAGETYPE_ORIGINAL)
                Game():StartStageTransition(true, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
            elseif t == 1200 then
                bluePlan()
                assert(native.rooms_move(1, source, 0, -1))
            elseif t == 1450 then
                actor(1, function(p, room)
                    clear(room)
                    p:AddTrinket(TrinketType.TRINKET_BLUE_KEY, false)
                    p:AddKeys(-p:GetNumKeys())
                    local door = approach(p, room, treasure)
                    assert(door:IsLocked(), "Blue Key precondition needs a locked door")
                end)
            elseif t == 1650 then
                actor(1, function(p, room)
                    approach(p, room, treasure)
                end)
            elseif t == 1750 then
                assert(native.rooms_move(1, source, 0, -1))
            elseif t == 1850 then
                actor(1, function(p, room)
                    assert(p:TryRemoveTrinket(TrinketType.TRINKET_BLUE_KEY))
                    approach(p, room, treasure)
                end)
            elseif t == 2020 then
                actor(1, function(p)
                    p:ChangePlayerType(PlayerType.PLAYER_THEFORGOTTEN_B)
                end)
                assert(native.rooms_move(1, source, 0, -1))
            elseif t == 2050 then
                skeleton(true)
            elseif t == 2120 then
                skeleton(false)
            elseif t == 2180 then
                skeleton(true)
            elseif t == 2260 then
                local target = native.rooms_positions()["1"].index == source and treasure or source
                assert(native.rooms_move(1, target, 0, -1))
            elseif t == 2390 then
                assert(native.rooms_move(0, native.rooms_positions()["1"].index, 0, -1))
            end
            if t > 720 and t < 790 then
                actor(1, function(p, room)
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e.InitSeed == pickupSeed then
                            if e.SubType == replacement then
                                p.Position, p.Velocity = e.Position, Vector.Zero
                            else
                                -- The pedestal is reused for the discarded item.
                                -- Leave it after the first pickup, rather than
                                -- repeatedly collecting our own replacement.
                                p.Position = room:FindFreePickupSpawnPosition(
                                    e.Position + Vector(140, 0),
                                    0,
                                    true
                                )
                                p.Velocity, pickupSeed = Vector.Zero, nil
                            end
                            break
                        end
                    end
                end)
            end
            if t >= 1600 and t <= 1630 then
                actor(1, function(_, room)
                    clear(room)
                end)
            end
            sample(t)
        end,
        collect,
        function(bytes, t, ack, between, stable)
            local result = restore(bytes, t, ack, between, stable)
            if result == false then
                return false
            end
            snapshots = snapshots + 1
            local value = schema.unpack(_IsaacLanState.decode(bytes, stable), t)
            for _, a in ipairs(value.actors) do
                local inventory = a[fields.actor.inventory]
                if inventory[fields.inventory.type] == PlayerType.PLAYER_ISAAC_B then
                    local p = Isaac.GetPlayer(a[fields.actor.index])
                    assert(
                        native.actor_inventory_order(p:GetSprite())
                            == inventory[fields.inventory.order],
                        "Replica inventory order differs from the authoritative snapshot"
                    )
                end
            end
            sample(t)
            return result
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
