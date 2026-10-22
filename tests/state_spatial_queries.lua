-- Native broad-phase queries retain membership and deduplication on both peers.
local native, host, port = _IsaacLan, _IsaacLanTest.host, _IsaacLanTest.port
local originalFrame = _IsaacLanFrame
local renders, linked, chosen = 0, false, false
local spawned, checked, finished, cleaned = false, false, false, false
local owned = {}

local function identities(values)
    local result = {}
    for _, entity in ipairs(values) do
        local key = GetPtrHash(entity)
        assert(not result[key], "Spatial query returned a duplicate entity")
        result[key] = true
    end
    return result
end

local function compare(expected, values, label)
    local actual = identities(values)
    for key in pairs(expected) do
        assert(actual[key], "Spatial query omitted an entity: " .. label)
        actual[key] = nil
    end
    assert(next(actual) == nil, "Spatial query added an entity: " .. label)
    Isaac.DebugString("LAN_NETWORK SPATIAL " .. label .. " count=" .. #values)
end

function _IsaacLanFrame()
    if cleaned then
        return originalFrame()
    end
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = originalFrame()
    if cleaned then
        return status
    end
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    native.test_gamepad(0)
    if status.phase == 2 and not chosen then
        assert(_IsaacLanCommand("choose", "0:1"))
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
    if host and status.prepared and status.verified >= 60 and not spawned then
        spawned = true
        local player = Isaac.GetPlayer(0)
        local center = Game():GetRoom():GetCenterPos()
        for i = 1, 10 do
            local tear = player:FireTear(center + Vector(i * 10 - 50, i % 3 * 20), Vector.Zero)
            tear.FallingSpeed, tear.FallingAcceleration, tear.Height = 0, -0.1, -20
            tear.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
            -- Keep native entity collision enabled so the tear enters its partition.
            owned[#owned + 1] = { pointer = EntityPtr(tear), seed = tear.InitSeed }
        end
    end
    if status.prepared and status.verified >= 120 and not checked then
        local tears = Isaac.FindByType(EntityType.ENTITY_TEAR)
        assert(#tears == 10, "Spatial query fixture tears did not survive")
        local center = Game():GetRoom():GetCenterPos()
        local ordinary = Isaac.FindInRadius(center, 200, EntityPartition.TEAR)
        -- Replica tears have ENTCOLL_NONE and may be absent from the local partition.
        -- Only the host proves ten nonempty candidates; the guest checks its own baseline.
        local expected = identities(host and tears or ordinary)
        compare(expected, ordinary, "ordinary")
        Isaac.DebugString(
            "LAN_NETWORK SPATIAL baseline role="
                .. (host and "host" or "client")
                .. " replicas="
                .. #tears
                .. " partition="
                .. #ordinary
                .. " nonempty="
                .. tostring(#ordinary > 0)
        )
        compare(expected, Isaac.FindInRadius(center, 1000000, EntityPartition.TEAR), "huge")
        compare(expected, Isaac.FindInRadius(center, 10000000000, EntityPartition.TEAR), "wrapped")
        compare(
            expected,
            Isaac.FindInRadius(Vector(-100000, -100000), 1000000, EntityPartition.TEAR),
            "outside-wide"
        )
        compare(
            {},
            Isaac.FindInRadius(Vector(-100000, -100000), 1000, EntityPartition.TEAR),
            "outside-empty"
        )
        checked = true
        Isaac.DebugString("LAN_NETWORK CHECKED spatial query candidates and bounds")
    end
    if status.verified >= 160 and not finished then
        assert(checked, "Spatial queries did not execute")
        finished = true
        Isaac.DebugString("LAN_NETWORK PASS bounded native spatial queries")
    end
    return status
end

return {
    done = function()
        return finished
    end,
    cleanup = function()
        cleaned = true
        for _, value in ipairs(owned) do
            local tear = value.pointer.Ref
            if tear and tear:Exists() and tear.InitSeed == value.seed then
                tear:Remove()
            end
        end
        owned = {}
    end,
}
