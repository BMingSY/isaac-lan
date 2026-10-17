-- audit/exportCatalog are supplied by tools/item_audit.py. Test code only.
-- Each case gets a fresh native run; processes are reused across cases.
local native, json = assert(_IsaacLan), require("json")
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local Phase, Command = native.net_phases(), native.net_commands()
local GamepadButton = { bomb = 0x0100, consumable = 0x0200 }
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
local owner = { Name = "Isolated item compatibility audit" }
local index, renders, linked, chosen, started = 1, 0, false, false, false
local prepared, used, moved, exiting, finished = false, false, false, false, false
local beganAt, sampleAt, relinkAt, useCount = nil, 0, 0, 0
local catalogued, seen, lastTick, lastPhase = false, 0, 0, nil
local placed, damaged, deathProbed = false, false, false
local useSampled = false
local floorMoved = false
local cleanupRoom
local edenInitial, pendingEden
local case = audit.cases[index]
local journal = assert(io.open(audit.journal[host and "host" or "client"], "a"))
local function report(event, values)
    values = values or {}
    values.event, values.key = event, values.key or (case and case.key)
    values.role, values.now_ms = host and "host" or "client", native.api_info().nowMs
    local line = "LAN_ITEM_AUDIT " .. json.encode(values)
    journal:write(line .. "\n")
    journal:flush()
    Isaac.DebugString(line)
end
local stress = createStress(report)
local roomEffects = createRoomEffects(report)
local traceDamage = createDamageTrace(report, function()
    return host and prepared and not exiting and case and case.damage_effects
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, p)
    traceDamage("player_effects", p)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_NEW_ROOM, function()
    traceDamage("new_room")
end)
local lastRender
local function observationEnd()
    return case.end_tick or ((case.mega or case.companion or case.kind == "stress") and 1100 or 150)
end
local function actor(slot, fn)
    local found = false
    local ok = native.rooms_with_player(slot, function()
        local head = native.rooms_heads()[tostring(slot)]
        if head ~= nil then
            found = true
            fn(Isaac.GetPlayer(head), Game():GetRoom())
        end
    end)
    assert(ok or not found, "Audit actor callback failed")
    return ok and found
end
local function observeEdenStart(tick)
    if not case or tick < 5 or tick > 15 then
        return
    end
    local function inventory(slot, event, key)
        return actor(slot, function(p)
            local count, items = 0, {}
            for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
                local n = p:GetCollectibleNum(id, true)
                if n > 0 then
                    count, items[tostring(id)] = count + n, n
                end
            end
            report(event, {
                key = key,
                tick = tick,
                count = count,
                items = items,
                seed = Game():GetSeeds():GetStartSeedString(),
            })
        end)
    end
    if pendingEden and inventory(pendingEden.slot, "eden_next_run", pendingEden.key) then
        inventory(1 - pendingEden.slot, "eden_next_peer", pendingEden.key)
        pendingEden = nil
    end
    if case.trigger_effects and case.trigger_effects.eden_next_run and not edenInitial then
        edenInitial = inventory(case.slot, "eden_run_initial", case.key)
    end
end
local function otherRoom(origin)
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= origin then
            return d.SafeGridIndex
        end
    end
    error("Audit seed has no ordinary second room")
end
local function moveHolderRoom()
    local target = otherRoom(native.rooms_positions()[tostring(case.slot)].index)
    -- The move is queued; cleanupRoom clears the actual destination on entry.
    actor(case.slot, function(p)
        p:SetMinDamageCooldown(case.damage_effects and 20 or 300)
    end)
    assert(native.rooms_move(case.slot, target, 0, -1))
    cleanupRoom = target
    report("room_changed", { target = target })
end
local function moveHolderFloor()
    actor(case.slot, function(p, room)
        if case.damage_effects or case.familiar_effects then
            -- Enter through the native grid collision so player departure
            -- effects follow the same path as normal play.
            local index = room:GetGridIndex(room:GetCenterPos() + Vector(80, 0))
            assert(not room:GetGridEntity(index), "Damage trial trapdoor grid is occupied")
            assert(room:SpawnGridEntity(index, GridEntityType.GRID_TRAPDOOR, 0, 187, 0))
            local trap = assert(room:GetGridEntity(index))
            trap.State = 2
            p.Position, p.Velocity = trap.Position, Vector.Zero
        else
            Game():StartStageTransition(false, 0, p)
        end
    end)
end
local damageEffects = createDamageEffects(report, actor, moveHolderRoom, moveHolderFloor)
local familiarEffects = createFamiliarEffects(report, actor, moveHolderRoom, moveHolderFloor)
local triggerEffects = createTriggerEffects(report, actor, moveHolderRoom, moveHolderFloor)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, function()
    if host then
        familiarEffects.clearAward()
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_PROJECTILE_COLLISION, function(_, projectile, collider)
    if host then
        familiarEffects.projectileCollision(projectile, collider)
        triggerEffects.projectileCollision(projectile, collider)
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_NPC_UPDATE, function(_, npc)
    if host then
        return triggerEffects.holdTarget(npc) or familiarEffects.holdTarget(npc)
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, e, amount, _, source)
    if host then
        familiarEffects.damage(e, amount, source)
        if
            case
            and case.trigger_effects
            and case.trigger_effects.taurus_trial
            and e:ToNPC()
            and source
            and source.Entity
            and source.Entity:ToPlayer()
        then
            report("taurus_native_damage", { tick = lastTick, amount = amount, seed = e.InitSeed })
        end
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
    if host then
        familiarEffects.suppressPlayerTear(tear)
        triggerEffects.suppressPlayerTear(tear)
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_NEW_LEVEL, function()
    if not host or not case or not case.damage_effects then
        return
    end
    local players = {}
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        players[#players + 1] = {
            controller = p.ControllerIndex,
            seed = p.InitSeed,
            mantle = p:GetEffects()
                :GetCollectibleEffectNum(CollectibleType.COLLECTIBLE_HOLY_MANTLE),
        }
    end
    report("damage_native_floor", { stage = Game():GetLevel():GetStage(), players = players })
end)
local function sample(label, tick)
    if not native.rooms_ready() then
        return
    end
    local records = {}
    local positions = native.rooms_positions()
    local view = positions[tostring(_IsaacLanStatus().slot)]
    for slot = 0, 1 do
        local available = actor(slot, function(p, room)
            local count, tears, projectiles, effects = 0, 0, 0, 0
            local entities = {}
            local familiarCounts = { blue_flies = 0, blue_spiders = 0 }
            local familiars, targets = {}, {}
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                count = count + 1
                tears = tears + (e.Type == EntityType.ENTITY_TEAR and 1 or 0)
                projectiles = projectiles + (e.Type == EntityType.ENTITY_PROJECTILE and 1 or 0)
                effects = effects + (e.Type == EntityType.ENTITY_EFFECT and 1 or 0)
                if case.kind ~= "stress" then
                    local key = e.Type .. "." .. e.Variant .. "." .. e.SubType
                    entities[key] = (entities[key] or 0) + 1
                end
                if case.effect_check then
                    local familiar = e:ToFamiliar()
                    if familiar then
                        local player = familiar.Player
                        familiars[#familiars + 1] = {
                            variant = familiar.Variant,
                            owner = player and player.ControllerIndex or -1,
                        }
                        if player and GetPtrHash(player) == GetPtrHash(p) then
                            if familiar.Variant == FamiliarVariant.BLUE_FLY then
                                familiarCounts.blue_flies = familiarCounts.blue_flies + 1
                            elseif familiar.Variant == FamiliarVariant.BLUE_SPIDER then
                                familiarCounts.blue_spiders = familiarCounts.blue_spiders + 1
                            end
                        end
                    end
                    if
                        case.recipe
                        and case.recipe.enemy_damage
                        and e.Type == EntityType.ENTITY_GAPER
                    then
                        targets[#targets + 1] = { seed = e.InitSeed, hp = e.HitPoints }
                    end
                end
            end
            table.sort(targets, function(a, b)
                return a.seed < b.seed
            end)
            records[#records + 1] = {
                slot = slot,
                room_visible = host
                    or (
                        positions[tostring(slot)].index == view.index
                        and positions[tostring(slot)].dimension == view.dimension
                    ),
                x = p.Position.X,
                y = p.Position.Y,
                type = p:GetPlayerType(),
                damage = p.Damage,
                delay = p.MaxFireDelay,
                speed = p.MoveSpeed,
                range = p.TearRange,
                shot_speed = p.ShotSpeed,
                luck = p.Luck,
                hearts = p:GetHearts(),
                max_hearts = p:GetMaxHearts(),
                soul = p:GetSoulHearts(),
                bone = p:GetBoneHearts(),
                eternal = p:GetEternalHearts(),
                black = p:GetBlackHearts(),
                broken = p:GetBrokenHearts(),
                shield = case.damage_effects
                        and {
                            mantle = p:GetEffects():GetCollectibleEffectNum(
                                CollectibleType.COLLECTIBLE_HOLY_MANTLE
                            ),
                            shadows = p:GetEffects():GetCollectibleEffectNum(
                                CollectibleType.COLLECTIBLE_BOOK_OF_SHADOWS
                            ),
                            invincible = p:HasInvincibility(),
                        }
                    or nil,
                coins = p:GetNumCoins(),
                bombs = p:GetNumBombs(),
                keys = p:GetNumKeys(),
                golden_bomb = p:HasGoldenBomb(),
                golden_key = p:HasGoldenKey(),
                flying = p.CanFly,
                blue_flies = p:GetNumBlueFlies(),
                blue_spiders = p:GetNumBlueSpiders(),
                owned_blue_flies = familiarCounts.blue_flies,
                owned_blue_spiders = familiarCounts.blue_spiders,
                familiars = familiars,
                targets = targets,
                pocket_slots = p:GetMaxPocketItems(),
                trinket_slots = p:GetMaxTrinkets(),
                controls_cooldown = p.ControlsCooldown,
                controls_enabled = p:AreControlsEnabled(),
                visible = p.Visible,
                dead = p:IsDead(),
                ghost = p:IsCoopGhost(),
                size = p.Size,
                scale_x = p.SpriteScale.X,
                scale_y = p.SpriteScale.Y,
                active = p:GetActiveItem(),
                temporary_count = case.kind == "collectible" and p:GetEffects()
                    :GetCollectibleEffectNum(case.id) or nil,
                charge = p:GetActiveCharge(),
                item_count = p:GetCollectibleCount(),
                target_count = case.kind == "collectible" and p:GetCollectibleNum(case.id, true)
                    or nil,
                trinket = p:GetTrinket(0),
                card = p:GetCard(0),
                pill = p:GetPill(0),
                room = native.rooms_positions()[tostring(slot)].index,
                stage = Game():GetLevel():GetStage(),
                entities = count,
                tears = tears,
                projectiles = projectiles,
                effects = effects,
                entity_types = entities,
            }
            -- Remote replica shells do not own a native room descriptor.
            -- IsClear dereferences that descriptor; only query the authority.
            if host then
                records[#records].clear = room:IsClear()
                records[#records].room_type = room:GetType()
                if case.wall_use then
                    local doors = {}
                    for doorSlot = 0, 7 do
                        local door = room:GetDoor(doorSlot)
                        if door then
                            doors[#doors + 1] = { slot = doorSlot, target = door.TargetRoomIndex }
                        end
                    end
                    records[#records].doors = doors
                end
            end
        end)
        if not available then
            records[#records + 1] = { slot = slot, missing = true }
        end
    end
    local actors = {}
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        actors[#actors + 1] = {
            index = i,
            type = p:GetPlayerType(),
            variant = p.Variant,
            controller = p.ControllerIndex,
            parent_controller = p.Parent
                    and p.Parent:ToPlayer()
                    and p.Parent:ToPlayer().ControllerIndex
                or nil,
            visible = p.Visible,
            dead = p:IsDead(),
            x = p.Position.X,
            y = p.Position.Y,
        }
    end
    seen = seen + 1
    report("sample", {
        label = label,
        tick = tick,
        players = records,
        actors = actors,
        uses = useCount,
        floor_effects = roomEffects.sample(case),
    })
end
local function shotProbe(tick)
    if not case.shot_effect or tick < 85 then
        return
    end
    actor(case.slot, function(p)
        local tears = {}
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            local tear = e:ToTear()
            local source = tear and tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
            if source and source.ControllerIndex == p.ControllerIndex then
                local data = tear:GetData()
                tears[#tears + 1] = {
                    id = data.__isaac_lan_replica or data.__isaac_lan_entity or 0,
                    age = tear.FrameCount,
                    damage = tear.CollisionDamage,
                    vx = tear.Velocity.X,
                    vy = tear.Velocity.Y,
                }
            end
        end
        report("shot_probe", { tick = tick, tears = tears })
    end)
end
local function poolProbe(label)
    if case.kind ~= "collectible" or case.id ~= CollectibleType.COLLECTIBLE_CHAOS then
        return
    end
    for slot = 0, 1 do
        actor(slot, function(p)
            local results = {}
            for i = 1, 32 do
                results[i] = Game()
                    :GetItemPool()
                    :GetCollectible(ItemPoolType.POOL_TREASURE, false, 100003 + i * 7919)
            end
            report("pool_probe", {
                label = label,
                slot = slot,
                owned = p:GetCollectibleNum(case.id, true),
                results = results,
            })
        end)
    end
end
local function observedUse(kind, id, p)
    if case and case.kind == kind and case.id == id then
        useCount = useCount + 1
        report("use_callback", {
            tick = lastTick,
            kind = kind,
            id = id,
            controller = p and p.ControllerIndex,
            x = p and p.Position.X,
            y = p and p.Position.Y,
        })
        if not host then
            report(
                "problem",
                { category = "non_native", detail = "replica executed authoritative use callback" }
            )
        end
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_USE_ITEM, function(_, id, _, p)
    observedUse("collectible", id, p)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_CARD, function(_, id, p)
    observedUse("card", id, p)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_PILL, function(_, id, p)
    observedUse("pill", id, p)
    if case and case.trigger_effects and case.trigger_effects.pill_callbacks then
        report("trigger_pill", { tick = lastTick, id = id, controller = p.ControllerIndex })
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_CURSE_EVAL, function(_, curses)
    roomEffects.curseRoll(case, curses)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
    local p = entity:ToPlayer()
    if case and p then
        local from = source and source.Entity
        report("player_damage", {
            tick = lastTick,
            controller = p.ControllerIndex,
            amount = amount,
            flags = flags,
            source_type = from and from.Type,
            source_variant = from and from.Variant,
        })
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    familiarEffects.prepare({})
    if not prepared and seen == 0 then
        return
    end
    if case.kind == "stress" then
        stress.finish()
    end
    local expected = host and exiting or not host and lastTick >= observationEnd() - 5
    report(
        expected and "case_end" or "case_aborted",
        { samples = seen, uses = useCount, expected_exit = expected }
    )
    if case.trigger_effects and case.trigger_effects.eden_next_run then
        pendingEden = { key = case.key, slot = case.slot }
    end
    edenInitial = nil
    index = index + 1
    case = audit.cases[index]
    prepared, used, moved, exiting = false, false, false, false
    placed, damaged, deathProbed = false, false, false
    useSampled = false
    floorMoved = false
    cleanupRoom = nil
    linked, chosen, started = false, false, false
    beganAt, sampleAt, useCount, seen, lastTick = nil, 0, 0, 0, 0
    lastRender = nil
    relinkAt = native.api_info().nowMs + (host and 300 or 1000)
    if not case then
        finished = true
    end
end)
local function prepare(tick)
    prepared, beganAt = true, native.api_info().nowMs
    report("case_begin", { kind = case.kind, id = case.id, slot = case.slot, split = case.split })
    roomEffects.prepare(case)
    if case.recipe and case.recipe.teleport then
        local destination = case.recipe.teleport
        local expected = { types = {} }
        if destination == "start" then
            expected.index = Game():GetLevel():GetStartingRoomIndex()
        else
            for _, name in ipairs(destination) do
                expected.types[#expected.types + 1] = assert(RoomType[name])
            end
        end
        report("teleport_target", expected)
    end
    for slot = 0, 1 do
        actor(slot, function(p, room)
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type ~= EntityType.ENTITY_PLAYER then
                    e:Remove()
                end
            end
            room:SetClear(true)
            if case.shot_effect or case.open_room then
                for grid = 0, room:GetGridSize() - 1 do
                    local e = room:GetGridEntity(grid)
                    if
                        e
                        and e:GetType() ~= GridEntityType.GRID_WALL
                        and e:GetType() ~= GridEntityType.GRID_DOOR
                    then
                        room:RemoveGridEntity(grid, 0, false)
                    end
                end
            end
            if case.kind == "stress" or case.companion then
                p:SetMinDamageCooldown(100000)
            end
            if case.recipe and case.recipe.team_hearts then
                p:AddHearts(case.recipe.team_hearts - p:GetHearts())
            end
            p.Position, p.Velocity =
                room:GetCenterPos() + Vector(
                    slot == case.slot and -65 or 65,
                    case.familiar_effects and 20 or 60
                ),
                Vector.Zero
            if slot == case.slot and case.moving_use then
                -- Directional actives need an unobstructed approach. A fixed
                -- center offset can put the split-room holder inside a rock.
                local selected, distance
                for grid = 0, room:GetGridSize() - 1 do
                    local position = room:GetGridPosition(grid)
                    local clear = true
                    for dy = -140, 20, 20 do
                        for dx = -15, 15, 15 do
                            local probe = position + Vector(dx, dy)
                            clear = clear
                                and room:IsPositionInRoom(probe, 30)
                                and room:GetGridCollisionAtPos(probe)
                                    == GridCollisionClass.COLLISION_NONE
                        end
                    end
                    local d = position:DistanceSquared(p.Position)
                    if clear and (not distance or d < distance) then
                        selected, distance = position, d
                    end
                end
                assert(selected, "No clear approach for directional item")
                p.Position = selected
                report("use_position", { x = selected.X, y = selected.Y })
            end
        end)
    end
    if case.kind ~= "stress" and not case.mega then
        actor(case.slot, function(p, room)
            -- Rerolls/consumption get a real inventory and pedestal target;
            -- attack/kill effects get an ordinary native enemy.
            p:AddCollectible(CollectibleType.COLLECTIBLE_BREAKFAST, 0, false)
            if case.coins then
                p:AddCoins(case.coins - p:GetNumCoins())
            end
            -- Damage cooldown makes the native player blink. Empty effect
            -- rooms need no protection, so keep models visible for review.
            if case.protect_use and not case.quiet_room then
                p:SetMinDamageCooldown(300)
            end
            local recipe = case.recipe or {}
            local resources = recipe.resources or {}
            if resources.coins then
                p:AddCoins(resources.coins - p:GetNumCoins())
            end
            if resources.bombs then
                p:AddBombs(resources.bombs - p:GetNumBombs())
            end
            if resources.keys then
                p:AddKeys(resources.keys - p:GetNumKeys())
            end
            if resources.hearts then
                p:AddHearts(resources.hearts - p:GetHearts())
            end
            if resources.soul then
                p:AddSoulHearts(resources.soul - p:GetSoulHearts())
            end
            if recipe.golden_bomb then
                p:AddGoldenBomb()
            end
            if case.occupied_pocket then
                p:SetCard(0, Card.CARD_FOOL)
            end
            if recipe.enemy_damage then
                for i = 1, 2 do
                    local enemy = Isaac.Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        0,
                        room:GetCenterPos() + Vector(i == 1 and -80 or 80, -70),
                        Vector.Zero,
                        nil
                    )
                    enemy:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                    enemy.MaxHitPoints, enemy.HitPoints = 200, 200
                end
                room:SetClear(false)
            end
            Isaac.Spawn(
                EntityType.ENTITY_PICKUP,
                PickupVariant.PICKUP_COLLECTIBLE,
                CollectibleType.COLLECTIBLE_BREAKFAST,
                room:GetCenterPos() + Vector(120, -60),
                Vector.Zero,
                nil
            )
            if not case.quiet_room then
                Isaac.Spawn(
                    EntityType.ENTITY_GAPER,
                    0,
                    0,
                    p.Position - Vector(0, 110),
                    Vector.Zero,
                    nil
                )
                room:SetClear(false)
            end
            if case.wall_use then
                local level = Game():GetLevel()
                local origin = native.rooms_positions()[tostring(case.slot)].index
                local offsets = { -1, -13, 1, 13 }
                local selected
                for doorSlot = 0, 3 do
                    local target = origin + offsets[doorSlot + 1]
                    if
                        room:IsDoorSlotAllowed(doorSlot)
                        and not room:GetDoor(doorSlot)
                        and target >= 0
                        and target < 169
                        and not level:GetRoomByIdx(target, 0).Data
                    then
                        selected = doorSlot
                        local wall = room:GetDoorSlotPosition(doorSlot)
                        p.Position = wall + (room:GetCenterPos() - wall):Normalized() * 20
                        break
                    end
                end
                assert(selected, "No empty door slot for wall-use prerequisite")
                report("wall_use_position", { slot = selected })
            end
        end)
    end
    damageEffects.prepare(case)
    familiarEffects.prepare(case)
    triggerEffects.prepare(case, tick)
    sample("before", tick)
    poolProbe("before")
    actor(case.slot, function(p, room)
        report("give_begin")
        if case.kind == "collectible" then
            local config = assert(Isaac.GetItemConfig():GetCollectible(case.id))
            if case.trigger_effects and case.trigger_effects.pocket_active then
                local pocketOwner = case.trigger_effects.pocket_subplayer and p:GetSubPlayer() or p
                if p:GetActiveItem(ActiveSlot.SLOT_POCKET) == case.id then
                    pocketOwner = p
                end
                report("native_pocket_prerequisite", {
                    primary = p:GetActiveItem(ActiveSlot.SLOT_POCKET),
                    subplayer = pocketOwner and pocketOwner:GetActiveItem(ActiveSlot.SLOT_POCKET)
                        or -1,
                })
                assert(
                    pocketOwner and pocketOwner:GetActiveItem(ActiveSlot.SLOT_POCKET) == case.id,
                    "Native pocket item prerequisite missing"
                )
            elseif case.trigger_effects and case.trigger_effects.native_prerequisite_only then
                assert(
                    p:GetPlayerType() == PlayerType.PLAYER_JUDAS
                        and p:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT),
                    "Native Belial prerequisites missing"
                )
            elseif case.trigger_effects and case.trigger_effects.physical_pickup then
                local pickup = Isaac.Spawn(
                    EntityType.ENTITY_PICKUP,
                    PickupVariant.PICKUP_COLLECTIBLE,
                    case.id,
                    p.Position,
                    Vector.Zero,
                    nil
                ):ToPickup()
                pickup.Wait = 0
            elseif
                not (
                    case.trigger_effects
                    and case.trigger_effects.character_before
                    and p:HasCollectible(case.id)
                )
            then
                p:AddCollectible(case.id, config.MaxCharges, true)
            end
        elseif case.kind == "trinket" then
            p:AddTrinket(case.id, true)
        elseif case.kind == "card" then
            p:SetCard(0, case.id)
        elseif case.kind == "pill" then
            local pool = Game():GetItemPool()
            local color = pool:ForceAddPillEffect(case.id)
            assert(color > 0, "Pill effect has no assigned color")
            color = color | (case.horse and PillColor.PILL_GIANT_FLAG or 0)
            local effect = pool:GetPillEffect(color, p)
            report("pill_assigned", { color = color, effect = effect })
            assert(effect == case.id, "Pill color does not resolve to the requested effect")
            case.pill_color = color
            if case.physical then
                p:SetPill(0, color)
            end
        elseif case.kind == "stress" then
            stress.prepare(case, p, room)
        end
        report("give_end")
    end)
    sample("acquired", tick)
    poolProbe("acquired")
end
local function activate(tick)
    used = true
    actor(case.slot, function(p)
        report("use_begin", { tick = tick })
        if case.kind == "collectible" then
            local config = assert(Isaac.GetItemConfig():GetCollectible(case.id))
            if config.Type == ItemType.ITEM_ACTIVE and not case.physical then
                p:UseActiveItem(case.id, 0, ActiveSlot.SLOT_PRIMARY)
            end
        elseif case.kind == "card" and not case.physical then
            p:UseCard(case.id, 0)
        elseif case.kind == "pill" and not case.physical then
            p:UsePill(case.id, case.pill_color, 0)
        end
        report("use_return", { tick = tick })
    end)
end
local function advance(tick)
    observeEdenStart(tick)
    lastTick = tick
    if not native.rooms_ready() or not case or exiting then
        return
    end
    if cleanupRoom and native.rooms_positions()[tostring(case.slot)].index == cleanupRoom then
        actor(case.slot, function(p, room)
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if
                    e.Type ~= EntityType.ENTITY_PLAYER
                    and not (case.familiar_effects and e.Type == EntityType.ENTITY_FAMILIAR)
                    and not (
                        case.trigger_effects
                        and case.trigger_effects.laser_persists_room
                        and e.Type == EntityType.ENTITY_LASER
                    )
                then
                    e:Remove()
                end
            end
            for grid = 0, room:GetGridSize() - 1 do
                local e = room:GetGridEntity(grid)
                if
                    e
                    and e:GetType() ~= GridEntityType.GRID_WALL
                    and e:GetType() ~= GridEntityType.GRID_DOOR
                then
                    room:RemoveGridEntity(grid, 0, false)
                end
            end
            room:SetClear(true)
            p.Position, p.Velocity = room:GetCenterPos(), Vector.Zero
        end)
        report("room_fixture_ready", { target = cleanupRoom, tick = tick })
        cleanupRoom = nil
    end
    if not catalogued then
        catalogued = true
        exportCatalog(report)
    end
    if not placed and tick >= 20 then
        placed = true
        local triggerRoom = triggerEffects.startingRoom(case)
        if triggerRoom then
            assert(native.rooms_move(case.slot, triggerRoom, 0, -1))
            assert(
                native.rooms_move(
                    1 - case.slot,
                    case.split and otherRoom(triggerRoom) or triggerRoom,
                    0,
                    -1
                )
            )
        elseif case.recipe and case.recipe.teleport == "start" then
            local start = Game():GetLevel():GetStartingRoomIndex()
            local origin = otherRoom(start)
            assert(native.rooms_move(case.slot, origin, 0, -1))
            assert(native.rooms_move(1 - case.slot, case.split and start or origin, 0, -1))
        elseif case.split then
            -- The starting room has an empty wall suitable for Red Key.
            -- Keep the holder there and move the teammate for this prerequisite.
            local slot = case.wall_use and (1 - case.slot) or 1
            assert(native.rooms_move(slot, otherRoom(native.rooms_positions()["0"].index), 0, -1))
        end
        return
    end
    if not prepared and tick >= 30 then
        prepare(tick)
    end
    if not prepared then
        return
    end
    local elapsed = native.api_info().nowMs - beganAt
    local useTick = case.use_tick or 60
    if case.physical and tick >= useTick - 2 and tick <= useTick + 14 then
        actor(case.slot, function(p)
            local action = (case.kind == "card" or case.kind == "pill")
                    and ButtonAction.ACTION_PILLCARD
                or ButtonAction.ACTION_ITEM
            report("input_probe", {
                tick = tick,
                action = action,
                value = Input.GetActionValue(action, p.ControllerIndex),
                triggered = Input.IsActionTriggered(action, p.ControllerIndex),
                charge = p:GetActiveCharge(),
                battery = p:GetBatteryCharge(),
                item_state = p:GetItemState(),
                x = p.Position.X,
                y = p.Position.Y,
                move_x = p:GetMovementInput().X,
                move_y = p:GetMovementInput().Y,
            })
        end)
    end
    if not used and tick >= useTick then
        activate(tick)
    end
    damageEffects.advance(case, tick)
    familiarEffects.advance(case, tick)
    triggerEffects.advance(case, tick)
    if used and tick % 30 == 0 then
        sample("observe", tick)
    end
    if
        not damaged
        and tick >= useTick + 60
        and case.kind ~= "stress"
        and not case.mega
        and not case.recipe
    then
        damaged = true
        actor(case.slot, function(p)
            if not p:IsDead() and not p:IsCoopGhost() and p:GetHearts() + p:GetSoulHearts() > 1 then
                report("damage_probe")
                p:ResetDamageCooldown()
                p:TakeDamage(1, 0, EntityRef(p), 0)
            end
        end)
    end
    if
        case.recipe
        and (case.recipe.expire_room or case.recipe.golden_lifecycle or case.recipe.eternal_lifecycle or case.room_effects and case.room_effects.floor_lifecycle)
        and not moved
        and tick >= 150
    then
        sample("before_room", tick)
        moved = true
        moveHolderRoom()
    end
    if case.recipe and case.recipe.reunite and not moved and tick >= 150 then
        moved = true
        local target = native.rooms_positions()[tostring(case.slot)]
        assert(native.rooms_move(1 - case.slot, target.index, target.dimension, -1))
        report("reunited", { tick = tick, target = target.index })
    end
    if
        case.recipe
        and (case.recipe.golden_lifecycle or case.recipe.eternal_lifecycle or case.room_effects and case.room_effects.floor_lifecycle)
        and not floorMoved
        and tick >= 240
    then
        floorMoved = true
        sample("before_floor", tick)
        moveHolderFloor()
        report("floor_requested", { tick = tick })
    end
    if (case.mega or case.companion) and not moved and tick >= 240 then
        sample("before_room", tick)
        moved = true
        local target = otherRoom(native.rooms_positions()[tostring(case.slot)].index)
        assert(native.rooms_move(case.slot, target, 0, -1))
        report("room_changed", { target = target })
    end
    if case.companion and not deathProbed and tick >= 600 then
        deathProbed = true
        actor(case.slot, function(p)
            report("owner_death_probe")
            p:ResetDamageCooldown()
            p:TakeDamage(99, 0, EntityRef(p), 0)
        end)
    end
    local endTick = observationEnd()
    local deadline = (case.mega or case.companion or case.kind == "stress") and 65000 or 16000
    if case.end_tick then
        deadline = math.max(deadline, endTick * 1000 / 30 + 15000)
    end
    if used and (tick >= endTick or elapsed >= deadline) then
        sample("after", tick)
        if case.kind == "collectible" and case.id == CollectibleType.COLLECTIBLE_CHAOS then
            actor(case.slot, function(p)
                p:RemoveCollectible(case.id)
            end)
            poolProbe("removed")
        end
        if elapsed >= deadline and tick < endTick then
            report(
                "problem",
                { category = "incomplete", detail = "case exceeded its native tick deadline" }
            )
        end
        exiting = true
        report("exit_requested")
        assert(native.net_command(Command.saveExit))
    end
end
function _IsaacLanBotFrame()
    local s = _IsaacLanStatus()
    local mask = 0
    if case and s.slot == case.slot and native.api_info().ready == 1 then
        local useTick = case.use_tick or 60
        if
            not case.recipe
            and s.verified >= useTick + 25
            and s.verified < (case.shot_effect and 240 or useTick + 80)
        then
            mask = 1 << ButtonAction.ACTION_SHOOTUP
        end
        if case.familiar_effects then
            mask = familiarEffects.input(case, s.verified)
        end
        if case.trigger_effects then
            mask = triggerEffects.input(case, s.verified)
        end
    end
    assert(native.input_bot(mask ~= 0 and 1 or 0, mask), "Unsupported audit movement/fire mask")
end
function _IsaacLanFrame()
    renders = renders + 1
    Options.FoundHUD, Options.ExtraHUDStyle = true, 1
    traceDamage("before_frame")
    local s = baseFrame()
    traceDamage("after_frame")
    local now = native.api_info().nowMs
    if case and case.kind == "stress" and s.prepared and s.verified >= 150 then
        local measured = Isaac.GetTime()
        if lastRender then
            stress.record("render", measured - lastRender)
        end
        lastRender = measured
    else
        lastRender = nil
    end
    if finished then
        if s.scene == 1 and not s.prepared then
            Isaac.DebugString("LAN_NETWORK PASS item audit batch")
        end
        return s
    end
    if
        not linked
        and s.scene == 1
        and (relinkAt > 0 and now >= relinkAt or relinkAt == 0 and renders >= (host and 300 or 360))
    then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if s.phase == Phase.lobby and not chosen then
        chosen = true
        local character = case and case.trigger_effects and case.trigger_effects.character_before
        local selected = character and s.slot == case.slot and assert(PlayerType[character]) or 0
        _IsaacLanCommand("choose", selected .. ":1")
    end
    if
        host
        and not started
        and s.phase == Phase.lobby
        and s.players == 2
        and s.ready0 == 1
        and s.ready1 == 1
    then
        started = true
        local character = case and case.trigger_effects and case.trigger_effects.character_before
        local selected = character and assert(PlayerType[character]) or 0
        _IsaacLanCommand(
            "start",
            "YV039KQF:0:"
                .. (case.slot == 0 and selected or 0)
                .. ":"
                .. (case.slot == 1 and selected or 0)
                .. ":0:0"
        )
    end
    if (s.phase == Phase.waiting or s.phase == Phase.failed) and s.phase ~= lastPhase then
        report("problem", { category = "reconnect", detail = s.error, phase = s.phase })
    end
    lastPhase = s.phase
    local active = case
        and case.physical
        and s.slot == case.slot
        and s.verified >= (case.use_tick or 60)
        and s.verified < (case.use_tick or 60) + (case.hold_ticks or 6)
    local rules = case and case.trigger_effects
    local holder = case and s.slot == case.slot
    local bomb = holder
        and rules
        and rules.bomb_trial
        and s.verified >= 70
        and s.verified < (rules.bomb_hold_until or 74)
    local priorActive = holder
        and rules
        and rules.prior_active
        and s.verified >= 45
        and s.verified < 49
    local extraUse = holder
        and rules
        and s.verified >= (case.use_tick or 60)
        and s.verified < (case.use_tick or 60) + 6
    local extraCard = extraUse and rules.use_pocket
    local extraActive = extraUse and rules.use_existing_active
    local scheduledDrop = false
    if holder and rules then
        for _, action in ipairs(rules.input_schedule or {}) do
            if s.verified >= action[1] and s.verified < action[2] then
                extraCard = extraCard or action[3] == "card"
                extraActive = extraActive or action[3] == "active"
                scheduledDrop = scheduledDrop or action[3] == "drop"
                bomb = bomb or action[3] == "bomb"
            end
        end
    end
    local repeatedActive = holder
        and rules
        and rules.repeat_uses
        and s.verified >= (case.use_tick or 60)
        and s.verified < (case.use_tick or 60) + rules.repeat_uses * (rules.repeat_interval or 30)
        and (s.verified - (case.use_tick or 60)) % (rules.repeat_interval or 30) < 6
    local discharge = holder
        and rules
        and rules.overcharge
        and ((s.verified >= 180 and s.verified < 186) or (s.verified >= 240 and s.verified < 246))
    native.test_gamepad(
        bomb and GamepadButton.bomb
            or extraCard and GamepadButton.consumable
            or active and rules and rules.pocket_active and GamepadButton.consumable
            or active and (case.kind == "card" or case.kind == "pill") and GamepadButton.consumable
            or 0,
        (
            (active and case.kind == "collectible" and not (rules and rules.pocket_active))
            or priorActive
            or extraActive
            or repeatedActive
            or discharge
        )
                and 255
            or 0,
        scheduledDrop and 255 or 0,
        0,
        case
                and case.moving_use
                and s.slot == case.slot
                and s.verified >= (case.use_tick or 60) - 5
                and s.verified < (case.use_tick or 60) + 14 + (case.hold_ticks or 6)
                and 32767
            or 0
    )
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(capture, function(tick, ...)
        before(tick, ...)
        if host then
            advance(tick)
        end
    end, function(...)
        local _, tick = ...
        if
            case
            and prepared
            and case.kind ~= "stress"
            and (tick % 30 == 0 or case.effect_check and tick >= (case.use_tick or 60) + 30)
        then
            -- Compare peers after this native simulation step, at the actual
            -- snapshot boundary, rather than against the pre-update probe.
            sample("captured", tick)
        end
        local began = Isaac.GetTime()
        local bytes = collect(...)
        if case.recipe and useCount > 0 and not useSampled then
            useSampled = true
            sample("post_use", tick)
        end
        shotProbe(tick)
        familiarEffects.sample(case, tick, true)
        triggerEffects.sample(case, tick, true)
        if case.kind == "stress" and lastTick >= 150 then
            stress.record("capture", Isaac.GetTime() - began)
            stress.record("raw_bytes", #bytes)
        end
        return bytes
    end, function(bytes, tick, ...)
        local began = Isaac.GetTime()
        local result = restore(bytes, tick, ...)
        if case.kind == "stress" and tick >= 150 then
            stress.record("apply", Isaac.GetTime() - began)
            stress.record("raw_bytes", #bytes)
        end
        if result ~= false then
            observeEdenStart(tick)
            shotProbe(tick)
            familiarEffects.sample(case, tick, false)
            triggerEffects.sample(case, tick, false)
            lastTick = tick
            if not prepared then
                prepared = true
                report(
                    "case_begin",
                    { kind = case.kind, id = case.id, slot = case.slot, split = case.split }
                )
            end
            if tick - sampleAt >= 30 then
                sampleAt = tick
                sample("replica", tick)
            end
        end
        return result
    end, present, beginFloor)
end
