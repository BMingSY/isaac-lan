-- Numeric binding and animation differential without a performance workload.
local native, host, port = _IsaacLan, _IsaacLanTest.host, _IsaacLanTest.port
local reference = assert(_IsaacLanModules["sync/codec"])
local probe = createEntityFieldsProbe(
    native,
    reference,
    _IsaacLanModules["sync/entity_schema"](EntityType),
    host
)
local verified, finished, linked, chosen = false, false, false, false
local renders = 0
local originalFrame, originalGate = _IsaacLanFrame, native.net_gate
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = originalFrame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    native.test_gamepad(0)
    if status.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if status.verified >= 200 and not finished then
        assert(verified, "Entity field differential did not execute")
        finished = true
        Isaac.DebugString("LAN_NETWORK PASS native entity field and animation differential")
    end
    return status
end
local function verify(bytes, tick)
    if verified or tick < 100 then
        return
    end
    local types = probe()
    assert(
        reference.encode(types) == reference.encode({ 2, 3, 1000 }),
        "Missing native field types: " .. table.concat(types, ",")
    )
    assert(native.state_encode(reference.decode(bytes)) == bytes, "Native outer encoding differs")
    assert(reference.encode(native.state_decode(bytes)) == bytes, "Native outer decoding differs")
    verified = true
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return originalGate(capture, function(tick, ...)
        before(tick, ...)
        if tick == 60 then
            Isaac.GetPlayer(0):AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
        end
        if tick == 99 then
            local player = Isaac.GetPlayer(0)
            local position = Game():GetRoom():GetCenterPos()
            local tear = player:FireTear(position, Vector.Zero)
            tear.FallingSpeed, tear.FallingAcceleration, tear.Height = 0, 0, -20
            tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
            tear.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
            local effect = Isaac.Spawn(
                EntityType.ENTITY_EFFECT,
                EffectVariant.CREEP_RED,
                0,
                position,
                Vector.Zero,
                player
            ):ToEffect()
            effect.Timeout = 500
        end
    end, function(slot, tick)
        local bytes, stable = collect(slot, tick)
        verify(bytes, tick)
        return bytes, stable
    end, function(bytes, tick, ...)
        local result = restore(bytes, tick, ...)
        if result ~= false then
            verify(bytes, tick)
        end
        return result
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
