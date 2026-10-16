return function(fields)
    local Room, Grid, Door = fields.room, fields.grid, fields.door
    -- Complete, immutable room views shared by peers in the same room/tick.
    return function(native, entity, sprite, crawlspace, types, localEffect)
        local captureTick, captureEpoch, rooms
        local function collect(slot)
            local value
            assert(native.rooms_with_player(slot, function()
                local room = Game():GetRoom()
                local entities, grids = {}, {}
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
                        local door = grid:ToDoor()
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
                                        assert(native.door_sprite(door:GetSprite()))
                                    ),
                                }
                            or false
                        grids[#grids + 1] = {
                            [Grid.index] = index,
                            [Grid.type] = grid:GetType(),
                            [Grid.variant] = grid:GetVariant(),
                            [Grid.state] = grid.State,
                            [Grid.collision] = grid.CollisionClass,
                            [Grid.data] = grid.VarData,
                            [Grid.sprite] = sprite(grid:GetSprite()),
                            [Grid.seed] = grid:GetSaveState().SpawnSeed,
                            [Grid.door] = extra,
                        }
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
                captureTick, captureEpoch, rooms = tick, epoch, {}
            end
            local key = location.dimension .. ":" .. location.index
            if not rooms[key] then
                rooms[key] = collect(slot)
            end
            return rooms[key]
        end
    end
end
