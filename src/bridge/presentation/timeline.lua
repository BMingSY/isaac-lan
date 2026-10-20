-- Map the authority's monotonic capture clock onto the local render clock.
-- RTT/2 supplies an estimate, not a claim of symmetric one-way latency.
return function()
    local window, cursor, lastSource, offset = {}, 0, nil, nil
    local samples, maxHalfRtt = 64, 0.25
    local function reset()
        window, cursor, lastSource, offset = {}, 0, nil, nil
    end
    local function observe(sourceMs, received, rttMs)
        if not sourceMs or sourceMs <= 0 then
            return received
        end
        local source = sourceMs / 1000
        if lastSource and source < lastSource then
            reset()
        end
        lastSource = source
        local halfRtt = rttMs and rttMs >= 0 and math.min(maxHalfRtt, rttMs / 2000)
        cursor = cursor % samples + 1
        window[cursor] = { delay = received - source, halfRtt = halfRtt }
        local minimumDelay, minimumHalfRtt = math.huge, math.huge
        for _, candidate in ipairs(window) do
            minimumDelay = math.min(minimumDelay, candidate.delay)
            if candidate.halfRtt then
                minimumHalfRtt = math.min(minimumHalfRtt, candidate.halfRtt)
            end
        end
        offset = minimumDelay - (minimumHalfRtt < math.huge and minimumHalfRtt or 0)
        -- Jitter can make a sample older, never put it in the local future.
        return math.min(received, source + offset)
    end
    return { observe = observe, reset = reset }
end
