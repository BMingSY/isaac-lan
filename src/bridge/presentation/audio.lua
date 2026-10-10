-- Audience selection is performed by the engine before these events arrive.
return function(native, sfxManager)
    local unpack = string.unpack
    local hostLoops, replicaLoops, lastSound = {}, {}, 0
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
    local function captureSound(slot)
        local bytes = native.sound_events(slot)
        local loops = hostLoops[slot] or {}
        hostLoops[slot] = loops
        for _, event in ipairs(soundEvents(bytes)) do
            if event[6] ~= 0 then
                loops[event[3]] = event
            end
        end
        local playing = {}
        for id, event in pairs(loops) do
            if sfxManager():IsPlaying(id) then
                playing[#playing + 1] = event
            else
                loops[id] = nil
            end
        end
        return { bytes, playing }
    end
    local function applySound(value, tick)
        local sfx = sfxManager()
        for _, event in ipairs(soundEvents(value[1])) do
            if event[1] > lastSound then
                if event[6] == 0 and tick - event[2] <= 10 then
                    sfx:Play(event[3], event[4], event[5], false, event[7], event[8])
                end
                lastSound = event[1]
            end
        end
        local playing = {}
        for _, event in ipairs(value[2]) do
            playing[event[3]] = true
            if not replicaLoops[event[3]] or not sfx:IsPlaying(event[3]) then
                sfx:Play(event[3], event[4], event[5], true, event[7], event[8])
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
            hostLoops, replicaLoops, lastSound = {}, {}, 0
        end,
    }
end
