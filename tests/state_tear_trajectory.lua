-- Ordinary shooting through real input, including transverse movement and stats.
local native, json = assert(_IsaacLan), require("json")
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame, gate, counter = _IsaacLanFrame, native.net_gate, native.diagnostics_counter
local firstTick, duration, beginShooting, endShooting = 60, 180, 20, 150
local cases = {
    { name = "still", speed = 1 },
    { name = "cross", speed = 1, move = true },
    { name = "slow", speed = 0.6, move = true },
    { name = "fast", speed = 1.6, move = true },
    { name = "short", speed = 1, item = CollectibleType.COLLECTIBLE_NUMBER_ONE, copies = 1 },
    { name = "long", speed = 1, item = CollectibleType.COLLECTIBLE_MOMS_HEELS, copies = 4 },
    { name = "tap", speed = 1, move = true, tap = true },
}
local renders, linked, chosen, finished, checked = 0, false, false, false, 0
local metrics, baseline = {}, {}
local baseRange
local function phase(tick)
    local elapsed = tick - firstTick
    return elapsed >= 0 and cases[math.floor(elapsed / duration) + 1] or nil, elapsed % duration
end
local function report(label, value)
    Isaac.DebugString("LAN_NETWORK TEAR_TRAJECTORY " .. label .. " " .. json.encode(value))
end
native.diagnostics_counter = function(name, value)
    if name:match("^attack%.") then
        metrics[name] = value
    end
    return counter(name, value)
end
local function finishCase(index)
    if not host then
        local result = { name = cases[index].name }
        for _, name in ipairs({ "previews", "confirmed", "timed_out", "grid_stops", "landed" }) do
            local key = "attack." .. name
            result[name] = (metrics[key] or 0) - (baseline[key] or 0)
        end
        report("CASE", result)
        assert(result.previews >= 5, "Insufficient previews: " .. result.name)
        assert(result.confirmed == result.previews, "A shot failed to hand over: " .. result.name)
        assert(result.timed_out == 0 and result.grid_stops == 0 and result.landed == 0)
        for key, value in pairs(metrics) do
            baseline[key] = value
        end
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
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
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    local case, at = phase(status.verified)
    local buttons = 0
    if not host and status.prepared and case and at >= beginShooting and at < endShooting then
        -- Every tap lasts three simulation ticks, so it reaches the authority.
        if not case.tap or at % 8 < 3 then
            buttons = 0x1000
        end
        if case.move then
            -- Use the wider room axis for strafing so inherited high-speed
            -- shots cannot touch a wall before their first confirmation.
            buttons = buttons | (math.floor(at / 10) % 2 == 0 and 4 or 8)
        end
    end
    native.test_gamepad(buttons)
    while checked < #cases and status.verified >= firstTick + (checked + 1) * duration do
        checked = checked + 1
        finishCase(checked)
    end
    if checked == #cases and not finished then
        finished = true
        report("PASS", "speed, range, transverse inertia and rapid taps")
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(tick, count, bytes)
        before(tick, count, bytes)
        local case, at = phase(tick)
        if not case or at ~= 0 then
            return
        end
        assert(native.rooms_with_player(1, function()
            local player = Isaac.GetPlayer(native.rooms_heads()["1"])
            for _, item in ipairs({
                CollectibleType.COLLECTIBLE_NUMBER_ONE,
                CollectibleType.COLLECTIBLE_MOMS_HEELS,
            }) do
                while player:HasCollectible(item) do
                    player:RemoveCollectible(item)
                end
            end
            if case.item then
                for _ = 1, case.copies do
                    player:AddCollectible(case.item)
                end
            end
            player.Position, player.Velocity = Vector(320, 280), Vector.Zero
            player.ShotSpeed = case.speed
            player:SetMinDamageCooldown(10000)
            baseRange = baseRange or player.TearRange
            assert(case.name ~= "short" or player.TearRange < baseRange)
            assert(case.name ~= "long" or player.TearRange > baseRange)
            report("STATS", {
                name = case.name,
                speed = player.ShotSpeed,
                range = player.TearRange,
                height = player.TearHeight,
                falling = player.TearFallingSpeed,
            })
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type ~= EntityType.ENTITY_PLAYER then
                    entity:Remove()
                end
            end
            local room = Game():GetRoom()
            for index = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(index)
                if
                    grid
                    and grid:GetType() ~= GridEntityType.GRID_WALL
                    and grid:GetType() ~= GridEntityType.GRID_DOOR
                then
                    room:RemoveGridEntity(index, 0, false)
                end
            end
            room:Update()
        end))
    end, collect, restore, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        native.diagnostics_counter = counter
    end,
}
