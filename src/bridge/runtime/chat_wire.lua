-- Reliable session messages, independent of world snapshots and Mod action traffic.
local wire = { request = 1, output = 2, emote = 3 }
local requestFormat = ">BI4I4i2Bs1s1s2"
local emoteFormat = ">BI4BBs1"
local outputFormat = ">BI4BBs1s2"
function wire.encodeRequest(value)
    return string.pack(
        requestFormat,
        wire.request,
        value.sequence,
        value.epoch,
        value.room,
        value.dimension,
        value.nonce,
        value.run,
        value.text
    )
end
function wire.encodeOutput(value)
    local flags = (value.bubble and 1 or 0) | (value.kind == "team" and 2 or 0)
    return string.pack(
        outputFormat,
        wire.output,
        value.sequence,
        value.owner,
        flags,
        value.nonce,
        value.text
    )
end
function wire.encodeEmote(value)
    return string.pack(emoteFormat, wire.emote, value.sequence, value.owner, value.id, value.nonce)
end
function wire.decode(bytes)
    assert(type(bytes) == "string" and #bytes <= 3072, "invalid_chat_packet")
    local kind = bytes:byte()
    local value, tail
    if kind == wire.request then
        local _, sequence, epoch, room, dimension, nonce, run, text, ending =
            string.unpack(requestFormat, bytes)
        assert(#nonce == 32 and (#run == 0 or #run == 32) and dimension <= 2)
        value = {
            sequence = sequence,
            epoch = epoch,
            room = room,
            dimension = dimension,
            nonce = nonce,
            run = run,
            text = text,
        }
        tail = ending
    elseif kind == wire.output then
        local _, sequence, owner, flags, nonce, text, ending = string.unpack(outputFormat, bytes)
        assert(owner < 4 and flags <= 3 and #nonce == 32)
        value = {
            sequence = sequence,
            owner = owner,
            bubble = flags & 1 ~= 0,
            kind = flags & 2 ~= 0 and "team" or "system",
            nonce = nonce,
            text = text,
        }
        tail = ending
    elseif kind == wire.emote then
        local _, sequence, owner, id, nonce, ending = string.unpack(emoteFormat, bytes)
        assert((owner < 4 or owner == 255) and id > 0 and #nonce == 32)
        value = { sequence = sequence, owner = owner, id = id, nonce = nonce }
        tail = ending
    else
        error("invalid_chat_kind")
    end
    assert(tail == #bytes + 1 and value.sequence > 0)
    value.packet = kind
    return value
end
return wire
