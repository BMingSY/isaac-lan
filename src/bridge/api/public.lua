local modules, native = assert(_IsaacLanModules), assert(_IsaacLan)
local bridge = { handles = {}, modHandles = {}, context = nil, players = {}, identities = {} }
local api = { API_VERSION = 2 }
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
local sdk = assert(modules["api/sdk"])
local function identity(player)
    if not bridge.ready() or not player then
        return nil
    end
    local ok, hash = pcall(GetPtrHash, player)
    return ok and bridge.identities[hash] or nil
end
function bridge.actor(ownerId, playerId)
    for _, actor in ipairs(native.api_actors()) do
        if actor.owner == ownerId and "p" .. actor.owner .. ":" .. actor.role == playerId then
            return Isaac.GetPlayer(actor.index)
        end
    end
end
function api:Attach(mod, id)
    assert(
        type(mod) == "table" and type(id) == "string" and #id <= 64 and id:match("^[%w_.%-]+$"),
        "invalid_registration"
    )
    local installing = bridge.compatibilityInstalling
    local builtin = installing ~= nil and installing.target.mod == mod
    if
        not builtin
        and bridge.modHandles[mod]
        and bridge.modHandles[mod].builtin
        and bridge.registry
    then
        bridge.registry.nativeIntegration(mod)
    end
    local existing = bridge.handles[id]
    if existing then
        assert(existing.mod == mod, "duplicate_integration_id")
        return existing
    end
    assert(not bridge.modHandles[mod], "mod_already_registered")
    local handle
    handle = sdk.create(mod, id, {
        active = bridge.active,
        solo = function()
            return bridge.info().networked == 0
        end,
        ready = bridge.ready,
        authority = function()
            return bridge.info().authority == 1
        end,
        view = function()
            if not bridge.ready() then
                return nil
            end
            local value = bridge.copy(bridge.context)
            value.players = {}
            for index, player in ipairs(bridge.players) do
                value.players[index] = player
            end
            value.ownerId, value.networked = bridge.info().slot + 1, true
            return value
        end,
        owner = function(player)
            local value = identity(player)
            return value and value.owner
        end,
        playerId = function(player)
            local value = identity(player)
            return value and value.id
        end,
        withView = bridge.withView,
        on = function(event, fn)
            return bridge.lifecycle.on(id, event, fn)
        end,
        register = function(name, definition)
            return bridge.actions.register(id, name, definition)
        end,
        has = function(name, version)
            return bridge.actions.has(id, name, version)
        end,
        request = function(name, version, payload, playerId, fn)
            return bridge.actions.request(id, name, version, payload, playerId, fn)
        end,
        close = function()
            bridge.lifecycle.remove(id)
            bridge.actions.remove(id)
            if bridge.handles[id] == handle then
                bridge.handles[id] = nil
            end
            if bridge.modHandles[mod] == handle then
                bridge.modHandles[mod] = nil
            end
        end,
    })
    handle.builtin = builtin
    bridge.handles[id], bridge.modHandles[mod] = handle, handle
    if builtin then
        installing.target.addCleanup(function()
            handle:Close()
        end)
    elseif bridge.registry then
        bridge.registry.nativeIntegration(mod)
    end
    return handle
end
function api:RegisterAdapter(definition)
    return bridge.registry.register(definition)
end
function api:GetAdapters()
    return bridge.registry.status()
end
function api:SetAdapterEnabled(id, enabled)
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
