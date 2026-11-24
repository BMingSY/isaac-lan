-- Local registrations live with their SDK handles. Remote requests live with
-- their connection and run. A floor transition preserves existing requests.
return function(classes, variants)
    local effects, counts, remote = {}, {}, {}
    local required, advertised = 0, 0
    local run, authority, connected
    function effects.register(variant, subtype)
        local mask = classes.mask(variants, variant, subtype)
        if mask == 0 then
            return
        end
        counts[mask] = (counts[mask] or 0) + 1
        required = required | mask
        return function()
            counts[mask] = counts[mask] - 1
            if counts[mask] == 0 then
                counts[mask] = nil
                required = 0
                for active in pairs(counts) do
                    required = required | active
                end
            end
        end
    end
    function effects.forPeer(slot)
        return required | (remote[slot] or 0)
    end
    function effects.peerRequest(slot)
        return remote[slot]
    end
    local function valid(mask)
        return math.type(mask) == "integer" and mask >= 0 and (mask & ~classes.all) == 0
    end
    function effects.receive(info, sender, message)
        if
            info.active == 1
            and info.authority == 1
            and message.runId == info.runId
            and message.worldEpoch == info.worldEpoch
            and sender > 0
            and sender < info.players
            and (info.connected & (1 << sender)) ~= 0
            and valid(message.mask)
        then
            remote[sender] = message.mask ~= 0 and message.mask or nil
        end
    end
    function effects.confirm(mask)
        if valid(mask) then
            advertised = mask
        end
    end
    function effects.poll(info)
        local activeRun = info.active == 1 and info.runId or nil
        if run ~= activeRun or (activeRun and authority ~= info.authority) then
            run, authority = activeRun, info.authority
            remote, connected, advertised = {}, nil, 0
        end
        if not activeRun then
            return
        end
        if authority == 1 then
            if connected ~= info.connected then
                connected = info.connected
                for slot in pairs(remote) do
                    if (connected & (1 << slot)) == 0 then
                        remote[slot] = nil
                    end
                end
            end
        elseif advertised ~= required then
            -- The periodic host capabilities echo repairs a missed announcement,
            -- including a release to zero. Default clients send no extra packet.
            advertised = required
            return required
        end
    end
    return effects
end
