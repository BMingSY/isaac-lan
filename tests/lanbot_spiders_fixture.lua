-- Exercise the real fixture against an external native lifecycle model.
-- Damage attempts do not count as hits; health changes do. Player movement
-- after release and Spider AI are supplied exclusively by this model.
local root = assert(arg[1])
local testInput = dofile(root .. "/tests/support/input.lua")
local vectorMeta = {}
local function vec(x, y)
    return setmetatable({ X = x, Y = y }, vectorMeta)
end
vectorMeta.__index = {
    Distance = function(a, b)
        return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
    end,
}
vectorMeta.__add = function(a, b)
    return vec(a.X + b.X, a.Y + b.Y)
end
vectorMeta.__sub = function(a, b)
    return vec(a.X - b.X, a.Y - b.Y)
end
local Vector = setmetatable({ Zero = vec(0, 0) }, {
    __call = function(_, x, y)
        return vec(x, y)
    end,
})
for _, host in ipairs({ true, false }) do
    local callbacks, messages, entities, inputs, commands = {}, {}, {}, {}, {}
    local health, clock, phase, scene, view, hooks, releaseTick = 6, 0, 3, 2, 1, nil, nil
    local points = { vec(320, 280), vec(140, 280) }
    local locations = { ["0"] = { index = 84 }, ["1"] = { index = 84 } }
    local players = {}
    for slot = 0, 1 do
        local index = slot
        local methods = {
            ControllerIndex = index + 1,
            MoveSpeed = 1,
            GetPlayerType = function()
                return 0
            end,
            GetHearts = function()
                return index == 1 and health or 6
            end,
            GetMaxHearts = function()
                return 6
            end,
            GetSoulHearts = function()
                return 0
            end,
            GetCollectibleCount = function()
                return 0
            end,
            IsDead = function()
                return index == 1 and health == 0
            end,
            IsCoopGhost = function()
                return index == 1 and health == 0
            end,
        }
        methods.ToPlayer = function()
            return players[index]
        end
        players[index] = setmetatable({}, {
            __index = function(_, key)
                return key == "Position" and points[index + 1] or methods[key]
            end,
            __newindex = function(_, key, value)
                assert(not releaseTick, "Fixture wrote player after release: " .. key)
                assert(key == "Position" or key == "Velocity")
                if key == "Position" then
                    points[index + 1] = value
                end
            end,
        })
    end
    local function spawn(kind, variant, subtype, position)
        local e = { Type = kind, InitSeed = #entities + 1, Position = position, HitPoints = 10 }
        e.ToNPC = function()
            return e
        end
        e.GetChampionColorIdx = function()
            return -1
        end
        e.Exists = function()
            return true
        end
        e.IsDead = function()
            return false
        end
        e.Remove = function()
            error("Fixture removed a trial Spider")
        end
        entities[#entities + 1] = e
        return e
    end
    local native = {
        api_info = function()
            return { ready = phase == 3 and 1 or 0, nowMs = clock }
        end,
        input_bot = function(active, buttons)
            assert(buttons & 240 == 0, "Fixture forwarded shooting")
            inputs[#inputs + 1] = { active, buttons }
            return true
        end,
        test_gamepad = function(b)
            assert(b == 0)
        end,
        rooms_ready = function()
            return true
        end,
        rooms_heads = function()
            return { ["0"] = 0, ["1"] = 1 }
        end,
        rooms_positions = function()
            return locations
        end,
        rooms_move = function(slot, index)
            assert(host and slot == 0 and index == 85, "Fixture moved the subject")
            locations["0"].index = index
            return true
        end,
        rooms_with_player = function(slot, fn)
            view = slot
            fn()
            return true
        end,
        net_gate = function(...)
            hooks = { ... }
            return true
        end,
    }
    local env = setmetatable({
        Vector = Vector,
        _IsaacLan = native,
        _IsaacLanTest = { host = host, port = 30990 },
        _IsaacLanTestInput = testInput,
        _IsaacLanModules = {
            ["api/public"] = {
                ready = function()
                    return true
                end,
                withView = function(fn)
                    view = 1
                    fn()
                end,
            },
        },
        _IsaacLanFrame = function()
            return { phase = phase, scene = scene, prepared = false }
        end,
        _IsaacLanCommand = function() end,
        EntityType = { ENTITY_PLAYER = 1, ENTITY_SPIDER = 85 },
        ModCallbacks = { MC_PRE_NPC_UPDATE = 1, MC_ENTITY_TAKE_DMG = 2, MC_POST_FIRE_TEAR = 3 },
        Isaac = {
            AddCallback = function(_, id, fn)
                callbacks[id] = fn
            end,
            DebugString = function(text)
                messages[#messages + 1] = text
            end,
            ConsoleOutput = function() end,
            GetPlayer = function(slot)
                return players[slot]
            end,
            GetRoomEntities = function()
                return view == 1 and entities or {}
            end,
            Spawn = spawn,
        },
        Game = function()
            return {
                GetLevel = function()
                    return {
                        GetStage = function()
                            return 1
                        end,
                        GetCurrentRoomIndex = function()
                            return locations[tostring(view)].index
                        end,
                    }
                end,
                GetRoom = function()
                    return {
                        GetCenterPos = function()
                            return vec(320, 280)
                        end,
                        GetGridPosition = function(_, i)
                            return vec(40 + i % 15 * 40, 120 + math.floor(i / 15) * 40)
                        end,
                        GetGridSize = function()
                            return 135
                        end,
                        GetTopLeftPos = function()
                            return vec(60, 140)
                        end,
                        GetBottomRightPos = function()
                            return vec(580, 420)
                        end,
                        GetDoor = function(_, slot)
                            return slot == 0 and { TargetRoomIndex = 85, Close = function() end }
                                or nil
                        end,
                        SetClear = function(_, value)
                            assert(value == false)
                        end,
                    }
                end,
            }
        end,
    }, { __index = _G })
    env._IsaacLanBotCommand = function(args)
        commands[#commands + 1] = args
        env.Isaac.ConsoleOutput("LANBOT " .. (args == "on" and "running" or "off"))
    end
    local completion = assert(loadfile(root .. "/tests/state_lanbot_spiders.lua", "t", env))()
    native.net_gate(
        function() end,
        function() end,
        function() end,
        function() end,
        function() end,
        function() end
    )
    local function has(pattern)
        for _, line in ipairs(messages) do
            if line:find(pattern, 1, true) then
                return true
            end
        end
        return false
    end
    if host then
        local input = testInput.neutral .. testInput.buttons(1)
        for tick = 1, 400 do
            clock = tick * 1000 / 30
            hooks[2](tick, 2, input)
            env._IsaacLanFrame()
            if not releaseTick and has(" RELEASE ") then
                releaseTick = tick
            end
            for _, npc in ipairs(entities) do
                local frozen = callbacks[1](nil, npc)
                assert((frozen == true) == not releaseTick, "Spider AI release order is incorrect")
                if not frozen then
                    npc.Position = npc.Position + vec(0.25, 0)
                end
            end
            if releaseTick then
                points[2] = points[2] + vec(0.3, 0)
                -- Repeated collisions while invulnerable must not inflate hits.
                callbacks[2](nil, players[1], 1, 0, { Type = 85 })
                if tick > releaseTick and (tick - releaseTick) % 30 == 0 and health > 0 then
                    health = health - 1
                end
            end
        end
        assert(releaseTick and releaseTick >= 92, "Spiders were not staged for three seconds")
        assert(has("LAN_NETWORK MENU_READY"), "Native runner cannot recognize fixture readiness")
        assert(#entities == 9 and locations["0"].index ~= locations["1"].index)
        assert(has("RESULT dead=true") and has("hits=6 hearts=0 spiders_alive=9 tears=0"))
        local count = 0
        for _, line in ipairs(messages) do
            if line:find(" HIT number=", 1, true) then
                count = count + 1
            end
        end
        assert(count == 6, "Damage attempts were counted as actual hits")
        for _, npc in ipairs(entities) do
            assert(npc.HitPoints == 10)
        end
    else
        for row = -1, 1 do
            for col = -1, 1 do
                spawn(85, 0, 0, vec(320 + col * 40, 280 + row * 40))
            end
        end
        for tick = 1, 110 do
            clock = tick * 1000 / 30
            env._IsaacLanFrame()
        end
        assert(has("BOT_ACTIVE") and commands[1] == "mode hold" and commands[2] == "on")
        for _ = 1, 12 do
            native.input_bot(1, 255)
        end
        assert(inputs[#inputs][2] == 15)
        phase, scene = 0, 1
        env._IsaacLanFrame()
        assert(has("GUEST_FINISHED move_inputs=12 masked_fire=12 tears=0"))
    end
    assert(not pcall(callbacks[3]), "Native firing did not invalidate the pure-dodging run")
end
print(
    "PASS Spider fixture: staged AI, real guest input, six health drops, firing masked, no actor writes after release"
)
