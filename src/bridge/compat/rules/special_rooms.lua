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
    local function reset()
        if pending then
            local info = native.api_info()
            for slot in pairs(pending.waiting) do
                cancel(slot, pending, info)
            end
        end
        previous, pending = {}, nil
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
    local function step(info)
        local positions, current = native.rooms_positions(), {}
        for slot = 0, info.players - 1 do
            local position = positions[tostring(slot)]
            if position and (info.connected & (1 << slot)) ~= 0 then
                current[slot] = { index = position.index, dimension = position.dimension }
            end
        end
        local before = previous
        previous = current
        if pending then
            local valid = sameRoom(current[pending.owner], pending.destination)
                and info.nowMs - pending.started < arrivalTimeout
            for slot, source in pairs(pending.waiting) do
                local position = current[slot]
                if not valid or not position or sameRoom(position, pending.destination) then
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
            -- Consume arrivals together, including partial arrivals. They must
            -- never become new invitations that pull an exiting player back.
            return
        end
        for owner = 0, info.players - 1 do
            local destination = current[owner]
            if
                before[owner]
                and destination
                and not sameRoom(before[owner], destination)
                and special(owner)
            then
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
