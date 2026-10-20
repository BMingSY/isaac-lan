-- Concentrated native acceptance. All phases share one pair and connection.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local linked, chosen, finished, renders = false, false, false, 0
local step, stepAt, desiredFamiliars, snapshots = "prepare", 0, 0, 0
local lastPopulation = 0
local origin, shop, selected, pillColor, pocketBytes, certificateOrigin, certificateExplore
local expectedShopPrice, restockPosition, purchase, purchaseCoins, purchaseHearts
local purchaseSeed, purchaseShopId
local devilCoins, devilHearts, devilPosition
local function report(message)
    Isaac.DebugString("LAN_NETWORK PARTY_COMPAT " .. message)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function mark(nextStep, tick)
    step, stepAt = nextStep, tick
    report("STEP " .. step .. " tick=" .. tick)
end
local function location(slot)
    return assert(native.rooms_positions()[tostring(slot)])
end
local function clearRoom()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) then
            entity:Remove()
        end
    end
end
local function move(slot, index, dimension)
    assert(native.rooms_move(slot, index, dimension or 0, -1))
end
local function familiarCount()
    local count = 0
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_FAMILIAR then
            count = count + 1
        end
    end
    return count
end
local function liveFamiliars()
    local count, seen = 0, {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_FAMILIAR and entity:Exists() then
            local key = GetPtrHash(entity)
            if not seen[key] then
                seen[key], count = true, count + 1
            end
        end
    end
    return count
end
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "localhost:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", host and "0:1" or "33:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:33:0:0")
    end
    native.test_gamepad(0)
    return s
end
local function advance(t)
    local level = Game():GetLevel()
    if step == "prepare" and t >= 30 then
        origin = location(0).index
        level:RemoveCurses(level:GetCurses())
        for i = 0, level:GetRooms().Size - 1 do
            local d = level:GetRooms():Get(i)
            if d.Data and d.Data.Type == RoomType.ROOM_SHOP then
                shop = d.SafeGridIndex
                assert(
                    d.Data.Subtype >= 100,
                    "Remote Tainted Keeper did not upgrade the first-floor shop"
                )
                report("SHOP subtype=" .. d.Data.Subtype)
            end
        end
        assert(shop, "Fixture seed has no shop")
        for slot = 0, 1 do
            actor(slot, function(p)
                p:SetMinDamageCooldown(10000)
                p:AddCoins(99)
                clearRoom()
                p.Position = Game():GetRoom():GetCenterPos() + Vector(slot * 80, 0)
            end)
        end
        mark("familiars64", t)
    elseif step:match("^familiars") then
        local target = tonumber(step:match("(%d+)$"))
        if t == stepAt + 1 then
            actor(1, function(p)
                for _ = p:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, true) + 1, target do
                    p:AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, 0, false)
                end
                p:CheckFamiliar(
                    FamiliarVariant.BROTHER_BOBBY,
                    target,
                    p:GetCollectibleRNG(CollectibleType.COLLECTIBLE_BROTHER_BOBBY),
                    Isaac.GetItemConfig():GetCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
                )
                desiredFamiliars = target
            end)
        end
        if t - stepAt >= 100 then
            actor(1, function()
                -- Vanilla's factory keeps 64 live slots. Request larger
                -- populations to exercise replacement, preserving that rule.
                assert(
                    liveFamiliars() == math.min(target, 64),
                    "Unexpected native familiar population"
                )
                report(
                    "FAMILIARS requested="
                        .. target
                        .. " count="
                        .. familiarCount()
                        .. " unique="
                        .. liveFamiliars()
                        .. " connected="
                        .. native.rooms_connected()
                )
            end)
            assert(native.rooms_connected() == 3, "Familiar stress disconnected the guest")
            mark(
                target == 64 and "familiars65" or target == 65 and "familiars128" or "inventory",
                t
            )
        end
    elseif step == "inventory" then
        actor(1, function(p)
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
            while p:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, true) > 0 do
                p:RemoveCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
            end
            p:CheckFamiliar(
                FamiliarVariant.BROTHER_BOBBY,
                0,
                p:GetCollectibleRNG(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
            )
            p:AddCollectible(CollectibleType.COLLECTIBLE_SCHOOLBAG, 0, false)
            p:AddCollectible(CollectibleType.COLLECTIBLE_D6, 6, false, ActiveSlot.SLOT_PRIMARY)
            p:AddCollectible(
                CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL,
                3,
                false,
                ActiveSlot.SLOT_SECONDARY
            )
            p:SetPocketActiveItem(CollectibleType.COLLECTIBLE_RED_KEY, ActiveSlot.SLOT_POCKET, true)
            p:SetCard(1, Card.CARD_FOOL)
            pocketBytes = native.actor_pockets(p:GetSprite())
            pillColor = Game():GetItemPool():ForceAddPillEffect(PillEffect.PILLEFFECT_BAD_GAS)
            p:UsePill(PillEffect.PILLEFFECT_BAD_GAS, pillColor, UseFlag.USE_NOANIM)
            Game():GetItemPool():IdentifyPill(pillColor)
        end)
        desiredFamiliars = 0
        move(0, shop)
        mark("shared-items", t)
    elseif step == "shared-items" and t - stepAt >= 90 then
        actor(1, function(p)
            for _, id in ipairs({
                CollectibleType.COLLECTIBLE_RESTOCK,
                CollectibleType.COLLECTIBLE_STEAM_SALE,
                CollectibleType.COLLECTIBLE_TREASURE_MAP,
                CollectibleType.COLLECTIBLE_BLUE_MAP,
                CollectibleType.COLLECTIBLE_COMPASS,
            }) do
                p:AddCollectible(id, 0, false)
            end
        end)
        actor(0, function(p)
            clearRoom()
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                local pickup = e:ToPickup()
                if
                    pickup
                    and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
                    and pickup.SubType > 0
                    and pickup.ShopItemId >= 0
                    and pickup.Price > 0
                then
                    purchase = EntityPtr(pickup)
                    purchaseSeed, purchaseShopId = pickup.InitSeed, pickup.ShopItemId
                    pickup.AutoUpdatePrice, pickup.Price = true, 15
                    p.Position = pickup.Position + Vector(0, 80)
                    report("SHOP_STOCK id=" .. purchaseShopId .. " seed=" .. purchaseSeed)
                    break
                end
            end
            assert(purchase, "Native shop has no paid collectible")
        end)
        mark("shop-discount", t)
    elseif step == "shop-discount" and t - stepAt >= 90 then
        local revealed = 0
        for i = 0, level:GetRooms().Size - 1 do
            local d = level:GetRooms():Get(i)
            if d.Data and d.SafeGridIndex >= 0 then
                if d.Data.Type == RoomType.ROOM_DEFAULT then
                    assert(
                        d.DisplayFlags & 1 ~= 0,
                        "Shared Treasure Map left an ordinary room hidden"
                    )
                    revealed = revealed + 1
                elseif
                    d.Data.Type == RoomType.ROOM_SECRET
                    or d.Data.Type == RoomType.ROOM_SUPERSECRET
                then
                    assert(
                        d.DisplayFlags & 4 ~= 0,
                        "Shared Blue Map left a secret room icon hidden"
                    )
                elseif
                    d.Data.Type == RoomType.ROOM_BOSS or d.Data.Type == RoomType.ROOM_TREASURE
                then
                    assert(
                        d.DisplayFlags & 4 ~= 0,
                        "Shared Compass left a special room icon hidden"
                    )
                end
            end
        end
        assert(revealed > 3)
        report("MAP ordinary, secret and special-room visibility shared")
        actor(0, function(p)
            local pickup = assert(purchase.Ref):ToPickup()
            assert(
                pickup.Price > 0 and pickup.Price < 15,
                "Split-room Steam Sale did not discount the shop"
            )
            expectedShopPrice, restockPosition, purchaseCoins =
                pickup.Price, pickup.Position, p:GetNumCoins()
            p.Position, p.Velocity = pickup.Position - Vector(18, 0), Vector(2, 0)
            report("SHOP_PRICE price=" .. pickup.Price)
        end)
        mark("shop-restock", t)
    elseif step == "shop-restock" then
        actor(0, function(p)
            if p:GetNumCoins() == purchaseCoins then
                p.Position, p.Velocity = restockPosition - Vector(12, 0), Vector(1, 0)
            else
                p.Position, p.Velocity =
                    Game():GetRoom():GetCenterPos() + Vector(0, 100), Vector.Zero
            end
        end)
        if t - stepAt >= 90 then
            actor(0, function(p)
                assert(p:GetNumCoins() < purchaseCoins, "Native shop purchase did not charge coins")
                local replacement = false
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    local pickup = entity:ToPickup()
                    replacement = replacement
                        or pickup
                            and pickup.ShopItemId == purchaseShopId
                            and pickup.InitSeed ~= purchaseSeed
                end
                assert(replacement, "Split-room Restock did not replace the bought item")
            end)
            actor(0, function()
                Game():GetRoom():TrySpawnDevilRoomDoor(true, true)
                assert(
                    Game():GetLevel():GetRoomByIdx(GridRooms.ROOM_DEVIL_IDX).Data,
                    "Cannot initialize native Devil room"
                )
            end)
            move(0, GridRooms.ROOM_DEVIL_IDX)
            move(1, GridRooms.ROOM_DEVIL_IDX)
            mark("devil-keeper", t)
        end
    elseif step == "devil-keeper" and t - stepAt >= 90 then
        actor(0, function(p)
            p.Position, p.Velocity = Game():GetRoom():GetCenterPos() + Vector(-100, 0), Vector.Zero
        end)
        actor(1, function(p)
            clearRoom()
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity:ToPickup() then
                    entity:Remove()
                end
            end
            local pickup = Game():Spawn(
                EntityType.ENTITY_PICKUP,
                PickupVariant.PICKUP_COLLECTIBLE,
                Game():GetRoom():GetCenterPos(),
                Vector.Zero,
                nil,
                CollectibleType.COLLECTIBLE_BREAKFAST,
                22345
            ):ToPickup()
            pickup.ShopItemId, pickup.AutoUpdatePrice = 0, true
            pickup.Price = native.pickup_price(pickup:GetSprite(), p:GetSprite())
            assert(pickup.Price > 0, "Keeper Devil deal is not a coin price")
            devilPosition, devilCoins, devilHearts = pickup.Position, p:GetNumCoins(), p:GetHearts()
            p.Position, p.Velocity = pickup.Position - Vector(12, 0), Vector(1, 0)
        end)
        mark("devil-keeper-pay", t)
    elseif step == "devil-keeper-pay" or step == "devil-keeper-normal-pay" then
        actor(1, function(p)
            p.Position, p.Velocity = devilPosition - Vector(10, 0), Vector(1, 0)
        end)
        if t - stepAt >= 90 then
            actor(1, function(p)
                assert(
                    p:GetNumCoins() < devilCoins and p:GetHearts() >= devilHearts,
                    "Keeper Devil purchase did not use coins"
                )
                p.Position = devilPosition + Vector(80, 0)
            end)
            if step == "devil-keeper-pay" then
                actor(1, function(p)
                    p:ChangePlayerType(PlayerType.PLAYER_KEEPER)
                    p:AddCoins(99)
                    p:SetMinDamageCooldown(10000)
                    local pickup = Game():Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        Game():GetRoom():GetCenterPos(),
                        Vector.Zero,
                        nil,
                        CollectibleType.COLLECTIBLE_INNER_EYE,
                        42345
                    ):ToPickup()
                    pickup.ShopItemId, pickup.AutoUpdatePrice = 2, true
                    pickup.Price = native.pickup_price(pickup:GetSprite(), p:GetSprite())
                    assert(pickup.Price > 0, "Normal Keeper Devil deal is not a coin price")
                    devilPosition, devilCoins, devilHearts =
                        pickup.Position, p:GetNumCoins(), p:GetHearts()
                    p.Position, p.Velocity = pickup.Position - Vector(12, 0), Vector(1, 0)
                end)
                mark("devil-keeper-normal-pay", t)
            else
                actor(0, function(p)
                    p:AddMaxHearts(12)
                    p:AddHearts(12)
                    local pickup = Game():Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        Game():GetRoom():GetCenterPos(),
                        Vector.Zero,
                        nil,
                        CollectibleType.COLLECTIBLE_SPOON_BENDER,
                        32345
                    ):ToPickup()
                    pickup.ShopItemId, pickup.AutoUpdatePrice = 1, true
                    pickup.Price = native.pickup_price(pickup:GetSprite(), p:GetSprite())
                    assert(pickup.Price < 0, "Non-Keeper Devil deal is not a heart price")
                    devilPosition, devilCoins, devilHearts =
                        pickup.Position, p:GetNumCoins(), p:GetMaxHearts()
                    p.Position, p.Velocity = pickup.Position - Vector(12, 0), Vector(1, 0)
                end)
                mark("devil-hearts-pay", t)
            end
        end
    elseif step == "devil-hearts-pay" then
        actor(0, function(p)
            p.Position, p.Velocity = devilPosition - Vector(10, 0), Vector(1, 0)
        end)
        if t - stepAt >= 90 then
            actor(0, function(p)
                assert(
                    p:GetMaxHearts() < devilHearts and p:GetNumCoins() == devilCoins,
                    "Non-Keeper Devil purchase did not use hearts"
                )
            end)
            report("DEVIL normal/Tainted Keeper coins and non-Keeper hearts")
            move(0, origin)
            move(1, origin)
            mark("certificate-use", t)
        end
    elseif step == "certificate-use" and t - stepAt >= 60 then
        actor(1, function(p)
            p:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM)
        end)
        certificateOrigin = location(1).index
        mark("certificate-entry", t)
    elseif step == "certificate-entry" and t - stepAt >= 90 then
        assert(
            location(0).dimension == 2 and location(1).dimension == 2,
            "Death Certificate did not carry the full party"
        )
        assert(location(0).index == location(1).index, "Death Certificate entry split the party")
        local target
        actor(0, function(p)
            p.Position = Game():GetRoom():GetCenterPos() + Vector(0, 100)
            for slot = 0, 7 do
                local door = Game():GetRoom():GetDoor(slot)
                if door and door.TargetRoomIndex >= 0 then
                    target = door.TargetRoomIndex
                    break
                end
            end
        end)
        assert(target, "Death Certificate entry has no exploration door")
        certificateExplore = target
        move(1, target, 2)
        mark("certificate-split", t)
    elseif step == "certificate-split" and t - stepAt >= 90 then
        assert(
            location(0).dimension == 2
                and location(1).dimension == 2
                and location(0).index ~= location(1).index,
            "Death Certificate cannot be explored separately"
        )
        actor(1, function(p)
            p:UseCard(Card.CARD_FOOL, UseFlag.USE_NOANIM)
        end)
        mark("certificate-card", t)
    elseif step == "certificate-card" and t - stepAt >= 90 then
        assert(
            location(0).dimension == 2 and location(1).dimension == 2,
            "A teleport card escaped Death Certificate"
        )
        -- Fool can return to the annex's empty entrance. Resume exploration
        -- before selecting an actual pedestal from the next native chamber.
        move(1, certificateExplore, 2)
        mark("certificate-item", t)
    elseif step == "certificate-item" and t - stepAt >= 90 then
        actor(1, function(p)
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                local pickup = entity:ToPickup()
                if
                    pickup
                    and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
                    and pickup.SubType > 0
                then
                    selected = EntityPtr(pickup)
                    p.Position, p.Velocity = pickup.Position - Vector(12, 0), Vector(1, 0)
                    break
                end
            end
        end)
        assert(selected, "Death Certificate room contains no collectible")
        mark("certificate-pickup", t)
    elseif step == "certificate-pickup" then
        if location(1).dimension == 2 then
            actor(1, function(p)
                if selected.Ref and selected.Ref:Exists() then
                    p.Position, p.Velocity = selected.Ref.Position - Vector(10, 0), Vector(1, 0)
                end
            end)
        elseif t - stepAt >= 90 then
            assert(
                location(0).dimension == 0 and location(1).dimension == 0,
                "Only the picker returned from Death Certificate"
            )
            assert(
                location(0).index == certificateOrigin and location(1).index == certificateOrigin,
                "Death Certificate lost its return room"
            )
            report("CERTIFICATE full party enter, split, card confinement and pickup return")
            mark("done", t)
        end
    elseif step == "done" and not finished and t - stepAt >= 100 then
        finished = true
        report("PASS native party compatibility")
    end
    assert(t - stepAt < 900, "Party compatibility stalled at " .. step)
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        advance(t)
    end, function(slot, t)
        local bytes, stable = collect(slot, t)
        if not bytes then
            return bytes, stable
        end
        local unique, familiarIDs = 0, {}
        for _, v in ipairs(_IsaacLanState.decode(bytes, stable)[11][3]) do
            if v[2] == EntityType.ENTITY_FAMILIAR and not familiarIDs[v[1]] then
                familiarIDs[v[1]] = true
                unique = unique + 1
            end
        end
        if unique ~= lastPopulation then
            lastPopulation = unique
            report("AUTHORITATIVE_FAMILIARS unique=" .. unique .. " requested=" .. desiredFamiliars)
        end
        return string.pack(">s4", bytes) .. _IsaacLanState.encode({
            step,
            finished,
            desiredFamiliars,
            pillColor or 0,
            pocketBytes or "",
            unique,
        }),
            stable
    end, function(bytes, t, ack, betweenUpdates, stable)
        local body, cursor = string.unpack(">s4", bytes)
        if restore(body, t, ack, betweenUpdates, stable) == false then
            return false
        end
        local value, meta =
            _IsaacLanState.decode(body, stable), _IsaacLanState.decode(bytes:sub(cursor))
        snapshots = snapshots + 1
        if meta[3] > 0 and step == meta[1] then
            assert(liveFamiliars() >= meta[6], "Replica lost authoritative familiars above 64")
        end
        if meta[4] > 0 then
            assert(
                Game():GetItemPool():IsPillIdentified(meta[4]),
                "Replica lost pill identification"
            )
            assert(
                Game():GetItemPool():GetPillEffect(meta[4]) == PillEffect.PILLEFFECT_BAD_GAS,
                "Replica pill effect differs"
            )
        end
        if meta[5] ~= "" then
            actor(1, function(p)
                assert(
                    native.actor_pockets(p:GetSprite()) == value[9][2][4][11],
                    "Replica pocket order differs"
                )
            end)
        end
        if meta[1] ~= step then
            step = meta[1]
            report("REPLICA_STEP " .. step)
            if meta[3] > 0 then
                local missing, tags = 0, {}
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == EntityType.ENTITY_FAMILIAR then
                        local id = e:GetData().__isaac_lan_replica
                        if not id then
                            missing = missing + 1
                        end
                        tags[id or 0] = true
                    end
                end
                report("FAMILIAR_DATA missing_tags=" .. missing .. " target=" .. meta[3])
            end
        end
        if meta[2] and not finished then
            assert(snapshots > 200)
            finished = true
            report("PASS native party compatibility")
        end
        return true
    end, present, beginFloor)
end

-- Explicit test-only lifecycle consumed by both suite coordinators.
return {
    done = function()
        return finished
    end,
}
