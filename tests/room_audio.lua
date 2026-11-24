local makeAudio = dofile(assert(arg[1]) .. "/src/bridge/presentation/audio.lua")
local fire, fireRoom, otherRoom = 269, { dimension = 0, index = 71 }, { dimension = 0, index = 70 }
local volume, pitch, starts, stops, adjustments = 0.25, 1, 0, 0, 0
local playing = {}
local sfx = {
    IsPlaying = function(_, id)
        return playing[id] ~= nil
    end,
    Play = function(_, id, v, delay, loop, p, pan)
        assert(id == fire and loop and delay == 2 and pan == 0)
        playing[id], starts = { v, p }, starts + 1
    end,
    Stop = function(_, id)
        assert(playing[id])
        playing[id], stops = nil, stops + 1
    end,
    AdjustVolume = function(_, id, value)
        playing[id][1], adjustments = value, adjustments + 1
    end,
    AdjustPitch = function(_, id, value)
        playing[id][2], adjustments = value, adjustments + 1
    end,
}
local host = makeAudio({
    sound_events = function(slot, dimension, index)
        assert(slot == 1 and dimension == 0)
        return "", index == fireRoom.index and string.pack(">I4ff", fire, volume, pitch) or ""
    end,
}, function()
    error("Capturing room ambience queried the host's physical mixer")
end)
local guest = makeAudio({}, function()
    return sfx
end)
local function receive(view)
    guest.apply(host.capture(1, view), 100)
end
receive(fireRoom)
receive(fireRoom)
assert(starts == 1 and adjustments == 0 and playing[fire][1] == volume)
volume, pitch = 0.75, 1.25
receive(fireRoom)
receive(fireRoom)
assert(
    starts == 1 and adjustments == 2 and playing[fire][1] == volume and playing[fire][2] == pitch
)
receive(otherRoom)
receive(otherRoom)
assert(stops == 1 and not playing[fire])
receive(fireRoom)
guest.reset()
guest.reset()
assert(starts == 2 and stops == 2 and not playing[fire])
print("PASS per-room sustained sound, adjustments, replay and cleanup")
