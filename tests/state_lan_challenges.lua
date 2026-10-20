-- Embedded by run_lan_challenges.py. All cases reuse the same native processes.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local file = assert(io.open("./lan-test-role.txt", "r"))
local role = file:read("*l")
file:close()
local ordinal = assert(({ host = 0, client = 1, client2 = 2, client3 = 3 })[role])
local owner = { Name = "Concentrated LAN challenge acceptance" }
local cases = { { name = "ordinary-save", players = 2 } }
for players = 2, challengeMaxPlayers do
    cases[#cases + 1] = {
        name = (challengeHudOnly and "hud-" or "challenge-") .. players,
        players = players,
        challenge = true,
        hud = challengeHudOnly,
    }
end
if not challengeHudOnly then
    cases[#cases + 1] = { name = "challenge-exit", players = 2, challenge = true, exit = true }
end
cases[#cases + 1] = { name = "ordinary-resume", players = 2, resume = true }
local current, case = 0, nil
local linked, started, participated, menuDone, reported = false, false, false, false, false
local chosen, configured = false, false
local renders, startAt, exitedAt, lastHeartbeat = 0, 0, nil, 0
local phase, phaseAt, snapshots, wins, exits = "init", 0, 0, 0, 0
local bagBaseline, archiveBaseline, progressBaseline, targetRoom
local hourglassSource, hourglassEpoch, rkeyEpoch
local previousButtons, verified, eidChecked, ghostChecked = 0, -1, false, false
local fillStart, fillDone, pendingDrops = nil, false, {}
local lastActivation, lastSwipe = {}, {}
local hudOffsetRecorded, hudOffsetZeroed, ghostBagObserved = false, false, {}
local pocketChecked = false
local routeEpoch, routeTarget, routeTrap, sawSatan, satanChest
local floorEvents, lastReplicaEpoch = {}, nil
local sawLamb, trophy, contactAt, returned = false, nil, nil, false
local lambRoomIndex
local voidExitIndex, voidExitChecked = nil, false
local reconnectRequested, reconnectDeparted, reconnectJoined, sawDisconnected =
    false, false, false, false
local reconnectVerified = false
local reconnectSnapshot = false
local function read(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end
    local value = handle:read("*a")
    handle:close()
    return value
end
local function write(path, value)
    local handle = assert(io.open(path, "w"))
    handle:write(value)
    handle:close()
end
local function report(text)
    Isaac.DebugString(
        "LAN_NETWORK LAN_CHALLENGE case=" .. (case and case.name or "boot") .. " " .. text
    )
end
local function mark(name, tick)
    phase, phaseAt = name, tick
    report("STEP " .. name .. " tick=" .. tick .. " ms=" .. native.api_info().nowMs)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function clear()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function bags()
    local values = {}
    for slot = 0, case.players - 1 do
        actor(slot, function(player)
            values[slot + 1] = assert(native.actor_crafting_bag(player:GetSprite()))
        end)
    end
    return values
end
local function checkBags(label)
    local values = bags()
    for i, value in ipairs(values) do
        assert(value == bagBaseline[i], label .. " changed P" .. i .. " bag")
    end
    report(label .. " materials_preserved=true")
end
local function pocketValues(slot)
    if slot % 2 == 0 then
        return slot == 0 and Card.CARD_FOOL or Card.CARD_WORLD, 0
    end
    return 0, PillColor.PILL_BLUE_BLUE
end
local function checkPocket(player)
    local slot = player.ControllerIndex - 1
    local card, pill = pocketValues(slot)
    assert(
        player:GetCard(1) == card and player:GetPill(1) == pill,
        "Native card/pill pocket changed for slot " .. slot
    )
    assert(
        player:GetActiveItem(ActiveSlot.SLOT_POCKET) == CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING,
        "Card/pill fixture replaced the pocket Bag of Crafting"
    )
end
local function checkPockets(label)
    for slot = 0, case.players - 1 do
        actor(slot, checkPocket)
    end
    report(label .. " native_card_pill_preserved=true")
end
local function ordinaryResources(expectedCoins)
    local values = {}
    for slot = 0, case.players - 1 do
        actor(slot, function(player)
            local coins, bombs, keys =
                player:GetNumCoins(), player:GetNumBombs(), player:GetNumKeys()
            assert(not expectedCoins or coins == expectedCoins, "Shared coin baseline differs")
            values[#values + 1] = string.format("%d:%d:%d:%d", slot, coins, bombs, keys)
        end)
    end
    return table.concat(values, ";")
end
local function archive()
    local result = {}
    for i = 0, 3 do
        result[i] = read("./isaac-lan/session-" .. i .. ".bin")
    end
    return result
end
local function checkArchive()
    local value = archive()
    local present = false
    for i = 0, 3 do
        assert(value[i] == archiveBaseline[i], "Challenge replaced an ordinary LAN save")
        present = present or value[i] ~= nil
    end
    assert(not host or present, "Ordinary save baseline is missing")
    report("ORDINARY_ARCHIVE_PRESERVED")
end
local function checkRules()
    local info = native.api_info()
    assert(
        info.challenge == 1001 and info.challengeVersion == 2 and info.restrictedBags == 1,
        "Challenge rules were lost"
    )
    assert(Game().Challenge == 0 and Game().Difficulty == 0, "Native challenge/difficulty changed")
    assert(info.players == case.players, "Challenge roster changed")
end
local function separate(slot)
    local level, positions = Game():GetLevel(), native.rooms_positions()
    for i = 0, level:GetRooms().Size - 1 do
        local desc = level:GetRooms():Get(i)
        if
            desc.Data
            and desc.Data.Type == RoomType.ROOM_DEFAULT
            and desc.SafeGridIndex ~= positions[tostring(slot)].index
        then
            targetRoom = desc.SafeGridIndex
            assert(native.rooms_move(slot, targetRoom, 0, -1))
            return
        end
    end
    error("Fixture floor has no separate default room")
end
local function prepareLamb(t)
    for slot = 0, case.players - 1 do
        actor(slot, function(player)
            if not player:HasCollectible(CollectibleType.COLLECTIBLE_NEGATIVE) then
                player:AddCollectible(CollectibleType.COLLECTIBLE_NEGATIVE)
            end
        end)
    end
    sawSatan, satanChest = false, nil
    report("LAMB_SETUP fixture=native-trapdoors negative=fixture satan_chest=native")
    mark("native-route-ready", t)
end
local function bossRoom(kind)
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc.Data and desc.Data.Type == RoomType.ROOM_BOSS then
            for j = 0, desc.Data.SpawnCount - 1 do
                local spawn = desc.Data.Spawns:Get(j)
                for k = 0, spawn.EntryCount - 1 do
                    if spawn.Entries:Get(k).Type == kind then
                        return desc.SafeGridIndex
                    end
                end
            end
        end
    end
    error("Generated floor lacks the expected boss " .. kind)
end
local function usableParty()
    if native.presentation_active() then
        return false
    end
    local usable = true
    for slot = 0, case.players - 1 do
        actor(slot, function(player)
            usable = usable
                and not player:IsDead()
                and not player:IsCoopGhost()
                and player:AreControlsEnabled()
                and player:IsExtraAnimationFinished()
        end)
    end
    return usable
end
local function pickup(slot, variant)
    local pointer
    actor(slot, function(player)
        clear()
        player.Position, player.Velocity = Vector(130 + slot * 130, 220), Vector.Zero
        local drop = Isaac.Spawn(
            EntityType.ENTITY_PICKUP,
            variant,
            1,
            player.Position + Vector(40, 0),
            Vector.Zero,
            nil
        ):ToPickup()
        drop.Timeout, drop.Wait = -1, 0
        drop.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
        pointer = EntityPtr(drop)
        -- Each use arms exactly one swipe. Material must exist before that
        -- swipe begins; the actor returns to ordinary tears after it ends.
        player:UseActiveItem(CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING, 0, ActiveSlot.SLOT_POCKET)
        report(
            "BAG_DROP slot="
                .. slot
                .. " variant="
                .. variant
                .. " x="
                .. drop.Position.X
                .. " y="
                .. drop.Position.Y
                .. " activation=UseActiveItem"
        )
    end)
    return pointer
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, knife)
    if not host or phase ~= "fill-bags" or knife.Variant ~= 4 or knife.SubType ~= 4 then
        return
    end
    local player = knife.Parent and knife.Parent:ToPlayer()
        or knife.SpawnerEntity and knife.SpawnerEntity:ToPlayer()
    if not player then
        return
    end
    local slot = player.ControllerIndex - 1
    lastSwipe[slot] = native.api_info().tick
    local pending = pendingDrops[slot]
    local sprite = knife:GetSprite()
    if
        not pending
        or pending.collected
        or not pending.pickup.Ref
        or not pending.pickup.Ref:Exists()
    then
        return
    end
    if pending.lastFrame ~= sprite:GetFrame() then
        pending.lastFrame = sprite:GetFrame()
        report(
            "NATIVE_BAG_SWIPE slot="
                .. slot
                .. " subtype="
                .. knife.SubType
                .. " animation="
                .. sprite:GetAnimation()
                .. " frame="
                .. sprite:GetFrame()
                .. " knife="
                .. knife.Position.X
                .. ","
                .. knife.Position.Y
                .. " drop="
                .. pending.pickup.Ref.Position.X
                .. ","
                .. pending.pickup.Ref.Position.Y
                .. " collision="
                .. pending.pickup.Ref.EntityCollisionClass
                .. " wait="
                .. pending.pickup.Ref:ToPickup().Wait
        )
    end
    -- Diagnostics only. The pickup stays forty units to the right of its
    -- actor, inside the native rightward swipe and outside body pickup range.
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_END, function(_, gameOver)
    wins = wins + 1
    report("NATIVE_GAME_END game_over=" .. tostring(gameOver))
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    exits, exitedAt = exits + 1, native.api_info().nowMs
    report("NATIVE_EXIT count=" .. exits)
end)
local function advance(t)
    if not native.rooms_ready() then
        return
    end
    if phase == "init" and native.rooms_connected() ~= (1 << case.players) - 1 then
        return
    end
    if case.exit then
        checkRules()
        if phase == "init" and t >= 30 then
            for slot = 0, case.players - 1 do
                actor(slot, function(player)
                    assert(player:GetPlayerType() == PlayerType.PLAYER_CAIN_B)
                    player:SetMinDamageCooldown(10000)
                    clear()
                end)
            end
            mark("challenge-exit-ready", t)
        elseif phase == "challenge-exit-ready" and t - phaseAt > 90 then
            mark("challenge-exit-requested", t)
            assert(native.net_command(3))
        end
        return
    end
    if not case.challenge then
        if phase == "init" and t >= 30 then
            for slot = 0, case.players - 1 do
                actor(slot, function(player)
                    clear()
                    assert(
                        player:GetPlayerType() == PlayerType.PLAYER_ISAAC,
                        "Ordinary run inherited challenge character"
                    )
                    if not case.resume and slot == 0 then
                        -- Native co-op shares coins. Set one common target,
                        -- then record every actor's actual resources at save.
                        player:AddCoins(20 - player:GetNumCoins())
                    end
                end)
            end
            if case.resume then
                local expected = assert(read(challengeCoordination .. "/ordinary-resources.txt"))
                local actual = ordinaryResources()
                report("ORDINARY_RESUME_RESOURCES actual=" .. actual .. " expected=" .. expected)
                assert(actual == expected, "Ordinary resume lost saved resources")
            end
            assert(native.api_info().challenge == 0 and native.api_info().restrictedBags == 0)
            mark("ordinary-ready", t)
        elseif phase == "ordinary-ready" and t - phaseAt > 90 then
            if not case.resume then
                local baseline = ordinaryResources(20)
                write(challengeCoordination .. "/ordinary-resources.txt", baseline)
                report("ORDINARY_SAVE_RESOURCES actual=" .. baseline)
            end
            mark("ordinary-exit", t)
            assert(native.net_command(3))
        end
        return
    end
    checkRules()
    if phase == "init" and t >= 30 then
        local usable = not native.presentation_active()
        for slot = 0, case.players - 1 do
            actor(slot, function(player)
                usable = usable
                    and player.ControlsEnabled
                    and player:AreControlsEnabled()
                    and player:IsExtraAnimationFinished()
            end)
        end
        if not usable then
            return
        end
        for slot = 0, case.players - 1 do
            actor(slot, function(player)
                assert(
                    player:GetPlayerType() == PlayerType.PLAYER_CAIN_B,
                    "Challenge did not force Tainted Cain"
                )
                player:SetMinDamageCooldown(10000)
                clear()
            end)
        end
        report("BAG_ACTIVATION fixture=UseActiveItem swipe_source=native_shoot_input")
        mark("fill-bags", t)
        fillStart = t
        write(challengeCoordination .. "/fill-" .. current .. ".txt", tostring(t))
    elseif phase == "fill-bags" then
        local elapsed = t - phaseAt
        local values, full = bags(), true
        local variants = {
            PickupVariant.PICKUP_COIN,
            PickupVariant.PICKUP_KEY,
            PickupVariant.PICKUP_BOMB,
            PickupVariant.PICKUP_HEART,
        }
        for index, value in ipairs(values) do
            local slot, count = index - 1, 0
            for i = 1, 8 do
                if value:byte(i) > 0 then
                    count = count + 1
                end
            end
            local preview = string.unpack(">I4", value, 9)
            full = full and count == 8 and preview > 0
            if elapsed % 30 == 0 then
                local hex = value:gsub(".", function(c)
                    return string.format("%02x", c:byte())
                end)
                report("BAG_PROGRESS slot=" .. slot .. " count=" .. count .. " bytes=" .. hex)
            end
            local pending = pendingDrops[slot]
            if pending then
                if count == pending.before + 1 then
                    -- The native Collect animation may outlive the bag
                    -- update. Stop observing this collected pickup and let
                    -- its original cleanup complete before making another.
                    pending.collected = true
                    if not pending.pickup.Ref or not pending.pickup.Ref:Exists() then
                        pendingDrops[slot] = nil
                    end
                else
                    assert(
                        t - pending.at < 150,
                        "Native swipe did not collect owned pickup for slot " .. slot
                    )
                end
            elseif
                count < 8
                and elapsed >= 20
                and (not lastActivation[slot] or t - lastActivation[slot] >= 30)
                and (not lastSwipe[slot] or t - lastSwipe[slot] > 2)
            then
                pendingDrops[slot] =
                    { pickup = pickup(slot, variants[index]), before = count, at = t }
                lastActivation[slot] = t
            end
        end
        assert(elapsed < 600, "Native bag filling did not finish before timeout")
        if full then
            fillDone, bagBaseline = true, values
            -- Give cards/pills only after collecting the eight ingredients;
            -- they must remain visible without activating either pocket.
            for slot = 0, case.players - 1 do
                actor(slot, function(player)
                    local card, pill = pocketValues(slot)
                    -- Pocket index zero contains the character's active bag;
                    -- use the secondary card/pill position, as vanilla does.
                    player:SetCard(1, 0)
                    player:SetPill(1, 0)
                    if card ~= 0 then
                        player:SetCard(1, card)
                    else
                        player:SetPill(1, pill)
                    end
                    checkPocket(player)
                    report(
                        "POCKET_FIXTURE slot="
                            .. slot
                            .. " pocket=1 card="
                            .. card
                            .. " pill="
                            .. pill
                    )
                end)
            end
            write(challengeCoordination .. "/fill-done-" .. current .. ".txt", tostring(t))
            for index, value in ipairs(values) do
                local hex = value:gsub(".", function(c)
                    return string.format("%02x", c:byte())
                end)
                report("BAG slot=" .. (index - 1) .. " bytes=" .. hex)
                if index > 1 then
                    assert(value ~= values[index - 1], "Bag fixtures are not distinct")
                end
            end
            mark("same-room-visual", t)
            Isaac.DebugString("LAN_NETWORK VISUAL_READY")
        end
    elseif phase == "same-room-visual" and t - phaseAt > 150 then
        checkPockets("SAME_ROOM_POCKETS")
        separate(case.players - 1)
        mark("split-room-visual", t)
    elseif phase == "split-room-visual" and t - phaseAt > 180 then
        checkBags("SPLIT_BAGS")
        checkPockets("SPLIT_ROOM_POCKETS")
        if case.players == 2 then
            actor(1, function(player)
                player:Kill()
            end)
            mark("ghost-visual", t)
        elseif case.hud then
            mark("hud-exit-ready", t)
        else
            prepareLamb(t)
        end
    elseif phase == "ghost-visual" and t - phaseAt > 120 then
        actor(1, function(player)
            assert(player:IsCoopGhost(), "Challenge actor did not become a ghost")
        end)
        -- Lua Revive handles dead-player state but does not convert a co-op
        -- ghost. Use the existing isolated-lab native conversion first.
        assert(native.actor_ghost(native.rooms_heads()["1"], 0))
        actor(1, function(player)
            player:Revive()
            player:AddHearts(6)
            assert(not player:IsCoopGhost(), "Native co-op revival kept the actor a ghost")
        end)
        report("REVIVE_FIXTURE source=native.actor_ghost slot=1")
        ghostChecked = true
        mark("revive-visual", t)
    elseif phase == "revive-visual" and t - phaseAt > 100 then
        -- Death/revival keeps its ordinary native inventory semantics. Record
        -- the resulting bags for the rewind/restart checks that follow.
        bagBaseline = bags()
        report("REVIVED original_slot=1")
        actor(1, function(player)
            assert(not player:IsCoopGhost(), "Challenge actor remained a ghost")
            clear()
        end)
        if case.hud then
            write(challengeCoordination .. "/reconnect-" .. current .. ".txt", "request")
            mark("hud-reconnect-wait", t)
            return
        end
        local position = native.rooms_positions()["1"]
        local level = Game():GetLevel()
        hourglassSource = {
            index = position.index,
            dimension = position.dimension,
            stage = level:GetStage(),
            stageType = level:GetStageType(),
        }
        if challengeHourglassSharedRoom then
            -- Explicit control case for the known split starting-room/Home
            -- boundary. Preserve the default path as its reproduction.
            separate(0)
        end
        separate(1)
        report(
            "HOURGLASS_MODE "
                .. (challengeHourglassSharedRoom and "shared-room-control" or "split-room")
                .. " split_starting_room_boundary="
                .. tostring(not challengeHourglassSharedRoom)
        )
        mark("hourglass-checkpoint", t)
    elseif phase == "hud-reconnect-wait" then
        local connected = native.api_info().connected
        if connected ~= 3 then
            sawDisconnected = true
        end
        if
            sawDisconnected
            and connected == 3
            and read(challengeCoordination .. "/reconnect-restored-" .. current .. ".txt")
        then
            checkRules()
            checkBags("RECONNECT_BAGS")
            mark("hud-exit-ready", t)
        end
    elseif phase == "hud-exit-ready" and t - phaseAt > 90 and usableParty() then
        checkBags("HUD_EXIT_BAGS")
        report("HUD_LIFECYCLE_PASS")
        mark("hud-exit-requested", t)
        assert(native.net_command(3))
    elseif phase == "hourglass-checkpoint" and t - phaseAt > 90 then
        local positions = native.rooms_positions()
        assert(
            positions["1"].index ~= hourglassSource.index,
            "Hourglass fixture did not enter a different room"
        )
        if challengeHourglassSharedRoom then
            assert(
                positions["0"].index == positions["1"].index
                    and positions["0"].dimension == positions["1"].dimension
                    and positions["1"].index ~= Game():GetLevel():GetStartingRoomIndex(),
                "Hourglass shared-room control is not in one nonstarting room"
            )
        end
        hourglassEpoch = native.api_info().worldEpoch
        actor(1, function(player)
            clear()
            player:UseActiveItem(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, 0, -1)
        end)
        mark("hourglass-wait", t)
    elseif phase == "hourglass-wait" and t - phaseAt > 180 and not native.presentation_active() then
        checkBags("HOURGLASS_BAGS")
        checkRules()
        local position = native.rooms_positions()["1"]
        local level = Game():GetLevel()
        assert(
            position.index == hourglassSource.index
                and position.dimension == hourglassSource.dimension
                and level:GetStage() == hourglassSource.stage
                and level:GetStageType() == hourglassSource.stageType
                and native.api_info().worldEpoch > hourglassEpoch,
            "Hourglass did not restore the source floor/room and advance its epoch"
        )
        report(
            "HOURGLASS_RESTORED stage="
                .. level:GetStage()
                .. " stage_type="
                .. level:GetStageType()
                .. " room="
                .. position.index
                .. " epoch="
                .. native.api_info().worldEpoch
        )
        rkeyEpoch = native.api_info().worldEpoch
        actor(1, function(player)
            player:UseActiveItem(CollectibleType.COLLECTIBLE_R_KEY, UseFlag.USE_NOANIM)
        end)
        mark("r-key-wait", t)
    elseif phase == "r-key-wait" and t - phaseAt > 240 then
        assert(Game():GetLevel():GetStage() == 1, "R Key did not return to Basement I")
        assert(native.api_info().worldEpoch > rkeyEpoch, "R Key did not start a new floor epoch")
        checkRules()
        checkBags("R_KEY_BAGS")
        prepareLamb(t)
    elseif phase == "native-route-ready" and t - phaseAt > 60 and usableParty() then
        local stage = Game():GetLevel():GetStage()
        if stage == LevelStage.STAGE6 then
            mark("dark-room-load", t)
        elseif stage == LevelStage.STAGE5 then
            assert(native.rooms_move(case.players - 1, bossRoom(EntityType.ENTITY_SATAN), 0, -1))
            mark("satan-fight", t)
        else
            routeTarget =
                assert(({ 2, 3, 4, 5, 6, 7, 8, 10 })[stage], "Unexpected native route floor")
            routeEpoch = native.api_info().worldEpoch
            actor(0, function(player)
                clear()
                local room = Game():GetRoom()
                local index = room:GetGridIndex(room:GetCenterPos() + Vector(80, 0))
                assert(room:SpawnGridEntity(index, GridEntityType.GRID_TRAPDOOR, 0, 123, 0))
                local grid = assert(room:GetGridEntity(index))
                grid.State = 2
                routeTrap = grid.Position
                player.Position, player.Velocity = room:GetCenterPos() - Vector(100, 0), Vector.Zero
            end)
            report(
                "NATIVE_ROUTE_EXIT fixture=trapdoor from=" .. stage .. " expected=" .. routeTarget
            )
            mark("native-trapdoor", t)
        end
    elseif phase == "native-trapdoor" then
        if native.api_info().worldEpoch > routeEpoch then
            mark("native-floor-wait", t)
        elseif t - phaseAt > 30 then
            actor(0, function(player)
                player.Position, player.Velocity = routeTrap, Vector.Zero
            end)
        end
    elseif phase == "satan-fight" then
        actor(case.players - 1, function(player)
            player:SetMinDamageCooldown(10000)
            player.Position, player.Velocity = Vector(120, 180), Vector.Zero
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_SATAN then
                    sawSatan = true
                end
                if
                    entity:IsActiveEnemy(false)
                    and not entity:IsDead()
                    and t - phaseAt > 120
                    and t % 15 == 0
                then
                    entity:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(player), 0)
                elseif
                    entity.Type == EntityType.ENTITY_PICKUP
                    and entity.Variant == PickupVariant.PICKUP_BIGCHEST
                then
                    satanChest = EntityPtr(entity)
                end
            end
            if sawSatan and satanChest and satanChest.Ref and Game():GetRoom():IsClear() then
                report("NATIVE_SATAN_CHEST")
                mark("satan-chest", t)
            end
        end)
    elseif phase == "satan-chest" and t - phaseAt > 90 then
        routeEpoch, routeTarget = native.api_info().worldEpoch, LevelStage.STAGE6
        actor(case.players - 1, function(player)
            assert(player:HasCollectible(CollectibleType.COLLECTIBLE_NEGATIVE))
            local pickup = assert(satanChest.Ref:ToPickup())
            assert(pickup.Wait <= 0, "Satan chest is not ready")
            player.Position, player.Velocity = pickup.Position, Vector.Zero
        end)
        mark("native-floor-wait", t)
    elseif
        phase == "native-floor-wait"
        and native.api_info().worldEpoch > routeEpoch
        and usableParty()
    then
        local level, positions = Game():GetLevel(), native.rooms_positions()
        assert(level:GetStage() == routeTarget, "Native route reached the wrong floor")
        for slot = 1, case.players - 1 do
            assert(
                positions[tostring(slot)].index == positions["0"].index
                    and positions[tostring(slot)].dimension == positions["0"].dimension,
                "Native floor transition did not gather the party"
            )
        end
        checkRules()
        report(
            "NATIVE_ROUTE_FLOOR stage="
                .. level:GetStage()
                .. " type="
                .. level:GetStageType()
                .. " epoch="
                .. native.api_info().worldEpoch
        )
        mark("native-route-ready", t)
    elseif phase == "dark-room-load" and t - phaseAt > 200 then
        assert(
            Game():GetLevel():GetStage() == LevelStage.STAGE6
                and Game():GetLevel():GetStageType() == StageType.STAGETYPE_ORIGINAL,
            "Dark Room did not load"
        )
        lambRoomIndex = bossRoom(EntityType.ENTITY_THE_LAMB)
        assert(native.rooms_move(case.players - 1, lambRoomIndex, 0, -1))
        mark("lamb-fight", t)
    elseif phase == "lamb-fight" then
        actor(case.players - 1, function(player)
            player:SetMinDamageCooldown(10000)
            player.Position, player.Velocity = Vector(120, 180), Vector.Zero
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_THE_LAMB then
                    sawLamb = true
                end
                if
                    entity:ToNPC()
                    and entity:IsActiveEnemy(false)
                    and not entity:IsDead()
                    and t - phaseAt > 120
                    and t % 15 == 0
                then
                    entity:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(player), 0)
                elseif
                    entity.Type == EntityType.ENTITY_PICKUP
                    and entity.Variant == PickupVariant.PICKUP_TROPHY
                then
                    trophy = EntityPtr(entity)
                end
            end
            if sawLamb and trophy and trophy.Ref and Game():GetRoom():IsClear() then
                assert(Game():GetVictoryLap() == 0, "Lamb death started a Victory Lap")
                local room = Game():GetRoom()
                voidExitIndex = room:GetGridIndex(room:GetCenterPos() + Vector(120, 80))
                assert(not room:GetGridEntity(voidExitIndex), "Void fixture grid is occupied")
                assert(room:SpawnGridEntity(voidExitIndex, GridEntityType.GRID_TRAPDOOR, 1, 187, 1))
                local grid = assert(room:GetGridEntity(voidExitIndex))
                grid.VarData, grid.State = 1, 2
                report("VOID_EXIT_FIXTURE variant=1 var_data=1 index=" .. voidExitIndex)
                mark("trophy-visual", t)
                report("NATIVE_LAMB_TROPHY victory_lap=0")
            end
        end)
    elseif phase == "trophy-visual" and not voidExitChecked and t - phaseAt > 30 then
        actor(case.players - 1, function()
            assert(not Game():GetRoom():GetGridEntity(voidExitIndex), "Lamb Void exit survived")
            assert(trophy and trophy.Ref and trophy.Ref:Exists(), "Void cleanup removed trophy")
            assert(Game():GetLevel():GetStage() == LevelStage.STAGE6)
            assert(Game():GetVictoryLap() == 0)
        end)
        voidExitChecked = true
        report("VOID_EXIT_REMOVED trophy_preserved=true victory_lap=0")
    elseif phase == "trophy-visual" and t - phaseAt > 150 and case.players == 2 then
        assert(Game():GetVictoryLap() == 0, "Trophy presentation started a Victory Lap")
        report("TROPHY_VISUAL victory_lap=0")
        write(challengeCoordination .. "/reconnect-" .. current .. ".txt", "request")
        mark("reconnect-wait", t)
    elseif phase == "reconnect-wait" then
        local connected = native.api_info().connected
        if connected ~= 3 then
            sawDisconnected = true
        end
        if sawDisconnected and connected == 3 then
            checkRules()
            checkBags("RECONNECT_BAGS")
            -- Rejoin follows the host's room. Reload the objective room and
            -- its authoritative pickup instead of retaining an unloaded ptr.
            assert(native.rooms_move(case.players - 1, assert(lambRoomIndex), 0, -1))
            trophy = nil
            mark("reconnect-trophy", t)
        end
    elseif
        (phase == "trophy-visual" and t - phaseAt > 150)
        or (
            phase == "reconnect-trophy"
            and t - phaseAt > 30
            and native.rooms_positions()[tostring(case.players - 1)].index == lambRoomIndex
            and usableParty()
        )
    then
        assert(Game():GetVictoryLap() == 0, "Challenge entered a Victory Lap before completion")
        report("TROPHY_READY victory_lap=0")
        local collector = case.players - 1
        actor(collector, function(player)
            assert(Game():GetLevel():GetCurrentRoomIndex() == lambRoomIndex)
            if phase == "reconnect-trophy" then
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if
                        entity.Type == EntityType.ENTITY_PICKUP
                        and entity.Variant == PickupVariant.PICKUP_TROPHY
                    then
                        trophy = EntityPtr(entity)
                        break
                    end
                end
            end
            assert(trophy and trophy.Ref and trophy.Ref:Exists(), "Native trophy disappeared")
            if phase == "reconnect-trophy" then
                report("RECONNECT_LAMB_ROOM index=" .. lambRoomIndex .. " trophy_reloaded=true")
            end
            local pickup = trophy.Ref:ToPickup()
            assert(pickup.Wait <= 0, "Native trophy is not collectable")
            player.Position, player.Velocity = pickup.Position, Vector.Zero
        end)
        contactAt = native.api_info().nowMs
        write(challengeCoordination .. "/contact-" .. current .. ".txt", tostring(contactAt))
        mark("finish-wait", t)
        report("TROPHY_CONTACT collector=" .. collector)
    elseif phase == "finish-wait" then
        assert(
            native.api_info().nowMs - contactAt < 15000,
            "Native FinishChallenge did not leave the run"
        )
    end
    assert(t - phaseAt < 1800, "Challenge fixture phase stalled: " .. phase)
end
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
function _IsaacLanFrame()
    renders = renders + 1
    local status = baseFrame()
    local now = native.api_info().nowMs
    if renders == 60 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    native.test_gamepad(0)
    local requested = tonumber(read(challengeCoordination .. "/case.txt"))
    if requested and requested > #cases then
        if not reported then
            reported = true
            Isaac.DebugString("LAN_NETWORK PASS concentrated LAN challenges")
        end
        return status
    end
    if requested and requested ~= current then
        -- Each case owns a separate room/configuration. Successful runs now
        -- retain their lobby, so end it only after all peers recorded results.
        if current and status.scene == 1 and not status.prepared and status.phase ~= 0 then
            _IsaacLanCommand("close")
            return status
        end
        if status.phase ~= 0 or status.scene ~= 1 or status.prepared then
            return status
        end
        current, case = requested, assert(cases[requested])
        linked, started, participated, menuDone = false, false, false, false
        chosen, configured = false, false
        startAt, exitedAt, phase, phaseAt, snapshots =
            now + (current == 1 and 8000 or 2000), nil, "init", 0, 0
        previousButtons, eidChecked, sawLamb, trophy, contactAt, returned =
            0, false, false, nil, nil, false
        fillStart, fillDone, pendingDrops = nil, false, {}
        lastActivation, lastSwipe = {}, {}
        hudOffsetRecorded, hudOffsetZeroed, ghostBagObserved = false, false, {}
        pocketChecked, voidExitIndex, voidExitChecked, lambRoomIndex = false, nil, false, nil
        floorEvents, lastReplicaEpoch = {}, nil
        reconnectRequested, reconnectDeparted, reconnectJoined, sawDisconnected =
            false, false, false, false
        reconnectVerified, reconnectSnapshot = false, false
        archiveBaseline, progressBaseline = archive(), native.net_progress()
        report("BEGIN ordinal=" .. ordinal .. " players=" .. case.players)
    end
    if not case or ordinal >= case.players then
        return status
    end
    if status.phase == 4 or (status.phase == 9 and status.error ~= "") then
        Isaac.DebugString("LAN_NETWORK FAILED " .. status.error)
        return status
    end
    verified = status.verified
    if not linked and now >= startAt + ordinal * 900 and status.scene == 1 then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("LINK")
    end
    if status.phase == 2 then
        if host and not configured then
            configured = true
            if status.challenge ~= (case.challenge and 1001 or 0) then
                _IsaacLanCommand("challenge", case.challenge and "1001" or "0")
            end
        end
        if status.challenge == (case.challenge and 1001 or 0) and not chosen then
            -- One choice per rules revision. Waiting for the asynchronous
            -- ready echo must not enqueue stale choices after host start.
            chosen = true
            _IsaacLanCommand("choose", (case.challenge and "23" or "0") .. ":1")
        end
        local ready = status.players == case.players
            and status.challenge == (case.challenge and 1001 or 0)
        for i = 0, case.players - 1 do
            ready = ready and status["ready" .. i] == 1
        end
        if host and ready and not started then
            started = true
            _IsaacLanCommand(
                case.resume and "resume" or "start",
                case.resume and ""
                    or (case.challenge and "YV039KQF:0:23:23:23:23" or "YV039KQF:0:0:0:0:0")
            )
        end
    end
    local info = native.api_info()
    if not host and case.challenge and case.players == 2 then
        if
            not reconnectRequested
            and status.phase == 3
            and read(challengeCoordination .. "/reconnect-" .. current .. ".txt")
        then
            reconnectRequested = true
            assert(native.net_command(4))
            report("RECONNECT_LEAVE slot=" .. info.slot)
            -- net_command synchronously exits and clears the run. The info
            -- captured earlier in this render describes the old session.
            return status
        elseif
            reconnectRequested
            and not reconnectJoined
            and exitedAt
            and status.scene == 1
            and not status.prepared
            and now - exitedAt > 1000
        then
            reconnectJoined, exitedAt = true, nil
            lastReplicaEpoch = nil
            _IsaacLanCommand("join", "127.0.0.1:" .. port)
            report("RECONNECT_JOIN")
        end
    end
    if info.ready == 1 then
        participated = true
        if case.challenge then
            checkRules()
            if reconnectJoined and not reconnectVerified then
                assert(
                    info.slot == ordinal and info.players == 2,
                    "Rejoin changed the original slot"
                )
                reconnectVerified = true
                report("RECONNECT_IDENTITY_PRESERVED slot=" .. info.slot)
            end
            if not eidChecked and verified > 90 then
                assert(not challengeRequireEid or EID, "Requested EID fixture did not load")
                if EID then
                    EID:setPlayer()
                    assert(
                        EID.player and EID.player.ControllerIndex == info.slot + 1,
                        "EID selected the wrong local player"
                    )
                end
                eidChecked = true
                report(
                    "EID_LOCAL_VIEW present="
                        .. tostring(EID ~= nil)
                        .. " next_slot="
                        .. ((info.slot + 1) % case.players)
                )
            end
            if not hudOffsetRecorded then
                hudOffsetRecorded = true
                report("HUD_OFFSET_INITIAL actual=" .. tostring(Options.HUDOffset))
            end
            local fullAt =
                tonumber(read(challengeCoordination .. "/fill-done-" .. current .. ".txt"))
            if fullAt and verified >= fullAt + 90 and not hudOffsetZeroed then
                -- J460's Lua setter clamps values above 0.01. Preserve the
                -- native options.ini offset for the first full-bag frames,
                -- then test the other endpoint by setting zero only once.
                Options.HUDOffset = 0
                hudOffsetZeroed = true
                report("HUD_OFFSET_SET requested=0 actual=" .. tostring(Options.HUDOffset))
            end
        end
    end
    if
        participated
        and exitedAt
        and not menuDone
        and (not reconnectRequested or reconnectJoined)
        and (status.phase == 0 or status.phase == native.net_phases().lobby)
        and status.scene == 1
        and not status.prepared
        and now - exitedAt > 2000
    then
        if case.challenge then
            if not case.exit and not case.hud then
                assert(
                    read(challengeCoordination .. "/contact-" .. current .. ".txt"),
                    "Challenge exited before trophy contact"
                )
            end
            assert(host or snapshots > 100, "Too few challenge replica states")
            checkArchive()
            local progress = native.net_progress()
            for i = 2, 643 do
                assert(
                    progressBaseline:byte(i) == 0 or progress:byte(i) == 1,
                    "Challenge discarded a prior local achievement"
                )
            end
            assert(
                progress:sub(-4) == progressBaseline:sub(-4),
                "Challenge replaced this peer's private progress counter"
            )
            report("LOCAL_PROGRESS_BASELINE_PRESERVED")
        end
        menuDone = true
        write(challengeCoordination .. "/done-" .. current .. "-" .. ordinal .. ".txt", "done")
        report("PASS menu_cleanup=true snapshots=" .. snapshots)
    end
    if host and menuDone then
        local all = true
        for i = 0, case.players - 1 do
            all = all
                and read(challengeCoordination .. "/done-" .. current .. "-" .. i .. ".txt")
                    ~= nil
        end
        if all then
            write(challengeCoordination .. "/case.txt", tostring(current + 1))
        end
    end
    if now - lastHeartbeat > 10000 then
        lastHeartbeat = now
        report("HEARTBEAT phase=" .. status.phase .. " step=" .. phase .. " tick=" .. verified)
    end
    return status
end
local menuRender, menuShown = assert(_IsaacLanMenuRender), false
function _IsaacLanMenuRender(available, visible, ...)
    -- Record the real empty-IP prompt during the existing startup wait.
    -- Once the fixture connects, native menu visibility proceeds normally.
    if current == 1 and not linked then
        if not menuShown then
            menuShown = true
            _IsaacLanMenuOpen(true)
            report("LAN_INPUT_PROMPT_VISIBLE")
        end
        visible = true
    end
    return menuRender(available, visible, ...)
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        function()
            local input, buttons = {}, 0
            if case.challenge and not fillStart then
                fillStart = tonumber(read(challengeCoordination .. "/fill-" .. current .. ".txt"))
            end
            local elapsed = fillStart and verified - fillStart or -1
            if fillStart and not fillDone then
                fillDone = read(challengeCoordination .. "/fill-done-" .. current .. ".txt") ~= nil
            end
            for action = 0, 15 do
                local held = case.challenge
                    and action == ButtonAction.ACTION_SHOOTRIGHT
                    and elapsed >= 10
                    and not fillDone
                input[#input + 1] = string.pack(">I2", held and 65535 or 0)
                if held then
                    buttons = buttons | (1 << action)
                end
            end
            input[#input + 1] = string.pack(">I2", buttons & ~previousButtons)
            previousButtons = buttons
            return table.concat(input)
        end,
        function(t, n, bytes)
            before(t, n, bytes)
            advance(t)
        end,
        collect,
        function(bytes, t, ack, betweenUpdates, stable)
            if restore(bytes, t, ack, betweenUpdates, stable) == false then
                return false
            end
            snapshots = snapshots + 1
            if case.challenge then
                local value = _IsaacLanState.decode(bytes, stable)
                local level, epoch = Game():GetLevel(), value[14]
                local fullAt =
                    tonumber(read(challengeCoordination .. "/fill-done-" .. current .. ".txt"))
                local pocketWindow = fullAt and t >= fullAt + 30 and t <= fullAt + 300
                assert(
                    level:GetStage() == value[4] and level:GetStageType() == value[5],
                    "Replica native floor differs from authority"
                )
                if epoch ~= lastReplicaEpoch then
                    assert(
                        lastReplicaEpoch == nil or floorEvents[epoch],
                        "Replica changed floors without a reliable event"
                    )
                    lastReplicaEpoch = epoch
                    report(
                        "FLOOR_REPLICA stage="
                            .. value[4]
                            .. " type="
                            .. value[5]
                            .. " epoch="
                            .. epoch
                    )
                end
                for _, entry in ipairs(value[9]) do
                    local player = Isaac.GetPlayer(entry[1])
                    if pocketWindow then
                        checkPocket(player)
                    end
                    assert(player:IsCoopGhost() == entry[4][9], "Replica ghost state differs")
                    if player:IsCoopGhost() then
                        -- Ghost conversion owns hidden native inventory.
                        -- Capture omits the bag and apply leaves it untouched;
                        -- byte equality resumes when this actor is revived.
                        assert(entry[8] == false, "Ghost exposed crafting bag state")
                        if not ghostBagObserved[entry[1]] then
                            ghostBagObserved[entry[1]] = true
                            report("GHOST_BAG_OMITTED actor=" .. entry[1] .. " tick=" .. t)
                        end
                    else
                        assert(
                            native.actor_crafting_bag(player:GetSprite())
                                == (entry[8] and entry[8][1] or string.rep("\0", 12)),
                            "Replica bag differs from authoritative actor"
                        )
                        if ghostBagObserved[entry[1]] then
                            ghostBagObserved[entry[1]] = nil
                            report("REVIVED_BAG_MATCH actor=" .. entry[1] .. " tick=" .. t)
                        end
                    end
                end
                if pocketWindow and not pocketChecked then
                    pocketChecked = true
                    report("REPLICA_POCKETS native_card_pill_preserved=true")
                end
                if reconnectJoined and not reconnectSnapshot then
                    reconnectSnapshot = true
                    write(
                        challengeCoordination .. "/reconnect-restored-" .. current .. ".txt",
                        "ready"
                    )
                    report("RECONNECT_SNAPSHOT_RESTORED tick=" .. t)
                end
            end
            return true
        end,
        present,
        function(epoch, stage, stageType, ...)
            floorEvents[epoch] = true
            report("FLOOR_EVENT epoch=" .. epoch .. " source=" .. stage .. ":" .. stageType)
            return beginFloor(epoch, stage, stageType, ...)
        end
    )
end
