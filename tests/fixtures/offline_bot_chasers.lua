-- Independent burst-and-rest pursuit world. This is a stress model, not a
-- reimplementation of native Spider AI. Snapshots and controls are delayed;
-- collision, walls, damage and enemy steering belong to the world.
return function(root)
    local modules = {}
    for _, name in ipairs({ "navigation", "hazards", "combat", "items", "greed", "planner" }) do
        modules["lanbot/" .. name] = dofile(root .. "/src/bridge/lanbot/" .. name .. ".lua")
    end
    local create = dofile(root .. "/src/bridge/lanbot.lua")
    local fixture = {}
    local frame, player, enemies, snapshots, controls, bot, mask, lag, hits, firstHit, deadAt
    local walk, previous, switchCount, blocked, seed
    local function distance(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end
    local function copy(e)
        local result = {}
        for key, value in pairs(e) do
            result[key] = value
        end
        return result
    end
    local function snapshot()
        local p, dangers = copy(player), {}
        for _, e in ipairs(enemies) do
            dangers[#dangers + 1] = copy(e)
        end
        return { actor = p, dangers = dangers, tick = math.floor(frame / 2) }
    end
    function fixture.reset(latency, worldSeed, stationary)
        frame, mask, hits, firstHit, deadAt = 0, 0, 0, -1, -1
        previous, switchCount, blocked, seed = 0, 0, 0, worldSeed
        lag = math.ceil(latency * 60 / 1000)
        walk = {}
        for row = 0, 8 do
            for col = 0, 14 do
                walk[row * 15 + col + 1] = row > 0 and row < 8 and col > 0 and col < 14
            end
        end
        player = {
            id = "isaac",
            x = 140,
            y = 280,
            vx = 0,
            vy = 0,
            radius = 12,
            speed = 264.705882,
            range = 260,
            health = 6,
            keys = 0,
            items = 0,
        }
        enemies = {}
        for row = -1, 1 do
            for col = -1, 1 do
                enemies[#enemies + 1] = {
                    id = "chaser:" .. (#enemies + 1),
                    x = 320 + col * 40,
                    y = 280 + row * 40,
                    vx = 0,
                    vy = 0,
                    radius = 10,
                    attackable = true,
                    contact = true,
                    chaseSpeed = player.speed * 0.6,
                    peak = 0,
                    threat = 1,
                }
            end
        end
        snapshots, controls = { [0] = snapshot() }, { [0] = 0 }
        bot = create({
            info = function()
                return {
                    active = 1,
                    runId = "stress",
                    authority = lag == 0 and 1 or 0,
                    nowMs = frame * 1000 / 60,
                }
            end,
            clock = function()
                return 0
            end,
            log = function(message)
                error(message)
            end,
            input = function(_, value)
                mask = stationary and 0 or value & 15
            end,
            observe = function()
                if player.health == 0 then
                    return nil, "dead"
                end
                local key = math.max(0, frame - 1 - lag)
                key = key - key % 2
                local s = snapshots[key]
                local dangers = {}
                for _, e in ipairs(s.dangers) do
                    dangers[#dangers + 1] = copy(e)
                end
                return {
                    actor = copy(s.actor),
                    enemies = dangers,
                    dangers = dangers,
                    frame = frame,
                    world = "stress:1",
                    room = "0:84",
                    simulationTick = s.tick,
                    age = (frame % 2) / 60,
                    controlDelay = latency * 2 / 1000 + 1 / 30,
                    map = {
                        x = 40,
                        y = 120,
                        step = 40,
                        width = 15,
                        height = 9,
                        walk = walk,
                        speed = player.speed * 0.7,
                    },
                    clear = false,
                    partyReady = false,
                    pickups = {},
                    doors = {},
                    buttons = {},
                    shotLine = function()
                        return true
                    end,
                }
            end,
        }, modules)
        bot.command("mode hold")
        bot.command("on")
        return fixture.read()
    end
    local function physical(e, dx, dy, dt)
        -- Native walking slides along solid boundaries. Grid queries are not
        -- delegated to the navigation module under test.
        e.x = math.max(72, math.min(568, e.x + dx * dt))
        e.y = math.max(152, math.min(408, e.y + dy * dt))
    end
    function fixture.step(count)
        assert(count >= 0 and count <= 10800)
        for _ = 1, count do
            if deadAt >= 0 then
                break
            end
            frame = frame + 1
            bot.step(frame)
            if mask ~= previous then
                switchCount = switchCount + 1
                previous = mask
            end
            controls[frame] = mask
            local input = controls[math.max(0, frame - lag)] or 0
            local dx = ((input & 2) ~= 0 and 1 or 0) - ((input & 1) ~= 0 and 1 or 0)
            local dy = ((input & 8) ~= 0 and 1 or 0) - ((input & 4) ~= 0 and 1 or 0)
            local scale = dx ~= 0 and dy ~= 0 and 1 / math.sqrt(2) or 1
            local retain = math.sqrt(0.775)
            player.vx = player.vx * retain + dx * scale * player.speed * (1 - retain)
            player.vy = player.vy * retain + dy * scale * player.speed * (1 - retain)
            local x, y = player.x, player.y
            physical(player, player.vx, player.vy, 1 / 60)
            if input ~= 0 and distance(player, { x = x, y = y }) < 0.1 then
                blocked = blocked + 1
            end
            for i, e in ipairs(enemies) do
                local period, phase = 84, (frame + i * 7 + seed * 11) % 84
                if frame > 60 then
                    if phase == 0 then
                        local d = math.max(1, distance(player, e))
                        local speed = 210 + ((seed + i) % 4) * 30
                        e.vx, e.vy = (player.x - e.x) / d * speed, (player.y - e.y) / d * speed
                        e.peak = math.max(e.peak, speed)
                    elseif phase >= 26 then
                        e.vx, e.vy = e.vx * 0.82, e.vy * 0.82
                    end
                end
                local ex, ey = e.x, e.y
                physical(e, e.vx, e.vy, 1 / 60)
                local min = modules["lanbot/navigation"].segmentDistance(
                    0,
                    0,
                    x - ex,
                    y - ey,
                    player.x - e.x,
                    player.y - e.y
                )
                if min < player.radius + e.radius and frame >= (player.cooldown or 0) then
                    hits, player.health, player.cooldown = hits + 1, player.health - 1, frame + 72
                    if firstHit < 0 then
                        firstHit = frame / 60
                    end
                    if player.health == 0 then
                        deadAt = frame / 60
                    end
                end
                e.chaseSpeed = math.max(player.speed * 0.6, e.peak)
            end
            if frame % 2 == 0 then
                snapshots[frame] = snapshot()
            end
            if frame - lag - 6 >= 0 then
                snapshots[frame - lag - 6] = nil
            end
            if frame - lag - 2 >= 0 then
                controls[frame - lag - 2] = nil
            end
        end
        return fixture.read()
    end
    function fixture.read()
        return {
            frame / 60,
            firstHit,
            hits,
            deadAt,
            player.health,
            switchCount,
            blocked,
            player.x,
            player.y,
            bot.state,
            bot.task,
        }
    end
    return fixture
end
