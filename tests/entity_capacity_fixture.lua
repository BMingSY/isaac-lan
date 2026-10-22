-- Run the actual fixture and scenario cleanup against observable game API doubles.
local fixture, root, selected = assert(arg[1]), assert(arg[2]), assert(arg[3])
local Vector
local function vector(x, y)
    return setmetatable({ X = x, Y = y }, {
        __add = function(a, b)
            return Vector(a.X + b.X, a.Y + b.Y)
        end,
    })
end
Vector = setmetatable({ Zero = vector(0, 0) }, {
    __call = function(_, ...)
        return vector(...)
    end,
})

local function world(host)
    local h = {
        entities = {},
        refs = {},
        logs = {},
        born = 0,
        spawns = 0,
        frameCalls = 0,
        removes = 0,
        chooses = 0,
        starts = 0,
        tick = 0,
        pads = 0,
        room = 84,
    }
    local status = {
        phase = 0,
        players = 2,
        verified = 0,
        slot = host and 0 or 1,
        ready0 = 0,
        ready1 = 0,
        choice0 = 0,
        choice1 = 0,
    }
    h.status = status
    local function entity(kind, variant, position, seed)
        h.born = h.born + 1
        local e = {
            Type = kind,
            Variant = variant,
            InitSeed = seed or h.born,
            Position = position or Vector.Zero,
            Velocity = Vector.Zero,
            FrameCount = 0,
            alive = true,
            flags = 1,
            pointer = h.born,
        }
        function e:Exists()
            return self.alive
        end
        function e:Remove()
            assert(self.alive, "Removed an entity twice")
            self.alive = false
            h.removes = h.removes + 1
        end
        function e:ToNPC()
            return self.Type == 13 and self or nil
        end
        function e:ToProjectile()
            assert(self.Type == 9)
            return self
        end
        function e:ToEffect()
            assert(self.Type == 1000)
            return self
        end
        function e:AddFreeze(_, duration)
            self.freeze = duration
        end
        function e:ClearEntityFlags(flags)
            self.flags = self.flags & ~flags
        end
        h.entities[#h.entities + 1] = e
        return e
    end
    h.entity = entity
    local player = {}
    function player:FireTear(position)
        assert(host, "Guest fixture generated a local tear instead of a replica")
        h.spawns = h.spawns + 1
        return entity(2, 0, position)
    end
    function player:SetMinDamageCooldown(duration)
        assert(duration >= 460)
        h.protected = (h.protected or 0) + 1
    end
    local env = setmetatable({
        Vector = Vector,
        EntityType = {
            ENTITY_ATTACKFLY = 13,
            ENTITY_TEAR = 2,
            ENTITY_PROJECTILE = 9,
            ENTITY_EFFECT = 1000,
        },
        EffectVariant = { CREEP_RED = 22 },
        EntityFlag = { FLAG_APPEAR = 1 },
        EntityCollisionClass = { ENTCOLL_NONE = 0 },
        EntityGridCollisionClass = { GRIDCOLL_NONE = 0 },
        _IsaacLanTest = { host = host, port = "1234" },
    }, { __index = _G })
    h.env = env
    env.Isaac = {
        AddCallback = function() end,
        RemoveCallback = function() end,
        DebugString = function(message)
            h.logs[#h.logs + 1] = message
        end,
        GetPlayer = function(index)
            assert(index == 0 or index == 1)
            return player
        end,
        GetRoomEntities = function()
            local result = {}
            for _, e in ipairs(h.entities) do
                if e.alive then
                    result[#result + 1] = e
                end
            end
            return result
        end,
        Spawn = function(kind, variant, _, position)
            assert(host, "Guest fixture spawned instead of applying replicas")
            h.spawns = h.spawns + 1
            return entity(kind, variant, position)
        end,
    }
    env.GetPtrHash = function(e)
        return e.pointer
    end
    env.EntityRef = function(e)
        return e
    end
    env.EntityPtr = function(e)
        local ref = { Ref = e }
        h.refs[#h.refs + 1] = ref
        return ref
    end
    env.Game = function()
        return {
            GetRoom = function()
                return {
                    GetCenterPos = function()
                        return Vector(320, 280)
                    end,
                }
            end,
            GetLevel = function()
                return {
                    GetCurrentRoomIndex = function()
                        return h.room
                    end,
                }
            end,
        }
    end
    env._IsaacLan = {
        net_phases = function()
            return dofile(root .. "/tests/fixtures/net_phases.lua")
        end,
        test_gamepad = function(buttons)
            assert(buttons == 0)
            h.pads = h.pads + 1
        end,
        rooms_heads = function()
            return { ["0"] = 0, ["1"] = 1 }
        end,
        rooms_ready = function()
            return h.readyRooms ~= false
        end,
        rooms_with_player = function(_, callback)
            callback()
            return true
        end,
    }
    env._IsaacLanFrame = function()
        h.frameCalls = h.frameCalls + 1
        return status
    end
    env._IsaacLanCommand = function(action, value)
        if action == "host" or action == "join" then
            assert(action == (host and "host" or "join"))
            assert(value == (host and "1234" or "127.0.0.1:1234"))
            status.phase = 2
        elseif action == "choose" then
            assert(value == "0:1")
            h.chooses = h.chooses + 1
            -- The command is void. A later status poll acknowledges selection.
        else
            assert(action == "start" and host and value == "YV039KQF:0:0:0:0:0")
            assert(status.ready0 == 1 and status.ready1 == 1)
            status.phase = 3
            h.starts = h.starts + 1
        end
    end
    local create = assert(loadfile(root .. "/tests/support/scenario.lua", "t", env))()
    h.scenario = create(function()
        return assert(loadfile(fixture, "t", env))()
    end)
    function h:frame(tick)
        if tick then
            for _, e in ipairs(self.entities) do
                if e.alive then
                    e.FrameCount = e.FrameCount + tick - self.tick
                end
            end
            self.tick, status.verified = tick, tick
        end
        return self.scenario.call(env._IsaacLanFrame)
    end
    function h:ready()
        for _ = 1, (host and 300 or 360) do
            self:frame()
        end
        assert(self.chooses == 1 and self.starts == 0 and not self.scenario.done())
        status.ready0, status.ready1 = 1, 1
        self:frame()
        status.phase, status.prepared = 3, true
        self:frame(0)
    end
    return h
end

local function replicate(source, target)
    local bySeed = {}
    for _, e in ipairs(target.entities) do
        bySeed[e.InitSeed] = e
        e.alive = false
    end
    for _, e in ipairs(source.entities) do
        if e.alive then
            local copy = bySeed[e.InitSeed]
                or target.entity(e.Type, e.Variant, e.Position, e.InitSeed)
            copy.alive, copy.FrameCount = true, e.FrameCount
        end
    end
end

local function count(h)
    return #h.env.Isaac.GetRoomEntities()
end
local function expectFailure(h, tick, message)
    local ok, failure = pcall(function()
        h:frame(tick)
    end)
    assert(not ok and tostring(failure):find(message, 1, true), tostring(failure))
    assert(not h.scenario.done(), "A failed fixture reported completion")
end
local function signatures(h)
    local result = {}
    for _, line in ipairs(h.logs) do
        local label, signature = line:match("SAMPLE label=(%S+).*signature=(%d+)")
        if label then
            result[label] = signature
        end
    end
    return result
end

if selected == "startup-host" or selected == "startup-client" then
    local h = world(selected == "startup-host")
    for _ = 1, 365 do
        h:frame()
    end
    assert(h.chooses == 1 and h.starts == 0 and not h.scenario.done())
    h.scenario.cleanup()
    local pads, frames = h.pads, h.frameCalls
    h:frame()
    assert(h.pads == pads and h.frameCalls == frames + 1)
elseif selected == "unconfirmed" then
    local h = world(false)
    for _ = 1, 360 do
        h:frame()
    end
    h.status.phase, h.status.prepared = 3, true
    expectFailure(h, 0, "character selection was not confirmed")
elseif selected == "not-ready" then
    local h = world(true)
    h:ready()
    assert(not h.protected and count(h) == 0)
    h.readyRooms = false
    h:frame(60)
    h:frame(80)
    assert(not h.protected and count(h) == 0)
    h.readyRooms = true
    h:frame(81)
    assert(h.protected == 2 and count(h) == 64)
    h.scenario.cleanup()
    assert(count(h) == 0)
elseif selected == "success" or selected == "missing-replica" then
    local host, client = world(true), world(false)
    host:ready()
    client:ready()
    for tick = 1, 460 do
        host:frame(tick)
        replicate(host, client)
        -- Replica ages come from the authoritative sample, not local Update.
        client.tick = tick
        if selected == "missing-replica" and tick == 260 then
            client.entities[1].alive = false
            expectFailure(client, tick, "count differs")
            host.scenario.cleanup()
            assert(count(host) == 0 and client.spawns == 0)
            print("PASS entity capacity fixture " .. selected)
            return
        end
        client:frame(tick)
        if tick == 200 then
            assert(count(host) == 2100 and count(client) == 2100 and client.spawns == 0)
            for _, e in ipairs(host.entities) do
                assert(e.EntityCollisionClass == 0 and e.GridCollisionClass == 0)
                assert(e.CollisionDamage == 0 and e.flags == 0)
                if e.Type == 13 then
                    assert(e.freeze == 1000)
                end
            end
        end
    end
    assert(host.scenario.done() and client.scenario.done())
    assert(host.protected == 2 and client.protected == 2)
    assert(host.spawns == 2100 and host.removes == 2100 and count(host) == 0 and count(client) == 0)
    local a, b = signatures(host), signatures(client)
    assert(a["260"] and a["260"] == a["320"] and a["260"] == b["260"] and a["320"] == b["320"])
    assert(a.cleared == "0" and b.cleared == "0")
    host.scenario.cleanup()
    host.scenario.cleanup()
    client.scenario.cleanup()
    assert(host.removes == 2100)
elseif selected == "replacement" then
    local h = world(true)
    h:ready()
    for tick = 1, 260 do
        h:frame(tick)
    end
    h.entities[1].InitSeed = h.entities[1].InitSeed + 100000
    expectFailure(h, 320, "replaced entities")
    assert(count(h) == 1, "Cleanup removed a reused object belonging to another identity")
elseif selected == "pool-budget" then
    local h = world(true)
    h:ready()
    for _ = 1, 1024 do
        h.entity(1000, 999)
    end
    for tick = 1, 159 do
        h:frame(tick)
    end
    expectFailure(h, 160, "saturate the effect pool")
    assert(count(h) == 1024, "Cleanup removed unrelated effects")
elseif selected == "cleanup-reuse" then
    local h = world(true)
    h:ready()
    for tick = 1, 200 do
        h:frame(tick)
    end
    local original = h.refs[1].Ref
    local replacement = h.entity(13, 0, Vector.Zero, 100000)
    original.alive, h.refs[1].Ref = false, replacement
    h.scenario.cleanup()
    h.scenario.cleanup()
    assert(count(h) == 1 and replacement.alive and h.removes == 2099)
    local pads, spawns = h.pads, h.spawns
    h:frame(500)
    assert(h.pads == pads and h.spawns == spawns and not h.scenario.done())
elseif selected == "incomplete" then
    local h = world(true)
    h:ready()
    h:frame(80)
    expectFailure(h, 440, "count differs")
    assert(count(h) == 0)
elseif selected == "room-escape" then
    local h = world(true)
    h:ready()
    h:frame(80)
    h.room = 85
    expectFailure(h, 81, "left its arena")
    assert(count(h) == 0)
else
    error("Unknown capacity fixture test")
end
print("PASS entity capacity fixture " .. selected)
