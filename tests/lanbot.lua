local root = assert(arg[1], "repository root required")
local modules = {}
for _, name in ipairs({
    "navigation",
    "hazards",
    "terrain",
    "combat",
    "items",
    "greed",
    "planner",
    "observe",
}) do
    modules["lanbot/" .. name] = dofile(root .. "/src/bridge/lanbot/" .. name .. ".lua")
end
modules.lanbot = dofile(root .. "/src/bridge/lanbot.lua")
local nav = modules["lanbot/navigation"]
local combat = modules["lanbot/combat"](nav, modules["lanbot/hazards"](nav))
local planner = modules["lanbot/planner"](nav, modules["lanbot/greed"], modules["lanbot/items"])
local count = 0
local function test(name, fn)
    local ok, reason = pcall(fn)
    assert(ok, name .. ": " .. tostring(reason))
    count = count + 1
end
local function snapshot()
    local walk = {}
    for i = 1, 120 do
        walk[i] = true
    end
    return {
        frame = 1,
        world = "run:1",
        room = "0:1",
        clear = true,
        partyReady = true,
        actor = {
            x = 160,
            y = 160,
            vx = 0,
            vy = 0,
            radius = 10,
            speed = 260,
            range = 260,
            keys = 2,
            health = 6,
            items = 0,
        },
        map = { x = 0, y = 0, step = 40, width = 12, height = 10, walk = walk },
        enemies = {},
        dangers = {},
        pickups = {},
        doors = {},
        shotLine = function()
            return true
        end,
    }
end
local function door(slot, to, options)
    local d = { slot = slot, to = to, x = 440, y = 160, dx = 1, dy = 0, open = true }
    for key, value in pairs(options or {}) do
        d[key] = value
    end
    return d
end
local function fixture()
    local obs, info = snapshot(), { active = 1, authority = 1, runId = "run" }
    local source = { active = false, mask = 0, calls = 0 }
    local observations, logs = 0, {}
    local env = {
        info = function()
            return info
        end,
        input = function(active, mask)
            source.active, source.mask, source.calls = active, mask, source.calls + 1
        end,
        observe = function(frame)
            observations = observations + 1
            obs.frame = frame
            return obs
        end,
        clock = function()
            return 0
        end,
        log = function(message)
            logs[#logs + 1] = message
        end,
    }
    return modules.lanbot(env, modules),
        source,
        obs,
        info,
        env,
        function()
            return observations
        end,
        logs
end
test("commands validate without side effects", function()
    local bot, source, _, info = fixture()
    assert(bot.command(""):find("on | pause"))
    for _, command in ipairs({
        "on extra",
        "mode unknown",
        "mode run extra",
        "style unknown",
        "unknown",
        "next extra",
    }) do
        assert(bot.command(command):find("error="))
        assert(bot.state == "off" and source.calls == 0)
    end
    assert(bot.command("resume"):find("use_on_first"))
    info.active = 0
    assert(bot.command("on"):find("lan_game_required"))
end)
test("on is idempotent; pause/off restore manual input", function()
    local bot, source = fixture()
    bot.command("on")
    bot.step(1)
    bot.step(2)
    local calls = source.calls
    bot.command("on")
    assert(source.calls == calls)
    bot.command("pause")
    assert(bot.state == "paused" and not source.active and source.mask == 0)
    bot.command("pause")
    assert(bot.state == "paused")
    bot.command("resume")
    assert(bot.state == "running")
    bot.command("off")
    bot.command("off")
    assert(bot.state == "off" and not source.active)
end)
test("configuration survives pause/off but resets with session", function()
    local bot, _, _, info = fixture()
    bot.command("mode explore")
    bot.command("style cautious")
    assert(bot.state == "off")
    bot.command("on")
    bot.command("pause")
    bot.command("off")
    assert(bot.mode == "explore" and bot.style == "cautious")
    bot.command("on")
    info.runId = "another"
    bot.poll()
    assert(bot.state == "off" and bot.mode == "run" and bot.style == "balanced" and not bot.runId)
    bot.poll()
    bot.command("mode hold")
    bot.poll()
    assert(bot.mode == "hold")
end)
test("render deduplication and transition neutrality", function()
    local bot, source, obs, _, _, observations = fixture()
    obs.doors = { door(2, "0:2") }
    bot.command("on")
    bot.step(1)
    assert(source.active and source.mask == 0)
    bot.step(1)
    assert(observations() == 1)
    bot.step(2)
    assert(source.mask ~= 0)
    obs.room = "0:2"
    bot.step(3)
    assert(source.mask == 0)
    obs.world = "run:2"
    bot.step(4)
    assert(source.mask == 0 and not bot.plan.nodes["0:1"])
end)
test("waiting releases gameplay, reconnect does not resume", function()
    local bot, source, _, info, env = fixture()
    bot.command("on")
    env.observe = function()
        return nil, "dead"
    end
    bot.step(1)
    assert(source.active and source.mask == 0 and bot.reason == "dead")
    env.observe = function()
        return nil, "interface_or_transition"
    end
    bot.step(2)
    assert(source.mask == 0 and bot.reason == "interface_or_transition")
    info.active = 0
    bot.poll()
    assert(bot.state == "off" and not source.active)
    info.active = 1
    bot.step(3)
    assert(not source.active)
end)
test("actor replacement clears old input and local path", function()
    local bot, source, obs = fixture()
    obs.actor.id = "first"
    obs.doors = { door(2, "0:2") }
    bot.command("on")
    bot.step(1)
    bot.step(2)
    assert(source.mask ~= 0)
    obs.actor.id = "replacement"
    bot.step(3)
    assert(source.mask == 0 and bot.actor == "replacement" and not bot.plan.advance)
end)
test("next survives walking through known rooms to the exit", function()
    local bot, _, obs = fixture()
    bot.command("mode explore")
    bot.command("on")
    obs.exit = { x = 300, y = 160 }
    obs.doors = { door(2, "0:2") }
    bot.step(1)
    obs.room, obs.exit, obs.doors = "0:2", nil, { door(0, "0:1"), door(2, "0:3") }
    bot.step(2)
    obs.room, obs.doors = "0:3", { door(0, "0:2") }
    bot.step(3)
    assert(not bot.command("next"):find("error="))
    bot.step(4)
    assert(bot.plan.advance and bot.task == "move_to_door")
    obs.room, obs.doors = "0:2", { door(0, "0:1"), door(2, "0:3") }
    bot.step(5)
    bot.step(6)
    assert(bot.plan.advance and bot.task == "move_to_door")
    obs.room, obs.exit, obs.partyReady = "0:1", { x = 300, y = 160 }, false
    bot.step(7)
    bot.step(8)
    assert(bot.plan.advance and bot.task == "move_to_exit")
end)
test("policy errors pause and release", function()
    local bot, source, _, _, env, _, logs = fixture()
    bot.command("on")
    env.observe = function()
        error("fixture failure")
    end
    bot.step(1)
    assert(bot.state == "paused" and not source.active and bot.reason == "decision_error")
    assert(#logs == 1 and logs[1]:find("fixture failure"))
end)
test("exploration returns through visited branches and terminates", function()
    local plan, obs = planner.new(), snapshot()
    obs.doors = { door(2, "0:2"), door(1, "0:3") }
    plan:observe(obs)
    obs.room = "0:2"
    obs.doors = { door(0, "0:1") }
    plan:observe(obs)
    assert(plan:choose(obs, "explore", "balanced").door.to == "0:1")
    obs.room = "0:3"
    obs.doors = { door(0, "0:1") }
    plan:observe(obs)
    local goal, reason = plan:choose(obs, "explore", "balanced")
    assert(not goal and reason == "exploration_complete")
end)
test("explore ignores known exit until next", function()
    local plan, obs = planner.new(), snapshot()
    obs.exit = { x = 200, y = 200 }
    obs.doors = { door(2, "0:2") }
    plan:observe(obs)
    obs.room, obs.exit = "0:2", nil
    obs.doors = { door(0, "0:1"), door(2, "0:3") }
    plan:observe(obs)
    assert(plan:choose(obs, "explore", "balanced").door.to == "0:3")
    assert(plan:nextExit())
    assert(plan:choose(obs, "explore", "balanced").door.to == "0:1")
    obs.world = "run:2"
    plan:observe(obs)
    assert(not plan.advance and not plan:nextExit())
end)
test("hold stays; run waits for party; next bypass is one-shot", function()
    local bot, _, obs = fixture()
    obs.exit = { x = 320, y = 160 }
    obs.partyReady = false
    bot.command("on")
    bot.step(1)
    bot.step(2)
    assert(bot.reason == "wait_for_party")
    bot.command("mode hold")
    assert(bot.command("next"):find("next_requires"))
    bot.step(3)
    assert(bot.reason == "room_clear")
    bot.command("mode explore")
    assert(not bot.command("next"):find("error="))
    bot.step(4)
    assert(bot.task == "move_to_exit")
    obs.world = "run:2"
    bot.step(5)
    assert(not bot.plan.advance)
end)
test("keys and paid/unsafe branches are excluded", function()
    local plan, obs = planner.new(), snapshot()
    obs.actor.keys = 0
    obs.doors = { door(2, "0:2", { open = false, locked = true }), door(1, "0:3", { skip = true }) }
    plan:observe(obs)
    local goal, reason = plan:choose(obs, "run", "balanced")
    assert(not goal and reason == "resource_missing")
    obs.actor.keys = 1
    assert(plan:choose(obs, "run", "balanced").door.to == "0:2")
    obs.room, obs.doors = "0:2", { door(0, "0:1") }
    plan:observe(obs)
    assert(plan.nodes["0:1"].edges[2].open and not plan.nodes["0:1"].edges[2].locked)
end)
test("boss reward is limited after actual pickup", function()
    local plan, obs = planner.new(), snapshot()
    obs.boss = true
    obs.pickups = { { id = "item1", x = 200, y = 160, collectible = true } }
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").id == "item1")
    obs.actor.items = 1
    plan:observe(obs)
    obs.pickups = { { id = "item2", x = 240, y = 160, collectible = true } }
    assert(not plan:choose(obs, "run", "balanced"))
end)
test("A-star detours around obstacles without cutting corners", function()
    local obs = snapshot()
    local map = obs.map
    for row = 1, 6 do
        map.walk[row * map.width + 6] = false
    end
    local from, to = { x = 120, y = 120 }, { x = 320, y = 120 }
    assert(not nav.line(map, from, to, 10))
    local path = assert(nav.path(map, from, to, 10, 640))
    local previous = from
    for _, point in ipairs(path) do
        assert(nav.line(map, previous, point, 10))
        previous = point
    end
    assert(previous.x == to.x and previous.y == to.y)
    assert(not nav.path(map, from, to, 10, 1))
end)
test("swapping an active boss reward still counts toward the one-reward limit", function()
    local plan, obs = planner.new(), snapshot()
    obs.boss = true
    obs.pickups = { { id = "active1", x = 170, y = 160, collectible = true } }
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").id == "active1")
    obs.pickups = { { id = "active2", x = 240, y = 160, collectible = true } }
    plan:observe(obs)
    assert(obs.actor.items == 0 and not plan:choose(obs, "run", "balanced"))
end)
test("door corridor only permits selected doorway", function()
    local obs = snapshot()
    for row = 0, 9 do
        obs.map.walk[row * 12 + 12] = false
    end
    local point = { x = 470, y = 160 }
    assert(not nav.passable(obs.map, point.x, point.y, 10))
    assert(nav.passable(obs.map, point.x, point.y, 10, door(2, "0:2")))
    assert(not nav.passable(obs.map, point.x, point.y + 35, 10, door(2, "0:2")))
end)
test("continuous movement reaches nearby waypoints and crosses the selected door", function()
    for _, settings in ipairs({ { x = 384, y = 154 }, { x = 160, y = 160 } }) do
        local obs, plan = snapshot(), planner.new()
        obs.actor.x, obs.actor.y = settings.x, settings.y
        local selected = door(2, "0:2")
        obs.doors = { selected }
        for row = 0, 9 do
            obs.map.walk[row * 12 + 12] = false
        end
        local crossed = false
        for frame = 1, 300 do
            obs.frame = frame
            plan:observe(obs)
            local goal = assert(plan:choose(obs, "explore", "balanced"))
            local waypoint = plan:waypoint(obs, goal)
            local buttons = combat.move(obs, waypoint, "balanced", 0, selected)
            local dx = ((buttons & 2) ~= 0 and 1 or 0) - ((buttons & 1) ~= 0 and 1 or 0)
            local dy = ((buttons & 8) ~= 0 and 1 or 0) - ((buttons & 4) ~= 0 and 1 or 0)
            local scale = dx ~= 0 and dy ~= 0 and 0.7071 or 1
            local p = obs.actor
            p.vx = p.vx * 0.88 + dx * scale * p.speed * 0.12
            p.vy = p.vy * 0.88 + dy * scale * p.speed * 0.12
            p.x, p.y = p.x + p.vx / 60, p.y + p.vy / 60
            if p.x >= selected.x then
                assert(math.abs(p.y - selected.y) + p.radius <= 22)
                crossed = true
                break
            end
        end
        assert(crossed, "Planner stalled before the doorway")
    end
end)
test("stuck targets cool down and alternate doors are chosen", function()
    local plan, obs = planner.new(), snapshot()
    obs.doors = { door(2, "0:2"), door(1, "0:3") }
    plan:observe(obs)
    local goal = plan:choose(obs, "explore", "balanced")
    plan:waypoint(obs, goal)
    obs.frame = 123
    local waypoint, reason = plan:waypoint(obs, goal)
    assert(not waypoint and reason == "route_blocked")
    assert(plan:choose(obs, "explore", "balanced").id ~= goal.id)
end)
test("combat styles change actual positioning and ignore invulnerable targets", function()
    local obs = snapshot()
    local target = { id = "enemy", x = 400, y = 160, radius = 12, attackable = true }
    obs.enemies = { { id = "immune", x = 161, y = 160, radius = 12, attackable = false }, target }
    assert(combat.target(obs, "balanced") == target)
    local aggressive, cautious =
        combat.goal(obs, target, "aggressive"), combat.goal(obs, target, "cautious")
    assert(aggressive.x ~= cautious.x)
    target.x, target.y = 5, 5
    local corner = assert(combat.goal(obs, target, "balanced"))
    assert(nav.passable(obs.map, corner.x, corner.y, obs.actor.radius))
end)
test("all nine movements evaluated; incoming bullet is avoided", function()
    local obs = snapshot()
    obs.dangers = { { x = 250, y = 160, vx = -300, vy = 0, radius = 5 } }
    local button, _, evaluated = combat.move(obs, nil, "balanced", 0)
    assert(evaluated == 9 and (button & (4 | 8)) ~= 0)
end)
test("laser segment and upcoming explosion trigger evasive movement", function()
    local obs = snapshot()
    obs.dangers = { { x = 0, y = 160, bx = 440, by = 160, radius = 8 } }
    assert((combat.move(obs, nil, "cautious", 0) & (4 | 8)) ~= 0)
    obs.dangers = { { x = 160, y = 160, at = 0.1, radius = 40 } }
    assert(combat.move(obs, nil, "balanced", 0) ~= 0)
end)
test("charge hold/release and aim/line/range checks", function()
    local obs, memory = snapshot(), {}
    local target = { id = "enemy", x = 300, y = 160, radius = 12, attackable = true }
    assert(combat.shoot(obs, target, memory) == 32)
    obs.actor.charge = 30
    assert(combat.shoot(obs, target, memory) == 32)
    obs.frame = 31
    assert(combat.shoot(obs, target, memory) == 0)
    obs.frame = 32
    assert(combat.shoot(obs, target, memory) == 0)
    obs.frame = 33
    assert(combat.shoot(obs, target, memory) == 0)
    obs.frame = 34
    assert(combat.shoot(obs, target, memory) == 32)
    combat.shoot(obs, nil, memory)
    assert(not memory.charging)
    obs.actor.charge = nil
    obs.shotLine = function()
        return false
    end
    assert(combat.shoot(obs, target, memory) == 0)
end)

test("run finishes reachable branches before selecting a known exit", function()
    local plan, obs = planner.new(), snapshot()
    obs.exit = { id = "floor-exit", x = 240, y = 160 }
    obs.doors = { door(2, "0:2"), door(1, "0:3") }
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").task == "move_to_door")
    obs.room, obs.exit, obs.doors = "0:2", nil, { door(0, "0:1") }
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").door.to == "0:1")
    obs.room, obs.doors = "0:3", { door(0, "0:1") }
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").door.to == "0:1")
    obs.room, obs.exit, obs.doors =
        "0:1", plan.nodes["0:1"].exit, { door(2, "0:2"), door(1, "0:3") }
    obs.partyReady = false
    plan:observe(obs)
    local goal, reason = plan:choose(obs, "run", "balanced")
    assert(not goal and reason == "wait_for_party")
    assert(plan:nextExit())
    assert(plan:choose(obs, "run", "balanced").task == "move_to_exit")
end)
test("next uses the current exit when several rooms have exits", function()
    local plan, obs = planner.new(), snapshot()
    obs.exit, obs.doors = { x = 200, y = 160 }, { door(2, "0:2") }
    plan:observe(obs)
    obs.room, obs.doors = "0:2", { door(0, "0:1") }
    plan:observe(obs)
    assert(plan:nextExit())
    assert(plan:choose(obs, "explore", "balanced").task == "move_to_exit")
end)
test("observed doors replace stale edges and failures belong to their source room", function()
    local plan, obs = planner.new(), snapshot()
    obs.doors = { door(2, "0:2"), door(1, "0:3") }
    plan:observe(obs)
    plan:block("door:2:0:2", 300)
    assert(not plan:available("door:2:0:2", 1))
    obs.room, obs.doors = "0:3", { door(2, "0:2") }
    plan:observe(obs)
    assert(plan:available("door:2:0:2", 1))
    obs.doors = {}
    plan:observe(obs)
    assert(not next(plan.nodes["0:3"].edges))
end)
test("buttons are attempted before room clear and need actual activation", function()
    local plan, obs = planner.new(), snapshot()
    obs.clear = false
    obs.buttons = { { id = "one", x = 160, y = 160 }, { id = "two", x = 300, y = 160 } }
    plan:observe(obs)
    assert(plan:choose(obs, "explore", "balanced").id == "one")
    obs.frame = 40
    assert(plan:choose(obs, "explore", "balanced").id == "one")
    obs.buttons = { obs.buttons[2] }
    assert(plan:choose(obs, "explore", "balanced").id == "two")
    obs.actor.x, obs.frame = 300, 41
    plan:choose(obs, "explore", "balanced")
    obs.frame = 140
    local goal, reason = plan:choose(obs, "explore", "balanced")
    assert(not goal and reason == "button_not_activated")
    obs.buttons, obs.clear = {}, true
    plan:observe(obs)
    goal, reason = plan:choose(obs, "explore", "balanced")
    assert(not goal and reason == "exploration_complete")
end)
test("exit contact circles protect every exit and allow outward recovery", function()
    local obs = snapshot()
    local first = { id = "a", x = 200, y = 160, radius = 24, exit = true }
    local second = { id = "b", x = 320, y = 160, radius = 24, exit = true }
    obs.map.zones = { first, second }
    assert(not nav.passable(obs.map, 170, 160, 10))
    assert(not nav.line(obs.map, obs.actor, { x = 250, y = 160 }, 10))
    obs.map.allowedExit = "a"
    assert(nav.passable(obs.map, 200, 160, 10))
    assert(not nav.passable(obs.map, 320, 160, 10))
    obs.map.allowedExit = nil
    assert(nav.line(obs.map, { x = 180, y = 160 }, { x = 150, y = 160 }, 10))
    assert(not nav.line(obs.map, { x = 180, y = 160 }, { x = 190, y = 160 }, 10))
end)
test("timed traps wait for a sufficient window without cooling down a valid route", function()
    local plan, obs = planner.new(), snapshot()
    for i = 1, 120 do
        obs.map.walk[i] = false
    end
    for col = 2, 9 do
        obs.map.walk[4 * 12 + col + 1] = true
    end
    obs.actor.x, obs.actor.y, obs.actor.radius = 120, 160, 6
    obs.map.timed, obs.map.speed = true, 200
    local spike = { id = "spike", x = 200, y = 160, radius = 19, timed = true, safeFor = 0 }
    obs.map.zones = { spike }
    local goal = { id = "button", x = 280, y = 160 }
    plan:observe(obs)
    local point, reason = plan:waypoint(obs, goal)
    assert(
        point
            and point.x > obs.actor.x
            and point.x < 175
            and reason == "wait_for_trap"
            and plan:available(goal.id, obs.frame)
    )
    obs.frame = 200
    assert(select(2, plan:waypoint(obs, goal)) == "wait_for_trap")
    spike.safeFor = 0.1
    assert(not nav.path(obs.map, obs.actor, goal, 6))
    spike.safeFor = 2
    assert(plan:waypoint(obs, goal))
    spike.timed, obs.map.timed = false, false
    assert(select(2, plan:waypoint(obs, goal)) == "route_blocked")
end)
test("complete spike cycles use simulation ticks and reset at identity boundaries", function()
    local terrain = modules["lanbot/terrain"]()
    terrain:reset("w", "r", "p")
    assert(terrain:spikes(1, 1, 0) == 0)
    for tick = 1, 9 do
        terrain:spikes(1, 1, tick)
    end
    for tick = 10, 19 do
        terrain:spikes(1, 0, tick)
    end
    for tick = 20, 49 do
        terrain:spikes(1, 1, tick)
    end
    for tick = 50, 59 do
        terrain:spikes(1, 0, tick)
    end
    assert(terrain:spikes(1, 1, 60) > 0.8)
    assert(terrain:spikes(1, 1, 60) == terrain:spikes(1, 1, 60))
    for tick = 61, 88 do
        terrain:spikes(1, 1, tick)
    end
    assert(terrain:spikes(1, 1, 88) == 0)
    assert(terrain:spikes(1, 1, 200) == 0) -- Missed observations invalidate the learned phase.
    terrain:reset("w", "next", "p")
    assert(terrain:spikes(1, 1, 60) == 0)
    terrain:reset("w", "next", "replacement")
    assert(terrain:spikes(1, 1, 60) == 0)
end)
test("continuous danger checks catch fast crossings and compensate view age", function()
    local obs = snapshot()
    local hazards = modules["lanbot/hazards"](nav)
    obs.dangers = { { x = 100, y = 160, vx = 6000, radius = 4 } }
    assert(hazards.risk(obs, obs.actor, obs.actor, 0, 1 / 30, combat.styles.balanced) > 2800)
    obs.dangers = { { x = 100, y = 160, vx = 300, radius = 4 } }
    obs.age = 0.2
    assert(hazards.risk(obs, obs.actor, obs.actor, 0, 0.01, combat.styles.balanced) > 2800)
    obs.dangers = { { x = 160, y = 160, at = 1, radius = 85 } }
    assert(hazards.risk(obs, obs.actor, obs.actor, 0, 0.3, combat.styles.balanced) == 0)
end)
test("nearby waypoints do not truncate danger prediction", function()
    local obs = snapshot()
    obs.dangers = { { x = 260, y = 160, vx = -300, radius = 5 } }
    local move = combat.move(obs, { x = 162, y = 160 }, "balanced", 2)
    assert((move & (4 | 8)) ~= 0)
end)
test("firing lanes avoid danger and targets remain stable for similar distances", function()
    local obs = snapshot()
    local enemy = { id = "a", x = 400, y = 160, radius = 12, attackable = true }
    local ordinary = assert(combat.goal(obs, enemy, "balanced"))
    obs.dangers = { { x = ordinary.x, y = ordinary.y, radius = 30 } }
    assert(combat.goal(obs, enemy, "balanced").id ~= ordinary.id)
    obs.enemies = { enemy, { id = "b", x = 380, y = 160, radius = 12, attackable = true } }
    assert(combat.target(obs, "balanced", "a").id == "a")
    enemy.attackable = false
    assert(combat.target(obs, "balanced", "a").id == "b")
end)

-- Exercise the game adapter with documented API-shaped fakes. No game process.
EntityFlag = { FLAG_FRIENDLY = 1, FLAG_CHARM = 2, FLAG_NO_TARGET = 4 }
EntityType = {
    ENTITY_PLAYER = 1,
    ENTITY_FAMILIAR = 3,
    ENTITY_SLOT = 6,
    ENTITY_PROJECTILE = 9,
    ENTITY_FIREPLACE = 33,
    ENTITY_EFFECT = 1000,
}
PlayerType = { PLAYER_AZAZEL = 7 }
WeaponType = { WEAPON_BRIMSTONE = 4, WEAPON_KNIFE = 3, WEAPON_TECH_X = 9 }
CollectibleType = { COLLECTIBLE_CHOCOLATE_MILK = 69 }
ItemType = { ITEM_PASSIVE = 1, ITEM_ACTIVE = 3 }
CacheFlag = { CACHE_DAMAGE = 1, CACHE_FIREDELAY = 2 }
GridCollisionClass = {
    COLLISION_NONE = 0,
    COLLISION_PIT = 1,
    COLLISION_OBJECT = 2,
    COLLISION_WALL_EXCEPT_PLAYER = 5,
}
GridEntityType = {
    GRID_POOP = 14,
    GRID_TRAPDOOR = 17,
    GRID_STAIRS = 18,
    GRID_PRESSURE_PLATE = 20,
    GRID_SPIKES = 8,
    GRID_SPIKES_ONOFF = 9,
}
EffectVariant = {
    HEAVEN_LIGHT_DOOR = 39,
    CREEP_RED = 22,
    CREEP_GREEN = 23,
    CREEP_YELLOW = 24,
    CREEP_WHITE = 25,
    CREEP_BLACK = 26,
}
RoomType = {
    ROOM_SHOP = 2,
    ROOM_GREED_EXIT = 24,
    ROOM_BOSS = 5,
    ROOM_TREASURE = 4,
    ROOM_CURSE = 10,
    ROOM_SACRIFICE = 13,
    ROOM_SECRET = 7,
    ROOM_SUPERSECRET = 8,
    ROOM_CHALLENGE = 11,
}
PickupVariant = {
    PICKUP_COLLECTIBLE = 100,
    PICKUP_HEART = 10,
    PICKUP_COIN = 20,
    PICKUP_KEY = 30,
    PICKUP_BOMB = 40,
    PICKUP_BIGCHEST = 340,
}
HeartSubType = {
    HEART_SOUL = 3,
    HEART_HALF_SOUL = 8,
    HEART_BLACK = 6,
    HEART_BONE = 11,
    HEART_GOLDEN = 7,
    HEART_ROTTEN = 12,
    HEART_ETERNAL = 4,
}
Vector = function(x, y)
    return { X = x, Y = y }
end
local function fakePlayer(seed)
    return setmetatable({
        InitSeed = seed,
        Type = 1,
        Variant = 0,
        Position = Vector(seed, 160),
        Velocity = Vector(0, 0),
        Size = 10,
        MoveSpeed = 1,
        TearRange = 260,
        MaxFireDelay = 10,
        ControlsEnabled = true,
        ControlsCooldown = 0,
        CanFly = false,
    }, {
        __index = {
            IsCoopGhost = function()
                return false
            end,
            AreControlsEnabled = function()
                return true
            end,
            IsDead = function()
                return false
            end,
            GetNumKeys = function()
                return 2
            end,
            GetCollectibleCount = function()
                return 0
            end,
            GetHearts = function()
                return 6
            end,
            GetSoulHearts = function()
                return 0
            end,
            GetEffectiveMaxHearts = function()
                return 8
            end,
            GetPlayerType = function()
                return 0
            end,
            HasWeaponType = function()
                return false
            end,
            HasCollectible = function()
                return false
            end,
            CanPickupItem = function()
                return true
            end,
            CanPickRedHearts = function()
                return false
            end,
            CanPickSoulHearts = function()
                return true
            end,
            GetNumCoins = function()
                return 0
            end,
            GetNumBombs = function()
                return 0
            end,
        },
    })
end
local roster = { [0] = fakePlayer(100), [2] = fakePlayer(200) }
local entities, paused, viewed = {}, false, false
local greed, greedStage, greedWave, difficulty, challenge = false, 1, 0, 2, 0
local aliases = {}
local room = {
    GetGridPosition = function(_, i)
        return Vector(i % 12 * 40, math.floor(i / 12) * 40)
    end,
    GetFrameCount = function()
        return 0
    end,
    GetGridWidth = function()
        return 12
    end,
    GetGridSize = function()
        return 120
    end,
    GetGridEntity = function()
        return nil
    end,
    GetGridCollision = function()
        return 0
    end,
    IsPositionInRoom = function()
        return true
    end,
    IsClear = function()
        return true
    end,
    GetType = function()
        return 1
    end,
    GetDoor = function()
        return nil
    end,
    CheckLine = function()
        return true
    end,
}
Game = function()
    return {
        IsPaused = function()
            return paused
        end,
        IsGreedMode = function()
            return greed
        end,
        Challenge = challenge,
        Difficulty = difficulty,
        GetLevel = function()
            assert(viewed)
            return {
                GreedModeWave = greedWave,
                GetStage = function()
                    return greedStage
                end,
                GetRoomByIdx = function(_, index)
                    return { Data = {}, SafeGridIndex = aliases[index] or index }
                end,
            }
        end,
        GetRoom = function()
            assert(viewed)
            return room
        end,
    }
end
local positions = { ["0"] = { index = 1, dimension = 0 }, ["1"] = { index = 2, dimension = 0 } }
local native = {
    api_actors = function()
        return { { index = 0, owner = 1 }, { index = 2, owner = 2 } }
    end,
    rooms_positions = function()
        return positions
    end,
}
local bridge = {
    ready = function()
        return true
    end,
    withView = function(fn)
        viewed = true
        fn()
        viewed = false
    end,
}
local callbacks, output = {}, {}
Isaac = {
    GetItemConfig = function()
        return {
            GetCollectible = function()
                return { Type = ItemType.ITEM_PASSIVE }
            end,
        }
    end,
    GetPlayer = function(index)
        assert(not viewed, "global roster read inside local view")
        return assert(roster[index])
    end,
    GetRoomEntities = function()
        assert(viewed)
        return entities
    end,
    AddCallback = function(_, id, fn)
        assert(not callbacks[id])
        callbacks[id] = fn
    end,
    GetTime = function()
        return 0
    end,
    DebugString = function() end,
    ConsoleOutput = function(message)
        output[#output + 1] = message
    end,
}
local observe = modules["lanbot/observe"](
    native,
    bridge,
    nav,
    modules["lanbot/terrain"],
    modules["lanbot/items"]
)
local localInfo = {
    ready = 1,
    active = 1,
    slot = 1,
    connected = 3,
    authority = 0,
    runId = "run",
    worldEpoch = 1,
    tick = 1,
    nowMs = 0,
}
test("observer binds owning actor before scoping room; waits for remote party", function()
    local obs = assert(observe.read(1, localInfo))
    assert(obs.actor.x == 200 and not obs.partyReady)
    positions["0"].index = 2
    assert(observe.read(2, localInfo).partyReady)
    roster[2] = fakePlayer(250)
    assert(observe.read(3, localInfo).actor.x == 250)
    roster[2].IsDead = function()
        return true
    end
    local missing, reason = observe.read(4, localInfo)
    assert(not missing and reason == "dead")
    roster[2] = fakePlayer(200)
end)
test("observer excludes empty grid outside room walls and L-shaped cutouts", function()
    local inside = room.IsPositionInRoom
    room.IsPositionInRoom = function(_, pos, margin)
        assert(viewed and margin == 0)
        return pos.X >= 40
            and pos.X <= 400
            and pos.Y >= 40
            and pos.Y <= 320
            and not (pos.X >= 240 and pos.Y < 160)
    end
    local obs = assert(observe.read(1, localInfo))
    assert(not nav.passable(obs.map, 0, 80, 0))
    assert(not nav.passable(obs.map, 440, 80, 0))
    assert(not nav.passable(obs.map, 280, 80, 0))
    assert(nav.passable(obs.map, 80, 80, 0))
    assert(nav.passable(obs.map, 280, 200, 0))
    room.IsPositionInRoom = inside
end)
test("observer handles gameplay gate and pause", function()
    localInfo.ready = 0
    local obs, reason = observe.read(1, localInfo)
    assert(not obs and reason == "view_not_ready")
    localInfo.ready = 1
    paused = true
    obs, reason = observe.read(2, localInfo)
    assert(not obs and reason == "interface_or_transition")
    paused = false
end)
test(
    "Greed observer drives native start and Boss buttons, protects live and bonus buttons",
    function()
        local original = room.GetGridEntity
        local animation = "Off"
        local plate = {
            State = 0,
            GetType = function()
                return GridEntityType.GRID_PRESSURE_PLATE
            end,
            GetVariant = function()
                return 2
            end,
            GetSprite = function()
                return {
                    GetAnimation = function()
                        return animation
                    end,
                }
            end,
        }
        room.GetGridEntity = function(_, index)
            return index == 52 and plate or nil
        end
        greed = true
        local obs = assert(observe.read(1, localInfo))
        assert(obs.greed.stage == 1 and obs.greed.wave == 0 and obs.greed.bossWave == 10)
        assert(#obs.buttons == 1 and obs.buttons[1].greed)
        local plan = planner.new()
        plan:observe(obs)
        assert(plan:choose(obs, "run", "balanced").task == "press_button")
        obs.partyReady = false
        assert(select(2, plan:choose(obs, "run", "balanced")) == "wait_for_party")
        greedWave, animation = 1, "OffRed"
        obs = assert(observe.read(2, localInfo))
        assert(#obs.buttons == 0 and #obs.dangers == 1 and #obs.map.zones == 1)
        local zone = obs.map.zones[1]
        assert(
            not nav.line(
                obs.map,
                { x = zone.x - 80, y = zone.y },
                { x = zone.x + 80, y = zone.y },
                10
            )
        )
        greedWave, animation = 8, "OffSkull"
        assert(#observe.read(3, localInfo).buttons == 1)
        greedWave, animation = 10, "OffPentagram"
        assert(#observe.read(4, localInfo).buttons == 0)
        difficulty, greedWave, animation = 3, 9, "OffSkull"
        obs = assert(observe.read(5, localInfo))
        assert(obs.greed.bossWave == 11 and #obs.buttons == 1)
        greedWave = 11
        assert(#observe.read(6, localInfo).buttons == 0)
        greedStage, greedWave, animation = 7, 0, "Off"
        assert(#observe.read(7, localInfo).buttons == 0)
        greed, greedStage, greedWave, difficulty = false, 1, 0, 2
        obs = assert(observe.read(8, localInfo))
        assert(not obs.greed and #obs.buttons == 0 and #obs.map.zones == 0)
        challenge = 1
        local missing, reason = observe.read(9, localInfo)
        assert(not missing and reason == "unsupported_run")
        challenge, room.GetGridEntity = 0, original
    end
)
test("Greed run prioritizes its real exit door over optional treasure exploration", function()
    local plan, obs = planner.new(), snapshot()
    obs.doors = { door(0, "0:2", { treasure = true }), door(2, "0:3", { greedExit = true }) }
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").door.to == "0:3")
    assert(plan:choose(obs, "explore", "balanced").door.to == "0:2")
end)
test(
    "blocked route shoots a real poop and resumes only after the grid is actually broken",
    function()
        local bot, source, obs = fixture()
        obs.doors = { door(2, "0:2") }
        obs.breakables = {}
        for row = 0, 9 do
            local cell = row * 12 + 6
            obs.map.walk[cell] = false
            obs.breakables[#obs.breakables + 1] = {
                id = "poop:" .. cell,
                cell = cell,
                x = 200,
                y = row * 40,
                radius = 20,
                attackable = true,
                breakable = true,
            }
        end
        bot.command("on")
        bot.step(1)
        bot.step(2)
        assert(bot.task == "clear_obstacle" and source.mask & 240 ~= 0)
        local broken = assert(bot.plan.breaking)
        for frame = 3, 10 do
            bot.step(frame)
            assert(bot.plan.breaking == broken and source.mask & 240 ~= 0)
            for _, poop in ipairs(obs.breakables) do
                assert(not obs.map.walk[poop.cell])
            end
        end
        -- Supply the native tear collision result; the bot never changes this map.
        for i, poop in ipairs(obs.breakables) do
            if poop.id == broken then
                obs.map.walk[poop.cell] = true
                table.remove(obs.breakables, i)
                break
            end
        end
        bot.step(250)
        assert(not bot.plan.breaking and bot.task == "move_to_door" and source.mask & 15 ~= 0)
        obs.world = "run:2"
        bot.step(251)
        assert(not bot.plan.breaking and source.mask == 0)
    end
)
test(
    "poop route identification leaves rock walls and all original grid collisions intact",
    function()
        local plan, obs = planner.new(), snapshot()
        for row = 0, 9 do
            obs.map.walk[row * 12 + 6] = false
        end
        obs.breakables = { { id = "poop:1", cell = 1, x = 0, y = 0, radius = 20 } }
        plan:observe(obs)
        assert(not plan:obstacle(obs, { x = 320, y = 160 }))
        for row = 0, 9 do
            assert(not obs.map.walk[row * 12 + 6])
        end
    end
)
test("a free healing goal behind one poop gap in a rock wall triggers normal shooting", function()
    local bot, source, obs = fixture()
    obs.actor.x, obs.actor.y, obs.actor.radius = 200, 280, 12
    obs.pickups = { { id = "heart", x = 440, y = 280, radius = 10, heal = true } }
    for row = 0, 9 do
        obs.map.walk[row * 12 + 9] = false
    end
    obs.breakables = {
        {
            id = "poop",
            x = 320,
            y = 280,
            cell = 93,
            radius = 20,
            breakable = true,
            attackable = true,
        },
    }
    bot.command("mode hold")
    bot.command("on")
    bot.step(1)
    bot.step(2)
    assert(bot.task == "clear_obstacle" and source.mask & 240 ~= 0)
end)
test("observer accepts a native first hit on its poop but rejects another blocking grid", function()
    local grid, collision, line, gridIndex =
        room.GetGridEntity, room.GetGridCollision, room.CheckLine, room.GetGridIndex
    local state = 0
    room.GetGridEntity = function(_, index)
        if index == 52 then
            return {
                State = state,
                GetType = function()
                    return GridEntityType.GRID_POOP
                end,
            }
        end
    end
    room.GetGridCollision = function(_, index)
        return index == 52 and state < 1000 and GridCollisionClass.COLLISION_OBJECT or 0
    end
    local traceEnd, aheadBlocked = nil, false
    room.CheckLine = function(_, _, to)
        traceEnd = to
        return false, { X = 136, Y = 160 }
    end
    room.GetGridIndex = function(_, position)
        return position.X < 140 and 51 or 52
    end
    room.GetGridCollision = function(_, index)
        return (index == 52 and state < 1000 or index == 51 and aheadBlocked)
                and GridCollisionClass.COLLISION_OBJECT
            or 0
    end
    local obs = assert(observe.read(1, localInfo))
    assert(#obs.breakables == 1 and not obs.map.walk[53])
    assert(obs.shotLine({ x = 80, y = 160 }, obs.breakables[1]))
    assert(traceEnd.X == 160 and traceEnd.Y == 160)
    aheadBlocked = true
    assert(not obs.shotLine({ x = 80, y = 160 }, obs.breakables[1]))
    state = 1000
    obs = assert(observe.read(2, localInfo))
    assert(#obs.breakables == 0 and obs.map.walk[53])
    room.GetGridEntity, room.GetGridCollision, room.CheckLine, room.GetGridIndex =
        grid, collision, line, gridIndex
end)
test(
    "known Greed shops are revisited for affordable missing resources and then stop attracting routes",
    function()
        local plan, obs = planner.new(), snapshot()
        obs.greed, obs.actor.keys, obs.actor.coins = { stage = 1, wave = 0, bossWave = 10 }, 0, 0
        obs.doors = { door(0, "0:shop", { shop = true }), door(2, "0:exit", { greedExit = true }) }
        plan:observe(obs)
        obs.room, obs.shop, obs.doors = "0:shop", true, { door(0, "0:1") }
        obs.shopOffers = { { key = true, price = 5 }, { recovery = true, price = 3 } }
        plan:observe(obs)
        obs.room, obs.shop, obs.doors =
            "0:1",
            false,
            { door(0, "0:shop", { shop = true }), door(2, "0:exit", { greedExit = true }) }
        obs.actor.coins = 27
        plan:observe(obs)
        assert(plan:choose(obs, "run", "balanced").door.to == "0:shop")
        obs.actor.keys, obs.actor.needsHeal = 1, true
        assert(plan:choose(obs, "run", "balanced").door.to == "0:shop")
        obs.actor.needsHeal = false
        assert(plan:choose(obs, "run", "balanced").door.to == "0:exit")
        obs.actor.keys, obs.room, obs.shop, obs.doors, obs.shopOffers =
            0, "0:shop", true, { door(0, "0:1") }, {}
        plan:observe(obs)
        obs.room, obs.shop, obs.doors =
            "0:1",
            false,
            { door(0, "0:shop", { shop = true }), door(2, "0:exit", { greedExit = true }) }
        plan:observe(obs)
        assert(plan:choose(obs, "run", "balanced").door.to == "0:exit")
    end
)
test("client observation ages, goes neutral when stale, then recovers", function()
    localInfo.nowMs = 100
    assert(observe.read(1, localInfo).age == 0.1)
    localInfo.nowMs = 300
    local obs, reason = observe.read(2, localInfo)
    assert(not obs and reason == "stale_view")
    localInfo.tick = 2
    assert(observe.read(3, localInfo).age == 0)
    localInfo.nowMs = 0
end)
test("accepted actor pose ignores prediction, expires and follows cache clearing", function()
    local pose = dofile(root .. "/src/bridge/sync/actor_pose.lua")
    local motion = {}
    local player = {
        ControllerIndex = 2,
        Position = Vector(198, 277),
    }
    motion[42] = {
        actor = true,
        controller = 2,
        at = 1,
        target = Vector(244, 277),
        velocity = Vector(-1, 0),
        display = player.Position,
    }
    local value = assert(pose(motion, 42, player.ControllerIndex, 1.1))
    assert(value.x == 244 and value.vx == -60 and player.Position.X == 198)
    value.x = 0
    assert(pose(motion, 42, player.ControllerIndex, 1.1).x == 244, "Borrowed pose was mutated")
    assert(not pose(motion, 42, player.ControllerIndex, 1.3), "Expired pose used for input")
    player.ControllerIndex = 1
    assert(not pose(motion, 42, player.ControllerIndex, 1.1), "Replacement actor inherited pose")
    assert(not pose({}, 42, player.ControllerIndex, 1.1), "Cleared room cache retained pose")
end)
test(
    "client observation uses accepted positions when prediction is already outside chest",
    function()
        local old = roster[2].Position
        roster[2].Position = Vector(198, 277)
        local reader = modules["lanbot/observe"](
            native,
            bridge,
            nav,
            modules["lanbot/terrain"],
            modules["lanbot/items"],
            function(p)
                if p == roster[2] then
                    return { x = 244, y = 277, vx = 0, vy = 0 }
                end
                return { x = p.Position.X, y = p.Position.Y, vx = 0, vy = 0 }
            end
        )
        local obs = assert(reader.read(1, localInfo))
        assert(obs.actor.x == 244 and roster[2].Position.X == 198)
        local waiting = modules["lanbot/observe"](
            native,
            bridge,
            nav,
            modules["lanbot/terrain"],
            modules["lanbot/items"],
            function()
                return nil
            end
        )
        local missing, reason = waiting.read(1, localInfo)
        assert(not missing and reason == "view_not_ready")
        roster[2].Position = old
    end
)
local function fakeEntity(kind, flags)
    local e = {
        InitSeed = 10 + kind,
        Type = kind,
        Variant = 0,
        Position = Vector(300, 160),
        Velocity = Vector(0, 0),
        Size = 10,
        HitPoints = 10,
        SpawnerType = 0,
    }
    e.Exists = function()
        return true
    end
    e.IsDead = function()
        return false
    end
    e.GetEntityFlags = function()
        return flags or 0
    end
    e.ToNPC = function()
        return kind == 20 and e or nil
    end
    e.IsActiveEnemy = function()
        return true
    end
    e.IsInvincible = function()
        return false
    end
    e.IsVulnerableEnemy = function()
        return false
    end
    e.IsBoss = function()
        return false
    end
    e.ToPickup = function()
        return kind == 5 and e or nil
    end
    e.ToLaser = function()
        return nil
    end
    e.ToBomb = function()
        return nil
    end
    return e
end
test("client replicas remain targets; friendly OR charmed entities excluded", function()
    entities = {
        fakeEntity(20, 0),
        fakeEntity(20, EntityFlag.FLAG_FRIENDLY),
        fakeEntity(20, EntityFlag.FLAG_CHARM),
    }
    local obs = observe.read(1, localInfo)
    assert(#obs.enemies == 1 and obs.enemies[1].attackable)
    localInfo.authority = 1
    assert(not observe.read(2, localInfo).enemies[1].attackable)
    localInfo.authority = 0
    entities = { fakeEntity(20, EntityFlag.FLAG_NO_TARGET) }
    obs = observe.read(3, localInfo)
    assert(#obs.enemies == 1 and not obs.enemies[1].attackable and #obs.dangers == 1)
end)
test("free useful soul heart picked with full red health; paid pickup excluded", function()
    local heart, paid = fakeEntity(5), fakeEntity(5)
    heart.Variant, heart.SubType, heart.Price, heart.Wait = 10, 3, 0, 0
    paid.Variant, paid.SubType, paid.Price, paid.Wait = 100, 1, 15, 0
    entities = { heart, paid }
    local obs = observe.read(1, localInfo)
    assert(#obs.pickups == 1 and obs.pickups[1].heal)
    entities = {}
end)
test(
    "Greed shopping requires funds and need; poor-value items and heart deals stay excluded",
    function()
        local player = roster[2]
        local coins, keys, heal, kind =
            player.GetNumCoins, player.GetNumKeys, player.CanPickRedHearts, room.GetType
        local wallet, keyCount, hurt = 4, 0, false
        player.GetNumCoins = function()
            return wallet
        end
        player.GetNumKeys = function()
            return keyCount
        end
        player.CanPickRedHearts = function()
            return hurt
        end
        room.GetType = function()
            return RoomType.ROOM_SHOP
        end
        local key, heart, item, deal = fakeEntity(5), fakeEntity(5), fakeEntity(5), fakeEntity(5)
        key.Variant, key.Price, key.Wait = PickupVariant.PICKUP_KEY, 5, 0
        heart.Variant, heart.SubType, heart.Price, heart.Wait =
            PickupVariant.PICKUP_HEART, HeartSubType.HEART_SOUL, 3, 0
        item.Variant, item.SubType, item.Price, item.Wait =
            PickupVariant.PICKUP_COLLECTIBLE, 1, 15, 0
        deal.Variant, deal.SubType, deal.Price, deal.Wait =
            PickupVariant.PICKUP_COLLECTIBLE, 1, -1, 0
        entities, greed = { key, heart, item, deal }, true
        local obs = assert(observe.read(1, localInfo))
        assert(#obs.pickups == 0 and #obs.shopOffers == 3)
        wallet = 27
        obs = assert(observe.read(2, localInfo))
        assert(#obs.pickups == 1 and obs.pickups[1].key and obs.pickups[1].price == 5)
        keyCount, hurt = 1, true
        obs = assert(observe.read(3, localInfo))
        assert(#obs.pickups == 1 and obs.pickups[1].heal and obs.pickups[1].price == 3)
        hurt = false
        assert(#observe.read(4, localInfo).pickups == 0)
        greed = false
        assert(#observe.read(5, localInfo).pickups == 0)
        entities = {}
        player.GetNumCoins, player.GetNumKeys, player.CanPickRedHearts, room.GetType =
            coins, keys, heal, kind
    end
)
test(
    "only the selected purchase can be crossed and the permission expires with its goal",
    function()
        local bot, source, obs = fixture()
        local key = { id = "shop:key", x = 280, y = 160, price = 5, paid = true }
        obs.pickups = { key }
        obs.map.zones = {
            { id = key.id, x = key.x, y = key.y, radius = 30, purchase = true },
            { id = "shop:collectible", x = 320, y = 280, radius = 30, purchase = true },
        }
        bot.command("on")
        bot.step(1)
        bot.step(2)
        assert(bot.task == "pickup" and source.mask & 15 ~= 0 and obs.map.allowedPickup == key.id)
        assert(nav.line(obs.map, obs.actor, key, obs.actor.radius))
        assert(not nav.passable(obs.map, 320, 280, obs.actor.radius))
        obs.pickups = {}
        bot.step(3)
        assert(
            not obs.map.allowedPickup and not nav.passable(obs.map, key.x, key.y, obs.actor.radius)
        )
    end
)
test(
    "free active items never cause repeated swaps when a primary active is already equipped",
    function()
        local config, active = Isaac.GetItemConfig, roster[2].GetActiveItem
        local equipped = 105
        Isaac.GetItemConfig = function()
            return {
                GetCollectible = function()
                    return { Type = ItemType.ITEM_ACTIVE }
                end,
            }
        end
        roster[2].GetActiveItem = function()
            return equipped
        end
        local item = fakeEntity(5)
        item.Variant, item.SubType, item.Price, item.Wait =
            PickupVariant.PICKUP_COLLECTIBLE, 706, 0, 0
        entities = { item }
        local obs = assert(observe.read(1, localInfo))
        assert(#obs.pickups == 0 and #obs.map.zones == 1 and obs.map.zones[1].purchase)
        assert(not nav.passable(obs.map, item.Position.X, item.Position.Y, obs.actor.radius))
        equipped = 0
        obs = assert(observe.read(2, localInfo))
        assert(#obs.pickups == 1 and #obs.map.zones == 0)
        equipped = 706
        item.SubType = 105
        assert(#observe.read(3, localInfo).pickups == 0)
        entities = {}
        Isaac.GetItemConfig, roster[2].GetActiveItem = config, active
    end
)
test("observer protects exits and unselected doorways from ordinary movement", function()
    local getGrid, getDoor = room.GetGridEntity, room.GetDoor
    room.GetGridEntity = function(_, index)
        if index == 52 then
            return {
                GetType = function()
                    return GridEntityType.GRID_TRAPDOOR
                end,
                State = 1,
            }
        end
    end
    room.GetDoor = function(_, slot)
        if slot == 2 then
            return {
                Position = Vector(440, 160),
                TargetRoomType = 1,
                TargetRoomIndex = 3,
                IsOpen = function()
                    return true
                end,
                IsLocked = function()
                    return false
                end,
            }
        end
    end
    local obs = observe.read(1, localInfo)
    assert(obs.exit.cell == 53 and not obs.map.walk[53] and not obs.map.walk[60])
    assert(not nav.passable(obs.map, 440, 160, 10))
    assert(nav.passable(obs.map, 440, 160, 10, obs.doors[1]))
    room.GetGridEntity, room.GetDoor = getGrid, getDoor
end)
test("closed Boss exit retreats, waits for native opening and then contacts it", function()
    local getGrid, player = room.GetGridEntity, roster[2]
    local oldPosition, oldVelocity = player.Position, player.Velocity
    local trapdoor = {
        State = 0,
        GetType = function()
            return GridEntityType.GRID_TRAPDOOR
        end,
    }
    room.GetGridEntity = function(_, index)
        return index == 52 and trapdoor or nil
    end
    player.Position, player.Velocity = Vector(160, 160), Vector(0, 0)
    local bot, source, _, _, env = fixture()
    local observed, opened, contacted, retreat, awaySince = nil, false, false, 0, nil
    env.observe = function(frame)
        observed = assert(observe.read(frame, localInfo))
        return observed
    end
    bot.command("mode hold")
    bot.command("on")
    for frame = 1, 360 do
        bot.step(frame)
        assert(bot.state == "running", bot.reason)
        if not opened then
            assert(
                not observed.exit and bot.task ~= "move_to_exit",
                "Closed trapdoor became a route"
            )
        end
        local dx = ((source.mask & 2) ~= 0 and 1 or 0) - ((source.mask & 1) ~= 0 and 1 or 0)
        local dy = ((source.mask & 8) ~= 0 and 1 or 0) - ((source.mask & 4) ~= 0 and 1 or 0)
        if dx ~= 0 and dy ~= 0 then
            dx, dy = dx * 0.7071, dy * 0.7071
        end
        local velocity = player.Velocity
        velocity.X, velocity.Y =
            velocity.X * 0.775 + dx * (260 / 30) * 0.225,
            velocity.Y * 0.775 + dy * (260 / 30) * 0.225
        player.Position.X = player.Position.X + velocity.X
        player.Position.Y = player.Position.Y + velocity.Y
        local distance = nav.distance(
            { x = player.Position.X, y = player.Position.Y },
            { x = 160, y = 160 }
        )
        retreat = math.max(retreat, distance)
        -- Independent native model; production can only observe this state.
        if not opened and distance > 50 then
            awaySince = awaySince or frame
            if frame - awaySince >= 30 then
                opened, trapdoor.State = true, 1
                bot.command("mode run")
            end
        elseif opened and distance < 20 then
            contacted = true
            break
        end
    end
    assert(
        opened and contacted and retreat > 50,
        "Closed exit did not open/contact: opened="
            .. tostring(opened)
            .. " contacted="
            .. tostring(contacted)
            .. " retreat="
            .. retreat
            .. " task="
            .. bot.task
            .. " reason="
            .. tostring(bot.reason)
            .. " mask="
            .. source.mask
    )
    bot.command("off")
    room.GetGridEntity, player.Position, player.Velocity = getGrid, oldPosition, oldVelocity
end)
test("both actors leave a chest so native collision delay can expire before re-entry", function()
    for _, boundary in ipairs({ 0, 81 }) do
        local bots, sources, observations = {}, {}, {}
        local bodies =
            { { x = 200, y = 160, vx = 0, vy = 0 }, { x = 225, y = 190, vx = 0, vy = 0 } }
        if boundary > 0 then
            bodies = {
                { x = 200 + boundary, y = 160, vx = 0, vy = 0 },
                { x = 200, y = 160 + boundary, vx = 0, vy = 0 },
            }
        end
        local delay, opened, away, sawContact = 10, false, false, false
        for slot = 1, 2 do
            local bot, source, obs = fixture()
            bots[slot], sources[slot], observations[slot] = bot, source, obs
            obs.actor = bodies[slot]
            for key, value in pairs(snapshot().actor) do
                if obs.actor[key] == nil then
                    obs.actor[key] = value
                end
            end
            obs.exit = {
                id = "native-chest",
                x = 200,
                y = 160,
                radius = 24,
                contactRadius = 60,
                contactWait = true,
                exit = true,
            }
            obs.map.zones = { obs.exit }
            bot.command("on")
        end
        for frame = 1, 360 do
            -- Independent native collision/update model: Lua Wait remains zero,
            -- but overlap while DropDelay is positive refreshes it to ten updates.
            local blocked, overlap = false, false
            for _, body in ipairs(bodies) do
                local distance = nav.distance(body, { x = 200, y = 160 })
                blocked = blocked or distance < 82
                overlap = overlap or distance < 55
            end
            if overlap then
                sawContact = true
                if delay > 0 then
                    delay = 10
                else
                    opened = true
                end
            else
                delay = math.max(0, delay - 1)
                away = true
            end
            if opened then
                break
            end
            for slot, bot in ipairs(bots) do
                local obs = observations[slot]
                obs.frame, obs.simulationTick = frame, frame
                obs.exit.contactBlocked = blocked
                bot.step(frame)
                assert(bot.state == "running", bot.reason)
                if frame == 1 then
                    local status = bot.command("next")
                    assert(not status:find("error=", 1, true), status)
                end
            end
            for slot, body in ipairs(bodies) do
                local buttons = sources[slot].mask
                local dx = ((buttons & 2) ~= 0 and 1 or 0) - ((buttons & 1) ~= 0 and 1 or 0)
                local dy = ((buttons & 8) ~= 0 and 1 or 0) - ((buttons & 4) ~= 0 and 1 or 0)
                if dx ~= 0 and dy ~= 0 then
                    dx, dy = dx * 0.7071, dy * 0.7071
                end
                body.vx, body.vy =
                    body.vx * 0.775 + dx * 260 * 0.225, body.vy * 0.775 + dy * 260 * 0.225
                body.x, body.y = body.x + body.vx / 30, body.y + body.vy / 30
            end
        end
        assert(
            sawContact and away and opened and delay == 0,
            "Chest overlap kept native drop delay alive"
        )
        for _, bot in ipairs(bots) do
            bot.command("off")
        end
    end
end)
test("only a selected exit task authorizes its contact zone", function()
    local bot, _, _, _, env = fixture()
    local observed
    env.observe = function(frame)
        observed = snapshot()
        observed.frame = frame
        observed.exit = { id = "exit:57", x = 320, y = 160, cell = 57, radius = 24, exit = true }
        observed.map.zones, observed.map.exitCells = { observed.exit }, { [57] = true }
        observed.map.walk[57] = false
        return observed
    end
    bot.command("mode explore")
    bot.command("on")
    bot.step(1)
    bot.step(2)
    assert(not observed.map.walk[57])
    bot.command("mode run")
    bot.step(3)
    assert(not observed.map.walk[57] and bot.task == "move_to_exit")
    assert(observed.map.allowedExit == "exit:57" and nav.passable(observed.map, 320, 160, 10))
end)
test("touch a big chest from the side without entering its overlapping Void portal", function()
    local bot, source, obs = fixture()
    local chest = {
        id = "chest",
        kind = "bigchest",
        x = 200,
        y = 160,
        radius = 24,
        contactRadius = 60,
        contactWait = true,
        exit = true,
    }
    local portal = { id = "void", x = 200, y = 160, radius = 24, exit = true }
    obs.exit, obs.map.zones = chest, { portal, chest }
    obs.actor.x, obs.actor.y = 300, 240
    local opened, entered, delay = false, false, 10
    bot.command("on")
    for frame = 1, 360 do
        local body = obs.actor
        -- Native chest collision is a wide ellipse, while the portal activates
        -- near its center. This world model independently performs contact.
        local overlap = ((body.x - 200) / 55) ^ 2 + ((body.y - 160) / 30) ^ 2 < 1
        entered = entered or nav.distance(body, portal) < 22
        if overlap then
            if delay > 0 then
                delay = 10
            else
                opened = true
            end
        else
            delay = math.max(0, delay - 1)
        end
        if opened or entered then
            break
        end
        obs.frame, obs.simulationTick = frame, frame
        chest.contactBlocked = nav.distance(body, chest) < 82
        bot.step(frame)
        assert(bot.state == "running", bot.reason)
        if bot.task == "move_to_exit" then
            assert(obs.map.allowedExit == "chest")
            assert(not nav.passable(obs.map, portal.x, portal.y, body.radius))
        end
        local buttons = source.mask
        local dx = ((buttons & 2) ~= 0 and 1 or 0) - ((buttons & 1) ~= 0 and 1 or 0)
        local dy = ((buttons & 8) ~= 0 and 1 or 0) - ((buttons & 4) ~= 0 and 1 or 0)
        if dx ~= 0 and dy ~= 0 then
            dx, dy = dx * 0.7071, dy * 0.7071
        end
        body.vx, body.vy = body.vx * 0.775 + dx * 260 * 0.225, body.vy * 0.775 + dy * 260 * 0.225
        body.x, body.y = body.x + body.vx / 30, body.y + body.vy / 30
    end
    assert(opened and not entered, "BOT failed native chest contact or entered the Void")
end)
test("replica retreats its actual body when prediction already left the chest", function()
    local oldLocal, oldRemote = roster[2].Position, roster[0].Position
    local chest = fakeEntity(5)
    chest.Position, chest.Variant, chest.Wait, chest.State =
        Vector(320, 160), PickupVariant.PICKUP_BIGCHEST, 0, 0
    entities = { chest }
    local actual, velocity = 244, 0
    roster[2].Position, roster[0].Position = Vector(199, 160), Vector(430, 160)
    local reader = modules["lanbot/observe"](
        native,
        bridge,
        nav,
        modules["lanbot/terrain"],
        modules["lanbot/items"],
        function(p)
            return {
                x = p == roster[2] and actual or 430,
                y = 160,
                vx = p == roster[2] and velocity or 0,
                vy = 0,
            }
        end
    )
    local bot, source, _, _, env = fixture()
    env.info, env.observe = function()
        return localInfo
    end, reader.read
    bot.command("on")
    local left
    for frame = 1, 12 do
        localInfo.tick = frame
        roster[2].Position = Vector(actual - 45, 160)
        bot.step(frame)
        if frame == 2 then
            assert(
                (source.mask & 1) ~= 0,
                "Predicted clearance stopped actual retreat: "
                    .. bot.status()
                    .. " mask="
                    .. source.mask
            )
        end
        velocity = velocity * 0.775 + ((source.mask & 1) ~= 0 and -260 or 0) * 0.225
        actual = actual + velocity / 30
        left = left or actual < 238
    end
    assert(left, "Actual body never left the contact boundary")
    bot.command("off")
    roster[2].Position, roster[0].Position, entities = oldLocal, oldRemote, {}
end)
test("observer selects the big chest before an optional Void trapdoor", function()
    local oldGrid = room.GetGridEntity
    local chest = fakeEntity(5)
    chest.Position, chest.Variant, chest.Wait, chest.State =
        Vector(160, 160), PickupVariant.PICKUP_BIGCHEST, 0, 0
    room.GetGridEntity = function(_, index)
        if index == 52 then
            return {
                State = 1,
                GetType = function()
                    return GridEntityType.GRID_TRAPDOOR
                end,
            }
        end
    end
    entities = { chest }
    local obs = observe.read(1, localInfo)
    assert(#obs.exits == 2 and obs.exit.kind == "bigchest")
    obs.map.allowedExit = obs.exit.id
    assert(not nav.passable(obs.map, 160, 160, 10), "Void protection was removed")
    entities, room.GetGridEntity = {}, oldGrid
end)
test("adapter observes ordinary unpressed buttons without treating rewards as puzzles", function()
    local getGrid, isClear = room.GetGridEntity, room.IsClear
    local plate = {
        State = 0,
        GetType = function()
            return GridEntityType.GRID_PRESSURE_PLATE
        end,
        GetVariant = function()
            return 0
        end,
    }
    room.GetGridEntity = function(_, index)
        return index == 52 and plate or nil
    end
    room.IsClear = function()
        return false
    end
    local obs = observe.read(1, localInfo)
    assert(not obs.clear and #obs.buttons == 1)
    plate.State = 1
    assert(#observe.read(2, localInfo).buttons == 1)
    plate.State = 3
    assert(#observe.read(3, localInfo).buttons == 0)
    plate.State, plate.GetVariant = 0, function()
        return 1
    end
    assert(#observe.read(4, localInfo).buttons == 0)
    room.GetGridEntity, room.IsClear = getGrid, isClear
end)
test("adapter guards multiple trapdoors and stairs even before clear", function()
    local getGrid, isClear = room.GetGridEntity, room.IsClear
    room.GetGridEntity = function(_, index)
        if index == 52 or index == 56 or index == 80 then
            return {
                GetType = function()
                    return index == 80 and GridEntityType.GRID_STAIRS
                        or GridEntityType.GRID_TRAPDOOR
                end,
                State = 1,
            }
        end
    end
    local obs = observe.read(1, localInfo)
    assert(#obs.exits == 2 and #obs.map.zones == 3)
    obs.map.allowedExit = obs.exit.id
    assert(nav.passable(obs.map, obs.exit.x, obs.exit.y, 10))
    assert(not nav.passable(obs.map, 320, 160, 10))
    room.IsClear = function()
        return false
    end
    obs = observe.read(2, localInfo)
    assert(not obs.exit and #obs.map.zones == 3)
    room.GetGridEntity, room.IsClear = getGrid, isClear
end)
test("adapter avoids hostile creep and respects flight and friendly ownership", function()
    local creep = fakeEntity(EntityType.ENTITY_EFFECT)
    creep.Variant = EffectVariant.CREEP_RED
    entities = { creep }
    local obs = observe.read(1, localInfo)
    assert(#obs.dangers == 1 and not nav.passable(obs.map, 300, 160, 10))
    roster[2].CanFly = true
    assert(#observe.read(2, localInfo).dangers == 0)
    roster[2].CanFly = false
    creep.SpawnerType = EntityType.ENTITY_PLAYER
    assert(#observe.read(3, localInfo).dangers == 0)
    entities = {}
end)
test("cleared retracted spikes pass; unknown and active spikes still block", function()
    local getGrid, isClear = room.GetGridEntity, room.IsClear
    local spike = { State = 1, Timeout = -1 }
    spike.GetType = function()
        return GridEntityType.GRID_SPIKES_ONOFF
    end
    spike.ToSpikes = function()
        return spike
    end
    room.GetGridEntity = function(_, index)
        return index == 52 and spike or nil
    end
    local obs = observe.read(1, localInfo)
    assert(nav.passable(obs.map, 160, 160, 10))
    room.IsClear = function()
        return false
    end
    assert(not nav.passable(observe.read(2, localInfo).map, 160, 160, 10))
    room.IsClear = isClear
    spike.State = 0
    assert(not nav.passable(observe.read(3, localInfo).map, 160, 160, 10))
    room.GetGridEntity = getGrid
end)
test(
    "entity exits are protected before clear, during pickup wait and regardless of ownership",
    function()
        local isClear = room.IsClear
        local chest = fakeEntity(5)
        chest.Variant, chest.Wait = PickupVariant.PICKUP_BIGCHEST, 10
        entities = { chest }
        room.IsClear = function()
            return false
        end
        local obs = observe.read(1, localInfo)
        assert(not obs.exit and not nav.passable(obs.map, 300, 160, 10))
        room.IsClear = isClear
        assert(not observe.read(2, localInfo).exit)
        chest.Wait, chest.State = 0, 0
        obs = observe.read(3, localInfo)
        assert(obs.exit and obs.exit.contactWait and not nav.passable(obs.map, 300, 160, 10))
        local previous = roster[0].Position
        roster[0].Position = Vector(300, 160)
        obs = observe.read(4, localInfo)
        assert(obs.exit.contactBlocked, "A remote actor near the chest was omitted")
        roster[0].Position = previous
        local light = fakeEntity(EntityType.ENTITY_EFFECT, EntityFlag.FLAG_FRIENDLY)
        light.Variant = EffectVariant.HEAVEN_LIGHT_DOOR
        entities = { light }
        obs = observe.read(4, localInfo)
        assert(obs.exit and not nav.passable(obs.map, 300, 160, 10))
        entities = {}
    end
)
test("embedded console entry dispatches lanbot and returns nil", function()
    modules["runtime/challenges"] = dofile(root .. "/src/bridge/runtime/challenges.lua")
    modules["compat/routes/challenge_goal"] =
        dofile(root .. "/src/bridge/compat/routes/challenge_goal.lua")
    native.net_phases = function()
        return dofile(root .. "/tests/fixtures/net_phases.lua")
    end

    native.net_commands = function()
        return dofile(root .. "/tests/fixtures/net_commands.lua")
    end
    native.net_challenges = function()
        return {}
    end
    modules["runtime/session"] = dofile(root .. "/src/bridge/runtime/session.lua")
    modules["runtime/party"] = dofile(root .. "/src/bridge/runtime/party.lua")
    native.input_ready = function()
        return true
    end
    native.net_fail = function(reason)
        error(reason)
    end
    modules["compat/characters/keeper"] = dofile(root .. "/src/bridge/compat/characters/keeper.lua")
    _IsaacLanState = { actorPose = function() end }
    local source = { active = false, mask = 0 }
    native.api_info = function()
        return localInfo
    end
    native.input_bot = function(active, mask)
        source.active, source.mask = active == 1, mask
        return true
    end
    bridge.reset = function() end
    modules["api/public"], modules["compat/mods/registry"] = bridge, {}
    modules["compat/mods/observation"] = dofile(root .. "/src/bridge/compat/mods/observation.lua")
    _IsaacLan, _IsaacLanModules = native, modules
    RegisterMod = function()
        return {}
    end
    ModCallbacks = {
        MC_EXECUTE_CMD = 1,
        MC_POST_GAME_STARTED = 2,
        MC_POST_UPDATE = 3,
        MC_PRE_GAME_EXIT = 4,
        MC_PRE_PICKUP_COLLISION = 5,
        MC_POST_PICKUP_INIT = 6,
        MC_POST_PICKUP_UPDATE = 7,
        MC_POST_NEW_LEVEL = 8,
        MC_PRE_SPAWN_CLEAN_AWARD = 9,
    }
    dofile(root .. "/tests/fixtures/app_bridge.lua")(root, _IsaacLan, _IsaacLanModules)
    dofile(root .. "/src/bridge/app/main.lua")
    assert(callbacks[1](nil, "another_command", "on") == nil and #output == 0)
    assert(callbacks[1](nil, "lanbot", "on") == nil and output[1]:find("running"))
    _IsaacLanBotFrame(1)
    assert(source.active)
    callbacks[1](nil, "lanbot", "pause")
    assert(not source.active and source.mask == 0)
    callbacks[1](nil, "lanbot", "resume")
    _IsaacLanBotFrame(2)
    assert(source.active)
    assert(_IsaacLanBotCommand("off") == nil and output[#output]:find("LANBOT off"))
    assert(not source.active)
    _IsaacLanBotCommand("on")
    _IsaacLanBotFrame(3)
    assert(source.active and output[#output]:find("running"))
    callbacks[4]()
    assert(not source.active)
end)
test("resting contact enemies retain pressure outside the collision radius", function()
    local obs = snapshot()
    local hazards = modules["lanbot/hazards"](nav)
    obs.controlDelay = 0.18
    obs.dangers = { { x = 280, y = 160, vx = 0, vy = 0, radius = 10 } }
    assert(hazards.risk(obs, obs.actor, obs.actor, 0, 0.1, combat.styles.balanced) == 0)
    obs.dangers[1].contact, obs.dangers[1].chaseSpeed = true, 300
    assert(hazards.risk(obs, obs.actor, obs.actor, 0, 0.1, combat.styles.balanced) > 0)
end)
test("crowd clears the arrival doorway before starting an orbit", function()
    local bot, source, obs = fixture()
    obs.actor.x, obs.actor.y, obs.clear = 430, 160, false
    obs.doors = { door(2, "0:2") }
    for i = 1, 3 do
        obs.enemies[i] = {
            id = "enemy:" .. i,
            x = 200,
            y = 160,
            vx = 0,
            vy = 0,
            radius = 10,
            contact = true,
            attackable = true,
        }
    end
    obs.dangers = obs.enemies
    bot.command("mode hold")
    bot.command("on")
    bot.step(1)
    bot.step(2)
    assert(bot.task == "leave_door" and not bot.kite and (source.mask & 1) ~= 0)
    obs.actor.x = 320
    bot.step(3)
    assert(bot.task == "kite" and bot.kite)
end)
test("crowd orbit keeps direction and advances before delayed arrival", function()
    local obs, memory = snapshot(), {}
    obs.actor.x, obs.actor.y, obs.controlDelay = 80, 180, 0.18
    for i = 1, 9 do
        obs.dangers[i] = { x = 240, y = 180, radius = 10, contact = true, chaseSpeed = 200 }
    end
    local goal = assert(combat.kite(obs, "balanced", memory))
    assert(goal.task == "kite" and nav.line(obs.map, obs.actor, goal, obs.actor.radius))
    local sign, index = memory.kite.sign, memory.kite.index
    -- Reordering moving enemies cannot reverse the established route.
    obs.dangers[1].x, obs.dangers[2].y = 270, 150
    assert(combat.kite(obs, "balanced", memory).id == goal.id)
    assert(memory.kite.sign == sign)
    obs.actor.x, obs.actor.y = goal.x, goal.y
    assert(combat.kite(obs, "balanced", memory).id ~= goal.id)
    assert(memory.kite.index ~= index and memory.kite.sign == sign)
end)
test("crowd route drops blocked segments and disappears with contact enemies", function()
    local obs, memory = snapshot(), {}
    obs.actor.x, obs.actor.y = 80, 180
    for i = 1, 3 do
        obs.dangers[i] = { x = 240, y = 180, radius = 10, contact = true }
    end
    local goal = assert(combat.kite(obs, "balanced", memory))
    obs.map.zones = { { id = "protected", x = goal.x, y = goal.y, radius = 30, exit = true } }
    assert(not combat.kite(obs, "balanced", memory) and not memory.kite)
    obs.map.zones, obs.dangers = {}, {}
    assert(not combat.kite(obs, "balanced", memory) and not memory.kite)
end)
test("crowd routing respects planner cooldowns", function()
    local obs, memory = snapshot(), {}
    obs.actor.x, obs.actor.y = 80, 180
    for i = 1, 3 do
        obs.dangers[i] = { x = 240, y = 180, radius = 10, contact = true }
    end
    local goal = assert(combat.kite(obs, "balanced", memory))
    local function available(id)
        return id ~= goal.id
    end
    assert(not combat.kite(obs, "balanced", memory, available) and not memory.kite)
    assert(combat.kite(obs, "balanced", memory, available).id ~= goal.id)
end)
test("latency forecast replays controls rather than extending the latest key", function()
    local obs, first = snapshot(), nil
    local measured = modules["lanbot/combat"](nav, {
        risk = function(_, from)
            first = first or from.x
            return 0
        end,
    })
    obs.now, obs.controlDelay = 1, 0.18
    obs.inputHistory = { { at = 0.8, buttons = 1 }, { at = 0.95, buttons = 2 } }
    measured.move(obs, nil, "balanced", 2)
    assert(first < obs.actor.x, "Pending left input was replaced by the latest right key")
    first, obs.inputHistory = nil, nil
    measured.move(obs, nil, "balanced", 2)
    assert(first > obs.actor.x)
end)
test("input history remains bounded at high FPS and clears at boundaries", function()
    local bot, _, obs, info = fixture()
    bot.command("mode hold")
    bot.command("on")
    for frame = 1, 1000 do
        info.nowMs = frame * 1.25
        bot.step(frame)
    end
    assert(#bot.inputs <= 32 and bot.inputs[1].at <= info.nowMs / 1000 - 0.25)
    bot.kite = { index = 1, sign = 1 }
    obs.room = "next"
    bot.step(1001)
    assert(#bot.inputs == 0 and not bot.kite)
    bot.command("off")
    assert(#bot.inputs == 0)
end)
test("observer preserves contact mobility through stops and resets on room change", function()
    local npc = fakeEntity(20)
    npc.CollisionDamage, npc.EntityCollisionClass, npc.Velocity = 1, 0, Vector(10, 0)
    entities = { npc }
    local watched = modules["lanbot/observe"](
        native,
        bridge,
        nav,
        modules["lanbot/terrain"],
        modules["lanbot/items"],
        nil,
        function()
            return { ping1 = 150 }
        end
    )
    local obs = assert(watched.read(1, localInfo))
    assert(obs.dangers[1].contact and obs.dangers[1].chaseSpeed == 300)
    assert(math.abs(obs.controlDelay - (0.15 + 1 / 30)) < 0.001)
    npc.Velocity = Vector(0, 0)
    assert(watched.read(2, localInfo).dangers[1].chaseSpeed == 300)
    positions["1"].index = 3
    assert(watched.read(3, localInfo).dangers[1].chaseSpeed < 300)
    npc.CollisionDamage = 0
    local harmless = assert(watched.read(4, localInfo))
    assert(not harmless.enemies[1].contact and #harmless.dangers == 0)
    positions["1"].index, entities = 2, {}
end)
test("large-room aliases share one exploration node and one party room", function()
    local getDoor, first, second = room.GetDoor, positions["0"].index, positions["1"].index
    aliases[71], aliases[85] = 70, 84
    room.GetDoor = function(_, slot)
        if slot == 1 then
            return {
                Position = Vector(240, 0),
                TargetRoomIndex = 71,
                TargetRoomType = RoomType.ROOM_SHOP,
                IsOpen = function()
                    return true
                end,
                IsLocked = function()
                    return false
                end,
            }
        end
    end
    positions["0"].index, positions["1"].index = 84, 85
    local obs = assert(observe.read(20, localInfo))
    assert(obs.room == "0:84" and obs.partyReady and obs.doors[1].to == "0:70")
    local plan = planner.new()
    plan:observe(obs)
    positions["1"].index = 70
    plan:observe(assert(observe.read(21, localInfo)))
    positions["1"].index = 85
    obs = assert(observe.read(22, localInfo))
    plan:observe(obs)
    assert(
        not plan:choose(obs, "run", "balanced"),
        "An already visited shop was treated as unexplored"
    )
    room.GetDoor, positions["0"].index, positions["1"].index = getDoor, first, second
    aliases = {}
end)
test("Greed workflow supplies once, gathers at its exit and resets on the next floor", function()
    local plan, obs = planner.new(), snapshot()
    obs.greed = { stage = 1, wave = 5, bossWave = 10 }
    obs.actor.keys, obs.actor.coins, obs.actor.needsHeal = 0, 27, true
    obs.doors = { door(0, "0:shop", { shop = true }), door(2, "0:exit", { greedExit = true }) }
    plan:observe(obs)
    plan:choose(obs, "run", "balanced")
    assert(plan.flow.phase == "fight")
    obs.greed.wave = 10
    assert(plan:choose(obs, "run", "balanced").door.to == "0:shop" and plan.flow.phase == "supply")
    obs.room, obs.shop, obs.doors = "0:shop", true, { door(0, "0:1") }
    obs.pickups = { { id = "key", paid = true, key = true, price = 5, x = 240, y = 160 } }
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").id == "key")
    obs.actor.keys, obs.actor.needsHeal, obs.pickups = 1, false, {}
    plan:choose(obs, "run", "balanced")
    assert(plan.flow.phase == "gather")
    obs.room, obs.shop, obs.doors =
        "0:1",
        false,
        { door(0, "0:shop", { shop = true }), door(2, "0:exit", { greedExit = true }) }
    obs.actor.needsHeal = true -- Damage cannot undo the completed floor phase.
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").door.to == "0:exit")
    obs.room, obs.doors, obs.exit, obs.partyReady =
        "0:exit", {}, { id = "stairs", x = 280, y = 160 }, false
    plan:observe(obs)
    local goal, reason = plan:choose(obs, "run", "balanced")
    assert(not goal and reason == "wait_for_party" and plan.flow.phase == "gather")
    obs.partyReady = true
    assert(plan:choose(obs, "run", "balanced").exit and plan.flow.phase == "leave")
    obs.greed.stage, obs.greed.wave, obs.exit = 2, 0, nil
    plan:choose(obs, "run", "balanced")
    assert(plan.flow.phase == "fight" and not plan.flow.enteredShop)
end)
test("Greed supply has a bounded wait for an unreachable paid pickup", function()
    local flow, obs = modules["lanbot/greed"].new(), snapshot()
    obs.greed, obs.shop = { stage = 1, wave = 10, bossWave = 10 }, true
    obs.pickups = { { paid = true } }
    flow:update(obs, "run")
    assert(flow.phase == "supply")
    obs.frame = 1201
    flow:update(obs, "run")
    assert(flow.phase == "loot" and flow.reason == "supply_unreachable")
    flow:update(obs, "hold")
    assert(not flow.phase)
end)
test("a direct poop blocker is chosen immediately even when a detour exists", function()
    local bot, source, obs = fixture()
    obs.doors = { door(2, "0:2") }
    obs.map.walk[54] = false
    obs.breakables = {
        {
            id = "poop",
            x = 200,
            y = 160,
            cell = 54,
            radius = 20,
            breakable = true,
            attackable = true,
        },
    }
    assert(nav.path(obs.map, obs.actor, { x = 400, y = 160 }, obs.actor.radius))
    bot.command("on")
    bot.step(1)
    bot.step(2)
    assert(bot.task == "clear_obstacle" and source.mask & 240 ~= 0)
end)
test("fireplaces are avoided; only brown and red live flames can be shot clear", function()
    local fires = {}
    for variant = 0, 3 do
        local fire = fakeEntity(20)
        fire.Type, fire.Variant, fire.HitPoints = EntityType.ENTITY_FIREPLACE, variant, 10
        fire.IsActiveEnemy = function()
            return false
        end
        fire.Position = Vector(200 + variant * 40, 160)
        fires[#fires + 1] = fire
    end
    entities = fires
    local obs = assert(observe.read(30, localInfo))
    assert(#obs.enemies == 0 and #obs.breakables == 2 and #obs.map.zones == 4)
    assert(obs.breakables[1].attackable and obs.breakables[2].attackable)
    assert(not nav.passable(obs.map, 280, 160, 10))
    fires[1].HitPoints = 1 -- Native ash survives with positive HP and no target.
    obs = assert(observe.read(31, localInfo))
    assert(#obs.breakables == 1 and #obs.map.zones == 3)
    entities = {}
end)
test("a blocking fireplace is cleared with ordinary input without granting zone access", function()
    local bot, source, obs = fixture()
    obs.pickups = { { id = "heart", x = 320, y = 160, heal = true } }
    local fire = { id = "fire", x = 200, y = 160, radius = 18, clearable = true, attackable = true }
    obs.breakables, obs.map.zones = { fire }, { fire }
    bot.command("mode hold")
    bot.command("on")
    bot.step(1)
    bot.step(2)
    assert(bot.task == "clear_obstacle" and source.mask & 240 ~= 0)
    assert(not nav.passable(obs.map, fire.x, fire.y, 10))
    obs.breakables, obs.map.zones = {}, {}
    bot.step(3)
    assert(bot.task == "pickup")
end)
test("distant contact enemies do not monopolize combat with an orbit", function()
    local obs, memory = snapshot(), {}
    obs.actor.x, obs.actor.y, obs.actor.range = 80, 80, 100
    for i = 1, 3 do
        obs.dangers[i] = { x = 400, y = 300, radius = 10, contact = true }
    end
    assert(not combat.kite(obs, "balanced", memory))
end)
test("unproductive orbit seeks a firing lane and resumes after a real opportunity", function()
    local obs, memory = snapshot(), {}
    local enemy = { id = "a", x = 360, y = 260, radius = 10, attackable = true }
    assert(combat.engagement(obs, enemy, memory))
    obs.frame = 100
    assert(not combat.engagement(obs, enemy, memory) and memory.engagement.phase == "seek")
    enemy.y = 160
    assert(combat.engagement(obs, enemy, memory) and memory.engagement.phase == "orbit")
end)
test("homing tears fire off axis but retain range, walls and precise obstacle aim", function()
    local obs = snapshot()
    local enemy = { x = 320, y = 260, radius = 10, attackable = true }
    assert(combat.shoot(obs, enemy, {}) == 0)
    obs.actor.homing = true
    assert(combat.shoot(obs, enemy, {}) == 32)
    enemy.breakable = true
    assert(combat.shoot(obs, enemy, {}) == 0)
    enemy.breakable, enemy.x = nil, 600
    assert(combat.shoot(obs, enemy, {}) == 0)
    enemy.x, obs.shotLine = 320, function()
        return false
    end
    assert(combat.shoot(obs, enemy, {}) == 0)
end)
test("target selection favors an actual firing opportunity", function()
    local obs = snapshot()
    obs.enemies = {
        { id = "near", x = 230, y = 230, radius = 10, attackable = true },
        { id = "lane", x = 350, y = 160, radius = 10, attackable = true },
    }
    assert(combat.target(obs, "balanced").id == "lane")
end)
test("stationary distant crowd is approached and fired on through normal inputs", function()
    local bot, source, obs = fixture()
    obs.clear, obs.actor.range = false, 140
    for i = 1, 3 do
        obs.enemies[i] = {
            id = "stationary:" .. i,
            x = 380,
            y = 250 + i * 15,
            radius = 10,
            attackable = true,
            contact = true,
            health = 30,
        }
    end
    obs.dangers = obs.enemies
    bot.command("on")
    local fired = false
    for frame = 1, 600 do
        bot.step(frame)
        fired = fired or source.mask & 240 ~= 0
        local dx = ((source.mask & 2) ~= 0 and 1 or 0) - ((source.mask & 1) ~= 0 and 1 or 0)
        local dy = ((source.mask & 8) ~= 0 and 1 or 0) - ((source.mask & 4) ~= 0 and 1 or 0)
        local scale = dx ~= 0 and dy ~= 0 and 0.7071 or 1
        local p = obs.actor
        p.vx, p.vy = p.vx * 0.88 + dx * scale * 260 * 0.12, p.vy * 0.88 + dy * scale * 260 * 0.12
        local x, y = p.x + p.vx / 60, p.y + p.vy / 60
        if x > 30 and x < 420 and y > 30 and y < 350 then
            p.x, p.y = x, y
        end
        if fired then
            break
        end
    end
    assert(fired, "The bot moved indefinitely without approaching a firing lane")
end)
test("wall-mounted enemy bodies are shootable while a fully hidden enemy stays blocked", function()
    local original = room.CheckLine
    room.CheckLine = function(_, from, to)
        return to.X >= 80
    end
    local obs = assert(observe.read(200, localInfo))
    local target = { x = 65, y = 160, radius = 12, attackable = true }
    assert(obs.shotLine({ x = 200, y = 160 }, target), "The body protrudes in front of the wall")
    target.x = 20
    assert(not obs.shotLine({ x = 200, y = 160 }, target), "A hidden body must not bypass a wall")
    target.x, target.clearable = 65, true
    assert(
        not obs.shotLine({ x = 200, y = 160 }, target),
        "Fire/grid targets keep their own clearance"
    )
    room.CheckLine = original
end)
test("native bombs without a readable countdown stay dangerous without a decision error", function()
    local bomb = fakeEntity(4)
    bomb.ToNPC = function() end
    bomb.ToBomb = function()
        return { RadiusMultiplier = 1.5 }
    end
    entities = { bomb }
    local obs = assert(observe.read(201, localInfo))
    assert(#obs.dangers == 1 and obs.dangers[1].at == 0 and obs.dangers[1].radius == 127.5)
    entities = {}
end)
test("clear room and native ending ignore positive-health replica boss statues", function()
    local statue, chest = fakeEntity(20), fakeEntity(5)
    statue.HitPoints = 4025
    chest.Variant, chest.State, chest.Wait = PickupVariant.PICKUP_BIGCHEST, 1, 0
    entities = { statue, chest }
    local obs = assert(observe.read(202, localInfo))
    assert(obs.clear and obs.exit and not obs.enemies[1].attackable)
    assert(
        obs.dangers[1].contact and obs.dangers[1].chaseSpeed == 0,
        "Inert bodies retain contact avoidance without a fictitious charge"
    )
    local original = room.IsClear
    room.IsClear = function()
        return false
    end
    obs = assert(observe.read(203, localInfo))
    assert(not obs.exit and obs.enemies[1].attackable, "An unfinished fight must remain active")
    room.IsClear, entities = original, {}
end)
test("machines are obstacles even when replica entity collisions are disabled", function()
    local machine = fakeEntity(6)
    machine.EntityCollisionClass = 0
    entities = { machine }
    local obs = assert(observe.read(204, localInfo))
    assert(#obs.map.zones == 1 and obs.map.zones[1].id:find("machine:", 1, true))
    assert(not nav.passable(obs.map, machine.Position.X, machine.Position.Y, obs.actor.radius))
    entities = {}
end)
test("ending chest routes around a machine blocking the nearest contact side", function()
    local bot, source, obs = fixture()
    local chest = { id = "chest", kind = "bigchest", x = 200, y = 160, radius = 24, exit = true }
    local machine = { id = "machine", x = 240, y = 160, radius = 32 }
    obs.exit, obs.map.zones = chest, { chest, machine }
    obs.actor.x, obs.actor.y = 320, 160
    bot.command("on")
    local opened, contact = false, false
    for frame = 1, 600 do
        bot.step(frame)
        local p, buttons = obs.actor, source.mask
        local dx = ((buttons & 2) ~= 0 and 1 or 0) - ((buttons & 1) ~= 0 and 1 or 0)
        local dy = ((buttons & 8) ~= 0 and 1 or 0) - ((buttons & 4) ~= 0 and 1 or 0)
        local scale = dx ~= 0 and dy ~= 0 and 0.7071 or 1
        p.vx, p.vy = p.vx * 0.88 + dx * scale * 260 * 0.12, p.vy * 0.88 + dy * scale * 260 * 0.12
        local x, y = p.x + p.vx / 60, p.y + p.vy / 60
        if nav.distance({ x = x, y = y }, machine) < 28 + p.radius then
            contact = true
        else
            p.x, p.y = x, y
        end
        opened = ((p.x - 200) / 55) ^ 2 + ((p.y - 160) / 30) ^ 2 < 1
        if opened then
            break
        end
    end
    assert(opened and not contact, "BOT stalled against a machine before reaching the ending chest")
end)
test("zero-damage native statues do not prevent normal ending chest contact", function()
    local statue, chest = fakeEntity(20), fakeEntity(5)
    statue.HitPoints, statue.CollisionDamage, statue.Size = 4025, 0, 25
    statue.Position = Vector(292, 346.6)
    chest.Position, chest.Size = Vector(292, 386.6), 18
    chest.Variant, chest.State, chest.Wait = PickupVariant.PICKUP_BIGCHEST, 1, 0
    entities = { statue, chest }
    local observed = assert(observe.read(205, localInfo))
    assert(#observed.dangers == 0, "A zero-damage statue creates fictitious collision damage")
    local bot, source, obs = fixture()
    obs.enemies, obs.dangers, obs.exit = observed.enemies, observed.dangers, observed.exit
    obs.map.height, obs.map.zones = 20, { observed.exit }
    for i = 1, obs.map.width * obs.map.height do
        obs.map.walk[i] = true
    end
    obs.actor.x, obs.actor.y, obs.actor.radius = 367.2, 404.9, 12
    bot.command("on")
    local opened, bodyContact = false, false
    for frame = 1, 600 do
        bot.step(frame)
        local p, buttons = obs.actor, source.mask
        local dx = ((buttons & 2) ~= 0 and 1 or 0) - ((buttons & 1) ~= 0 and 1 or 0)
        local dy = ((buttons & 8) ~= 0 and 1 or 0) - ((buttons & 4) ~= 0 and 1 or 0)
        local scale = dx ~= 0 and dy ~= 0 and 0.7071 or 1
        p.vx, p.vy = p.vx * 0.88 + dx * scale * 260 * 0.12, p.vy * 0.88 + dy * scale * 260 * 0.12
        local x, y = p.x + p.vx / 60, p.y + p.vy / 60
        if nav.distance({ x = x, y = y }, observed.enemies[1]) < 25 + p.radius then
            bodyContact = true
        else
            p.x, p.y = x, y
        end
        opened = ((p.x - 292) / 48) ^ 2 + ((p.y - 386.6) / 27) ^ 2 < 1
        if opened then
            break
        end
    end
    assert(
        opened and not bodyContact,
        "BOT never touched the ending chest beside a harmless statue"
    )
    entities = {}
end)
test(
    "normal inputs recover from conservative grid overlap without entering another wall",
    function()
        local bot, source, obs = fixture()
        obs.actor.x, obs.actor.y, obs.actor.radius = 212.1, 174.1, 12
        local rock = nav.cell(obs.map, 200, 160)
        obs.map.walk[rock] = false
        assert(not nav.passable(obs.map, obs.actor.x, obs.actor.y, obs.actor.radius))
        assert(not nav.line(obs.map, obs.actor, { x = 240, y = 200 }, 12))
        obs.map.gridRecovery = true
        assert(nav.line(obs.map, obs.actor, { x = 240, y = 200 }, 12))
        assert(not nav.line(obs.map, obs.actor, { x = 160, y = 160 }, 12))
        local nextWall = nav.cell(obs.map, 240, 200)
        obs.map.walk[nextWall] = false
        assert(not nav.line(obs.map, obs.actor, { x = 240, y = 200 }, 12))
        obs.map.walk[nextWall] = true
        obs.map.zones = { { id = "closed-exit", x = 240, y = 200, radius = 20, exit = true } }
        assert(not nav.line(obs.map, obs.actor, { x = 240, y = 200 }, 12))
        obs.map.zones = {}
        obs.pickups = { { id = "coin", x = 320, y = 240, radius = 10 } }
        bot.command("on")
        local picked, moved = false, false
        for frame = 1, 600 do
            bot.step(frame)
            local p, buttons = obs.actor, source.mask
            moved = moved or buttons & 15 ~= 0
            local dx = ((buttons & 2) ~= 0 and 1 or 0) - ((buttons & 1) ~= 0 and 1 or 0)
            local dy = ((buttons & 8) ~= 0 and 1 or 0) - ((buttons & 4) ~= 0 and 1 or 0)
            local scale = dx ~= 0 and dy ~= 0 and 0.7071 or 1
            p.vx, p.vy =
                p.vx * 0.88 + dx * scale * 260 * 0.12, p.vy * 0.88 + dy * scale * 260 * 0.12
            local x, y = p.x + p.vx / 60, p.y + p.vy / 60
            assert(nav.distance({ x = x, y = y }, { x = 200, y = 160 }) >= 18)
            p.x, p.y = x, y
            picked = nav.distance(p, obs.pickups[1]) < 20
            if picked then
                break
            end
        end
        assert(
            moved and picked,
            "All movement candidates stayed rejected at a legal native position"
        )
    end
)
test("restocked shop circles can be escaped without buying the new item", function()
    local bot, source, obs = fixture()
    local p = obs.actor
    p.x, p.y, p.radius = 235.9, 160.3, 12
    obs.map.zones = { { id = "restock", x = 240, y = 160, radius = 32, purchase = true } }
    for i, delta in ipairs({ { -80, 0 }, { 80, 0 }, { 0, -80 }, { 0, 80 } }) do
        obs.map.zones[#obs.map.zones + 1] = {
            id = "neighbor:" .. i,
            x = 240 + delta[1],
            y = 160 + delta[2],
            radius = 32,
            purchase = true,
        }
    end
    obs.doors = { door(2, "0:exit") }
    local zone = obs.map.zones[1]
    for _, delta in ipairs({ { -40, 0 }, { 40, 0 }, { 0, -40 }, { 0, 40 } }) do
        assert(not nav.passable(obs.map, zone.x + delta[1], zone.y + delta[2], p.radius))
    end
    assert(not nav.path(obs.map, p, { x = 400, y = 160 }, p.radius))
    bot.command("on")
    bot.step(1)
    local departed, closest = false, nav.distance(p, zone)
    for frame = 2, 600 do
        bot.step(frame)
        assert(bot.state == "running" and not obs.map.allowedPickup)
        local dt, retain = 1 / 60, math.sqrt(0.775)
        local dx = ((source.mask & 2) ~= 0 and 1 or 0) - ((source.mask & 1) ~= 0 and 1 or 0)
        local dy = ((source.mask & 8) ~= 0 and 1 or 0) - ((source.mask & 4) ~= 0 and 1 or 0)
        local scale = dx ~= 0 and dy ~= 0 and 0.7071 or 1
        p.vx, p.vy =
            p.vx * retain + dx * scale * p.speed * (1 - retain),
            p.vy * retain + dy * scale * p.speed * (1 - retain)
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        local distance = nav.distance(p, zone)
        assert(distance >= closest - 0.01, "Recovery steered back into a protected purchase")
        closest = math.min(distance, zone.radius + p.radius)
        if p.x > 420 then
            departed = true
            break
        end
    end
    assert(departed, "Shop restock left every movement input neutral")
end)
test("native shop boundary permits a turn before the predictive wall contact", function()
    for _, speed in ipairs({ 260, 340, 400 }) do
        local bot, source, obs = fixture()
        local p = obs.actor
        p.x, p.y, p.radius, p.speed = 397.943, 361.972, 10, speed
        obs.map = {
            x = 40,
            y = 120,
            width = 28,
            height = 9,
            step = 40,
            walk = {},
            zones = {},
            speed = 185,
        }
        for row = 0, 8 do
            for col = 0, 27 do
                obs.map.walk[row * 28 + col + 1] = row > 0 and row < 8 and col > 0 and col < 27
            end
        end
        for i, point in ipairs({
            { 400, 320 },
            { 280, 320 },
            { 520, 320 },
            { 640, 320 },
            { 760, 320 },
            { 880, 320 },
        }) do
            obs.map.zones[i] =
                { id = "shop:" .. i, x = point[1], y = point[2], radius = 32, purchase = true }
        end
        local exit = door(7, "0:84", { x = 840, y = 440, dx = 0, dy = 1 })
        obs.doors = { exit }
        assert(
            nav.path(obs.map, p, { x = 840, y = 408 }, p.radius, 640, exit),
            "Native route itself is reachable"
        )
        bot.command("on")
        bot.step(1)
        local departed = false
        for frame = 2, 900 do
            bot.step(frame)
            assert(bot.state == "running" and not obs.map.allowedPickup)
            local retain, dt = math.sqrt(0.775), 1 / 60
            local dx = ((source.mask & 2) ~= 0 and 1 or 0) - ((source.mask & 1) ~= 0 and 1 or 0)
            local dy = ((source.mask & 8) ~= 0 and 1 or 0) - ((source.mask & 4) ~= 0 and 1 or 0)
            local scale = dx ~= 0 and dy ~= 0 and 0.7071 or 1
            p.vx, p.vy =
                p.vx * retain + dx * scale * p.speed * (1 - retain),
                p.vy * retain + dy * scale * p.speed * (1 - retain)
            local x, y = p.x + p.vx * dt, p.y + p.vy * dt
            if not nav.line(obs.map, p, { x = x, y = p.y }, p.radius, exit) then
                x, p.vx = p.x, 0
            end
            if not nav.line(obs.map, { x = x, y = p.y }, { x = x, y = y }, p.radius, exit) then
                y, p.vy = p.y, 0
            end
            p.x, p.y = x, y
            for _, zone in ipairs(obs.map.zones) do
                assert(
                    nav.distance(p, zone) >= zone.radius + p.radius - 0.01,
                    "Recovery crossed an unselected product"
                )
            end
            if p.y > exit.y then
                departed = true
                break
            end
        end
        assert(
            departed,
            "Long predictions discarded every safe short step out of the shop at speed " .. speed
        )
    end
end)
test("fast client leaves the shop doorway without coasting into adjacent products", function()
    for _, delayedFrames in ipairs({ 0, 2 }) do
        local bot, source, obs, info = fixture()
        local p = obs.actor
        p.x, p.y, p.radius, p.speed = 840, 395.3, 10, 264.705882 * 1.3
        obs.controlDelay = 1 / 30 + delayedFrames / 60
        obs.map = {
            x = 40,
            y = 120,
            width = 28,
            height = 9,
            step = 40,
            walk = {},
            zones = {},
            speed = p.speed * 0.7,
        }
        for row = 0, 8 do
            for col = 0, 27 do
                obs.map.walk[row * 28 + col + 1] = row > 0 and row < 8 and col > 0 and col < 27
            end
        end
        for i, x in ipairs({ 760, 880 }) do
            obs.map.zones[i] =
                { id = "product:" .. i, x = x, y = 320, radius = 32, purchase = true }
        end
        local entry = door(7, "0:84", { x = 840, y = 440, dx = 0, dy = 1 })
        obs.doors = { entry }
        local physical = {}
        for key, value in pairs(obs.map) do
            physical[key] = value
        end
        physical.zones = {} -- Native physics has no invisible purchase-protection wall.
        local inputs, arrived = {}, false
        bot.command("mode hold")
        bot.command("on")
        bot.step(1)
        for frame = 2, 240 do
            info.nowMs = frame * 1000 / 60
            bot.step(frame)
            inputs[frame] = source.mask
            local mask = inputs[frame - delayedFrames] or 0
            local dx = ((mask & 2) ~= 0 and 1 or 0) - ((mask & 1) ~= 0 and 1 or 0)
            local dy = ((mask & 8) ~= 0 and 1 or 0) - ((mask & 4) ~= 0 and 1 or 0)
            local retain, dt = math.sqrt(0.775), 1 / 60
            local scale = dx ~= 0 and dy ~= 0 and 0.7071 or 1
            p.vx, p.vy =
                p.vx * retain + dx * scale * p.speed * (1 - retain),
                p.vy * retain + dy * scale * p.speed * (1 - retain)
            local x, y = p.x + p.vx * dt, p.y + p.vy * dt
            if not nav.line(physical, p, { x = x, y = p.y }, p.radius, entry) then
                x, p.vx = p.x, 0
            end
            if not nav.line(physical, { x = x, y = p.y }, { x = x, y = y }, p.radius, entry) then
                y, p.vy = p.y, 0
            end
            p.x, p.y = x, y
            for _, zone in ipairs(obs.map.zones) do
                assert(
                    nav.distance(p, zone) >= zone.radius + p.radius - 0.01,
                    "Delayed coast crossed an ignored product"
                )
            end
            arrived = arrived or not bot.plan.entry
        end
        assert(arrived and p.y <= 370, "Arrival kept rejecting all moves near the shop products")
    end
end)
test("item value preserves key and recovery budgets and discounts redundant purchases", function()
    local items = modules["lanbot/items"]
    local actor = { keys = 0, coins = 25, needsHeal = true, redDeficit = 4 }
    local value = items.score(
        { quality = 3, damage = true, maxHearts = 0, hearts = 0, soulHearts = 0 },
        actor
    )
    assert(value == 90 and items.reserve(actor) == 11)
    assert(not items.affordable(value, 15, actor))
    actor.coins = 26
    assert(items.affordable(value, 15, actor))
    assert(not items.affordable(value, -1, actor))
    local duplicate =
        items.score({ quality = 3, owned = true, maxHearts = 0, hearts = 0, soulHearts = 0 }, actor)
    assert(not items.affordable(duplicate, 15, actor))
    assert(not items.score({ quality = 4, active = true, maxHearts = 0 }, actor))
    assert(not items.score({ quality = 4, maxHearts = -2 }, actor))
end)
test("team items balance equipment, benefit and budgets with stable ownership", function()
    local items = modules["lanbot/items"]
    local meta = { quality = 3, maxHearts = 0, hearts = 2, soulHearts = 0 }
    local host = { id = "1:0", items = 8, keys = 1, coins = 20 }
    local client = { id = "2:1", items = 5, keys = 1, coins = 20 }
    assert(items.recipient(meta, { host, client }, 0) == client)
    assert(items.recipient(meta, { client, host }, 0) == client)
    host.items = 5
    assert(items.recipient(meta, { client, host }, 0) == host)
    client.needsHeal = true
    assert(items.recipient(meta, { host, client }, 0) == client)
    client.needsHeal, client.owned = false, true
    assert(items.recipient(meta, { host, client }, 0) == host)
    client.owned, client.items, client.coins = false, 3, 0
    assert(items.recipient(meta, { host, client }, 15) == host)
    client.coins, client.available = 20, false
    assert(items.recipient(meta, { host, client }, 0) == host)
    assert(not items.recipient({ active = true }, { host, client }, 0))
end)
test("Greed reserves a free item across rooms and releases stale or departed claims", function()
    local host, client = roster[0], roster[2]
    local hostCount, clientCount, dead =
        host.GetCollectibleCount, client.GetCollectibleCount, host.IsDead
    host.GetCollectibleCount, client.GetCollectibleCount =
        function()
            return 5
        end, function()
            return 8
        end
    local item = fakeEntity(5)
    item.Variant, item.SubType, item.Price, item.Wait = PickupVariant.PICKUP_COLLECTIBLE, 1, 0, 0
    local oldTick = localInfo.tick
    localInfo.tick, entities, greed = 100, { item }, true
    local reader = modules["lanbot/observe"](
        native,
        bridge,
        nav,
        modules["lanbot/terrain"],
        modules["lanbot/items"]
    )
    local obs = assert(reader.read(1, localInfo))
    assert(#obs.pickups == 0 and #obs.map.zones == 1)
    assert(not nav.passable(obs.map, item.Position.X, item.Position.Y, obs.actor.radius))
    -- Both owners independently choose the same actor even from different rooms.
    local hostInfo = {
        slot = 0,
        authority = 1,
        connected = 3,
        ready = 1,
        runId = "run",
        worldEpoch = 1,
        tick = 100,
    }
    local hostView = modules["lanbot/observe"](
        native,
        bridge,
        nav,
        modules["lanbot/terrain"],
        modules["lanbot/items"]
    )
    local offered = assert(hostView.read(1, hostInfo))
    assert(#offered.pickups == 1 and offered.pickups[1].recipient == "1:0")
    localInfo.tick = 700
    assert(#reader.read(2, localInfo).pickups == 1, "Unreachable reservation never expired")
    entities = {}
    reader.read(3, localInfo)
    entities = { item }
    assert(#reader.read(4, localInfo).pickups == 0, "Removed pickup retained expired ownership")
    host.IsDead = function()
        return true
    end
    assert(#reader.read(5, localInfo).pickups == 1)
    host.IsDead = dead
    localInfo.worldEpoch = localInfo.worldEpoch + 1
    assert(#reader.read(6, localInfo).pickups == 0, "New floor retained reservation expiry")
    localInfo.worldEpoch = localInfo.worldEpoch - 1
    host.GetCollectibleCount, client.GetCollectibleCount, localInfo.tick =
        hostCount, clientCount, oldTick
    entities, greed = {}, false
end)
test("an affordable Greed damage item is selected through native pickup planning", function()
    local player = roster[2]
    local getConfig, getCoins, getKeys, getType =
        Isaac.GetItemConfig, player.GetNumCoins, player.GetNumKeys, room.GetType
    local wallet = 30
    Isaac.GetItemConfig = function()
        return {
            GetCollectible = function()
                return {
                    Type = ItemType.ITEM_PASSIVE,
                    Quality = 3,
                    CacheFlags = CacheFlag.CACHE_DAMAGE,
                }
            end,
        }
    end
    player.GetNumCoins, player.GetNumKeys =
        function()
            return wallet
        end, function()
            return 0
        end
    room.GetType = function()
        return RoomType.ROOM_SHOP
    end
    local item = fakeEntity(5)
    item.Variant, item.SubType, item.Price, item.Wait = PickupVariant.PICKUP_COLLECTIBLE, 1, 15, 0
    entities, greed = { item }, true
    local obs = assert(observe.read(206, localInfo))
    assert(#obs.pickups == 1 and obs.pickups[1].paid and obs.pickups[1].itemScore == 90)
    local plan = planner.new()
    plan:observe(obs)
    local goal = assert(plan:choose(obs, "run", "balanced"))
    assert(goal.id == obs.pickups[1].id and goal.paid)
    wallet = 19 -- Reserve the missing key rather than spend all remaining coins.
    obs = assert(observe.read(207, localInfo))
    assert(#obs.pickups == 0 and obs.map.zones[1].purchase)
    Isaac.GetItemConfig, player.GetNumCoins, player.GetNumKeys, room.GetType =
        getConfig, getCoins, getKeys, getType
    entities, greed = {}, false
end)
test("Greed visits a keyed treasure room before gathering at the exit", function()
    local plan, obs = planner.new(), snapshot()
    obs.greed = { stage = 1, wave = 10, bossWave = 10 }
    obs.actor.keys, obs.actor.coins = 1, 0
    obs.doors = {
        door(0, "0:gold", { treasure = true, locked = true, open = false }),
        door(3, "0:exit", { greedExit = true }),
    }
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").door.to == "0:gold" and plan.flow.phase == "loot")
    obs.room, obs.doors = "0:gold", { door(0, "0:1") }
    obs.pickups = { { id = "free-item", x = 240, y = 160, collectible = true, itemScore = 90 } }
    plan:observe(obs)
    assert(plan:choose(obs, "run", "balanced").id == "free-item")
    obs.pickups, obs.actor.keys, obs.actor.items = {}, 0, 1
    local goal = assert(plan:choose(obs, "run", "balanced"))
    assert(plan.flow.phase == "gather" and goal.door.to == "0:1")
    obs.room, obs.doors =
        "0:1", { door(0, "0:gold", { treasure = true }), door(3, "0:exit", { greedExit = true }) }
    plan:observe(obs)
    local exitGoal, reason = plan:choose(obs, "run", "balanced")
    assert(exitGoal.door.to == "0:exit" and not reason, "A valid route was reported unreachable")
end)
test("Greed bounds a shop that cannot be reached and its following loot phase", function()
    local flow, obs = modules["lanbot/greed"].new(), snapshot()
    obs.greed, obs.actor.keys, obs.actor.coins = { stage = 1, wave = 10, bossWave = 10 }, 0, 27
    flow:update(obs, "run")
    assert(flow.phase == "supply")
    obs.frame = 1201
    flow:update(obs, "run")
    assert(flow.phase == "loot" and flow.reason == "shop_unreachable")
    obs.frame = 3001
    flow:update(obs, "run")
    assert(flow.phase == "gather" and flow.reason == "loot_unreachable")
end)
print("lanbot: " .. count .. " checks passed")
