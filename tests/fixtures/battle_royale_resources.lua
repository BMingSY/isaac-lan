-- Native resource acceptance, composed into the same protected process pair.
return function(env)
    local native, actor, report = env.native, env.actor, env.report
    local types =
        { RoomType.ROOM_TREASURE, RoomType.ROOM_SHOP, RoomType.ROOM_LIBRARY, RoomType.ROOM_ARCADE }
    local targets = { 16, 8, 4, 4 }
    local stage, number, selected, source, since, controls, price, purchased, currency
    local replica = {}
    local function mark(value)
        stage, since = value, Game():GetFrameCount()
    end
    local function map(state, spawns)
        local level, totals, first = Game():GetLevel(), {}, {}
        local bounds = env.rules.bounds(state.zones, 2)
        for index = 0, level:GetRooms().Size - 1 do
            local desc = level:GetRooms():Get(index)
            local kind, cell = desc.Data.Type, desc.SafeGridIndex
            if cell >= 0 then
                totals[kind] = (totals[kind] or 0) + 1
                if
                    cell % 13 >= bounds.left
                    and cell % 13 <= bounds.right
                    and cell // 13 >= bounds.top
                    and cell // 13 <= bounds.bottom
                then
                    first[kind] = (first[kind] or 0) + 1
                end
            end
        end
        for index, kind in ipairs(types) do
            report(
                "BATTLE resource type="
                    .. kind
                    .. " total="
                    .. (totals[kind] or 0)
                    .. " first="
                    .. (first[kind] or 0)
            )
            assert(
                (totals[kind] or 0) >= targets[index] and (first[kind] or 0) >= targets[index] // 2,
                "Special-room quota missing"
            )
        end
        for _, start in pairs(spawns) do
            local queue, seen, found = { { start.index, 0 } }, { [start.index] = true }, false
            local head = 1
            while head <= #queue do
                local index, depth = table.unpack(queue[head])
                head = head + 1
                local kind = level:GetRoomByIdx(index, 0).Data.Type
                if kind == RoomType.ROOM_TREASURE then
                    found = true
                    break
                end
                if depth < 3 then
                    for _, target in ipairs(native.room_connections(index)) do
                        if target >= 0 and not seen[target] then
                            local nextKind = level:GetRoomByIdx(target, 0).Data.Type
                            if
                                nextKind == RoomType.ROOM_DEFAULT
                                or nextKind == RoomType.ROOM_TREASURE
                                or nextKind == RoomType.ROOM_SHOP
                            then
                                seen[target] = true
                                queue[#queue + 1] = { target, depth + 1 }
                            end
                        end
                    end
                end
            end
            assert(found, "Spawn lacks a reachable treasure room within three steps")
        end
        report("BATTLE PASS native resource quotas, first circle and nearby treasures")
    end
    local function auditRewards()
        actor(0, function(player)
            local pool, pools, draws, seed = Game():GetItemPool(), {}, 0, 1907
            local fake = {
                Type = EntityType.ENTITY_PICKUP,
                Variant = PickupVariant.PICKUP_COLLECTIBLE,
                InitSeed = 1,
                SubType = CollectibleType.COLLECTIBLE_SYNTHOIL,
            }
            function fake:ToPickup()
                return self
            end
            function fake:Morph(_, _, item)
                self.SubType = item
            end
            local proxy = {
                GetCollectible = function(_, kind, decrease, value, fallback)
                    -- Exercise native Chaos selection without draining this run's
                    -- pools during the sample audit. Production still commits draws.
                    local item = pool:GetCollectible(kind, false, value, fallback)
                    if decrease then
                        pools[pool:GetLastPool()] = true
                        draws = draws + 1
                    end
                    return item
                end,
            }
            local settle = _IsaacLanModules["compat/challenges/battle_royale_rewards"]({
                enums = {
                    collectible = CollectibleType,
                    pool = ItemPoolType,
                    entity = EntityType,
                    pickup = PickupVariant,
                },
                game = function()
                    return {
                        GetItemPool = function()
                            return proxy
                        end,
                    }
                end,
                config = Isaac.GetItemConfig,
                entities = function()
                    return { fake }
                end,
                random = function()
                    seed = (seed * 48271) % 2147483647
                    return seed
                end,
            })
            local before = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_CHAOS)
            for _ = 1, 24 do
                settle(player)
                assert(Isaac.GetItemConfig():GetCollectible(fake.SubType).Quality >= 3)
                assert(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_CHAOS) == before)
            end
            local ids = {}
            for id in pairs(pools) do
                ids[#ids + 1] = id
            end
            table.sort(ids)
            report("BATTLE Chaos pools=" .. table.concat(ids, ",") .. " draws=" .. draws)
            assert(#ids >= 3, "Reward sampling did not use native Chaos pools")
            report("BATTLE PASS native cross-pool quality rewards and Chaos cleanup")
        end)
    end
    local function nextCase()
        number = (number or 0) + 1
        if not types[number] then
            native.api_move(0, env.rules.center, 0)
            native.api_move(1, env.rules.center, 0)
            stage = "done"
            return
        end
        local level = Game():GetLevel()
        selected, source = nil, nil
        for index = 0, level:GetRooms().Size - 1 do
            local desc = level:GetRooms():Get(index)
            if desc.SafeGridIndex >= 0 and desc.Data.Type == types[number] then
                if number > 2 then
                    selected = desc.SafeGridIndex
                    break
                end
                for _, neighbor in ipairs(native.room_connections(desc.SafeGridIndex)) do
                    local adjacent = neighbor >= 0 and level:GetRoomByIdx(neighbor, 0)
                    if adjacent and adjacent.Data.Type == RoomType.ROOM_DEFAULT then
                        selected, source = desc.SafeGridIndex, neighbor
                        break
                    end
                end
                if selected then
                    break
                end
            end
        end
        assert(selected, "Missing reachable resource sample")
        assert(native.api_move(0, source or selected, 0))
        mark("arrive")
    end
    local function step()
        if stage == "done" then
            return true
        end
        local elapsed = Game():GetFrameCount() - since
        assert(elapsed < 300, "Resource scene stalled: " .. stage)
        local position = native.rooms_positions()["0"]
        if stage == "arrive" and position.index == (source or selected) and elapsed > 30 then
            if not source then
                assert(native.api_move(1, selected, 0))
                mark("inspect")
                return
            end
            actor(0, function(player)
                player:AddKeys(-player:GetNumKeys())
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity:IsEnemy() then
                        entity:Remove()
                    end
                end
                Game():GetRoom():SetClear(true)
            end)
            mark("door")
        elseif stage == "door" and elapsed > 15 then
            actor(0, function(player)
                local inward = { Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) }
                for slot = 0, 7 do
                    local door = Game():GetRoom():GetDoor(slot)
                    if door and door.TargetRoomIndex == selected then
                        assert(
                            not door:IsLocked() and door:IsOpen(),
                            "Resource entrance requires a key"
                        )
                        player.Position = door.Position + inward[slot % 4 + 1] * 35
                        player.Velocity = Vector.Zero
                        controls = inward[slot % 4 + 1] * -32767
                        break
                    end
                end
                assert(controls, "Resource door missing")
            end)
            mark("walk")
        elseif stage == "walk" and position.index == selected then
            controls = nil
            actor(0, function(player)
                assert(player:GetNumKeys() == 0)
            end)
            assert(native.api_move(1, selected, 0))
            report("BATTLE PASS zero-key native entry type=" .. types[number])
            mark("inspect")
        elseif stage == "inspect" and elapsed > 75 then
            actor(0, function(player)
                local room = Game():GetRoom()
                assert(room:GetType() == types[number])
                local contents, paid = 0, nil
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity.Type == EntityType.ENTITY_PICKUP then
                        local p = entity:ToPickup()
                        if p.Variant == PickupVariant.PICKUP_COLLECTIBLE then
                            contents = contents + 1
                        end
                        if
                            p.Price > 0
                            and (
                                p.Variant == PickupVariant.PICKUP_KEY
                                or p.Variant == PickupVariant.PICKUP_BOMB
                            )
                        then
                            paid = p
                        end
                    elseif entity.Type == EntityType.ENTITY_SLOT then
                        contents = contents + 1
                    end
                end
                if number == 2 then
                    assert(paid, "Shop has no paid resource pickup")
                    currency = {
                        coins = player:GetNumCoins(),
                        keys = player:GetNumKeys(),
                        bombs = player:GetNumBombs(),
                    }
                    player:AddCoins(-player:GetNumCoins())
                    purchased, price = paid.InitSeed, paid.Price
                    player.Position = paid.Position
                    mark("unpaid")
                else
                    assert(contents > 0, "Native resource room has no contents")
                end
            end)
            if stage ~= "unpaid" then
                nextCase()
            end
        elseif stage == "unpaid" and elapsed > 30 then
            actor(0, function(player)
                local found
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity.InitSeed == purchased then
                        found = entity
                    end
                end
                assert(found and player:GetNumCoins() == 0, "Free entry also made shop goods free")
                player:AddCoins(price)
                player.Position = found.Position
            end)
            mark("buy")
        elseif stage == "buy" and elapsed > 45 then
            actor(0, function(player)
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    assert(entity.InitSeed ~= purchased, "Paid shop purchase failed")
                end
                assert(player:GetNumCoins() == 0, "Shop charged the wrong price")
                player:AddCoins(currency.coins)
                player:AddKeys(currency.keys - player:GetNumKeys())
                player:AddBombs(currency.bombs - player:GetNumBombs())
            end)
            report("BATTLE PASS shop prices, affordability and normal purchase")
            nextCase()
        end
    end
    return {
        map = map,
        start = function()
            auditRewards()
            nextCase()
        end,
        step = step,
        input = function()
            return controls and controls.X or 0, controls and -controls.Y or 0
        end,
        observe = function()
            local room = Game():GetRoom()
            local kind = room:GetType()
            for _, expected in ipairs(types) do
                if kind == expected and not replica[kind] then
                    replica[kind] = true
                    report("BATTLE PASS replica resource room type=" .. kind)
                end
            end
        end,
        checked = function()
            for _, kind in ipairs(types) do
                if not replica[kind] then
                    return false
                end
            end
            return true
        end,
    }
end
