return function(fields)
    local Room, Grid, Door = fields.room, fields.grid, fields.door
    -- Complete, immutable room views shared by peers in the same room/tick.
    return function(native, entity, sprite, crawlspace, types, localEffect, bossRush)
        local captureTick, captureEpoch, rooms, currentGrids, previousGrids
        local function captureDoor(door, previous)
            if not door then
                return false
            end
            local slot, target = door.Slot, door.TargetRoomIndex
            local roomType, targetType = door.CurrentRoomType, door.TargetRoomType
            local direction, locked = door.Direction, door:IsLocked()
            local busted, visible = door.Busted, door.ExtraVisible
            local pose = sprite(
                assert(native.door_sprite(door:GetSprite())),
                previous and previous[Door.sprite]
            )
            if
                previous
                and previous[Door.slot] == slot
                and previous[Door.target] == target
                and previous[Door.roomType] == roomType
                and previous[Door.targetType] == targetType
                and previous[Door.direction] == direction
                and previous[Door.locked] == locked
                and previous[Door.busted] == busted
                and previous[Door.visible] == visible
                and previous[Door.sprite] == pose
            then
                return previous
            end
            -- Wire order from sync/fields.door.
            return { slot, target, roomType, targetType, direction, locked, busted, visible, pose }
        end
        local function captureGrid(index, grid, previous)
            local door = captureDoor(grid:ToDoor(), previous and previous[Grid.door])
            local kind, variant = grid:GetType(), grid:GetVariant()
            local state, collision, data = grid.State, grid.CollisionClass, grid.VarData
            local pose = sprite(grid:GetSprite(), previous and previous[Grid.sprite])
            local seed = grid:GetSaveState().SpawnSeed
            if
                previous
                and previous[Grid.type] == kind
                and previous[Grid.variant] == variant
                and previous[Grid.state] == state
                and previous[Grid.collision] == collision
                and previous[Grid.data] == data
                and previous[Grid.sprite] == pose
                and previous[Grid.seed] == seed
                and previous[Grid.door] == door
            then
                return previous
            end
            -- Wire order from sync/fields.grid. The caller matches by grid index.
            return { index, kind, variant, state, collision, data, pose, seed, door }
        end
        local function collect(slot, previous)
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
                -- Both snapshots enumerate occupied grid indices in ascending order.
                local cursor, old = 1, previous and previous[1]
                local same = previous ~= nil
                for index = 0, room:GetGridSize() - 1 do
                    local grid = room:GetGridEntity(index)
                    if grid then
                        while old and old[Grid.index] < index do
                            cursor = cursor + 1
                            old = previous[cursor]
                        end
                        local matched = old and old[Grid.index] == index and old or nil
                        local record = captureGrid(index, grid, matched)
                        local position = #grids + 1
                        grids[position] = record
                        same = same and record == previous[position]
                    end
                end
                if same and #grids == #previous then
                    grids = previous
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
                    [Room.backdrop] = room:GetBackdropType(),
                    [Room.bossRush] = bossRush.capture(room),
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
