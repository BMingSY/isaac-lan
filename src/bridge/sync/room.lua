return function(fields)
    local Room, Grid, Door = fields.room, fields.grid, fields.door
    -- Complete, immutable room views shared by peers in the same room/tick.
    return function(native, entity, sprite, crawlspace, types, localEffect)
        local captureTick, captureEpoch, rooms, currentGrids, previousGrids
        local function collect(slot, previous)
            local value
            assert(native.rooms_with_player(slot, function()
                local room = Game():GetRoom()
                local entities, grids = {}, {}
                local oldGrids = {}
                for _, grid in ipairs(previous or {}) do
                    oldGrids[grid[Grid.index]] = grid
                end
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if
                        e:Exists()
                        and e.Type ~= types.ENTITY_PLAYER
                        and not (localEffect and localEffect(e))
                    then
                        entities[#entities + 1] = entity(e)
                    end
                end
                for index = 0, room:GetGridSize() - 1 do
                    local grid = room:GetGridEntity(index)
                    if grid then
                        local old = oldGrids[index]
                        local door = grid:ToDoor()
                        local oldDoor = old and old[Grid.door]
                        local extra = door
                                and {
                                    [Door.slot] = door.Slot,
                                    [Door.target] = door.TargetRoomIndex,
                                    [Door.roomType] = door.CurrentRoomType,
                                    [Door.targetType] = door.TargetRoomType,
                                    [Door.direction] = door.Direction,
                                    [Door.locked] = door:IsLocked(),
                                    [Door.busted] = door.Busted,
                                    [Door.visible] = door.ExtraVisible,
                                    [Door.sprite] = sprite(
                                        assert(native.door_sprite(door:GetSprite())),
                                        oldDoor and oldDoor[Door.sprite]
                                    ),
                                }
                            or false
                        if extra and oldDoor then
                            local same = true
                            for field, value in ipairs(extra) do
                                same = same and value == oldDoor[field]
                            end
                            if same then
                                extra = oldDoor
                            end
                        end
                        local value = {
                            [Grid.index] = index,
                            [Grid.type] = grid:GetType(),
                            [Grid.variant] = grid:GetVariant(),
                            [Grid.state] = grid.State,
                            [Grid.collision] = grid.CollisionClass,
                            [Grid.data] = grid.VarData,
                            [Grid.sprite] = sprite(grid:GetSprite(), old and old[Grid.sprite]),
                            [Grid.seed] = grid:GetSaveState().SpawnSeed,
                            [Grid.door] = extra,
                        }
                        if old then
                            local same = true
                            for field, item in ipairs(value) do
                                same = same and item == old[field]
                            end
                            if same then
                                value = old
                            end
                        end
                        grids[#grids + 1] = value
                    end
                end
                local old = previous
                if old and #old == #grids then
                    local same = true
                    for index, grid in ipairs(grids) do
                        same = same and grid == old[index]
                    end
                    if same then
                        grids = old
                    end
                end
                local current = room:GetWaterCurrent()
                value = {
                    [Room.clear] = room:IsClear(),
                    [Room.frame] = room:GetFrameCount(),
                    [Room.entities] = entities,
                    [Room.grids] = grids,
                    [Room.music] = native.music_state(),
                    [Room.layout] = native.room_layout(),
                    [Room.crawlspace] = crawlspace.capture(),
                    [Room.current] = { current.X, current.Y },
                    [Room.rails] = assert(native.room_rails()),
                }
            end))
            return value
        end
        return function(slot, tick, epoch, location)
            if tick ~= captureTick or epoch ~= captureEpoch then
                previousGrids = epoch == captureEpoch
                        and captureTick
                        and tick > captureTick
                        and currentGrids
                    or {}
                captureTick, captureEpoch, rooms, currentGrids = tick, epoch, {}, {}
            end
            local key = location.dimension .. ":" .. location.index
            if not rooms[key] then
                rooms[key] = collect(slot, previousGrids[key])
                currentGrids[key] = rooms[key][Room.grids]
                previousGrids[key] = nil
            end
            return rooms[key]
        end
    end
end
