return function(fields)
    local Map, Location = fields.map, fields.location
    local Actor = fields.actor
    -- One immutable capture generation per (floor epoch, tick). Peer-specific
    -- room/visual/event projections share common data and encoded fragments.
    return function(deps)
        local native, encode, worldSchema = deps.native, deps.encode, deps.schema
        local entity, inventory, sprite = deps.entity, deps.inventory, deps.sprite
        local poop, craftingBag = deps.poop, deps.craftingBag
        local captureTick, captureEpoch, captureActors, captureVisuals = nil, nil, {}, {}
        local captureEncoded, locations, shared = {}, nil, nil
        local captureStarted = 0
        local roomState = deps.roomFactory()
        local function reset()
            captureTick, captureEpoch = nil, nil
            captureActors, captureVisuals, captureEncoded = {}, {}, {}
            locations, shared = nil, nil
            roomState = deps.roomFactory()
        end
        local function capture(slot, tick, layered)
            local game = deps.game()
            local level = game:GetLevel()
            local epoch = native.net_floor_epoch()
            if captureTick ~= tick or captureEpoch ~= epoch then
                captureTick, captureEpoch = tick, epoch
                captureStarted = deps.clock and deps.clock() or 0
                captureActors, captureVisuals, captureEncoded = {}, {}, {}
                locations, shared = nil, nil
            end
            locations = locations or native.rooms_positions()
            local actors = {}
            local view = assert(locations[tostring(slot)])
            for index = 0, game:GetNumPlayers() - 1 do
                local p = deps.player(index)
                local base = captureActors[index]
                if not base then
                    base = {
                        [Actor.index] = index,
                        [Actor.controller] = p.ControllerIndex,
                        [Actor.entity] = entity(p, false),
                        [Actor.inventory] = inventory(p),
                        [Actor.visuals] = {},
                        [Actor.pose] = false,
                        [Actor.poop] = poop.capture(p),
                        [Actor.craftingBag] = craftingBag.capture(p),
                        [Actor.temporaryEffects] = deps.temporaryEffects.capture(p),
                        [Actor.babySkin] = p:GetBabySkin(),
                    }
                    captureActors[index] = base
                end
                local position = locations[tostring(p.ControllerIndex - 1)]
                if
                    position
                    and position.index == view.index
                    and position.dimension == view.dimension
                then
                    local full = captureVisuals[index]
                    if not full then
                        local visuals = {}
                        for _, s in
                            ipairs(
                                assert(
                                    native.actor_sprites(index, p:GetSprite()),
                                    "Native actor visual layout mismatch"
                                )
                            )
                        do
                            visuals[#visuals + 1] = sprite(s)
                        end
                        full = {
                            [Actor.index] = index,
                            [Actor.controller] = p.ControllerIndex,
                            [Actor.entity] = entity(p),
                            [Actor.inventory] = base[Actor.inventory],
                            [Actor.visuals] = visuals,
                            [Actor.pose] = assert(native.actor_pose(p:GetSprite())),
                            [Actor.poop] = base[Actor.poop],
                            [Actor.craftingBag] = base[Actor.craftingBag],
                            [Actor.temporaryEffects] = base[Actor.temporaryEffects],
                            [Actor.babySkin] = base[Actor.babySkin],
                        }
                        captureVisuals[index] = full
                    end
                    actors[#actors + 1] = full
                else
                    actors[#actors + 1] = base
                end
                local shared = actors[#actors]
                if captureEncoded[shared] == nil then
                    captureEncoded[shared] = false
                end
            end
            if not shared then
                local loc = {}
                local heads = native.rooms_heads()
                for player = 0, 3 do
                    local at = locations[tostring(player)]
                    if at then
                        local position = deps.player(heads[tostring(player)]).Position
                        loc[#loc + 1] = {
                            [Location.slot] = player,
                            [Location.dimension] = at.dimension,
                            [Location.index] = at.index,
                            [Location.x] = position.X,
                            [Location.y] = position.Y,
                        }
                    end
                end
                deps.reconcileShared(level, actors)
                local map, included = {}, {}
                local function addRoom(d, index, dimension)
                    local key = dimension .. ":" .. index
                    if included[key] then
                        return
                    end
                    included[key] = true
                    map[#map + 1] = {
                        [Map.index] = index,
                        [Map.display] = d.DisplayFlags,
                        [Map.visited] = d.VisitedCount,
                        [Map.clear] = d.Clear,
                        [Map.clearCount] = d.ClearCount,
                        [Map.flags] = d.Flags,
                        [Map.dimension] = dimension,
                        [Map.pickups] = native.map_pickups(index, dimension),
                        [Map.layout] = native.room_layout(index, dimension),
                    }
                end
                local rooms = level:GetRooms()
                for i = 0, rooms.Size - 1 do
                    local d = rooms:Get(i)
                    for dimension = 0, 2 do
                        local match = level:GetRoomByIdx(d.SafeGridIndex, dimension)
                        if match and match.Data and match.ListIndex == d.ListIndex then
                            addRoom(d, d.SafeGridIndex, dimension)
                            break
                        end
                    end
                end
                -- Off-map descriptors are absent from Level:GetRooms(). Remote
                -- actor inventory still needs their native room metadata.
                for _, at in pairs(locations) do
                    if at.index < 0 then
                        local d = level:GetRoomByIdx(at.index, at.dimension)
                        assert(d and d.Data, "Missing occupied special-room descriptor")
                        addRoom(d, at.index, at.dimension)
                    end
                end
                shared = {
                    frame = game:GetFrameCount(),
                    captured = captureStarted,
                    stage = level:GetStage(),
                    stageType = level:GetStageType(),
                    connected = native.rooms_connected(),
                    locations = loc,
                    map = map,
                    progress = native.net_progress(),
                    epoch = epoch,
                    curses = deps.curses.capture(level),
                    greed = deps.greed.capture(),
                    deals = deps.deals.capture(),
                    pills = deps.pills.capture(),
                    glitched = deps.glitched.capture(),
                    challenge = deps.challenge and deps.challenge() or false,
                }
                -- Memoize only immutable tuples; per-peer event queues still drain
                -- separately, even when both peers are looking at the same room.
                captureEncoded[shared.locations] = false
                captureEncoded[shared.map] = false
            end
            local room = roomState(slot, tick, epoch, view)
            if captureEncoded[room] == nil then
                captureEncoded[room] = false
            end
            local value = {}
            for name, field in pairs(shared) do
                value[name] = field
            end
            value.tick, value.actors, value.slot, value.room = tick, actors, slot, room
            if deps.projectMap then
                value.map = deps.projectMap(shared.map, slot)
            end
            value.sound = deps.audio.capture(slot)
            value.presentation = native.presentation_events(slot)
            value.items = deps.items.capture(slot)
            value.combat = native.combat_events and assert(native.combat_events(slot)) or nil
            if layered then
                local realtime, stable = deps.layers.split(value, captureEncoded)
                return encode(worldSchema.pack(realtime), captureEncoded),
                    encode(stable, captureEncoded)
            end
            return encode(worldSchema.pack(value), captureEncoded)
        end
        return { capture = capture, reset = reset }
    end
end
