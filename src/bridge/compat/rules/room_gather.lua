-- Observe committed authority locations outside native room scopes. Doors,
-- cards and commands share the same entry detection and resolved teleport path.
return function(deps)
    local native, types = deps.native, deps.roomTypes
    local arrivalTimeout = 3000
    local previous, pending = {}, nil
    local function sameRoom(a, b)
        return a and b and a.index == b.index and a.dimension == b.dimension
    end
    local function cancel(slot, batch, info)
        if info.authority == 1 and info.runId == batch.run and info.worldEpoch == batch.epoch then
            native.api_cancel_move(slot, batch.destination.index, batch.destination.dimension)
        end
    end
    local function cancelPending(info)
        if pending then
            for slot in pairs(pending.waiting) do
                cancel(slot, pending, info)
            end
        end
        pending = nil
    end
    local function reset()
        if pending then
            cancelPending(native.api_info())
        end
        previous = {}
    end
    local function special(slot)
        local kind
        native.api_with_owner(slot, function()
            kind = deps.game():GetRoom():GetType()
        end)
        -- Original special types are contiguous, ending at ultra secret.
        -- A red room with ROOM_DEFAULT remains an ordinary room.
        return kind and kind > types.ROOM_DEFAULT and kind <= types.ROOM_ULTRASECRET
    end
    local function placeNear(slot, owner)
        local target
        native.api_with_owner(owner, function()
            local position = deps.player(0).Position
            target = { x = position.X, y = position.Y }
        end)
        if target then
            deps.placeNear(slot, target)
        end
    end
    local function step(info, allRooms)
        local positions, current = native.rooms_positions(), {}
        for slot = 0, info.players - 1 do
            local position = positions[tostring(slot)]
            if position and (info.connected & (1 << slot)) ~= 0 then
                current[slot] = { index = position.index, dimension = position.dimension }
            end
        end
        local before = previous
        previous = current
        local consumed = {}
        if pending then
            local valid = sameRoom(current[pending.owner], pending.destination)
                and info.nowMs - pending.started < arrivalTimeout
            for slot, source in pairs(pending.waiting) do
                consumed[slot] = true
                local position = current[slot]
                if not valid or not position or sameRoom(position, pending.destination) then
                    if valid and allRooms and sameRoom(position, pending.destination) then
                        placeNear(slot, pending.owner)
                    end
                    cancel(slot, pending, info)
                    pending.waiting[slot] = nil
                elseif not sameRoom(position, source) then
                    -- The native queue may already contain a card/door move
                    -- when it accepts our request. Finish gathering after that
                    -- move commits, within the original bounded wait.
                    if
                        native.rooms_teleport(
                            slot,
                            pending.destination.index,
                            pending.destination.dimension
                        )
                    then
                        pending.waiting[slot] = position
                    else
                        cancel(slot, pending, info)
                        pending.waiting[slot] = nil
                    end
                end
            end
            if not next(pending.waiting) then
                pending = nil
            end
            -- Special-only gatherings let players leave freely. All-room
            -- gatherings also observe subsequent exits by the leader or an
            -- already-arrived player, but never turn forced arrivals into exits.
            if not allRooms then
                return
            end
        end
        for owner = 0, info.players - 1 do
            local destination = current[owner]
            if
                before[owner]
                and destination
                and not consumed[owner]
                and not sameRoom(before[owner], destination)
                and (allRooms or special(owner))
            then
                cancelPending(info)
                local batch = {
                    owner = owner,
                    destination = destination,
                    run = info.runId,
                    epoch = info.worldEpoch,
                    started = info.nowMs,
                    waiting = {},
                }
                for slot = 0, info.players - 1 do
                    local source = current[slot]
                    if
                        source
                        and not sameRoom(source, destination)
                        and native.rooms_teleport(slot, destination.index, destination.dimension)
                    then
                        batch.waiting[slot] = source
                    end
                end
                if next(batch.waiting) then
                    pending = batch
                end
                -- Simultaneous entries choose the first logical player, once.
                -- All observed positions above become the next baseline.
                return
            end
        end
    end
    return { reset = reset, step = step }
end
