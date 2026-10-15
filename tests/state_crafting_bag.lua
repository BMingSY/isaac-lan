-- Native partial bags and vanilla HUD in one LAN session.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local linked, chosen, finished, renders = false, false, false, 0
local verified, snapshots, materialsSeen, removedSeen = 0, 0, false, false
local owner = { Name = "Isolated native crafting bag HUD regression" }
local originals, afterFloor = {}, {}
local previousButtons = 0
local preserveKnife = assert(EntityFlag.FLAG_DONT_OVERWRITE)
local function report(message)
    Isaac.DebugString("LAN_NETWORK CRAFTING_BAG " .. message)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function contents(p)
    return assert(native.actor_crafting_bag(p:GetSprite()))
end
local function count(value)
    local n = 0
    for i = 1, 8 do
        if value:byte(i) ~= 0 then
            n = n + 1
        end
    end
    return n
end
local function clear()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:IsActiveEnemy(false) then
            e:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function pickup(slot, variant)
    actor(slot, function(p)
        clear()
        p.Position = Game():GetRoom():GetCenterPos() + Vector(slot == 0 and -100 or 100, 0)
        p.Velocity = Vector.Zero
        local drop = Isaac.Spawn(
            EntityType.ENTITY_PICKUP,
            variant,
            1,
            p.Position + Vector(40, 0),
            Vector.Zero,
            nil
        ):ToPickup()
        drop.Timeout = -1
        drop.Wait = 0
        drop.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
        local knife = Isaac.Spawn(EntityType.ENTITY_KNIFE, 4, 0, drop.Position, Vector.Zero, p)
            :ToKnife()
        knife.Parent = p
        knife:AddEntityFlags(preserveKnife)
        knife:GetData().lanBagPickup = EntityPtr(drop)
        report("PICKUP slot=" .. slot .. " variant=" .. variant)
    end)
end
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    verified = s.verified
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "23:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:23:23:0:0")
    end
    native.test_gamepad(0)
    if s.verified >= 900 and not finished then
        assert(
            materialsSeen and removedSeen,
            "Partial and removed bag snapshots were not both observed"
        )
        assert(Game():GetLevel():GetStage() == 2, "Floor transition did not finish")
        assert(host or snapshots > 100, "Too few replica bag snapshots")
        finished = true
        report("PASS both native partial crafting bags, separate rooms, removal and floor")
    end
    return s
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(function()
        local input, buttons = {}, 0
        for action = 0, 15 do
            local held = action == ButtonAction.ACTION_PILLCARD and verified >= 30 and verified < 33
            held = held
                or action == ButtonAction.ACTION_SHOOTRIGHT
                    and ((verified >= 40 and verified < 270) or (verified >= 350 and verified < 380) or (verified >= 600 and verified < 630))
            input[#input + 1] = string.pack(">I2", held and 65535 or 0)
            if held then
                buttons = buttons | (1 << action)
            end
        end
        input[#input + 1] = string.pack(">I2", buttons & ~previousButtons)
        previousButtons = buttons
        return table.concat(input)
    end, function(t, n, bytes)
        before(t, n, bytes)
        if t == 30 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    assert(p:GetPlayerType() == PlayerType.PLAYER_CAIN_B)
                    assert(
                        p:GetActiveItem(ActiveSlot.SLOT_POCKET)
                            == CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING
                    )
                    p:SetMinDamageCooldown(10000)
                    clear()
                end)
            end
        end
        if t == 40 then
            pickup(0, PickupVariant.PICKUP_COIN)
            pickup(1, PickupVariant.PICKUP_KEY)
        end
        if t == 280 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    originals[slot] = contents(p)
                    assert(count(originals[slot]) == 1, "Native bag did not collect its pickup")
                    assert(
                        string.unpack(">I4", originals[slot], 9) == 0,
                        "Partial bag retained a stale crafting preview"
                    )
                end)
            end
            assert(originals[0] ~= originals[1], "Two independent bags used the same fixture")
            materialsSeen = true
            report("PARTIAL_BAGS")
            Isaac.DebugString("LAN_NETWORK VISUAL_READY")
        end
        if t == 330 then
            local list = Game():GetLevel():GetRooms()
            local origin = native.rooms_positions()["0"].index
            local destination
            for i = 0, list.Size - 1 do
                local d = list:Get(i)
                if d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= origin then
                    destination = d.SafeGridIndex
                    break
                end
            end
            assert(destination and native.rooms_move(1, destination, 0, -1))
        end
        if t == 470 then
            actor(0, function(p)
                p:SetPocketActiveItem(
                    CollectibleType.COLLECTIBLE_RED_KEY,
                    ActiveSlot.SLOT_POCKET,
                    true
                )
            end)
            removedSeen = true
            report("REMOVED_BAG")
        end
        if t == 530 then
            actor(0, function(p)
                p:SetPocketActiveItem(
                    CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING,
                    ActiveSlot.SLOT_POCKET,
                    true
                )
            end)
        end
        if t == 640 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    afterFloor[slot] = contents(p)
                    assert(count(afterFloor[slot]) > 0)
                end)
            end
            actor(0, function(p)
                Game():StartStageTransition(false, 0, p)
            end)
        end
        if t == 850 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    assert(
                        contents(p) == afterFloor[slot],
                        "Floor transition changed bag materials"
                    )
                end)
            end
            report("FLOOR_BAGS")
        end
    end, function(slot, t)
        local bytes = collect(slot, t)
        if t % 30 == 0 then
            local value = _IsaacLanState.decode(bytes)
            report(
                "AUTHORITY tick="
                    .. t
                    .. " materials="
                    .. count(value[9][1][8] and value[9][1][8][1] or string.rep("\0", 12))
                    .. ","
                    .. count(value[9][2][8] and value[9][2][8][1] or string.rep("\0", 12))
            )
        end
        return bytes
    end, function(bytes, t, ack, betweenUpdates)
        if restore(bytes, t, ack, betweenUpdates) == false then
            return false
        end
        snapshots = snapshots + 1
        local value = _IsaacLanState.decode(bytes)
        local filled = 0
        for _, a in ipairs(value[9]) do
            local p = Isaac.GetPlayer(a[1])
            assert(
                contents(p) == (a[8] and a[8][1] or string.rep("\0", 12)),
                "Replica native bag differs from authoritative actor state"
            )
            local size = a[8] and count(a[8][1]) or 0
            filled = filled + (size > 0 and 1 or 0)
            if t >= 470 and t < 530 and a[2] == 1 and not a[8] then
                removedSeen = true
            end
        end
        if filled == 2 and not materialsSeen then
            materialsSeen = true
            report("PARTIAL_BAGS")
            Isaac.DebugString("LAN_NETWORK VISUAL_READY")
        end
        return true
    end, present, beginFloor)
end

-- Only owned fixture knives are placed at their pickup after animation update;
-- the ordinary collision path performs the native Player::AddPickupToBag.
Isaac.AddCallback(owner, ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, knife)
    local pointer = knife:GetData().lanBagPickup
    if host and pointer and pointer.Ref and pointer.Ref:Exists() then
        knife.Position = pointer.Ref.Position
        knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
        pointer.Ref.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
    elseif host and pointer then
        knife.Visible = false
        knife:Remove()
    end
end)
