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
local h = host.api:RegisterMod({}, { id = "test.travel", integrationVersion = 1 })
local g = guest.api:RegisterMod({}, { id = "test.travel", integrationVersion = 1 })
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
assert(host.api:RegisterMod(h.mod, { id = "test.travel", integrationVersion = 1 }) == h)
rejects(function()
    host.api:RegisterMod({}, { id = "test.travel", integrationVersion = 1 })
end)
local executions = 0
local unregister = h:RegisterAction("move", {
    version = 1,
    cooldownTicks = 1,
    validate = function(payload)
        return type(payload) == "table" and payload.index == 71
    end,
    execute = function(context, payload)
        assert(context.ownerId == 2 and context.player == actor2 and host.scope == 1)
        executions = executions + 1
        local operation = assert(h:MovePlayer(context, { index = payload.index, dimension = 0 }))
        local poll = operation.poll
        operation.poll = function()
            assert(host.scope == 1, "Operation polled in another participant's room")
            return poll()
        end
        return operation
    end,
})
rejects(function()
    h:RegisterAction("move", { version = 1, validate = function() end, execute = function() end })
end)
host.bridge.actions.poll()
guest.bridge.actions.poll()
assert(g:HasHostAction("move", 1) and not g:HasHostAction("move", 2))
local results = {}
local requestId = assert(g:RequestAction("move", { index = 71, forgedOwner = 1 }, function(result)
    results[#results + 1] = result
end))
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
assert(#results == 1 and results[1].status == "applied" and results[1].requestId == requestId)
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
assert(g:RequestAction("move", { index = 71 }, function(result)
    results[#results + 1] = result
end))
host.bridge.actions.step()
guest.bridge.actions.poll()
assert(results[#results].code == "source_changed" and executions == 1)
host.api:SetActionEnabled("test.travel", "move", false)
host.bridge.actions.poll()
guest.bridge.actions.poll()
assert(not g:HasHostAction("move", 1))
local unavailable, code = g:RequestAction("move", { index = 71 })
assert(not unavailable and code == "action_unavailable")
host.api:SetActionEnabled("test.travel", "move", true)
host.positions["1"].index = 84
host.tick = 20
host.bridge.actions.poll()
guest.bridge.actions.poll()
local unknown
assert(g:RequestAction("move", { index = 71 }, function(result)
    unknown = result
end))
guest.now = 5001
guest.bridge.actions.poll()
assert(unknown.status == "unknown" and unknown.code == "timeout" and executions == 1)
guest.epoch = 1
guest.bridge.commit()
assert(g:GetContext().worldEpoch == 1 and order[#order] == "SessionReady")
guest.active, guest.ready = 0, 0
guest.bridge.poll()
assert(not g:IsActive() and #g:GetLocalPlayers() == 0 and g:GetLocalRoom() == nil)
local echo = h:RegisterAction("echo", {
    version = 1,
    validate = function(value)
        return value == true
    end,
    execute = function(context)
        assert(context.ownerId == 1 and context.player == actor1)
        return { status = "applied", code = "echo" }
    end,
})
local echoed
assert(h:RequestAction("echo", true, function(result)
    echoed = result
end))
host.bridge.actions.step()
host.bridge.commit()
assert(echoed and echoed.status == "applied", "Host bypassed shared request processing")
echo()
local longId, longName = string.rep("i", 64), string.rep("a", 32)
local longHost = host.api:RegisterMod({}, { id = longId, integrationVersion = 1 })
local longGuest = guest.api:RegisterMod({}, { id = longId, integrationVersion = 1 })
longHost:RegisterAction(longName, {
    version = 2,
    validate = function()
        return true
    end,
    execute = function()
        return { status = "applied", code = "long" }
    end,
})
guest.active, guest.ready, guest.epoch = 1, 1, 0
guest.bridge.commit()
host.bridge.actions.poll()
guest.bridge.actions.poll()
assert(longGuest:HasHostAction(longName, 2), "Allowed long namespace failed capability encoding")
longHost:Unregister()
longGuest:Unregister()
local replacement = host.api:RegisterMod({}, { id = longId, integrationVersion = 1 })
rejects(function()
    longHost:On("ViewUpdated", function() end)
end)
rejects(function()
    longHost:RegisterAction("stale", {
        version = 1,
        validate = function()
            return true
        end,
        execute = function()
            return { status = "applied" }
        end,
    })
end)
local staleRequest, staleCode = longHost:RequestAction("stale", true)
assert(not staleRequest and staleCode == "integration_unregistered")
longHost:Unregister()
assert(host.bridge.handles[longId] == replacement)
replacement:Unregister()
unregister()
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
local wrapping = host.env._IsaacLanModules["compat/wrapping"]
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
        compatibilityHandle = api:RegisterMod(target.mod, {
            id = "test.compat.handle",
            integrationVersion = 1,
        })
        return function()
            cleanupCount = cleanupCount + 1
            compatibilityHandle:Unregister()
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
isolated.api:SetCompatibilityEnabled("test.compat", false)
assert(cleanupCount == 1)
isolated.api:SetCompatibilityEnabled("test.compat", true)
assert(installs == 2)
isolated.api:RegisterMod(mod, { id = "native.test", integrationVersion = 1 })
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
        api:RegisterMod(target.mod, { id = "test.late.handle", integrationVersion = 1 })
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
isolated.api:SetCompatibilityEnabled("test.authority-error", false)
local enabled, enableCode = isolated.api:SetCompatibilityEnabled("test.authority-error", true)
assert(not enabled and enableCode == "authority_install_failed" and authorityAttempts == 2)
-- Both pinned EID builds select the guest from its local view, including after
-- a room notification. A metadata/runtime mismatch must keep the adapter off.
for _, build in ipairs({
    { "5.23", 5.24, "980bb0b", "8f2614a6a4cd58d60345dd0a33072a0bc7822ecf06ad9106234a6a9b2380b3fc" },
    { "5.24", 5.25, "d7aab88", "705a61422ffc09c683d4250dedf2a569b6d76d4eee884dec70b705eedfa898f5" },
}) do
    local p = peer(1)
    p.modInfo = {
        workshopId = "836319872",
        metadataVersion = build[1],
        sourceHash = build[4],
        directory = "eid",
    }
    local eid = {
        Name = "External Item Descriptions",
        ModVersion = build[2],
        ModVersionCommit = build[3],
        OnRender = function() end,
        AddCallback = function() end,
        AddPriorityCallback = function() end,
        RemoveCallback = function() end,
        setPlayer = function(self)
            self.player = p.env.Isaac.GetPlayer(0)
        end,
    }
    p.env.EID = eid
    local adapter = assert(loadfile(root .. "/src/bridge/compat/eid.lua", "t", p.env))()
    local r = p.env._IsaacLanModules["compat/registry"]
    r.observeMod(eid, "eid-source")
    r.poll()
    assert(r.status()[1].state == "active", "Supported EID adapter was not installed")
    p.bridge.commit()
    eid:setPlayer()
    assert(eid.player == actor2 and p.scope == nil, "EID selected a remote actor")
    p.positions["1"].index = 71
    p.bridge.commit()
    eid:setPlayer()
    assert(eid.player == actor2, "EID retained the other room's actor")
    eid.ModVersion = 0
    assert(adapter.probe({ mod = eid, metadataVersion = build[1] }) == "unsupported")
end
print("PASS bridge codec, views, lifecycle, action authority, receipts, dedupe and compatibility")
