-- Factory for special_suite_driver.lua; append `return function() return finished end`.
-- Setup may place actors/enemies, but input, damage, pickups, doors and the
-- trapdoor all use the ordinary game path. No Kill/TakeDamage or room warp.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local lobbyAt
local localSlot = host and 0 or 1
local frame, gate = _IsaacLanFrame, native.net_gate
local finished, linked, chosen, started, renders = false, false, false, false, 0
local origin, target, exitSlot, seed, initialEpoch
local prepared, fought, doorPrepared, trapPrepared, floorChecked = false, false, false, false, false
local localEntered, floorEvents, snapshots = false, 0, 0
local playerSeeds, pickups, enemies, tears, hits, deaths, collisions =
    {}, {}, {}, { 0, 0 }, {}, {}, {}
local cleanedRooms = {}
local owner = { Name = "Release real-input smoke observers" }
local callbacks = {}
local function report(value)
    Isaac.DebugString("LAN_NETWORK RELEASE_SMOKE " .. value)
end
local function actor(slot, call)
    assert(native.rooms_with_player(slot, function()
        call(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function clear()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) or entity.Type == EntityType.ENTITY_PICKUP then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function clearLane(room)
    for i = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(i)
        if
            grid
            and grid:GetType() ~= GridEntityType.GRID_DOOR
            and room:GetGridCollision(i) ~= GridCollisionClass.COLLISION_WALL
        then
            room:RemoveGridEntity(i, 0, false)
        end
    end
end
local function usable()
    if
        not native.rooms_ready()
        or native.presentation_active()
        or native.rooms_connected() ~= 3
    then
        return false
    end
    local result = true
    for slot = 0, 1 do
        actor(slot, function(player)
            result = result and player:AreControlsEnabled() and player:IsExtraAnimationFinished()
        end)
    end
    return result
end
local function rememberWorld()
    if not origin and native.rooms_ready() then
        actor(localSlot, function()
            local level, room = Game():GetLevel(), Game():GetRoom()
            origin, seed = level:GetStartingRoomIndex(), Game():GetSeeds():GetStartSeed()
            initialEpoch = native.api_info().worldEpoch
            assert(
                level:GetCurrentRoomIndex() == origin,
                "Smoke did not start in the native start room"
            )
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door:IsOpen() and door.TargetRoomIndex >= 0 then
                    exitSlot, target = slot, door.TargetRoomIndex
                    break
                end
            end
            assert(exitSlot, "No open native starting-room door")
        end)
        for slot = 0, 1 do
            actor(slot, function(player)
                playerSeeds[slot + 1] = player.InitSeed
            end)
        end
        report("WORLD origin=" .. origin .. " target=" .. target .. " door=" .. exitSlot)
    end
end
local function checkActors(resources)
    assert(Game():GetSeeds():GetStartSeed() == seed, "Smoke changed the native run seed")
    for slot = 0, 1 do
        actor(slot, function(player)
            assert(
                player.ControllerIndex == slot + 1
                    and player:GetPlayerType() == PlayerType.PLAYER_ISAAC
                    and player.InitSeed == playerSeeds[slot + 1],
                "Native actor identity changed"
            )
            assert(
                player:GetCollectibleNum(slot + 1, true) == 1
                    and not player:HasCollectible(2 - slot),
                "Independent inventory merged or disappeared"
            )
            assert(
                player.Visible and player:HasEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK),
                "Protected smoke actor is invisible or missing NO_DAMAGE_BLINK"
            )
            assert(not player:IsDead() and not player:IsCoopGhost(), "Protected smoke actor died")
            if resources then
                assert(
                    player:GetNumCoins() == 11 and player:GetNumKeys() == 3,
                    "Pickup resources differ"
                )
            end
        end)
    end
end
local function observe(id, callback)
    callbacks[#callbacks + 1] = { id, callback }
    Isaac.AddCallback(owner, id, callback)
end
local function finish()
    if finished then
        return
    end
    assert(localEntered, "This viewport never observed its actor crossing a native door")
    for _, callback in ipairs(callbacks) do
        Isaac.RemoveCallback(owner, callback[1], callback[2])
    end
    native.test_gamepad(0)
    finished = true
    report("PASS authority=" .. tostring(host) .. " snapshots=" .. snapshots)
end
observe(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
    if host and not finished then
        local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        if player and player.ControllerIndex >= 1 and player.ControllerIndex <= 2 then
            tears[player.ControllerIndex] = tears[player.ControllerIndex] + 1
        end
    end
end)
observe(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
    if not host or finished then
        return
    end
    local slot = enemies[entity.InitSeed]
    if slot then
        local tear = source.Entity and source.Entity:ToTear()
        local player = tear and tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        assert(
            player and player.ControllerIndex == slot,
            string.format(
                "Controlled enemy damage did not come from its player's tear: target=%d:%d seed=%d expected=%d source=%d:%d player=%s amount=%g flags=%d",
                entity.Type,
                entity.Variant,
                entity.InitSeed,
                slot,
                source.Type,
                source.Variant,
                player and tostring(player.ControllerIndex) or "none",
                amount,
                flags
            )
        )
        hits[slot] = (hits[slot] or 0) + 1
    end
end)
observe(ModCallbacks.MC_POST_NPC_DEATH, function(_, npc)
    if host and not finished and enemies[npc.InitSeed] then
        local slot = enemies[npc.InitSeed]
        assert(hits[slot] and hits[slot] > 0, "Controlled enemy died without normal tear damage")
        deaths[slot] = (deaths[slot] or 0) + 1
    end
end)
observe(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, other)
    if host and not finished and pickups[pickup.InitSeed] then
        local player = other:ToPlayer()
        if player then
            local expected = pickups[pickup.InitSeed]
            assert(
                player.ControllerIndex == expected,
                "The wrong player touched the controlled pickup"
            )
            collisions[expected] = (collisions[expected] or 0) + 1
        end
    end
end)
local function advance(t)
    if finished then
        return
    end
    if not prepared and t >= 30 and usable() then
        rememberWorld()
        actor(0, function(player)
            clear()
            clearLane(Game():GetRoom())
            player:AddCoins(10 - player:GetNumCoins())
            player:AddKeys(2 - player:GetNumKeys())
        end)
        for slot = 0, 1 do
            actor(slot, function(player)
                local center = Game():GetRoom():GetCenterPos()
                player:AddCollectible(slot + 1)
                player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                player:SetMinDamageCooldown(10000)
                player.Position, player.Velocity =
                    center + Vector(-120, -60 + slot * 120), Vector.Zero
                local pickup = Isaac.Spawn(
                    EntityType.ENTITY_PICKUP,
                    slot == 0 and PickupVariant.PICKUP_COIN or PickupVariant.PICKUP_KEY,
                    1,
                    player.Position + Vector(65, 0),
                    Vector.Zero,
                    nil
                ):ToPickup()
                pickup.Wait = 0
                pickups[pickup.InitSeed] = slot + 1
            end)
        end
        prepared = true
        report("PREPARED pickup_input=80..110 shoot_input=180..310")
    elseif prepared and not fought and t >= 150 and usable() then
        assert(t < 180, "Smoke setup missed the shared shooting window")
        checkActors(true)
        assert(collisions[1] and collisions[2], "Coin/key were not collected by entity collision")
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            assert(not pickups[entity.InitSeed], "A controlled pickup survived collection")
        end
        report(
            "PICKUPS_PASS coin=11 keys=3 collision0="
                .. collisions[1]
                .. " collision1="
                .. collisions[2]
        )
        for slot = 0, 1 do
            actor(slot, function(player)
                local center = Game():GetRoom():GetCenterPos()
                player.Position, player.Velocity =
                    center + Vector(-140, -60 + slot * 120), Vector.Zero
                -- Keep one target per lane; Gapers can transform and recover health.
                local npc = Isaac.Spawn(
                    EntityType.ENTITY_ATTACKFLY,
                    0,
                    0,
                    player.Position + Vector(200, 0),
                    Vector.Zero,
                    nil
                ):ToNPC()
                npc:AddEntityFlags(
                    EntityFlag.FLAG_FREEZE
                        | EntityFlag.FLAG_NO_KNOCKBACK
                        | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK
                )
                npc.HitPoints, npc.MaxHitPoints = 1, 1
                enemies[npc.InitSeed] = slot + 1
                Game():GetRoom():SetClear(false)
            end)
        end
        fought = true
    elseif fought and not doorPrepared and t >= 350 and usable() then
        for slot = 1, 2 do
            assert(
                tears[slot] > 0 and hits[slot] and deaths[slot] == 1,
                string.format(
                    "Native shooting did not kill both controlled enemies: slot=%d tears=%d hits=%d deaths=%d",
                    slot,
                    tears[slot],
                    hits[slot] or 0,
                    deaths[slot] or 0
                )
            )
            report(
                "COMBAT_PASS slot="
                    .. (slot - 1)
                    .. " tears="
                    .. tears[slot]
                    .. " hits="
                    .. hits[slot]
                    .. " deaths=1"
            )
        end
        actor(0, clear)
        for slot = 0, 1 do
            actor(slot, function(player)
                local door = assert(Game():GetRoom():GetDoor(exitSlot))
                assert(door:IsOpen() and door.TargetRoomIndex == target)
                local inward = ({ Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) })[exitSlot % 4 + 1]
                player.Position, player.Velocity = door.Position + inward * 70, Vector.Zero
            end)
        end
        doorPrepared = true
        report("DOOR_PREPARED host_input=400..470 client_input=510..580")
    elseif doorPrepared and not trapPrepared then
        local positions = native.rooms_positions()
        for slot = 0, 1 do
            if positions[tostring(slot)].index == target and not cleanedRooms[target] then
                actor(slot, clear)
                cleanedRooms[target] = true
            end
        end
        if t >= 620 and usable() then
            assert(
                positions["0"].index == target and positions["1"].index == target,
                "Normal movement did not take both players through the native door"
            )
            checkActors(true)
            actor(0, function(player)
                local room = Game():GetRoom()
                clear()
                clearLane(room)
                local position = room:GetCenterPos() + Vector(80, 0)
                local index = room:GetGridIndex(position)
                assert(not room:GetGridEntity(index), "Trapdoor grid is occupied")
                assert(room:SpawnGridEntity(index, GridEntityType.GRID_TRAPDOOR, 0, 187, 0))
                local trap = assert(room:GetGridEntity(index))
                trap.State = 2
                player.Position, player.Velocity = trap.Position - Vector(100, 0), Vector.Zero
            end)
            actor(1, function(player)
                player.Position, player.Velocity =
                    Game():GetRoom():GetCenterPos() + Vector(-80, 80), Vector.Zero
            end)
            trapPrepared = true
            report("DOORS_PASS both=true TRAPDOOR_PREPARED host_input=680..730")
        end
    elseif trapPrepared and not floorChecked and t >= 900 and usable() then
        assert(
            Game():GetLevel():GetStage() == 2 and native.api_info().worldEpoch == initialEpoch + 1,
            "Physical trapdoor did not change the whole team's floor exactly once"
        )
        checkActors(true)
        local positions = native.rooms_positions()
        assert(
            positions["0"].index == Game():GetLevel():GetStartingRoomIndex()
                and positions["1"].index == positions["0"].index,
            "Team was split across the native floor transition"
        )
        floorChecked = true
        report("FLOOR_PASS stage=2 visible=true no_damage_blink=true independent_inventory=true")
        finish()
    end
    assert(t < 1250, "Release smoke did not complete")
end
function _IsaacLanFrame()
    renders = renders + 1
    local status = frame()
    assert(status.phase ~= 4 and not (status.phase == 9 and status.error ~= ""), status.error)
    if not linked and renders >= (host and 300 or 360) and status.scene == 1 then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if status.phase == 2 then
        if not chosen then
            chosen = true
            assert(native.net_choose(0, 1))
        end
        if
            host
            and not started
            and status.players == 2
            and status.ready0 == 1
            and status.ready1 == 1
        then
            lobbyAt = lobbyAt or native.api_info().nowMs
            if native.api_info().nowMs - lobbyAt >= 1500 then
                started = true
                _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
            end
        end
    end
    local buttons, t = 0, status.verified
    if status.phase == 3 and native.rooms_ready() and not finished then
        if t >= 35 and t < 150 then
            rememberWorld()
        end
        if origin and t >= 390 and t < 620 then
            local index = native.rooms_positions()[tostring(localSlot)].index
            if index ~= origin then
                assert(index == target, "Physical input entered an unexpected room")
                if not localEntered then
                    localEntered = true
                    report(
                        "DOOR_INPUT_PASS slot=" .. localSlot .. " room=" .. index .. " tick=" .. t
                    )
                end
            end
        end
        if t >= 80 and t < 110 then
            buttons = 8
        elseif t >= 180 and t < 310 then
            buttons = 8192
        elseif
            not localEntered
            and ((host and t >= 400 and t < 470) or (not host and t >= 510 and t < 580))
        then
            assert(exitSlot, "Local viewport did not capture the native door")
            buttons = ({ 4, 1, 8, 2 })[exitSlot % 4 + 1]
        elseif host and t >= 680 and t < 730 and native.api_info().worldEpoch == initialEpoch then
            buttons = 8
        end
    end
    native.test_gamepad(buttons)
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, bytes)
            before(t, n, bytes)
            advance(t)
        end,
        collect,
        function(bytes, t, ack, betweenUpdates)
            if restore(bytes, t, ack, betweenUpdates) == false then
                return false
            end
            snapshots = snapshots + 1
            if not finished and t >= 900 and usable() then
                assert(
                    origin and floorEvents == 1 and snapshots > 100,
                    "Replica missed world setup or floor event"
                )
                assert(
                    Game():GetLevel():GetStage() == 2
                        and native.api_info().worldEpoch == initialEpoch + 1,
                    "Replica floor/epoch differs"
                )
                checkActors(true)
                local positions = native.rooms_positions()
                assert(
                    positions["0"].index == positions["1"].index
                        and positions["0"].index == Game():GetLevel():GetStartingRoomIndex()
                )
                report(
                    "FLOOR_PASS stage=2 visible=true no_damage_blink=true independent_inventory=true"
                )
                finish()
            end
            return true
        end,
        present,
        function(epoch, stage, stageType, animation, same, rewind, restart, cinematic, ...)
            floorEvents = floorEvents + 1
            assert(
                floorEvents == 1 and stage == 1 and animation ~= 6 and #rewind == 0 and restart == 0,
                "Smoke received an unexpected floor transaction"
            )
            report(
                "FLOOR_EVENT epoch=" .. epoch .. " stage=" .. stage .. " animation=" .. animation
            )
            return beginFloor(
                epoch,
                stage,
                stageType,
                animation,
                same,
                rewind,
                restart,
                cinematic,
                ...
            )
        end
    )
end
