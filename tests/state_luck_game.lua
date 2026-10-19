-- One owned native pair exercises real pedestal collisions and the challenge end.
local native, game = assert(_IsaacLan), nil
local file = assert(io.open("./lan-test-role.txt", "r"))
local host = file:read("*l") == "host"
file:close()
file = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = file:read("*l")
file:close()
local owner = { Name = "Luck challenge acceptance" }
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local function has(text)
    for _, message in ipairs(_IsaacLanChatMessages()) do
        if message.text:find(text, 1, true) then
            return true
        end
    end
    return false
end
local function winnings()
    local count = 0
    for _, message in ipairs(_IsaacLanChatMessages()) do
        if message.text:find("获得了道具", 1, true) then
            count = count + 1
        end
    end
    return count
end
local function actor(slot, callback)
    assert(native.rooms_with_player(slot, function()
        local player = Isaac.GetPlayer(0)
        assert(player.ControllerIndex == slot + 1)
        callback(player)
    end, 1))
end
local function count(slot, id)
    local result
    actor(slot, function(player)
        result = player:GetCollectibleNum(id, true)
    end)
    return result
end
local function spawn(player, id, price, options)
    local p = Isaac.Spawn(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_COLLECTIBLE,
        id,
        player.Position,
        Vector.Zero,
        nil
    ):ToPickup()
    p:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, false, true, true)
    p.Wait, p.Price, p.AutoUpdatePrice, p.OptionsPickupIndex = 0, price or 0, false, options or 0
    return p
end
local boosts = false
Isaac.AddCallback(owner, ModCallbacks.MC_EVALUATE_CACHE, function(_, player, flag)
    if boosts and flag == CacheFlag.CACHE_LUCK then
        player.Luck = player.ControllerIndex == 2 and 500 or 0
    end
end)
local frame, action = _IsaacLanFrame, _IsaacLanActionStep
local frames, linked, chosen, running, finished = 0, false, false, false, false
local step, at, pickup, option, baseline, roomIndex = "start", 0, nil, nil, 0, nil
local replacedCharge
local guestValidated, reconnecting, sawWaiting, rejoined = false, false, false, false
local function mark(nextStep)
    step, at = nextStep, native.api_info().tick
    report("LUCK " .. nextStep)
end
local function park()
    for slot = 0, 1 do
        actor(slot, function(player)
            player:SetMinDamageCooldown(10000)
            player.Velocity = Vector.Zero
        end)
    end
end
local function changeStage(target)
    actor(0, function(player)
        game:GetLevel():SetStage(target, StageType.STAGETYPE_ORIGINAL)
        game:StartStageTransition(true, 0, player)
    end)
end
local function advance()
    action()
    local info = native.api_info()
    if not host or info.ready ~= 1 or info.connected ~= 3 or finished then
        return
    end
    game = Game()
    assert(info.challenge == 1002 and game.Difficulty == Difficulty.DIFFICULTY_NORMAL)
    running = true
    park()
    for slot = 0, 1 do
        actor(slot, function(player)
            assert(player:HasTrinket(TrinketType.TRINKET_NO), "Starting No! effect missing")
            for held = 0, 1 do
                assert(
                    player:GetTrinket(held) ~= TrinketType.TRINKET_NO,
                    "Starting No! occupies a trinket slot"
                )
            end
        end)
    end
    local elapsed = info.tick - at
    assert(elapsed < (step == "finish" and 450 or 1800), "Luck fixture stalled: " .. step)
    if step == "start" then
        boosts = true
        for slot = 0, 1 do
            actor(slot, function(player)
                player:AddCacheFlags(CacheFlag.CACHE_LUCK)
                player:EvaluateItems()
                player.Position = Vector(120 + slot * 300, 180)
            end)
        end
        actor(0, function(player)
            pickup = spawn(player, CollectibleType.COLLECTIBLE_SAD_ONION)
        end)
        mark("passive")
    elseif step == "passive" and elapsed > 90 then
        assert(count(0, 1) == 0 and count(1, 1) == 1, "Passive winner differs from luck scores")
        assert(winnings() == 1 and has("1P掷出 D100") and has("2P掷出 D100"))
        assert(has("拾取到了野生的") and has("+500="))
        for _, message in ipairs(_IsaacLanChatMessages()) do
            report("CHAT " .. message.text)
        end
        report("LUCK PASS passive and party chat")
        actor(0, function(player)
            player:AddCoins(-player:GetNumCoins())
            player:FlushQueueItem()
            pickup = spawn(player, CollectibleType.COLLECTIBLE_SPOON_BENDER, 15, 55)
            option = spawn(player, CollectibleType.COLLECTIBLE_INNER_EYE, 0, 55)
            option.Position = Vector(320, 220)
        end)
        baseline = winnings()
        mark("unaffordable")
    elseif step == "unaffordable" and elapsed > 60 then
        assert(winnings() == baseline and pickup:Exists(), "Unaffordable contact rolled dice")
        actor(0, function(player)
            player:AddCoins(15)
        end)
        mark("purchase")
    elseif step == "purchase" and elapsed > 90 then
        assert(winnings() == baseline + 1 and count(1, 3) == 1)
        assert(not option:Exists(), "Unchosen option survived the purchase")
        actor(0, function(player)
            assert(player:GetNumCoins() == 0)
        end)
        report("LUCK PASS native purchase and options")
        actor(0, function(player)
            player:FlushQueueItem()
            pickup = spawn(player, CollectibleType.COLLECTIBLE_D6)
            pickup.Charge = 4
        end)
        baseline = winnings()
        mark("active")
    elseif step == "active" and elapsed > 90 then
        assert(winnings() == baseline, "Active pickup rolled dice")
        actor(0, function(player)
            assert(
                player:GetActiveItem() == CollectibleType.COLLECTIBLE_D6
                    and player:GetActiveCharge() == 4,
                "Native active pickup lost its charge"
            )
        end)
        report("LUCK PASS active bypass and swallowed No!")
        actor(1, function(player)
            player:AddCollectible(CollectibleType.COLLECTIBLE_D6, 4, false)
        end)
        actor(0, function(player)
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_PICKUP then
                    entity:Remove()
                end
            end
            game:GetRoom():SetClear(false)
            Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, Vector(320, 240), Vector.Zero, nil)
            player.Position = Vector(120, 180)
        end)
        mark("combat")
    elseif step == "combat" and elapsed > 30 then
        actor(0, function(player)
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity:IsActiveEnemy(false) then
                    entity:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(player), 0)
                end
            end
        end)
        mark("pill")
    elseif step == "pill" and elapsed > 90 then
        actor(0, function(player)
            local found = 0
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if
                    entity.Type == EntityType.ENTITY_PICKUP
                    and entity.Variant == PickupVariant.PICKUP_PILL
                then
                    local p = entity:ToPickup()
                    if
                        game:GetItemPool():GetPillEffect(p.SubType) == PillEffect.PILLEFFECT_LUCK_UP
                    then
                        found = found + 1
                        assert(p.Price == 0 and p.OptionsPickupIndex == 0)
                    end
                end
            end
            assert(found == 1, "Clear did not drop exactly one extra Luck Up pill")
            local config = Isaac.GetItemConfig()
            for id = 1, config:GetCollectibles().Size - 1 do
                while player:GetCollectibleNum(id, true) > 0 do
                    player:RemoveCollectible(id, true)
                end
            end
            player:AddCollectible(CollectibleType.COLLECTIBLE_INNER_EYE, 0, false)
        end)
        report("LUCK PASS clear pill")
        changeStage(LevelStage.STAGE1_2)
        mark("floor")
    elseif
        step == "floor"
        and game:GetLevel():GetStage() == LevelStage.STAGE1_2
        and elapsed > 180
    then
        assert(
            count(0, 2) == 0 and count(1, 2) == 1,
            "Floor donation did not move the loser's item"
        )
        assert(has("将") and has("交给了 P2"))
        report("LUCK PASS floor donation")
        _IsaacLanChatOutput("LUCK_FIXTURE_RECONNECT", { audience = "party" })
        mark("reconnect")
    elseif step == "reconnect" and has("LUCK_FIXTURE_REJOINED") and elapsed > 120 then
        local positions = native.rooms_positions()
        local rooms = game:GetLevel():GetRooms()
        for i = 0, rooms.Size - 1 do
            local descriptor = rooms:Get(i)
            if
                descriptor.SafeGridIndex ~= positions["0"].index
                and descriptor.Data
                and descriptor.Data.Type == RoomType.ROOM_DEFAULT
            then
                roomIndex = descriptor.SafeGridIndex
                break
            end
        end
        assert(roomIndex and native.rooms_move(1, roomIndex, 0, -1))
        mark("split")
    elseif step == "split" and elapsed > 90 then
        assert(native.rooms_positions()["1"].index == roomIndex)
        baseline = count(1, 1)
        actor(0, function(player)
            player:FlushQueueItem()
            pickup = spawn(player, 1)
        end)
        mark("remote-pickup")
    elseif step == "remote-pickup" and elapsed > 90 then
        assert(count(0, 1) == 0 and count(1, 1) == baseline + 1)
        assert(native.rooms_positions()["1"].index == roomIndex)
        report("LUCK PASS split-room recipient")
        actor(0, function(player)
            player:AddCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL, 2, false)
        end)
        actor(1, function(player)
            replacedCharge = player:GetActiveCharge()
        end)
        baseline = winnings()
        changeStage(LevelStage.STAGE2_1)
        mark("active-floor")
    elseif
        step == "active-floor"
        and game:GetLevel():GetStage() == LevelStage.STAGE2_1
        and elapsed > 180
    then
        actor(0, function(player)
            assert(player:GetActiveItem() == 0, "Donor retained the transferred active")
        end)
        actor(1, function(player)
            assert(
                player:GetActiveItem() == CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL
                    and player:GetActiveCharge() == 2,
                "Floor transfer lost the active or its charge"
            )
            local dropped = Isaac.FindByType(
                EntityType.ENTITY_PICKUP,
                PickupVariant.PICKUP_COLLECTIBLE,
                CollectibleType.COLLECTIBLE_D6
            )
            assert(
                #dropped == 1 and dropped[1]:ToPickup().Charge == replacedCharge,
                "Replaced active was not preserved on its pedestal"
            )
        end)
        assert(winnings() == baseline, "Floor transfer recursively rolled a pickup")
        report("LUCK PASS active transfer and replacement")
        changeStage(LevelStage.STAGE3_2)
        mark("mom-floor")
    elseif
        step == "mom-floor"
        and game:GetLevel():GetStage() == LevelStage.STAGE3_2
        and elapsed > 180
    then
        local rooms = game:GetLevel():GetRooms()
        roomIndex = nil
        for i = 0, rooms.Size - 1 do
            local descriptor = rooms:Get(i)
            if descriptor.Data and descriptor.Data.Type == RoomType.ROOM_BOSS then
                for j = 0, descriptor.Data.SpawnCount - 1 do
                    local entry = descriptor.Data.Spawns:Get(j)
                    for k = 0, entry.EntryCount - 1 do
                        if entry.Entries:Get(k).Type == EntityType.ENTITY_MOM then
                            roomIndex = descriptor.SafeGridIndex
                        end
                    end
                end
            end
        end
        assert(roomIndex, "Native Mom room missing")
        assert(native.rooms_move(0, roomIndex, 0, -1) and native.rooms_move(1, roomIndex, 0, -1))
        mark("mom")
    elseif step == "mom" and elapsed > 90 then
        actor(0, function(player)
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity:IsActiveEnemy(false) then
                    entity:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(player), 0)
                end
            end
        end)
        actor(0, function()
            if game:GetRoom():IsClear() then
                mark("trophy")
            end
        end)
    elseif step == "trophy" and elapsed > 150 then
        actor(1, function(player)
            local trophy
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if
                    entity.Type == EntityType.ENTITY_PICKUP
                    and entity.Variant == PickupVariant.PICKUP_TROPHY
                then
                    assert(not trophy, "Duplicate challenge trophy")
                    trophy = entity:ToPickup()
                end
            end
            assert(trophy, "Mom clear did not create the challenge trophy")
            for index = 0, game:GetRoom():GetGridSize() - 1 do
                local grid = game:GetRoom():GetGridEntity(index)
                assert(
                    not grid
                        or (
                            grid:GetType() ~= GridEntityType.GRID_TRAPDOOR
                            and grid:GetType() ~= GridEntityType.GRID_STAIRS
                        ),
                    "Endpoint still has a floor exit"
                )
            end
            trophy.Wait = 0
            player.Position = trophy.Position
        end)
        report("LUCK PASS Mom trophy and endpoint exits")
        mark("finish")
    end
end
function _IsaacLanActionStep()
    local ok, message = pcall(advance)
    if not ok then
        report("FAILED " .. tostring(message))
        error(message)
    end
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
    if not running and status.phase == 2 then
        if host and status.challenge ~= 1002 then
            _IsaacLanCommand("challenge", "1002")
        end
        if status.challenge == 1002 and not chosen then
            chosen = true
            _IsaacLanCommand("choose", "0:1")
        end
        if host and status.players == 2 and status.ready0 == 1 and status.ready1 == 1 then
            _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
        end
    end
    local info = native.api_info()
    if info.active == 1 and info.ready == 1 then
        running = true
        game = Game()
        assert(info.challenge == 1002 and game.Difficulty == Difficulty.DIFFICULTY_NORMAL)
        if not host then
            if has("LUCK_FIXTURE_RECONNECT") and not reconnecting then
                assert(count(1, 1) == 1 and count(1, 2) == 1 and count(1, 3) == 1)
                actor(1, function(player)
                    assert(player:HasTrinket(TrinketType.TRINKET_NO))
                end)
                guestValidated, reconnecting = true, true
                _IsaacLanCommand("reconnect")
            elseif reconnecting and sawWaiting and not rejoined then
                assert(count(1, 1) == 1 and count(1, 2) == 1 and count(1, 3) == 1)
                actor(1, function(player)
                    assert(player:HasTrinket(TrinketType.TRINKET_NO))
                end)
                rejoined = true
                _IsaacLanChatSubmit("LUCK_FIXTURE_REJOINED")
                report("LUCK PASS replica inventory, chat and reconnect")
            end
        end
    elseif reconnecting and not rejoined then
        sawWaiting = true
    end
    if running and not finished and info.active ~= 1 and status.phase == 2 then
        assert(host and step == "finish" or not host and guestValidated and rejoined)
        finished = true
        report("PASS luck game")
    end
    return status
end
