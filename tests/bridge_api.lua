-- Portable API/transaction tests. No game or third-party source is required.
local root = arg[1] or "."
local function rejects(fn)
    assert(not pcall(fn), "invalid value accepted")
end
local codec = assert(loadfile(root .. "/src/bridge/api/codec.lua"))()
local value = { array = { true, false, 3.5, -7 }, text = "\0hello", empty = {} }
local decoded = codec.decode(codec.encode(value))
for _, integer in ipairs({ math.mininteger, math.maxinteger, 9007199254740993 }) do
    local roundTrip = codec.decode(codec.encode(integer))
    assert(roundTrip == integer and math.type(roundTrip) == "integer", "Integer precision lost")
end
assert(
    decoded.array[1]
        and decoded.array[2] == false
        and decoded.array[3] == 3.5
        and decoded.text == value.text
)
for _, bad in ipairs({ "", "X\0\0", "S\0\5x", "A\0\1", "N", "I", "Tjunk", "R\0\1T" }) do
    rejects(function()
        codec.decode(bad)
    end)
end
for _, bad in ipairs({
    math.huge,
    -math.huge,
    0 / 0,
    function() end,
    string.rep("x", 513),
    { [2] = true },
    setmetatable({}, {}),
}) do
    rejects(function()
        codec.encode(bad)
    end)
end
local cyclic = {}
cyclic.self = cyclic
rejects(function()
    codec.encode(cyclic)
end)
local runtime = assert(loadfile(root .. "/tests/fixtures/api_runtime.lua"))()(root)
local peer = runtime.peer
local actor1, actor2 = runtime.actors[1], runtime.actors[2]
local host, guest = peer(0), peer(1)
local h = host.api:Attach({}, "test.travel")
local g = guest.api:Attach({}, "test.travel")
local order = {}
for _, event in ipairs({
    "StateReset",
    "LocalPlayersChanged",
    "LocalRoomChanged",
    "ViewUpdated",
    "SessionReady",
}) do
    g:On(event, function()
        order[#order + 1] = event
    end)
end
host.bridge.commit()
guest.bridge.commit()
assert(table.concat(order, ",") == "LocalPlayersChanged,LocalRoomChanged,ViewUpdated,SessionReady")
assert(#g:GetLocalPlayers() == 1 and g:GetLocalPlayers()[1] == actor2)
assert(g:GetOwnerId(actor2) == 2 and g:GetPlayerId(actor2) == "p2:1")
assert(g:GetPlayerId(actor1) == "p1:1")
local copied = g:GetLocalRoom()
copied.index = -1
assert(g:GetLocalRoom().index == 84)
local a, b = g:WithLocalView(function()
    assert(guest.env.Game():GetNumPlayers() == 1 and guest.env.Isaac.GetPlayer(0) == actor2)
    return g:WithLocalView(function()
        return 7, nil
    end)
end)
assert(a == 7 and b == nil and guest.scope == nil)
rejects(function()
    g:WithLocalView(function()
        error("scope test")
    end)
end)
assert(guest.scope == nil)
local failures, successes = 0, 0
g:On("ViewUpdated", function()
    failures = failures + 1
    error("subscription test")
end)
local cancel = g:On("ViewUpdated", function()
    successes = successes + 1
end)
guest.bridge.commit()
guest.bridge.commit()
cancel()
guest.bridge.commit()
assert(failures == 1 and successes == 2)
assert(host.api:Attach(h.mod, "test.travel") == h)
rejects(function()
    host.api:Attach({}, "test.travel")
end)
assert(host.api.API_VERSION == 2 and host.api.RegisterMod == nil and h.RegisterAction == nil)
local executions = 0
local authorityMove = h:Action("move", {
    cooldownTicks = 1,
    validate = function(payload)
        return type(payload) == "table" and payload.index == 71
    end,
    execute = function(context, payload)
        assert(context.ownerId == 2 and context.player == actor2 and host.scope == 1)
        executions = executions + 1
        local operation = assert(context:MoveTo({ index = payload.index, dimension = 0 }))
        local poll = operation.poll
        operation.poll = function()
            assert(host.scope == 1, "Operation polled in another participant's room")
            return poll()
        end
        return operation
    end,
})
rejects(function()
    h:Action("move", { execute = function() end })
end)
local move = g:Action("move")
host.bridge.actions.poll()
guest.bridge.actions.poll()
assert(move:IsAvailable() and g:Action("move") == move)
local results = {}
local request = move:Request({ index = 71, forgedOwner = 1 }, {
    onResult = function(result)
        results[#results + 1] = result
    end,
})
assert(request.status == "pending")
local packet = guest.sent[#guest.sent].bytes
host.bridge.actions.poll()
assert(executions == 0, "request executed during polling/render")
host.bridge.actions.step()
assert(executions == 1 and #results == 0, "queue acknowledgement claimed arrival")
host.inbox[#host.inbox + 1] = { sender = 1, bytes = packet }
host.bridge.actions.step()
assert(executions == 1)
host.positions["1"].index = 71
host.queuedMove = nil
host.bridge.commit()
guest.bridge.actions.poll()
assert(#results == 1 and results[1].status == "applied" and results[1].requestId == request.id)
assert(request.status == "applied" and request.code == "arrived")
host.inbox[#host.inbox + 1] = { sender = 1, bytes = packet }
host.bridge.actions.step()
guest.bridge.actions.poll()
assert(executions == 1 and #results == 1)
local reused = codec.decode(packet)
reused.payload.index = 72
host.inbox[#host.inbox + 1] = { sender = 1, bytes = codec.encode(reused) }
host.bridge.actions.step()
assert(executions == 1)
local last = codec.decode(host.sent[#host.sent].bytes)
assert(last.code == "request_id_reused")
-- A request captured in the departure room cannot act on a different room.
host.tick, guest.tick = 10, 10
local departed = move:Request({ index = 71 })
host.bridge.actions.step()
guest.bridge.actions.poll()
assert(departed.code == "source_changed" and executions == 1)
host.api:SetActionEnabled("test.travel", "move", false)
host.bridge.actions.poll()
guest.bridge.actions.poll()
assert(not move:IsAvailable())
local callbacks = 0
local unavailable = move:Request({ index = 71 }, {
    onResult = function(result)
        callbacks = callbacks + 1
        assert(result.status == "rejected" and result.code == "action_unavailable")
    end,
})
assert(unavailable.status == "rejected" and callbacks == 1)
host.api:SetActionEnabled("test.travel", "move", true)
host.positions["1"].index = 84
host.tick = 20
host.bridge.actions.poll()
guest.bridge.actions.poll()
local unknown = move:Request({ index = 71 })
guest.now = 5001
guest.bridge.actions.poll()
assert(unknown.status == "unknown" and unknown.code == "timeout" and executions == 1)
guest.epoch = 1
guest.bridge.commit()
assert(g:View().worldEpoch == 1 and order[#order] == "SessionReady")
guest.active, guest.ready, guest.networked = 0, 0, 0
guest.bridge.poll()
assert(not g:IsActive() and #g:GetLocalPlayers() == 2 and not g:View().networked)
local echo = h:Action("echo", {
    validate = function(value)
        return value == true
    end,
    execute = function(context)
        assert(context.ownerId == 1 and context.player == actor1)
        return { status = "applied", code = "echo", data = { value = 42 } }
    end,
})
local echoed = echo:Request(true)
host.bridge.actions.step()
host.bridge.commit()
assert(
    echoed.status == "applied" and echoed.result.data.value == 42,
    "Host bypassed shared request processing"
)
echo:Close()
local longId, longName = string.rep("i", 64), string.rep("a", 32)
local longHost = host.api:Attach({}, longId)
local longGuest = guest.api:Attach({}, longId)
local hostAction = longHost:Action(longName, {
    version = 2,
    execute = function()
        return { status = "applied", code = "long" }
    end,
})
local guestAction = longGuest:Action(longName, { version = 2 })
guest.active, guest.ready, guest.epoch = 1, 1, 0
guest.bridge.commit()
host.bridge.actions.poll()
guest.bridge.actions.poll()
assert(guestAction:IsAvailable(), "Allowed long namespace failed capability encoding")
longHost:Close()
longGuest:Close()
local replacement = host.api:Attach({}, longId)
rejects(function()
    longHost:On("ViewUpdated", function() end)
end)
rejects(function()
    longHost:Action("stale", { execute = function() end })
end)
local staleRequest = hostAction:Request()
assert(staleRequest.status == "rejected" and staleRequest.code == "integration_closed")
longHost:Close()
assert(host.bridge.handles[longId] == replacement)
replacement:Close()
authorityMove:Close()
-- Original callback identity, parameters and priority survive wrapping/removal.
local callbacks, removed = {}, {}
local target = {
    mod = {
        AddCallback = function(_, id, fn, param)
            callbacks[#callbacks + 1] = { id, fn, param }
        end,
        AddPriorityCallback = function(_, id, priority, fn, param)
            callbacks[#callbacks + 1] = { id, fn, param, priority }
        end,
        RemoveCallback = function(_, id, fn)
            removed[fn] = true
        end,
    },
}
local wrapping = host.env._IsaacLanModules["compat/mods/wrapping"]
wrapping.callbacks(target, function(record, ...)
    return record.original(...)
end)
local fn = function(_, x)
    return x + 1
end
target.mod:AddPriorityCallback(99, -100, fn, 55)
assert(callbacks[1][3] == 55 and callbacks[1][4] == -100 and callbacks[1][2](target.mod, 8) == 9)
target.mod:RemoveCallback(99, fn)
assert(removed[callbacks[1][2]])
-- Unknown source and same-name impostors never install an adapter.
-- Give each registration its own source identity to test version rejection.
local isolated = peer(0)
local registry = isolated.bridge.registry
local installs, cleanupCount, compatibilityHandle = 0, 0, nil
isolated.modInfo = {
    directory = "mods/test",
    workshopId = "123",
    metadataVersion = "1",
    sourceHash = string.rep("f", 64),
}
local definition = {
    id = "test.compat",
    adapterVersion = 1,
    modName = "Test",
    targets = { { workshopId = "123", metadataVersion = "1", sourceHash = string.rep("f", 64) } },
    probe = function()
        return "ready"
    end,
    install = function(target, api)
        installs = installs + 1
        compatibilityHandle = api:Attach(target.mod, "test.compat.handle")
        return function()
            cleanupCount = cleanupCount + 1
            compatibilityHandle:Close()
        end
    end,
}
local invalidTarget = isolated.bridge.copy(definition)
invalidTarget.targets[1].workshopId = nil
rejects(function()
    registry.register(invalidTarget)
end)
registry.register(definition)
isolated.modInfo.sourceHash = string.rep("0", 64)
registry.observeMod({ Name = "Test" }, "impostor-source")
registry.poll()
assert(installs == 0 and registry.status()[1].state == "unsupported")
isolated.modInfo.sourceHash = string.rep("f", 64)
local mod = { Name = "Test" }
registry.observeMod(mod, "test-source")
registry.poll()
registry.poll()
assert(installs == 1 and registry.status()[1].state == "active")
isolated.api:SetAdapterEnabled("test.compat", false)
assert(cleanupCount == 1)
isolated.api:SetAdapterEnabled("test.compat", true)
assert(installs == 2)
isolated.api:Attach(mod, "native.test")
assert(cleanupCount == 2)
rejects(function()
    compatibilityHandle:On("ViewUpdated", function() end)
end)
local status = registry.status()[1]
assert(status.state == "disabled" and status.reason == "native_integration")
local initialized, partialCleanups = false, 0
registry.register({
    id = "test.late",
    adapterVersion = 1,
    modName = "Late",
    targets = definition.targets,
    probe = function()
        return initialized and "ready" or "pending"
    end,
    install = function(target, api)
        api:Attach(target.mod, "test.late.handle")
        target.mod.patched = true
        target.addCleanup(function()
            target.mod.patched = nil
            partialCleanups = partialCleanups + 1
        end)
        error("partial installation failed")
    end,
})
local lateMod = { Name = "Late" }
registry.observeMod(lateMod, "late-source")
registry.poll()
assert(registry.status()[2].state == "pending" and not lateMod.patched)
initialized = true
registry.poll()
assert(registry.status()[2].state == "error" and not lateMod.patched and partialCleanups == 1)
assert(not isolated.bridge.modHandles[lateMod], "Failed installation retained its registration")
registry.poll()
assert(partialCleanups == 1, "Failed adapter installed repeatedly")
local authorityAttempts = 0
local failingAuthority = isolated.bridge.copy(definition)
failingAuthority.id, failingAuthority.modName = "test.authority-error", "Authority error"
failingAuthority.authority = function()
    authorityAttempts = authorityAttempts + 1
    error("authority initialization failed")
end
registry.register(failingAuthority)
registry.observeMod({ Name = "Authority error" }, "authority-error-source")
assert(registry.status()[1].state == "error" and installs == 2)
isolated.api:SetAdapterEnabled("test.authority-error", false)
local enabled, enableCode = isolated.api:SetAdapterEnabled("test.authority-error", true)
assert(not enabled and enableCode == "authority_install_failed" and authorityAttempts == 2)
-- Released and updated EID builds use the same capability contract. Metadata,
-- runtime version and source changes alone must not disable local descriptions.
for _, build in ipairs({
    { "5.23", 5.24, "980bb0b", "8f2614a6a4cd58d60345dd0a33072a0bc7822ecf06ad9106234a6a9b2380b3fc" },
    { "5.24", 5.25, "d7aab88", "705a61422ffc09c683d4250dedf2a569b6d76d4eee884dec70b705eedfa898f5" },
    { "6.00", 6.01, "new-build", string.rep("a", 64) },
}) do
    local p = peer(1)
    p.env.ModCallbacks = {
        MC_POST_RENDER = 2,
        MC_POST_UPDATE = 1,
        MC_POST_NEW_ROOM = 19,
        MC_POST_NEW_LEVEL = 18,
        MC_POST_GAME_STARTED = 15,
    }
    p.modInfo = {
        workshopId = "836319872",
        metadataVersion = build[1],
        sourceHash = build[4],
        directory = "eid",
    }
    local callbacks = {}
    local eid = {
        Name = "External Item Descriptions",
        ModVersion = build[2],
        ModVersionCommit = build[3],
        OnRender = function() end,
        AddCallback = function(_, id, fn)
            callbacks[id] = fn
        end,
        AddPriorityCallback = function() end,
        RemoveCallback = function() end,
        setPlayer = function(self)
            self.player = p.env.Isaac.GetPlayer(0)
        end,
        EntitySanityCheck = function(_, entity)
            return entity ~= nil
        end,
        IsGridEntity = function(_, entity)
            return entity.grid == true
        end,
        getEntityData = function(_, entity, key)
            if entity and not entity.grid then
                return entity:GetData()[key]
            end
        end,
    }
    local originalGetEntityData = eid.getEntityData
    p.env.EID = eid
    local adapter = assert(loadfile(root .. "/src/bridge/compat/mods/eid.lua", "t", p.env))()
    local r = p.env._IsaacLanModules["compat/mods/registry"]
    r.observeMod(eid, "eid-source")
    r.poll()
    assert(r.status()[1].state == "active", "Supported EID adapter was not installed")
    -- An installed adapter is also present before entering LAN. With no LAN
    -- view, native startup, continued games and drawing must still run.
    p.active, p.ready = 0, 0
    local soloCalls = {}
    for _, id in ipairs({ 15, 18, 19, 1, 2 }) do
        eid:AddCallback(id, function(self, marker, gap, tail)
            assert(self == eid and marker == id and gap == nil and tail == "solo")
            assert(p.scope == nil, "Solo EID callback borrowed a LAN view")
            self:setPlayer()
            assert(self.player == actor1, "Solo EID did not use its native player")
            soloCalls[id] = (soloCalls[id] or 0) + 1
            return marker, nil, tail
        end)
        local first, gap, tail = callbacks[id](eid, id, nil, "solo")
        assert(first == id and gap == nil and tail == "solo", "Solo EID callback was blocked")
        assert(soloCalls[id] == 1, "Solo EID callback did not run exactly once")
    end
    p.active, p.ready = 1, 1
    p.bridge.commit()
    for _, count in pairs(soloCalls) do
        assert(count == 1, "Solo EID lifecycle was replayed after joining LAN")
    end
    eid:setPlayer()
    assert(eid.player == actor2 and p.scope == nil, "EID selected a remote actor")
    local replica = { FrameCount = 0, data = { __isaac_lan_replica = 7 } }
    function replica:GetData()
        return self.data
    end
    local function describable(entity)
        return entity.FrameCount > 0 or eid:getEntityData(entity, "EID_DescribeOnFirstFrame")
    end
    -- EID's render eligibility check must remain true for a committed replica
    -- that never runs Entity::Update, across cached and refreshed render frames.
    for _ = 1, 60 do
        p.bridge.commit()
        assert(describable(replica), "EID rejected a stable zero-age replica")
    end
    assert(replica.data.EID_DescribeOnFirstFrame == nil, "Adapter changed upstream entity data")
    replica.data.__isaac_lan_replica = nil
    assert(not describable(replica), "EID changed a native entity's first-frame rule")
    replica.data.__isaac_lan_replica = 7
    p.ready = 0
    assert(not describable(replica), "EID exposed an uncommitted replica")
    p.ready = 1
    replica.data.EID_DescribeOnFirstFrame = false
    assert(describable(replica) == false, "Adapter replaced an explicit EID entity setting")
    replica.data.EID_DescribeOnFirstFrame = nil
    replica.data.EID_Description = "custom"
    assert(eid:getEntityData(replica, "EID_Description") == "custom")
    assert(eid:getEntityData(nil, "EID_DescribeOnFirstFrame") == nil)
    assert(eid:getEntityData({ grid = true }, "EID_DescribeOnFirstFrame") == nil)
    -- The native spatial index can omit visible replicas or alternate between
    -- stale and current contents. Exercise the actual EID radius-query path.
    p.env.EntityPartition = { FAMILIAR = 1, ENEMY = 2, PICKUP = 4, PLAYER = 8 }
    local function pickup(id, distance, kind)
        return {
            hash = id,
            Type = kind or 5,
            FrameCount = 0,
            Position = {
                DistanceSquared = function()
                    return distance * distance
                end,
            },
            GetData = function()
                return { __isaac_lan_replica = id }
            end,
            Exists = function()
                return true
            end,
            IsEnemy = function()
                return false
            end,
        }
    end
    local near, far, effect = pickup(71, 60), pickup(72, 81), pickup(73, 20, 1000)
    local roomEntities, indexed = { near, far, effect }, false
    p.env.Isaac.GetRoomEntities = function()
        assert(p.scope == 1, "EID radius fallback left the local view")
        return roomEntities
    end
    local nativeFind = function()
        return indexed and { near } or {}
    end
    p.env.Isaac.FindInRadius = nativeFind
    local originalRender = callbacks[2]
    eid:AddCallback(2, function()
        local found = p.env.Isaac.FindInRadius({}, 80, 15)
        assert(#found == 1 and found[1] == roomEntities[1], "EID lost or duplicated a replica")
        if not indexed then
            assert(#p.env.Isaac.FindInRadius({}, 80, 4) == 0, "Unrelated query was replaced")
        end
        return 7, nil, "rendered"
    end)
    for frame = 1, 60 do
        indexed = frame % 2 == 0
        p.bridge.commit()
        local value, gap, tail = callbacks[2](eid)
        assert(value == 7 and gap == nil and tail == "rendered")
        assert(p.env.Isaac.FindInRadius == nativeFind, "Radius override escaped EID rendering")
    end
    indexed, roomEntities = false, { pickup(74, 80) }
    p.positions["1"].index = 70
    p.epoch = p.epoch + 1
    p.bridge.commit()
    callbacks[2](eid)
    eid:AddCallback(2, function()
        error("EID render failure")
    end)
    rejects(function()
        callbacks[2](eid)
    end)
    assert(p.env.Isaac.FindInRadius == nativeFind, "Radius override survived a render error")
    callbacks[2] = originalRender
    p.positions["1"].index = 71
    p.bridge.commit()
    eid:setPlayer()
    assert(eid.player == actor2, "EID retained the other room's actor")
    local entries, updates, previous = 0, 0, nil
    eid:AddCallback(p.env.ModCallbacks.MC_POST_NEW_ROOM, function(self, marker, gap, tail)
        assert(self == eid and marker == 12 and gap == nil and tail == "entry")
        assert(p.scope == 1 and self.player == actor2, "Deferred EID entry used the remote room")
        previous = { player = self.player }
        entries = entries + 1
    end)
    eid:AddCallback(p.env.ModCallbacks.MC_POST_UPDATE, function()
        updates = updates + 1
    end)
    p.ready, p.epoch = 0, p.epoch + 1
    callbacks[19](eid, 11, nil, "old")
    callbacks[19](eid, 12, nil, "entry")
    callbacks[1](eid)
    p.bridge.commit()
    assert(entries == 0 and updates == 0 and previous == nil)
    p.ready = 1
    p.bridge.commit()
    assert(entries == 1 and previous.player == actor2, "Rewind lost EID's native entry cache")
    p.bridge.commit()
    assert(entries == 1 and updates == 0, "EID replayed an entry or stale update twice")
    -- Returning from LAN clears its cached view, then a native continued game
    -- and render callback must recover player zero without readiness checks.
    local continuedGames = 0
    eid:AddCallback(15, function(self, continued)
        assert(self == eid and continued == true and p.scope == nil)
        self:setPlayer()
        assert(self.player == actor1, "Continued solo game retained the LAN player")
        continuedGames = continuedGames + 1
        return "continued"
    end)
    p.active, p.ready = 0, 0
    p.bridge.poll()
    assert(not describable(replica), "EID replica override survived leaving LAN")
    assert(callbacks[15](eid, true) == "continued" and continuedGames == 1)
    assert(callbacks[2](eid, 2, nil, "solo") == 2 and soloCalls[2] == 2)
    assert(p.api:SetAdapterEnabled(adapter.id, false))
    assert(eid.getEntityData == originalGetEntityData, "EID method was not restored on uninstall")
    eid.ModVersion = 0
    assert(adapter.probe({ mod = eid, metadataVersion = build[1] }) == "ready")
    eid.getEntityData = nil
    assert(adapter.probe({ mod = eid, metadataVersion = build[1] }) == "pending")
end
-- Stats+ may have cached both native actors before the LAN viewport was ready.
do
    local p = peer(1)
    p.modInfo = {
        workshopId = "2729900570",
        metadataVersion = "2.1.3",
        sourceHash = "f9bce56542b60f8f0291cf1fb6d85c059c87f841e1efa7b82ecef794e4a3bab2",
        directory = "stats",
    }
    local mod = {
        Name = "stats-plus",
        AddCallback = function() end,
        AddPriorityCallback = function() end,
        RemoveCallback = function() end,
    }
    local players = { { entityPlayer = actor1, index = 0 }, { entityPlayer = actor2, index = 1 } }
    local playerClass = {
        prototype = {
            getAllEntityPlayers = function()
                return { actor1, actor2 }
            end,
            getPlayers = function()
                return players
            end,
        },
    }
    local service = setmetatable({}, { __index = playerClass.prototype })
    local apiClass = {
        prototype = {
            provider = function(_, provider)
                return provider
            end,
        },
    }
    local updates, reloads = 0, 0
    local watcherClass = { prototype = { updatePlayer = function() end } }
    local watcher = {
        updatePlayer = function(_, player)
            assert(
                p.env.GetPtrHash(player.entityPlayer) == p.env.GetPtrHash(actor2),
                "Stats watcher updated a teammate"
            )
            updates = updates + 1
        end,
    }
    local lifecycleClass = {}
    local lifecycle = {
        reloadAll = function()
            reloads = reloads + 1
            players = {}
            for i, actor in ipairs(service:getAllEntityPlayers()) do
                players[i] = { entityPlayer = actor, index = i - 1 }
            end
        end,
    }
    local container = {
        resolve = function(_, class)
            return class == playerClass and service
                or class == watcherClass and watcher
                or lifecycle
        end,
    }
    assert(loadfile(root .. "/src/bridge/compat/mods/stats_plus.lua", "t", p.env))()
    local r = p.env._IsaacLanModules["compat/mods/registry"]
    r.observeRequire("stats-source", "services.PlayerService", { PlayerService = playerClass })
    r.observeRequire("stats-source", "services.extension.API", { API = apiClass })
    r.observeRequire(
        "stats-source",
        "services.stat.StatValueWatcher",
        { StatValueWatcher = watcherClass }
    )
    r.observeMod(mod, "stats-source")
    r.poll()
    assert(r.status()[1].state == "pending", "Stats adapter captured missing lifecycle exports")
    r.observeRequire(
        "stats-source",
        "app.APPLICATION_CONTAINER",
        { APPLICATION_CONTAINER = container }
    )
    r.observeRequire(
        "stats-source",
        "services.LifecycleService",
        { LifecycleService = lifecycleClass }
    )
    r.poll()
    p.bridge.commit()
    assert(reloads == 1 and updates == 1 and #service:getPlayers() == 1)
    assert(service:getPlayers()[1].entityPlayer == actor2 and service:getPlayers()[1].index == 0)
    players = { { entityPlayer = actor1, index = 0 }, { entityPlayer = actor2, index = 1 } }
    assert(#service:getPlayers() == 1, "Stats rendered a stale teammate multiplier")
    p.bridge.commit()
    assert(
        reloads == 2 and service:getPlayers()[1].index == 0,
        "Stats did not rebuild stale provider caches"
    )
    p.bridge.commit()
    assert(reloads == 2, "Unchanged Stats cache was rebuilt every snapshot")
    players[1].entityPlayer = setmetatable({}, { __index = actor2 })
    p.bridge.commit()
    assert(reloads == 2, "A fresh Lua wrapper rebuilt the same native player's cache")
    p.active = 0
    players = { { entityPlayer = actor1, index = 0 }, { entityPlayer = actor2, index = 1 } }
    assert(#service:getPlayers() == 2, "Stats adapter changed inactive native co-op")
end
-- Goodtrip's native callbacks can arrive after its cached actor was cleared
-- during loading, while the committed view and lifecycle identity are unchanged.
do
    local p = peer(1)
    p.env.ModCallbacks = {
        MC_POST_RENDER = 2,
        MC_POST_UPDATE = 1,
        MC_POST_NEW_ROOM = 19,
        MC_POST_NEW_LEVEL = 18,
        MC_POST_GAME_STARTED = 15,
    }
    p.modInfo = {
        workshopId = "1630477831",
        metadataVersion = "1.2.8",
        sourceHash = "57a2525436aac726053e9f465667090a9b4a68e150c19285a51dc035a6397858",
        directory = "goodtrip",
    }
    local id = "isaac-lan.compat.goodtrip"
    local lan = p.api:Attach({}, id)
    p.env._IsaacLanModules["compat/mods/goodtrip/authority"] = {
        id = id,
        integration = lan,
        install = function()
            return function() end
        end,
    }
    local callbacks, player, preparations = {}, nil, 0
    local gt = {
        Name = "goodtrip",
        AddCallback = function(_, cb, fn)
            callbacks[cb] = fn
        end,
        AddPriorityCallback = function() end,
        RemoveCallback = function() end,
        teleport_to_grid_index = function() end,
        tab_action = function() end,
        prep = function()
            player = p.env.Isaac.GetPlayer(0)
            preparations = preparations + 1
        end,
        new_room = function() end,
        new_level = function() end,
        step = function()
            if p.active == 1 then
                assert(
                    p.scope == 1 and player == actor2,
                    "Goodtrip rendered a missing or remote actor"
                )
            else
                assert(
                    p.scope == nil and player == actor1,
                    "Goodtrip retained a missing LAN actor after disconnect"
                )
            end
        end,
    }
    p.env.gt = gt
    assert(loadfile(root .. "/src/bridge/compat/mods/goodtrip/client.lua", "t", p.env))()
    p.env._IsaacLanModules["compat/mods/registry"].observeMod(gt, "goodtrip-source")
    gt:AddCallback(p.env.ModCallbacks.MC_POST_RENDER, gt.step)
    p.bridge.commit()
    player = nil
    local before = preparations
    callbacks[2](gt)
    assert(preparations == before + 1, "Goodtrip did not repair its loading-time actor cache")
    callbacks[2](gt)
    assert(preparations == before + 1, "Goodtrip rebuilt a valid cache every render")
    player = actor1
    callbacks[2](gt)
    assert(player == actor2 and preparations == before + 2)
    p.ready = 0
    player = nil
    callbacks[2](gt)
    assert(player == nil and not lan:IsReady(), "Uncommitted Goodtrip viewport accessed an actor")
    -- A disconnect before the first viewport commit must restore ordinary UI,
    -- even though the skipped game-start callback never prepared this cache.
    p.active = 0
    callbacks[2](gt)
    assert(player == actor1, "Partial LAN startup left the native Goodtrip UI uninitialized")
end
print("PASS bridge codec, views, lifecycle, action authority, receipts, dedupe and compatibility")
