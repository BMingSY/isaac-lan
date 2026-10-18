-- Host-owned consent; transport supplies the sender identity. A generation
-- invalidates votes after timeout or membership changes, even within one run.
return function(deps)
    local Message = { vote = 1, state = 2 }
    local wire = ">Bc32I4BB"
    local wireSize, maxMembers = string.packsize(wire), 0xf
    local run, generation, members, votes, deadline = "", 1, 0, 0, nil
    local lastState, pendingRequest, committed = {}, false, false
    local duration = 20000
    local function reset(id, mask)
        run, generation, members, votes, deadline = id, 1, mask, 0, nil
        lastState, pendingRequest, committed = {}, false, false
    end
    local function clear()
        generation, votes, deadline = generation + 1, 0, nil
    end
    local function packet(kind)
        return string.pack(wire, kind, run, generation, members, votes)
    end
    local function decode(bytes)
        if type(bytes) ~= "string" or #bytes ~= wireSize then
            return
        end
        local kind, id, serial, mask, accepted = string.unpack(wire, bytes)
        if
            (kind ~= Message.vote and kind ~= Message.state)
            or id ~= run
            or serial < 1
            or mask > maxMembers
            or accepted > maxMembers
        then
            return
        end
        return kind, serial, mask, accepted
    end
    local function vote(slot, now)
        local bit = 1 << slot
        if (members & bit) == 0 then
            return
        end
        if votes == 0 then
            deadline = now + duration
        end
        votes = votes | bit
    end
    return {
        poll = function(status)
            if status.phase ~= deps.running or status.restarting == 1 or #status.runId ~= 32 then
                -- The transport already names the next run while native Exit
                -- still owns the old one. Initialize consent after that tail.
                reset("", 0)
                status.restartVotes, status.restartMembers = 0, 0
                return
            end
            local host, now = status.hosting == 1, deps.now()
            if run ~= status.runId then
                reset(status.runId, status.connected)
                -- A guest must receive the authority's generation before voting.
                if not host then
                    generation = 0
                end
            end
            if host and (members ~= status.connected or (deadline and now >= deadline)) then
                members = status.connected
                clear()
            end
            local requested = deps.request()
            pendingRequest = pendingRequest or requested
            while true do
                local sender, bytes = deps.receive()
                if sender == nil then
                    break
                end
                local kind, serial, mask, accepted = decode(bytes)
                if host then
                    if kind == Message.vote and serial == generation and mask == members then
                        vote(sender, now)
                    end
                elseif
                    sender == 0
                    and kind == Message.state
                    and serial >= generation
                    and (accepted & mask) == accepted
                then
                    generation, members, votes = serial, mask, accepted
                end
            end
            if not committed and pendingRequest and generation > 0 then
                if host then
                    vote(status.slot, now)
                    pendingRequest = false
                elseif deps.send(0, packet(Message.vote)) then
                    pendingRequest = false
                end
            end
            if host and not committed then
                local value = packet(Message.state)
                for slot = 1, status.players - 1 do
                    if (members & (1 << slot)) ~= 0 and value ~= lastState[slot] then
                        if deps.send(slot, value) then
                            lastState[slot] = value
                        end
                    end
                end
                if votes ~= 0 and votes == members then
                    committed = deps.restart()
                end
            end
            status.restartVotes = committed and 0 or votes
            status.restartMembers = members
        end,
    }
end
