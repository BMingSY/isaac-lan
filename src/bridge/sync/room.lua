-- Complete, immutable room views shared by peers in the same room/tick.
return function(native, entity, sprite, crawlspace, types)
    local captureTick, captureEpoch, rooms
    local function collect(slot)
        local value
        assert(native.rooms_with_player(slot, function()
            local room = Game():GetRoom()
            local entities, grids = {}, {}
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:Exists() and e.Type ~= types.ENTITY_PLAYER then
                    entities[#entities + 1] = entity(e)
                end
            end
            for index = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(index)
                if grid then
                    local door = grid:ToDoor()
                    local extra = door
                            and {
                                door.Slot,
                                door.TargetRoomIndex,
                                door.CurrentRoomType,
                                door.TargetRoomType,
                                door.Direction,
                                door:IsLocked(),
                                door.Busted,
                                door.ExtraVisible,
                                sprite(assert(native.door_sprite(door:GetSprite()))),
                            }
                        or false
                    grids[#grids + 1] = {
                        index,
                        grid:GetType(),
                        grid:GetVariant(),
                        grid.State,
                        grid.CollisionClass,
                        grid.VarData,
                        sprite(grid:GetSprite()),
                        grid:GetSaveState().SpawnSeed,
                        extra,
                    }
                end
            end
            value = {
                room:IsClear(),
                room:GetFrameCount(),
                entities,
                grids,
                native.music_state(),
                native.room_layout(),
                crawlspace.capture(),
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
