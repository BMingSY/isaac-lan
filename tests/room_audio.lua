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

local laugh =
    dofile(assert(arg[1]) .. "/tests/fixtures/game_enums.lua").SoundEffect.SOUND_MOM_VOX_EVILLAUGH
local beep, plays = 3, {}
local listener = makeAudio({}, function()
    return {
        Play = function(_, id, v, delay, loop, p, pan)
            assert(v == 0.5 and delay == 10 and not loop and p == 1.25 and pan == -0.5)
            plays[#plays + 1] = id
        end,
    }
end, laugh)
local function event(serial, tick, id)
    return string.pack(">I4I4I4fI4Bff", serial, tick, id, 0.5, 10, 0, 1.25, -0.5)
end
local warning = event(1, 100, laugh)
listener.apply({ event(3, 110, beep), {} }, 120)
listener.apply({ warning .. event(2, 100, beep), {} }, 130)
listener.apply({ warning, {} }, 130)
listener.apply({ event(4, 100, laugh) .. event(5, 120, beep), {} }, 131)
assert(#plays == 2 and plays[1] == beep and plays[2] == laugh)
listener.reset()
listener.apply({ warning .. event(2, 100, laugh), {} }, 100)
assert(#plays == 4 and plays[3] == laugh and plays[4] == laugh)
print("PASS delayed room warnings, unseen serials, expiry and session reset")
