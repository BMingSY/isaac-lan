local root = assert(arg[1], "repository root required")
local modules = {}
for _, name in ipairs({ "navigation", "combat", "planner", "observe" }) do
    modules["lanbot/" .. name] = dofile(root .. "/src/bridge/lanbot/" .. name .. ".lua")
end
modules.lanbot = dofile(root .. "/src/bridge/lanbot.lua")
local nav = modules["lanbot/navigation"]
local combat = modules["lanbot/combat"](nav)
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

-- Exercise the game adapter with documented API-shaped fakes. No game process.
EntityFlag = { FLAG_FRIENDLY = 1, FLAG_CHARM = 2 }
EntityType = { ENTITY_PLAYER = 1, ENTITY_FAMILIAR = 3, ENTITY_PROJECTILE = 9 }
PlayerType = { PLAYER_AZAZEL = 7 }
WeaponType = { WEAPON_BRIMSTONE = 4, WEAPON_KNIFE = 3, WEAPON_TECH_X = 9 }
CollectibleType = { COLLECTIBLE_CHOCOLATE_MILK = 69 }
GridCollisionClass = {
    COLLISION_NONE = 0,
    COLLISION_PIT = 1,
    COLLISION_OBJECT = 2,
    COLLISION_WALL_EXCEPT_PLAYER = 5,
}
GridEntityType = { GRID_TRAPDOOR = 17, GRID_SPIKES = 8, GRID_SPIKES_ONOFF = 9 }
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
local observe = modules["lanbot/observe"](native, bridge, nav)
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
test("only a selected exit task unlocks its navigation cell", function()
    local bot, _, _, _, env = fixture()
    local observed
    env.observe = function(frame)
        observed = snapshot()
        observed.frame = frame
        observed.exit = { x = 320, y = 160, cell = 57 }
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
    assert(observed.map.walk[57] and bot.task == "move_to_exit")
end)
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
    modules["api/public"], modules["compat/registry"] = bridge, {}
    _IsaacLan, _IsaacLanModules = native, modules
    RegisterMod = function()
        return {}
    end
    ModCallbacks =
        { MC_EXECUTE_CMD = 1, MC_POST_GAME_STARTED = 2, MC_POST_UPDATE = 3, MC_PRE_GAME_EXIT = 4 }
    dofile(root .. "/src/bridge/main.lua")
    assert(callbacks[1](nil, "another_command", "on") == nil and #output == 0)
    assert(callbacks[1](nil, "lanbot", "on") == nil and output[1]:find("running"))
    _IsaacLanBotFrame(1)
    assert(source.active)
    callbacks[1](nil, "lanbot", "pause")
    assert(not source.active and source.mask == 0)
    callbacks[1](nil, "lanbot", "resume")
    _IsaacLanBotFrame(2)
    assert(source.active)
    callbacks[4]()
    assert(not source.active)
end)
print("lanbot: " .. count .. " checks passed")
