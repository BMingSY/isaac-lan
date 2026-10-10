-- Closed-loop decisions with virtual time and a small inertial collision world.
-- This verifies bot behavior, not Isaac's native physics or enemy AI.
return function(root)
    local modules = {}
    for _, name in ipairs({ "navigation", "hazards", "combat", "planner" }) do
        modules["lanbot/" .. name] = dofile(root .. "/src/bridge/lanbot/" .. name .. ".lua")
    end
    local create = dofile(root .. "/src/bridge/lanbot.lua")
    local fixture, bot, obs, info, frame, mask, active, door, crossings, collisions, arrival = {}
    local function solid(x, y)
        local col, row = math.floor(x / 40 + 0.5), math.floor(y / 40 + 0.5)
        return col < 0 or row < 0 or col >= 12 or row >= 10 or not obs.map.walk[row * 12 + col + 1]
    end
    local function allowed(x, y)
        local p = obs.actor
        if crossings == 0 then
            local dx, dy = x - door.x, y - door.y
            if
                dx * door.dx + dy * door.dy > -48
                and math.abs(dx * door.dy - dy * door.dx) + p.radius <= 22
            then
                return true
            end
        end
        return not (
            solid(x - p.radius, y - p.radius)
            or solid(x + p.radius, y - p.radius)
            or solid(x - p.radius, y + p.radius)
            or solid(x + p.radius, y + p.radius)
        )
    end
    function fixture.reset(side, speed, radius, offset, distance, obstacle, mode, style)
        local walk = {}
        for row = 0, 9 do
            for col = 0, 11 do
                walk[row * 12 + col + 1] = row > 0 and row < 9 and col > 0 and col < 11
            end
        end
        if obstacle then
            for row = 1, 6 do
                walk[row * 12 + 7] = false
            end
        end
        local doors = {
            { slot = 0, x = 0, y = 160, dx = -1, dy = 0 },
            { slot = 1, x = 240, y = 0, dx = 0, dy = -1 },
            { slot = 2, x = 440, y = 160, dx = 1, dy = 0 },
            { slot = 3, x = 240, y = 360, dx = 0, dy = 1 },
        }
        door = assert(doors[side + 1])
        door.to, door.open = "0:2", true
        obs = {
            frame = 0,
            world = "run:1",
            room = "0:1",
            clear = true,
            partyReady = true,
            actor = {
                id = 1,
                x = door.x - door.dx * distance - door.dy * offset,
                y = door.y - door.dy * distance + door.dx * offset,
                vx = 0,
                vy = 0,
                radius = radius,
                speed = speed,
                range = 260,
                keys = 2,
                health = 6,
                items = 0,
            },
            map = { x = 0, y = 0, step = 40, width = 12, height = 10, walk = walk },
            enemies = {},
            dangers = {},
            pickups = {},
            doors = { door },
            shotLine = function()
                return true
            end,
        }
        info = { active = 1, authority = 1, runId = "run" }
        frame, mask, active, crossings, collisions, arrival = 0, 0, false, 0, 0, -1
        bot = create({
            info = function()
                return info
            end,
            input = function(enabled, buttons)
                active, mask = enabled, buttons
            end,
            observe = function()
                return obs
            end,
            clock = function()
                return frame * 1000 / 60
            end,
            log = function(message)
                error(message)
            end,
        }, modules)
        bot.command("mode " .. mode)
        bot.command("style " .. style)
        bot.command("on")
        assert(allowed(obs.actor.x, obs.actor.y), "Scenario starts in a wall")
        return fixture.read()
    end
    function fixture.step(frames)
        assert(frames >= 0 and frames <= 2400, "Invalid simulation length")
        for _ = 1, frames do
            frame = frame + 1
            obs.frame = frame
            bot.step(frame)
            if obs.room == "0:2" and arrival == -1 then
                arrival = mask
            end
            local dx = ((mask & 2) ~= 0 and 1 or 0) - ((mask & 1) ~= 0 and 1 or 0)
            local dy = ((mask & 8) ~= 0 and 1 or 0) - ((mask & 4) ~= 0 and 1 or 0)
            local scale = dx ~= 0 and dy ~= 0 and 1 / math.sqrt(2) or 1
            local p = obs.actor
            p.vx = p.vx * 0.88 + dx * scale * p.speed * 0.12
            p.vy = p.vy * 0.88 + dy * scale * p.speed * 0.12
            local x, y = p.x + p.vx / 60, p.y + p.vy / 60
            if allowed(x, y) then
                p.x, p.y = x, y
            else
                collisions = collisions + 1
                p.vx, p.vy = 0, 0
            end
            if crossings == 0 and (p.x - door.x) * door.dx + (p.y - door.y) * door.dy >= 0 then
                assert(
                    math.abs((p.x - door.x) * door.dy - (p.y - door.y) * door.dx) + p.radius <= 22
                )
                crossings = crossings + 1
                obs.room, obs.doors = "0:2", {}
                p.x, p.y, p.vx, p.vy = 160, 160, 0, 0
            end
        end
        return fixture.read()
    end
    function fixture.command(command)
        local message = bot.command(command)
        return { message, fixture.read() }
    end
    function fixture.session(enabled, runId)
        info.active, info.runId = enabled and 1 or 0, runId
        bot.poll()
        return fixture.read()
    end
    function fixture.read()
        return {
            bot.state,
            active,
            mask,
            frame,
            crossings,
            collisions,
            arrival,
            obs.room,
            bot.task,
            bot.reason or "",
            obs.actor.x,
            obs.actor.y,
            bot.mode,
            bot.style,
        }
    end
    fixture.reset(2, 260, 10, 0, 56, false, "explore", "balanced")
    return fixture
end
