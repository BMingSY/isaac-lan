-- Consent belongs to one run, floor and native presentation event. The host
-- supplies the audience; a peer can only approve its own seat.
return function(deps)
    local Kind = deps.kinds
    local Message = { state = 1, vote = 2, finished = 3 }
    local wire = ">Bc32I4BI4BBBB"
    local wireSize, maxMembers = string.packsize(wire), 0xf
    local run, events, pending = "", {}, {}
    local function key(epoch, kind, id)
        return epoch .. ":" .. kind .. ":" .. id
    end
    local function packet(message, event)
        return string.pack(
            wire,
            message,
            run,
            event.epoch,
            event.kind,
            event.id,
            event.members,
            event.votes,
            event.done,
            event.committed and 1 or 0
        )
    end
    local function decode(bytes)
        if type(bytes) ~= "string" or #bytes ~= wireSize then
            return
        end
        local message, id, epoch, kind, serial, members, votes, done, committed =
            string.unpack(wire, bytes)
        if
            id ~= run
            or message < Message.state
            or message > Message.finished
            or (kind ~= Kind.boss and kind ~= Kind.floor)
            or members > maxMembers
            or (votes & members) ~= votes
            or (done & members) ~= done
            or committed > 1
        then
            return
        end
        return message,
            {
                epoch = epoch,
                kind = kind,
                id = serial,
                members = members,
                votes = votes,
                done = done,
                committed = committed == 1,
            }
    end
    return {
        poll = function(status)
            status.skipVotes, status.skipMembers = 0, 0
            local valid = status.phase == deps.running
                and status.restarting ~= 1
                and #status.runId == 32
            if not valid or run ~= status.runId then
                run, events, pending = valid and status.runId or "", {}, {}
            end
            if not valid then
                while deps.receive() ~= nil do
                end
                return
            end
            local host, bit = status.hosting == 1, 1 << status.slot
            local view = deps.view()
            local localKey = view.kind ~= Kind.none and key(view.epoch, view.kind, view.id) or nil
            if host then
                local live = {}
                for _, source in ipairs(view.events) do
                    local name = key(view.epoch, source.kind, source.id)
                    live[name] = true
                    local event = events[name]
                    if not event then
                        event = {
                            epoch = view.epoch,
                            kind = source.kind,
                            id = source.id,
                            members = source.members,
                            votes = 0,
                            done = 0,
                            sent = {},
                        }
                        events[name] = event
                    elseif source.kind == Kind.boss and not event.committed then
                        event.members = source.members
                    end
                end
                for name, event in pairs(events) do
                    if event.epoch ~= view.epoch then
                        events[name] = nil
                    else
                        event.members = event.members & status.connected
                        event.votes, event.done =
                            event.votes & event.members, event.done & event.members
                        if event.kind == Kind.boss and not live[name] then
                            event.done = event.members
                        end
                    end
                end
            end
            while true do
                local sender, bytes = deps.receive()
                if sender == nil then
                    break
                end
                local message, received = decode(bytes)
                if message and received.epoch >= view.epoch then
                    local name = key(received.epoch, received.kind, received.id)
                    if host then
                        local event = events[name]
                        local voter = 1 << sender
                        if event and (event.members & status.connected & voter) ~= 0 then
                            if message == Message.vote then
                                event.votes = event.votes | voter
                            elseif message == Message.finished and event.kind == Kind.floor then
                                event.done = event.done | voter
                            end
                        end
                    elseif sender == 0 and message == Message.state then
                        events[name] = received
                    end
                end
            end
            local requested = view.kind ~= Kind.none and deps.request()
            if view.kind == Kind.personal then
                if requested then
                    deps.skip(view.kind, view.id, view.epoch)
                end
            elseif requested then
                pending[localKey] = true
            end
            for name, event in pairs(events) do
                if event.epoch < view.epoch then
                    events[name], pending[name] = nil, nil
                else
                    local watching = event.epoch == view.epoch and localKey == name
                    if
                        event.kind == Kind.floor
                        and event.epoch == view.epoch
                        and not watching
                        and view.floorReady
                        and (event.members & bit) ~= 0
                    then
                        if host then
                            event.done = event.done | bit
                        elseif (event.done & bit) == 0 then
                            deps.send(0, packet(Message.finished, event))
                        end
                    end
                    if
                        watching
                        and pending[name]
                        and (event.members & bit) ~= 0
                        and not event.committed
                    then
                        if host then
                            event.votes = event.votes | bit
                            pending[name] = nil
                        elseif deps.send(0, packet(Message.vote, event)) then
                            pending[name] = nil
                        end
                    end
                    local members = event.members & ~event.done
                    if host then
                        if
                            not event.committed
                            and members ~= 0
                            and (event.votes & members) == members
                        then
                            event.committed = true
                            if deps.log then
                                deps.log(
                                    "animation_skip=COMMIT kind="
                                        .. event.kind
                                        .. " id="
                                        .. event.id
                                        .. " epoch="
                                        .. event.epoch
                                        .. " members="
                                        .. members
                                )
                            end
                        end
                        if
                            event.committed
                            and not event.applied
                            and (event.kind == Kind.boss or watching)
                        then
                            event.applied = deps.skip(event.kind, event.id, event.epoch)
                        end
                        local bytes = packet(Message.state, event)
                        for slot = 1, status.players - 1 do
                            if
                                (event.members & (1 << slot)) ~= 0
                                and event.sent[slot] ~= bytes
                                and deps.send(slot, bytes)
                            then
                                event.sent[slot] = bytes
                            end
                        end
                    elseif event.committed and watching then
                        deps.skip(event.kind, event.id, event.epoch)
                    end
                    if watching and not event.committed then
                        status.skipVotes, status.skipMembers = event.votes & members, members
                    end
                end
            end
            -- An input edge from a finished screen cannot approve its successor.
            for name in pairs(pending) do
                if name ~= localKey then
                    pending[name] = nil
                end
            end
        end,
    }
end
