local modules, native = assert(_IsaacLanModules), assert(_IsaacLan)
local bridge = { handles = {}, modHandles = {}, context = nil, players = {}, identities = {} }
local api = { API_VERSION = 1 }
bridge.api = api
function bridge.log(message)
    Isaac.DebugString("ISAAC_LAN integration " .. message)
end
function bridge.copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = bridge.copy(item)
    end
    return result
end
function bridge.info()
    return native.api_info()
end
function bridge.active()
    return bridge.info().active == 1
end
function bridge.ready()
    local info = bridge.info()
    return bridge.context ~= nil
        and info.ready == 1
        and bridge.context.runId == info.runId
        and bridge.context.worldEpoch == info.worldEpoch
end
function bridge.withView(fn)
    assert(type(fn) == "function", "invalid_view_function")
    if not bridge.ready() then
        return nil, "view_not_ready"
    end
    local result
    native.api_with_local_view(function()
        result = table.pack(fn())
    end)
    return table.unpack(result, 1, result.n)
end
bridge.lifecycle = modules["api/lifecycle"](bridge)
bridge.actions = modules["api/actions"](bridge)
local methods = {}
local function registered(handle)
    return bridge.handles[handle.id] == handle
end
function methods:IsActive()
    return bridge.active()
end
function methods:IsReady()
    return bridge.ready()
end
function methods:IsAuthority()
    return bridge.info().authority == 1
end
function methods:GetLocalPlayers()
    local result = {}
    if bridge.ready() then
        for i, player in ipairs(bridge.players) do
            result[i] = player
        end
    end
    return result
end
local function identity(player)
    if not bridge.ready() or not player then
        return nil
    end
    local ok, hash = pcall(GetPtrHash, player)
    return ok and bridge.identities[hash] or nil
end
function methods:GetOwnerId(player)
    local id = identity(player)
    return id and id.owner
end
function methods:GetPlayerId(player)
    local id = identity(player)
    return id and id.id
end
function methods:GetLocalRoom()
    return bridge.ready() and bridge.copy(bridge.context.room) or nil
end
function methods:GetContext()
    return bridge.ready() and bridge.copy(bridge.context) or nil
end
function methods:WithLocalView(fn)
    return bridge.withView(fn)
end
function methods:On(event, fn)
    assert(registered(self), "integration_unregistered")
    return bridge.lifecycle.on(self.id, event, fn)
end
function methods:RegisterAction(name, definition)
    assert(registered(self), "integration_unregistered")
    return bridge.actions.register(self.id, name, definition)
end
function methods:HasHostAction(name, version)
    return registered(self) and bridge.actions.has(self.id, name, version)
end
function methods:RequestAction(name, payload, fn)
    if not registered(self) then
        return nil, "integration_unregistered"
    end
    return bridge.actions.request(self.id, name, payload, fn)
end
function methods:CreateOperation(definition)
    assert(registered(self), "integration_unregistered")
    return bridge.actions.operation(definition)
end
function methods:MovePlayer(context, destination)
    if not registered(self) then
        return nil, "integration_unregistered"
    end
    return bridge.actions.move(context, destination)
end
function methods:Unregister()
    if bridge.handles[self.id] ~= self then
        return
    end
    bridge.lifecycle.remove(self.id)
    bridge.actions.remove(self.id)
    bridge.handles[self.id] = nil
    if bridge.modHandles[self.mod] == self then
        bridge.modHandles[self.mod] = nil
    end
end
local function register(mod, options, builtin)
    assert(type(mod) == "table" and type(options) == "table", "invalid_registration")
    assert(
        type(options.id) == "string" and #options.id <= 64 and options.id:match("^[%w_.%-]+$"),
        "invalid_integration_id"
    )
    assert(
        math.type(options.integrationVersion) == "integer" and options.integrationVersion >= 1,
        "invalid_integration_version"
    )
    if
        not builtin
        and bridge.modHandles[mod]
        and bridge.modHandles[mod].builtin
        and bridge.registry
    then
        bridge.registry.nativeIntegration(mod)
    end
    local existing = bridge.handles[options.id]
    if existing then
        assert(
            existing.mod == mod and existing.integrationVersion == options.integrationVersion,
            "duplicate_integration_id"
        )
        return existing
    end
    assert(not bridge.modHandles[mod], "mod_already_registered")
    local handle = setmetatable({
        id = options.id,
        mod = mod,
        integrationVersion = options.integrationVersion,
        builtin = builtin,
    }, { __index = methods })
    bridge.handles[handle.id], bridge.modHandles[mod] = handle, handle
    local installing = bridge.compatibilityInstalling
    if builtin and installing and installing.target.mod == mod then
        installing.target.addCleanup(function()
            handle:Unregister()
        end)
    end
    if not builtin and bridge.registry then
        bridge.registry.nativeIntegration(mod)
    end
    return handle
end
function api:RegisterMod(mod, options)
    local installing = bridge.compatibilityInstalling
    return register(mod, options, installing ~= nil and installing.target.mod == mod)
end
function api:RegisterCompatibility(definition)
    return bridge.registry.register(definition)
end
function api:GetCompatibilityStatus()
    return bridge.registry.status()
end
function api:SetCompatibilityEnabled(id, enabled)
    return bridge.registry.enable(id, enabled)
end
function api:SetActionEnabled(id, name, enabled)
    return bridge.actions.enable(id, name, enabled)
end
function bridge.reset(reason)
    if bridge.context then
        local context = bridge.copy(bridge.context)
        context.reason = reason
        bridge.context, bridge.players, bridge.identities = nil, {}, {}
        bridge.actions.reset(reason)
        bridge.lifecycle.emit("StateReset", context)
    end
end
function bridge.commit()
    local info = bridge.info()
    if info.ready ~= 1 then
        return
    end
    local previous = bridge.context
    if previous and (previous.runId ~= info.runId or previous.worldEpoch ~= info.worldEpoch) then
        bridge.reset(previous.runId ~= info.runId and "new_run" or "world_rebuilt")
        previous = nil
    end
    local players, identities, signature = {}, {}, {}
    -- This entry is called after native room/roster scopes have been restored.
    for _, actor in ipairs(native.api_actors()) do
        local player = Isaac.GetPlayer(actor.index)
        local id = "p" .. actor.owner .. ":" .. actor.role
        local hash = GetPtrHash(player)
        identities[hash] = { owner = actor.owner, id = id }
        if actor.owner == info.slot + 1 then
            players[#players + 1] = player
            signature[#signature + 1] = id .. ":" .. hash .. ":" .. player:GetPlayerType()
        end
    end
    if #players == 0 then
        return
    end
    local position = native.rooms_positions()[tostring(info.slot)]
    if not position then
        return
    end
    bridge.players, bridge.identities = players, identities
    local room = {
        runId = info.runId,
        worldEpoch = info.worldEpoch,
        index = position.index,
        dimension = position.dimension,
    }
    local context = {
        runId = info.runId,
        worldEpoch = info.worldEpoch,
        tick = info.tick,
        revision = previous and previous.revision + 1 or 1,
        room = room,
        playerSignature = table.concat(signature, ","),
    }
    bridge.context = context
    bridge.actions.commit()
    if not previous or context.playerSignature ~= previous.playerSignature then
        bridge.lifecycle.emit("LocalPlayersChanged", context)
    end
    if
        not previous
        or room.index ~= previous.room.index
        or room.dimension ~= previous.room.dimension
    then
        bridge.lifecycle.emit("LocalRoomChanged", context)
    end
    bridge.lifecycle.emit("ViewUpdated", context)
    if not previous then
        bridge.lifecycle.emit("SessionReady", context)
    end
end
function bridge.poll()
    local info = bridge.info()
    if info.active ~= 1 then
        bridge.reset("session_ended")
    elseif bridge.context and info.worldEpoch ~= bridge.context.worldEpoch then
        bridge.reset("world_rebuilt")
    end
    bridge.registry.poll()
    bridge.actions.poll()
end
_G.IsaacLAN = api
return bridge
