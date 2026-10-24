-- Reproducible same-room pressure, without recorder or heap observer overhead.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, json = config.host, require("json")
local frame, gate = _IsaacLanFrame, native.net_gate
local tick, renders, linked, chosen, finished = 0, 0, false, false, false
local counts = config.pickupCounts or { 0, 100, 300, 500 }
local start, length = 60, 400
local samples, lastRender = {}, nil
local function current()
    local index = math.floor((tick - start) / length) + 1
    return counts[index], index, (tick - start) % length
end
local function sample(name, value)
    local count, index, elapsed = current()
    if not count or elapsed < 90 or elapsed >= length - 10 then
        return
    end
    local s = samples[index] or {}
    samples[index] = s
    s[name] = s[name] or {}
    s[name][#s[name] + 1] = value
end
local function report()
    for index, count in ipairs(counts) do
        local result = { role = host and "host" or "client", pickups = count, metrics = {} }
        for name, values in pairs(assert(samples[index])) do
            table.sort(values)
            local sum = 0
            for _, value in ipairs(values) do
                sum = sum + value
            end
            result.metrics[name] = {
                count = #values,
                mean = sum / #values,
                p50 = values[math.ceil(#values * 0.5)],
                p95 = values[math.ceil(#values * 0.95)],
                max = values[#values],
            }
        end
        assert(result.metrics.render.count >= 100, "Insufficient steady-state frames")
        Isaac.DebugString("LAN_PICKUP_PRESSURE " .. json.encode(result))
    end
    for index, count in ipairs(counts) do
        for _, observed in ipairs(samples[index].pickups) do
            assert(observed == count, "Native pickup population differs from the workload")
        end
    end
end
local diagnostics = native.diagnostics_sample
if diagnostics then
    native.diagnostics_sample = function(name, value)
        sample(name, value)
        return diagnostics(name, value)
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    tick = status.verified
    local now = Isaac.GetTime()
    if lastRender then
        sample("render", now - lastRender)
    end
    lastRender = now
    if status.prepared and current() and tick % 30 == 0 then
        local n = 0
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity.Type == EntityType.ENTITY_PICKUP then
                n = n + 1
            end
        end
        sample("pickups", n)
    end
    if not finished and tick >= start + length * #counts then
        finished = true
        report()
        Isaac.DebugString("LAN_NETWORK PASS pickup pressure")
    end
    return status
end
function native.net_gate(inputCapture, before, collect, restore, present, beginFloor)
    return gate(inputCapture, function(t, ...)
        before(t, ...)
        tick = t
        local count, _, elapsed = current()
        if count and elapsed == 0 then
            assert(native.rooms_with_player(1, function()
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity.Type ~= EntityType.ENTITY_PLAYER then
                        entity:Remove()
                    end
                end
                local room = Game():GetRoom()
                for i = 0, room:GetGridSize() - 1 do
                    room:RemoveGridEntity(i, 0, false)
                end
                room:SetClear(true)
                room:Update() -- Reclaim removed native allocations before the next load.
                for i = 0, Game():GetNumPlayers() - 1 do
                    local p = Isaac.GetPlayer(i)
                    p.Position, p.Velocity = Vector(90, 350 + i * 40), Vector.Zero
                    p:SetMinDamageCooldown(100000)
                end
                local variants = {
                    PickupVariant.PICKUP_HEART,
                    PickupVariant.PICKUP_COIN,
                    PickupVariant.PICKUP_KEY,
                    PickupVariant.PICKUP_BOMB,
                    PickupVariant.PICKUP_COLLECTIBLE,
                }
                for i = 1, count do
                    local e = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        variants[(i - 1) % #variants + 1],
                        1,
                        Vector(200 + (i % 20) * 17, 150 + (math.floor(i / 20) % 16) * 15),
                        Vector.Zero,
                        nil
                    )
                    e.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
                    e:ToPickup().Wait = 100000 -- Keep repelled drops from reaching either actor during sampling.
                end
                Isaac.DebugString(
                    "LAN_PICKUP_PRESSURE_BEGIN "
                        .. json.encode({ pickups = count, tick = t, now = Isaac.GetTime() })
                )
            end, 1))
        end
    end, function(...)
        local began = Isaac.GetTime()
        local bytes, stable = collect(...)
        sample("capture", Isaac.GetTime() - began)
        sample("raw_bytes", #bytes)
        sample("stable_bytes", #(stable or ""))
        return bytes, stable
    end, function(bytes, t, ...)
        tick = t
        local began = Isaac.GetTime()
        local result = restore(bytes, t, ...)
        sample("apply", Isaac.GetTime() - began)
        sample("raw_bytes", #bytes)
        return result
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        native.diagnostics_sample = diagnostics
        _IsaacLanFrame, native.net_gate = frame, gate
    end,
}
