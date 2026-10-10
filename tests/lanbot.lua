local root = assert(arg[1], "repository root required")
local modules = {}
for _, name in ipairs({ "navigation", "hazards", "terrain", "combat", "planner", "observe" }) do
    modules["lanbot/" .. name] = dofile(root .. "/src/bridge/lanbot/" .. name .. ".lua")
end
modules.lanbot = dofile(root .. "/src/bridge/lanbot.lua")
local nav = modules["lanbot/navigation"]
local combat = modules["lanbot/combat"](nav, modules["lanbot/hazards"](nav))
local planner = modules["lanbot/planner"](nav)
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
EntityType = { ENTITY_PLAYER = 1, ENTITY_FAMILIAR = 3, ENTITY_PROJECTILE = 9, ENTITY_EFFECT = 1000 }
PlayerType = { PLAYER_AZAZEL = 7 }
WeaponType = { WEAPON_BRIMSTONE = 4, WEAPON_KNIFE = 3, WEAPON_TECH_X = 9 }
CollectibleType = { COLLECTIBLE_CHOCOLATE_MILK = 69 }
GridCollisionClass = {
    COLLISION_NONE = 0,
    COLLISION_PIT = 1,
    COLLISION_OBJECT = 2,
    COLLISION_WALL_EXCEPT_PLAYER = 5,
}
GridEntityType = {
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
            return false
        end,
        Challenge = 0,
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
local observe = modules["lanbot/observe"](native, bridge, nav, modules["lanbot/terrain"])
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
    ModCallbacks =
        { MC_EXECUTE_CMD = 1, MC_POST_GAME_STARTED = 2, MC_POST_UPDATE = 3, MC_PRE_GAME_EXIT = 4 }
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
print("lanbot: " .. count .. " checks passed")
