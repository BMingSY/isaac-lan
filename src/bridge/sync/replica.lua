return function(fields)
    local INVENTORY_REFRESH_TICKS, GRID_SPAWN_FALLBACK_SEED = 30, 1
    local Location = fields.location
    local Actor = fields.actor
    local Inventory = fields.inventory
    local Entity = fields.entity
    local Room = fields.room
    local Map = fields.map
    local Grid = fields.grid
    local Door = fields.door
    -- Restore in dependency order. Inventory setters can mutate shared gameplay
    -- state, so authoritative shared fields must be restored before map/HUD work.
    -- This is a staged apply, not a rollback transaction: native failures propagate
    -- to the runtime, and no completed view/tick is published on failure.
    return function(deps)
        local native, encode, decode = deps.native, deps.encode, deps.decode
        local worldSchema, floor, performance = deps.schema, deps.floor, deps.performance
        local entityCodec, vec, prediction = deps.entityCodec, deps.vec, deps.prediction
        local forms, applyInventory = deps.forms, deps.applyInventory
        local actorsPresentation, motionPresentation = deps.actors, deps.motion
        local poop, craftingBag, crawlspace = deps.poop, deps.craftingBag, deps.crawlspace
        local pills, curses, greed, deals = deps.pills, deps.curses, deps.greed, deps.deals
        local reconcileEntities, reconcileGrids, applySprite =
            deps.entitiesApply, deps.gridsApply, deps.applySprite
        local audioPresentation, itemPresentation = deps.audio, deps.items
        local pack = string.pack
        local lastInventory = {}
        local pendingBytes, pendingTick, pendingValue
        local replicas, motion = {}, {}
        local replicaRoom, receivedTick = nil, -1
        local actorVisuals = {}
        local appliedLocations
        local function locationIdentity(locations)
            local result = {}
            for _, location in ipairs(locations) do
                result[#result + 1] = {
                    location[Location.slot],
                    location[Location.dimension],
                    location[Location.index],
                }
            end
            return encode(result)
        end
        local function ref(identifier)
            local pointer = replicas[identifier]
            return pointer and pointer.Ref or nil
        end
        local function discard(e)
            -- J460 can keep a removed NPC in its floor-render queue for one update.
            -- Its replica has no native death update to turn that pose into gore;
            -- hiding before removal prevents baking the old silhouette into the floor.
            e.Visible = false
            e:Remove()
        end
        local function applyEntity(e, v, now, tick, registered)
            entityCodec.apply(e, v)
            -- Preserve ownership through EntityPtr; local allocation indices are never IDs.
            -- Entity reconciliation already resolved and validated retained refs.
            if not registered then
                local pointer = replicas[v[Entity.id]]
                local existing = pointer and pointer.Ref
                if not existing or deps.hash(existing) ~= deps.hash(e) then
                    replicas[v[Entity.id]] = deps.pointer(e)
                end
            end
            local prior = motion[v[Entity.id]]
            local actor = v[Entity.type] == deps.playerType
            local position, velocity = vec(v[Entity.position]), vec(v[Entity.velocity])
            local m = prior or {}
            m.target, m.display, m.velocity, m.at, m.tick =
                position, m.display or position, velocity, now, tick
            m.actor, m.controller = actor, actor and e:ToPlayer().ControllerIndex or -1
            m.prediction = actor and (m.prediction or prediction.new(position))
            m.attachment = deps.attachments and deps.attachments.capture(e, v)
            m.held = v[Entity.held]
            m.track = motionPresentation.track(
                m.track,
                position,
                velocity,
                now,
                tick,
                actor and 60 or 30,
                not not v[Entity.npc]
            )
            motion[v[Entity.id]] = m
        end

        local function restoreLocations(value)
            -- Register every generated descriptor before room transfer or map caching.
            -- Offscreen red rooms must also have a valid native list/cell index.
            for _, d in ipairs(value.map) do
                assert(native.room_layout(d[Map.layout]))
            end
            assert(native.room_layout(value.room[Room.layout]))
            local parts = { pack(">BB", value.connected, #value.locations) }
            for _, p in ipairs(value.locations) do
                parts[#parts + 1] = pack(">Bi4i4ff", table.unpack(p))
            end
            assert(native.rooms_sync(table.concat(parts)))
            local positions = native.rooms_positions()
            local localPosition = assert(positions[tostring(value.slot)])
            local key = localPosition.dimension .. ":" .. localPosition.index
            local roomChanged = key ~= replicaRoom
            if roomChanged then
                -- Reset before applying actors: room snapshots exclude player entities.
                -- Clearing afterward used to lose the arrival's player motion record.
                motion = {}
                replicaRoom = key
                motionPresentation.reset()
            end
            return roomChanged
        end
        local function restoreActors(value, now, tick)
            deps.restoreActorRoster(value.actors)
            for _, actor in ipairs(value.actors) do
                local p = forms.resolve(
                    actor[Actor.index],
                    actor[Actor.inventory],
                    actor[Actor.controller]
                )
                assert(
                    p and p.ControllerIndex == actor[Actor.controller],
                    "Replica actor roster differs: index="
                        .. actor[Actor.index]
                        .. " expectedController="
                        .. actor[Actor.controller]
                        .. " actualController="
                        .. (p and p.ControllerIndex or -1)
                        .. " expectedType="
                        .. actor[Actor.inventory][Inventory.type]
                        .. " actualType="
                        .. (p and p:GetPlayerType() or -1)
                )
                if p:IsCoopGhost() ~= actor[Actor.inventory][Inventory.ghost] then
                    assert(
                        native.actor_ghost(
                            actor[Actor.index],
                            actor[Actor.inventory][Inventory.ghost] and 1 or 0
                        )
                    )
                end
                local inventory = actor[Actor.inventory]
                -- Item/health setters and familiars stay in this actor's room. The
                -- native resource broadcast restores the whole team's shared pool;
                -- subsequent actor snapshots see the same count and apply no delta.
                assert(native.rooms_with_player(actor[Actor.controller] - 1, function()
                    applyInventory(
                        p,
                        actor[Actor.inventory],
                        not deps.sameInventory(
                                lastInventory[actor[Actor.entity][Entity.id]],
                                inventory
                            )
                            or tick % INVENTORY_REFRESH_TICKS == 0
                    )
                    deps.temporaryEffects.apply(p, actor[Actor.temporaryEffects])
                end, 1))
                lastInventory[actor[Actor.entity][Entity.id]] = inventory
                applyEntity(p, actor[Actor.entity], now, tick)
                actorsPresentation.apply(p, actor)
                poop.apply(p, actor[Actor.poop])
                craftingBag.apply(p, actor[Actor.craftingBag])
            end
            forms.prune(replicas, motion, lastInventory, value.actors)
        end
        local function restoreShared(value, level)
            pills.apply(value.pills)
            -- Inventory setters can clear local curses. The shared authoritative mask
            -- must win after those native side effects, before map/HUD caching.
            local cursesChanged = curses.apply(level, value.curses)
            greed.apply(value.greed)
            deals.apply(value.deals)
            return cursesChanged
        end
        local function restoreMap(value, level, roomChanged, cursesChanged)
            local mapChanged = roomChanged or cursesChanged
            for _, d in ipairs(value.map) do
                local ok, pickupsChanged = native.map_pickups(d[Map.pickups])
                assert(ok)
                mapChanged = mapChanged or pickupsChanged
                local descriptor = level:GetRoomByIdx(d[Map.index], d[Map.dimension])
                if descriptor and descriptor.Data then
                    mapChanged = mapChanged
                        or descriptor.DisplayFlags ~= d[Map.display]
                        or descriptor.VisitedCount ~= d[Map.visited]
                        or descriptor.Clear ~= d[Map.clear]
                        or descriptor.Flags ~= d[Map.flags]
                    descriptor.DisplayFlags, descriptor.VisitedCount, descriptor.Clear, descriptor.ClearCount, descriptor.Flags =
                        d[Map.display],
                        d[Map.visited],
                        d[Map.clear],
                        d[Map.clearCount],
                        d[Map.flags]
                end
            end
            return mapChanged
        end
        local function restoreRoom(value, game, now, tick, mapChanged)
            -- DisplayFlags already contain the host's visibility result. Recomputing
            -- it here both overrides that result and walks transient empty descriptors
            -- while the replica is replacing a room.
            assert(native.rooms_with_player(value.slot, function()
                local room = game:GetRoom()
                local data = value.room
                assert(native.room_water_current(data[Room.current][1], data[Room.current][2]))
                crawlspace.apply(data[Room.crawlspace])
                assert(native.room_rails(data[Room.rails]))
                local missingTears = reconcileEntities(data[Room.entities], {
                    ref = ref,
                    key = deps.hash,
                    spawn = function(v, spawner, subtype)
                        return game:Spawn(
                            v[Entity.type],
                            v[Entity.variant],
                            vec(v[Entity.position]),
                            vec(v[Entity.velocity]),
                            spawner,
                            subtype,
                            v[Entity.seed]
                        )
                    end,
                    discard = discard,
                    reclaim = function()
                        room:Update()
                    end,
                    apply = function(e, v, registered)
                        applyEntity(e, v, now, tick, registered)
                    end,
                    entities = deps.entities,
                    link = entityCodec.link,
                    localEffect = entityCodec.localEffect,
                })
                performance.counter("missing_player_tears", missingTears or 0)
                -- Visible actors share this room's graph. Offscreen actors carry
                -- zero links, clearing references retained from the previous view.
                for _, actor in ipairs(value.actors) do
                    entityCodec.link(
                        assert(ref(actor[Actor.entity][Entity.id])),
                        actor[Actor.entity],
                        ref
                    )
                end
                assert(native.door_slot(-1))
                reconcileGrids(data[Room.grids], {
                    get = function(index)
                        return room:GetGridEntity(index)
                    end,
                    size = function()
                        return room:GetGridSize()
                    end,
                    remove = function(index)
                        assert(native.grid_remove(index))
                    end,
                    spawn = function(v)
                        if v[Grid.door] then
                            assert(native.door_slot(v[Grid.door][Door.slot], v[Grid.index]))
                        else
                            room:SpawnGridEntity(
                                v[Grid.index],
                                v[Grid.type],
                                v[Grid.variant],
                                v[Grid.seed] ~= 0 and v[Grid.seed] or GRID_SPAWN_FALLBACK_SEED,
                                v[Grid.data]
                            )
                        end
                    end,
                    apply = function(grid, v)
                        -- Door variants change when locks/bars change. Preserve the
                        -- native door-slot pointer instead of destroying that door.
                        if grid:GetVariant() ~= v[Grid.variant] then
                            assert(native.grid_variant(grid:GetSprite(), v[Grid.variant]))
                        end
                        if v[Grid.door] then
                            local door = assert(grid:ToDoor())
                            local d = v[Grid.door]
                            if
                                door.CurrentRoomType ~= d[Door.roomType]
                                or door.TargetRoomType ~= d[Door.targetType]
                            then
                                door:SetRoomTypes(d[Door.roomType], d[Door.targetType])
                            end
                            if door:IsLocked() ~= d[Door.locked] then
                                door:SetLocked(d[Door.locked])
                            end
                            door.Slot, door.TargetRoomIndex, door.Direction =
                                d[Door.slot], d[Door.target], d[Door.direction]
                            assert(native.door_slot(d[Door.slot], v[Grid.index], grid:GetSprite()))
                            door.Busted, door.ExtraVisible = d[Door.busted], d[Door.visible]
                            applySprite(
                                assert(native.door_sprite(door:GetSprite())),
                                d[Door.sprite]
                            )
                        end
                        grid.State, grid.CollisionClass, grid.VarData =
                            v[Grid.state], v[Grid.collision], v[Grid.data]
                        applySprite(grid:GetSprite(), v[Grid.sprite])
                    end,
                })
                room:SetClear(data[Room.clear])
                assert(native.music_state(data[Room.music]))
                if mapChanged then
                    assert(native.map_refresh())
                end
            end))
        end
        local function commit(value, tick, ack)
            if deps.hits then
                deps.hits.confirm(value, tick, deps.now(), ref)
            end
            if deps.attacks then
                deps.attacks.confirm(value, tick, ack, deps.now(), ref)
            end
            for identifier, p in pairs(replicas) do
                if not p.Ref then
                    replicas[identifier] = nil
                    motion[identifier] = nil
                    lastInventory[identifier] = nil
                end
            end
            performance.counter("entities", #value.room[Room.entities])
            performance.counter("grids", #value.room[Room.grids])
            performance.counter("map_rooms", #value.map)
            for _, m in pairs(motion) do
                if m.actor and m.controller == value.slot + 1 then
                    m.prediction:confirm(m.target, ack, m.velocity * 60, tick)
                end
            end
            assert(native.rooms_with_player(value.slot, function()
                audioPresentation.apply(value.sound, tick)
                if deps.roomPresentation then
                    deps.roomPresentation.apply(value)
                end
            end))
            assert(native.presentation_events(value.presentation))
            itemPresentation.apply(value.slot, value.items)
            if deps.applyChallenge then
                deps.applyChallenge(value.challenge)
            end
            actorVisuals, receivedTick = value.actors, tick
        end
        restoreActors = performance.wrap("apply.actors", restoreActors)
        restoreRoom = performance.wrap("apply.room", restoreRoom)
        restoreLocations = performance.wrap("apply.locations", restoreLocations)
        restoreMap = performance.wrap("apply.map", restoreMap)
        commit = performance.wrap("apply.commit", commit)
        local stableBytes, stableValue
        local function apply(bytes, tick, ack, betweenUpdates, stable)
            performance.resources()
            if floor.waiting() then
                pendingBytes, pendingTick, pendingValue = nil, nil, nil
                return false
            end
            -- A half-update may defer a view to the next full update. Retain its
            -- immutable decoded tree until preflight succeeds or a newer view arrives.
            if pendingBytes ~= bytes or pendingTick ~= tick then
                pendingBytes, pendingTick, pendingValue = nil, nil, nil
                local decoded = worldSchema.unpack(decode(bytes), tick)
                if deps.hits then
                    deps.hits.validate(decoded.combat)
                end
                if stable and #stable > 0 then
                    assert(deps.layers, "Missing view dependency decoder")
                    if stableBytes ~= stable then
                        stableValue, stableBytes = decode(stable), stable
                    end
                    decoded = deps.layers.join(decoded, stableValue)
                end
                pendingBytes, pendingTick, pendingValue = bytes, tick, decoded
            end
            local value = pendingValue
            if betweenUpdates then
                -- Room transfers and roster replacements can allocate native room
                -- objects. Keep them on the full update path, before native cleanup.
                if locationIdentity(value.locations) ~= appliedLocations then
                    return false
                end
                for i, actor in ipairs(value.actors) do
                    local prior = actorVisuals[i]
                    if
                        not prior
                        or actor[Actor.index] ~= prior[Actor.index]
                        or actor[Actor.controller] ~= prior[Actor.controller]
                        or actor[Actor.entity][Entity.id] ~= prior[Actor.entity][Entity.id]
                        or actor[Actor.inventory][Inventory.type]
                            ~= prior[Actor.inventory][Inventory.type]
                    then
                        return false
                    end
                end
                if #value.actors ~= #actorVisuals then
                    return false
                end
            end
            local game = deps.game()
            local level = game:GetLevel()
            if not floor.ready(level, value.epoch, value.stage, value.stageType) then
                return false
            end
            -- Never reuse a tree after native restoration has started, including failure.
            pendingBytes, pendingTick, pendingValue = nil, nil, nil
            deps.glitched.apply(value.glitched)
            local roomChanged = restoreLocations(value)
            native.state_clock(value.frame)
            assert(native.net_progress(value.progress))
            local now = deps.now()
            if motionPresentation.observe then
                motionPresentation.observe(value.captured, now)
            end
            restoreActors(value, now, tick)
            local cursesChanged = restoreShared(value, level)
            local mapChanged = restoreMap(value, level, roomChanged, cursesChanged)
            restoreRoom(value, game, now, tick, mapChanged)
            -- Reclaiming removed NPCs runs a native room update and can advance
            -- Greed waves. Finish the snapshot with the authoritative counter.
            greed.apply(value.greed)
            commit(value, tick, ack)
            appliedLocations = locationIdentity(value.locations)
            return true
        end
        local function actorPose(player)
            local hash = deps.hash(player)
            for _, actor in ipairs(actorVisuals) do
                local id = actor[Actor.entity][Entity.id]
                local current = ref(id)
                if current and deps.hash(current) == hash then
                    return deps.pose(motion, id, player.ControllerIndex, deps.now())
                end
            end
        end

        local function resetView()
            if deps.hits then
                deps.hits.reset()
            end
            if deps.attacks then
                deps.attacks.reset()
            end
            stableBytes, stableValue = nil, nil
            pendingBytes, pendingTick, pendingValue = nil, nil, nil
            motion, actorVisuals, replicaRoom = {}, {}, nil
            appliedLocations = nil
            if deps.roomPresentation then
                deps.roomPresentation.reset()
            end
        end
        return {
            apply = apply,
            actorPose = actorPose,
            present = function(input, sequence)
                return motionPresentation.present(
                    input,
                    sequence,
                    actorVisuals,
                    motion,
                    ref,
                    receivedTick
                )
            end,
            resetView = resetView,
            reset = function()
                resetView()
                replicas, lastInventory, receivedTick = {}, {}, -1
                actorsPresentation.reset()
                motionPresentation.reset(true)
            end,
        }
    end
end
