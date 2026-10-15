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
    local replicas, motion = {}, {}
    local replicaRoom, receivedTick = nil, -1
    local actorVisuals = {}
    local appliedLocations
    local function locationIdentity(locations)
        local result = {}
        for _, location in ipairs(locations) do
            result[#result + 1] = { location[1], location[2], location[3] }
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
    local function applyEntity(e, v, now, tick)
        entityCodec.apply(e, v)
        -- Preserve ownership through EntityPtr; local allocation indices are never IDs.
        replicas[v[1]] = deps.pointer(e)
        local prior = motion[v[1]]
        local actor = e.Type == deps.playerType
        local position, velocity = vec(v[6]), vec(v[7])
        motion[v[1]] = {
            target = position,
            display = prior and prior.display or position,
            velocity = velocity,
            at = now,
            tick = tick,
            actor = actor,
            controller = actor and e:ToPlayer().ControllerIndex or -1,
            prediction = actor and (prior and prior.prediction or prediction.new(position)),
            track = motionPresentation.track(
                prior and prior.track,
                position,
                velocity * (actor and 60 or 30),
                now,
                tick
            ),
            doorway = prior and prior.doorway,
        }
    end

    local function restoreLocations(value)
        -- Register every generated descriptor before room transfer or map caching.
        -- Offscreen red rooms must also have a valid native list/cell index.
        for _, d in ipairs(value.map) do
            assert(native.room_layout(d[9]))
        end
        assert(native.room_layout(value.room[6]))
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
        for _, actor in ipairs(value.actors) do
            local p = forms.resolve(actor[1], actor[4], actor[2])
            assert(
                p and p.ControllerIndex == actor[2],
                "Replica actor roster differs: index="
                    .. actor[1]
                    .. " expectedController="
                    .. actor[2]
                    .. " actualController="
                    .. (p and p.ControllerIndex or -1)
                    .. " expectedType="
                    .. actor[4][1]
                    .. " actualType="
                    .. (p and p:GetPlayerType() or -1)
            )
            if p:IsCoopGhost() ~= actor[4][9] then
                assert(native.actor_ghost(actor[1], actor[4][9] and 1 or 0))
            end
            local encoded = encode({ actor[4][1], actor[4][2], actor[4][6] })
            -- Item/health setters and familiars stay in this actor's room. The
            -- native resource broadcast restores the whole team's shared pool;
            -- subsequent actor snapshots see the same count and apply no delta.
            assert(native.rooms_with_player(actor[2] - 1, function()
                applyInventory(p, actor[4], lastInventory[actor[3][1]] ~= encoded or tick % 30 == 0)
            end, 1))
            lastInventory[actor[3][1]] = encoded
            applyEntity(p, actor[3], now, tick)
            actorsPresentation.apply(p, actor)
            poop.apply(p, actor[7])
            craftingBag.apply(p, actor[8])
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
            local ok, pickupsChanged = native.map_pickups(d[8])
            assert(ok)
            mapChanged = mapChanged or pickupsChanged
            local descriptor = level:GetRoomByIdx(d[1], d[7])
            if descriptor and descriptor.Data then
                mapChanged = mapChanged
                    or descriptor.DisplayFlags ~= d[2]
                    or descriptor.VisitedCount ~= d[3]
                    or descriptor.Clear ~= d[4]
                    or descriptor.Flags ~= d[6]
                descriptor.DisplayFlags, descriptor.VisitedCount, descriptor.Clear, descriptor.ClearCount, descriptor.Flags =
                    d[2], d[3], d[4], d[5], d[6]
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
            assert(native.room_water_current(data[8][1], data[8][2]))
            crawlspace.apply(data[7])
            assert(native.room_rails(data[9]))
            reconcileEntities(data[3], {
                ref = ref,
                key = deps.hash,
                spawn = function(v, spawner, subtype)
                    return game:Spawn(v[2], v[3], vec(v[6]), vec(v[7]), spawner, subtype, v[5])
                end,
                discard = discard,
                reclaim = function()
                    room:Update()
                end,
                apply = function(e, v)
                    applyEntity(e, v, now, tick)
                end,
                entities = deps.entities,
                link = entityCodec.link,
                localEffect = entityCodec.localEffect,
            })
            -- Visible actors share this room's entity graph; offscreen actors
            -- carry no visual links and their rooms may only be replica shells.
            for _, actor in ipairs(value.actors) do
                if actor[3][10] then
                    entityCodec.link(assert(ref(actor[3][1])), actor[3], ref)
                end
            end
            assert(native.door_slot(-1))
            reconcileGrids(data[4], {
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
                    if v[9] then
                        assert(native.door_slot(v[9][1], v[1]))
                    else
                        room:SpawnGridEntity(v[1], v[2], v[3], v[8] ~= 0 and v[8] or 1, v[6])
                    end
                end,
                apply = function(grid, v)
                    -- Door variants change when locks/bars change. Preserve the
                    -- native door-slot pointer instead of destroying that door.
                    if grid:GetVariant() ~= v[3] then
                        assert(native.grid_variant(grid:GetSprite(), v[3]))
                    end
                    if v[9] then
                        local door = assert(grid:ToDoor())
                        local d = v[9]
                        if door.CurrentRoomType ~= d[3] or door.TargetRoomType ~= d[4] then
                            door:SetRoomTypes(d[3], d[4])
                        end
                        if door:IsLocked() ~= d[6] then
                            door:SetLocked(d[6])
                        end
                        door.Slot, door.TargetRoomIndex, door.Direction = d[1], d[2], d[5]
                        assert(native.door_slot(d[1], v[1], grid:GetSprite()))
                        door.Busted, door.ExtraVisible = d[7], d[8]
                        applySprite(assert(native.door_sprite(door:GetSprite())), d[9])
                    end
                    grid.State, grid.CollisionClass, grid.VarData = v[4], v[5], v[6]
                    applySprite(grid:GetSprite(), v[7])
                end,
            })
            room:SetClear(data[1])
            assert(native.music_state(data[5]))
            if mapChanged then
                assert(native.map_refresh())
            end
        end))
    end
    local function commit(value, tick, ack)
        for identifier, p in pairs(replicas) do
            if not p.Ref then
                replicas[identifier] = nil
                motion[identifier] = nil
                lastInventory[identifier] = nil
            end
        end
        performance.counter("entities", #value.room[3])
        performance.counter("grids", #value.room[4])
        performance.counter("map_rooms", #value.map)
        for _, m in pairs(motion) do
            if m.actor and m.controller == value.slot + 1 then
                m.prediction:confirm(m.target, ack, m.velocity * 60)
            end
        end
        assert(native.rooms_with_player(value.slot, function()
            audioPresentation.apply(value.sound, tick)
        end))
        assert(native.presentation_events(value.presentation))
        itemPresentation.apply(value.slot, value.items)
        actorVisuals, receivedTick = value.actors, tick
    end
    local function apply(bytes, tick, ack, betweenUpdates)
        performance.resources()
        if floor.waiting() then
            return false
        end
        local value = worldSchema.unpack(decode(bytes), tick)
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
                    or actor[1] ~= prior[1]
                    or actor[2] ~= prior[2]
                    or actor[3][1] ~= prior[3][1]
                    or actor[4][1] ~= prior[4][1]
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
        local roomChanged = restoreLocations(value)
        native.state_clock(value.frame)
        assert(native.net_progress(value.progress))
        local now = deps.now()
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
            local id = actor[3][1]
            local current = ref(id)
            if current and deps.hash(current) == hash then
                return deps.pose(motion, id, player.ControllerIndex, deps.now())
            end
        end
    end

    local function resetView()
        motion, actorVisuals, replicaRoom = {}, {}, nil
        appliedLocations = nil
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
            motionPresentation.reset()
        end,
    }
end
