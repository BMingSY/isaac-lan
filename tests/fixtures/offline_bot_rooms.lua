-- Closed-loop room graph, contact exits, buttons and timed hazards. The world
-- enforces collisions independently of navigation; no native physics claim.
return function(root)
    local modules = {}
    for _, name in ipairs({ "navigation", "hazards", "combat", "planner" }) do
        modules["lanbot/" .. name] = dofile(root .. "/src/bridge/lanbot/" .. name .. ".lua")
    end
    local create = dofile(root .. "/src/bridge/lanbot.lua")
    local fixture = {}
    local bot, obs, frame, mask, scenario, rooms, visited, crosses, exits, presses, hits, pickups
    local terrain = dofile(root .. "/src/bridge/lanbot/terrain.lua")()
    local function door(slot, to)
        local positions = {
            { x = 0, y = 160, dx = -1, dy = 0 },
            { x = 240, y = 0, dx = 0, dy = -1 },
            { x = 440, y = 160, dx = 1, dy = 0 },
            { x = 240, y = 360, dx = 0, dy = 1 },
        }
        local d = positions[slot + 1]
        d.slot, d.to, d.open = slot, to, true
        return d
    end
    local function distance(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end
    local function update()
        local room = rooms[obs.room]
        obs.frame, obs.doors, obs.buttons, obs.pickups =
            frame, room.doors, room.buttons, room.pickups
        obs.exit = room.exit
        obs.clear = #room.buttons == 0
        obs.map.zones = {}
        if room.exit then
            obs.map.zones[#obs.map.zones + 1] = room.exit
        end
        if scenario == "timed" or scenario == "timed-short" then
            local tick = math.floor(frame / 2)
            local phase = tick % (scenario == "timed-short" and 60 or 90)
            local state = phase < 30 and 0 or 1
            local safeFor = terrain:spikes(1, state, tick)
            obs.map.zones[#obs.map.zones + 1] = {
                id = "spikes",
                x = 200,
                y = 160,
                radius = 19,
                timed = true,
                safeFor = safeFor,
            }
        end
    end
    function fixture.reset(name, mode, side, speed)
        scenario, frame, mask, crosses, exits, presses, hits, pickups = name, 0, 0, 0, 0, 0, 0, 0
        local walk = {}
        for row = 0, 9 do
            for col = 0, 11 do
                walk[row * 12 + col + 1] = row > 0 and row < 9 and col > 0 and col < 11
            end
        end
        local p = {
            id = "player",
            x = 120,
            y = 160,
            vx = 0,
            vy = 0,
            radius = 10,
            speed = speed,
            range = 260,
            keys = 2,
            items = 0,
            health = 6,
        }
        rooms = {
            a = { doors = {}, buttons = {}, pickups = {} },
            b = { doors = {}, buttons = {}, pickups = {} },
            c = { doors = {}, buttons = {}, pickups = {} },
        }
        if name == "graph" then
            rooms.a.doors = { door(side, "b"), door((side + 1) % 4, "c") }
            rooms.b.doors = { door((side + 2) % 4, "a") }
            rooms.c.doors = { door((side + 3) % 4, "a") }
            rooms.a.exit = { id = "exit:a", x = 240, y = 160, radius = 24, exit = true }
        elseif name == "arrival" then
            rooms.a.doors = { door(side, "b") }
            local d = rooms.a.doors[1]
            p.x, p.y = d.x - d.dx * 28, d.y - d.dy * 28
            p.vx, p.vy = d.dx * speed * 0.5, d.dy * speed * 0.5
        elseif name == "buttons" or name == "timed" or name == "timed-short" then
            rooms.a.buttons = { { id = "one", x = 280, y = 160 }, { id = "two", x = 320, y = 240 } }
            if name == "timed" or name == "timed-short" then
                for i = 1, 120 do
                    walk[i] = false
                end
                for col = 1, 10 do
                    walk[4 * 12 + col + 1] = true
                end
                rooms.a.buttons = { { id = "one", x = 280, y = 160 } }
                if name == "timed-short" then
                    p.x = 80
                end
                terrain = dofile(root .. "/src/bridge/lanbot/terrain.lua")()
                terrain:reset("w", "a", "player")
            end
        elseif name == "exit-pickup" then
            rooms.a.exit = { id = "exit:a", x = 240, y = 160, radius = 24, exit = true }
            rooms.a.pickups = { { id = "coin", x = 320, y = 160 } }
        elseif name == "dodge" then
            p.x, p.y = 160, 160
        end
        obs = {
            world = "w",
            room = "a",
            actor = p,
            enemies = {},
            dangers = {},
            partyReady = true,
            map = {
                x = 0,
                y = 0,
                width = 12,
                height = 10,
                step = 40,
                walk = walk,
                timed = name == "timed" or name == "timed-short",
                speed = speed * 0.7,
            },
            shotLine = function()
                return true
            end,
        }
        visited = { a = true }
        bot = create({
            info = function()
                return { active = 1, runId = "w", authority = 1 }
            end,
            observe = function()
                return obs
            end,
            input = function(_, value)
                mask = value
            end,
            clock = function()
                return 0
            end,
            log = function(message)
                error(message)
            end,
        }, modules)
        bot.command("mode " .. mode)
        bot.command("on")
        update()
        return fixture.read()
    end
    local function physical(x, y)
        for _, d in ipairs(obs.doors) do
            local along = (x - d.x) * d.dx + (y - d.y) * d.dy
            local across = math.abs((x - d.x) * d.dy - (y - d.y) * d.dx)
            if along > -48 and along < 48 and across + obs.actor.radius <= 22 then
                return true
            end
        end
        for _, delta in ipairs({ { -10, -10 }, { 10, -10 }, { -10, 10 }, { 10, 10 } }) do
            local col, row =
                math.floor((x + delta[1]) / 40 + 0.5), math.floor((y + delta[2]) / 40 + 0.5)
            if
                col < 0
                or col >= 12
                or row < 0
                or row >= 10
                or not obs.map.walk[row * 12 + col + 1]
            then
                return false
            end
        end
        return true
    end
    function fixture.step(count)
        assert(count >= 0 and count <= 3600)
        for _ = 1, count do
            frame = frame + 1
            update()
            if scenario == "dodge" then
                obs.dangers = { { x = 320 - frame * 5, y = 160, vx = -300, radius = 5 } }
            end
            bot.step(frame)
            local dx = ((mask & 2) ~= 0 and 1 or 0) - ((mask & 1) ~= 0 and 1 or 0)
            local dy = ((mask & 8) ~= 0 and 1 or 0) - ((mask & 4) ~= 0 and 1 or 0)
            local scale = dx ~= 0 and dy ~= 0 and 1 / math.sqrt(2) or 1
            local p = obs.actor
            p.vx = p.vx * 0.88 + dx * scale * p.speed * 0.12
            p.vy = p.vy * 0.88 + dy * scale * p.speed * 0.12
            local x, y = p.x + p.vx / 60, p.y + p.vy / 60
            if physical(x, y) then
                p.x, p.y = x, y
            else
                p.vx, p.vy = 0, 0
            end
            if obs.exit and distance(p, obs.exit) < 24 then
                exits = exits + 1
                if scenario == "graph" then
                    assert(visited.b and visited.c, "Floor advanced before exploring the branches")
                end
                rooms[obs.room].exit = nil
            end
            for i = #obs.buttons, 1, -1 do
                local button = obs.buttons[i]
                if distance(p, button) < 12 then
                    button.held = (button.held or 0) + 1
                    if button.held >= 6 then
                        table.remove(obs.buttons, i)
                        presses = presses + 1
                    end
                else
                    button.held = 0
                end
            end
            for i = #obs.pickups, 1, -1 do
                if distance(p, obs.pickups[i]) < 16 then
                    table.remove(obs.pickups, i)
                    pickups = pickups + 1
                end
            end
            if
                (scenario == "timed" or scenario == "timed-short")
                and math.floor(frame / 2) % (scenario == "timed-short" and 60 or 90) < 30
                and distance(p, { x = 200, y = 160 }) < 29
            then
                hits = hits + 1
            end
            if scenario == "dodge" and distance(p, obs.dangers[1]) < 15 then
                hits = hits + 1
            end
            for _, d in ipairs(obs.doors) do
                if (p.x - d.x) * d.dx + (p.y - d.y) * d.dy >= 0 then
                    local previous = obs.room
                    obs.room, crosses, visited[d.to] = d.to, crosses + 1, true
                    local returnDoor
                    for _, back in ipairs(rooms[d.to].doors) do
                        if back.to == previous then
                            returnDoor = back
                        end
                    end
                    if returnDoor then
                        p.x, p.y =
                            returnDoor.x - returnDoor.dx * 28, returnDoor.y - returnDoor.dy * 28
                    else
                        p.x, p.y = 160, 160
                    end
                    p.vx, p.vy = 0, 0
                    break
                end
            end
        end
        return fixture.read()
    end
    function fixture.read()
        return {
            crosses,
            exits,
            presses,
            hits,
            pickups,
            obs.room,
            bot.task,
            bot.reason or "",
            obs.actor.x,
            obs.actor.y,
            visited.b or false,
            visited.c or false,
        }
    end
    fixture.reset("graph", "explore", 2, 260)
    return fixture
end
