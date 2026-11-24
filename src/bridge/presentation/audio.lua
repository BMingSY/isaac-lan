-- Audience selection is performed by the engine before these events arrive.
return function(native, sfxManager, roomWarning)
    local unpack = string.unpack
    local levelFormat = ">I4ff"
    local levelSize, nativeLoopDelay = string.packsize(levelFormat), 2
    local hostLoops, replicaLoops, lastSound = {}, {}, 0
    local heardWarnings = {}
    local oneShotTicks, historyTicks = 10, 30
    local function soundEvents(bytes)
        local result, cursor = {}, 1
        while cursor <= #bytes do
            local serial, tick, id, volume, delay, loop, pitch, pan
            serial, tick, id, volume, delay, loop, pitch, pan, cursor =
                unpack(">I4I4I4fI4Bff", bytes, cursor)
            result[#result + 1] = { serial, tick, id, volume, delay, loop, pitch, pan }
        end
        return result
    end
    local function captureSound(slot, view)
        local bytes, levels = native.sound_events(slot, view.dimension, view.index, roomWarning)
        local loops = hostLoops[slot] or {}
        hostLoops[slot] = loops
        for _, event in ipairs(soundEvents(bytes)) do
            if event[6] ~= 0 then
                loops[event[3]] = event
            end
        end
        local playing, mixed = {}, {}
        for cursor = 1, #(levels or ""), levelSize do
            local id, volume, pitch = unpack(levelFormat, levels, cursor)
            -- The active-loop tuple is the existing wire representation. The
            -- room mixer supplies levels without manufacturing Play events.
            playing[#playing + 1] = { 0, 0, id, volume, nativeLoopDelay, 1, pitch, 0 }
            mixed[id] = true
        end
        for id, event in pairs(loops) do
            if mixed[id] then
                loops[id] = nil
            elseif sfxManager():IsPlaying(id) then
                playing[#playing + 1] = event
            else
                loops[id] = nil
            end
        end
        return { bytes, playing }
    end
    local function applySound(value, tick)
        local sfx = sfxManager()
        for serial, issued in pairs(heardWarnings) do
            if tick - issued > historyTicks then
                heardWarnings[serial] = nil
            end
        end
        for _, event in ipairs(soundEvents(value[1])) do
            local play = false
            if event[3] == roomWarning and event[6] == 0 then
                -- A newly entered room can expose a warning older than other rooms' events.
                play = not heardWarnings[event[1]] and tick - event[2] <= historyTicks
                if play then
                    heardWarnings[event[1]] = event[2]
                end
            elseif event[1] > lastSound then
                play = event[6] == 0 and tick - event[2] <= oneShotTicks
                lastSound = event[1]
            end
            if play then
                sfx:Play(event[3], event[4], event[5], false, event[7], event[8])
            end
        end
        local playing = {}
        for _, event in ipairs(value[2]) do
            local id, previous = event[3], replicaLoops[event[3]]
            playing[id] = event
            if not previous or not sfx:IsPlaying(id) then
                sfx:Play(id, event[4], event[5], true, event[7], event[8])
            else
                if previous[4] ~= event[4] then
                    sfx:AdjustVolume(id, event[4])
                end
                if previous[7] ~= event[7] then
                    sfx:AdjustPitch(id, event[7])
                end
            end
        end
        for id in pairs(replicaLoops) do
            if not playing[id] then
                sfx:Stop(id)
            end
        end
        replicaLoops = playing
    end
    return {
        capture = captureSound,
        apply = applySound,
        reset = function()
            for id in pairs(replicaLoops) do
                sfxManager():Stop(id)
            end
            hostLoops, replicaLoops, lastSound = {}, {}, 0
            heardWarnings = {}
        end,
    }
end
