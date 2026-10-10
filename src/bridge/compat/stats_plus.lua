local bridge = _IsaacLanModules["api/public"]
local wrapping = _IsaacLanModules["compat/wrapping"]
local definition = {
    id = "isaac-lan.compat.stats-plus",
    adapterVersion = 1,
    modName = "stats-plus",
    targets = {
        {
            workshopId = "2729900570",
            metadataVersion = "2.1.3",
            sourceHash = "f9bce56542b60f8f0291cf1fb6d85c059c87f841e1efa7b82ecef794e4a3bab2",
        },
    },
}
local function exported(target, path, name)
    local module = target.modules[path]
    return type(module) == "table" and module[name]
end
function definition.probe(target)
    local playerClass = exported(target, "services.PlayerService", "PlayerService")
    local apiClass = exported(target, "services.extension.API", "API")
    local watcher = exported(target, "services.stat.StatValueWatcher", "StatValueWatcher")
    local container = exported(target, "app.APPLICATION_CONTAINER", "APPLICATION_CONTAINER")
    local lifecycle = exported(target, "services.LifecycleService", "LifecycleService")
    if not playerClass or not apiClass or not watcher or not container or not lifecycle then
        return "pending", "services_not_loaded"
    end
    if
        type(playerClass.prototype.getAllEntityPlayers) ~= "function"
        or type(playerClass.prototype.getPlayers) ~= "function"
        or type(apiClass.prototype.provider) ~= "function"
        or type(watcher.prototype.updatePlayer) ~= "function"
    then
        return "unsupported", "service_contract_mismatch"
    end
    return "ready"
end
function definition.install(target, api)
    local cleanups = {}
    target.addCleanup(function()
        wrapping.cleanup(cleanups)
    end)
    local lan = api:RegisterMod(target.mod, { id = definition.id, integrationVersion = 1 })
    local playerClass = exported(target, "services.PlayerService", "PlayerService")
    local apiClass = exported(target, "services.extension.API", "API")
    local cachedPlayers = playerClass.prototype.getPlayers
    wrapping.patch(cleanups, playerClass.prototype, "getPlayers", function(original)
        return function(service, ...)
            local players = original(service, ...)
            if not lan:IsActive() then
                return players
            end
            local localPlayers = {}
            for _, player in ipairs(players) do
                if lan:GetOwnerId(player.entityPlayer) == bridge.info().slot + 1 then
                    localPlayers[#localPlayers + 1] = player
                end
            end
            return localPlayers
        end
    end)
    wrapping.patch(cleanups, playerClass.prototype, "getAllEntityPlayers", function(original)
        return function(service, ...)
            if lan:IsActive() then
                return lan:GetLocalPlayers()
            end
            return original(service, ...)
        end
    end)
    wrapping.patch(cleanups, apiClass.prototype, "provider", function(original)
        return function(service, provider)
            if provider.id == "tear-cap-provider" then
                local compute = provider.computables.computeTearCap
                provider.computables.computeTearCap = function(self, ...)
                    if bridge.registry.isEnabled(definition.id) and lan:IsActive() then
                        return "UNKNOWN"
                    end
                    return compute(self, ...)
                end
            elseif provider.id == "d8-multiplier-provider" then
                local format = provider.display.value.format
                provider.display.value.format = function(...)
                    if bridge.registry.isEnabled(definition.id) and lan:IsActive() then
                        return nil
                    end
                    return format(...)
                end
            end
            return original(service, provider)
        end
    end)
    local container = exported(target, "app.APPLICATION_CONTAINER", "APPLICATION_CONTAINER")
    local lifecycleClass = exported(target, "services.LifecycleService", "LifecycleService")
    local watcherClass = exported(target, "services.stat.StatValueWatcher", "StatValueWatcher")
    local dirty = true
    cleanups[#cleanups + 1] = lan:On("StateReset", function()
        dirty = true
    end)
    cleanups[#cleanups + 1] = lan:On("LocalPlayersChanged", function()
        dirty = true
    end)
    cleanups[#cleanups + 1] = lan:On("ViewUpdated", function()
        assert(container and lifecycleClass, "stats_container_unavailable")
        local service = container:resolve(playerClass)
        local current = cachedPlayers(service)
        local expected = lan:GetLocalPlayers()
        if #current ~= #expected then
            dirty = true
        else
            for i, player in ipairs(current) do
                if
                    player.index ~= i - 1
                    or GetPtrHash(player.entityPlayer) ~= GetPtrHash(expected[i])
                then
                    dirty = true
                    break
                end
            end
        end
        if dirty then
            container:resolve(lifecycleClass):reloadAll()
            dirty = false
        end
        -- Native snapshots don't replay evaluate-cache callbacks on replicas.
        local watcher = container:resolve(watcherClass)
        for _, player in ipairs(service:getPlayers()) do
            watcher:updatePlayer(player)
        end
    end)
    return function()
        wrapping.cleanup(cleanups)
        lan:Unregister()
    end
end
function definition.dispatch(target, record, ...)
    local lan = bridge.handles[definition.id]
    if not lan or not lan:IsActive() then
        return record.original(...)
    end
    local callbacks = ModCallbacks
    if record.id == callbacks.MC_EVALUATE_CACHE then
        local args = table.pack(...)
        if lan:GetOwnerId(args[2]) ~= bridge.info().slot + 1 then
            return
        end
    end
    if
        record.id == callbacks.MC_POST_RENDER
        or record.id == callbacks.MC_POST_UPDATE
        or record.id == callbacks.MC_EVALUATE_CACHE
        or record.id == callbacks.MC_POST_PLAYER_INIT
        or record.id == callbacks.MC_POST_GAME_STARTED
    then
        if not lan:IsReady() then
            return
        end
        local args = table.pack(...)
        return lan:WithLocalView(function()
            return record.original(table.unpack(args, 1, args.n))
        end)
    end
    return record.original(...)
end
bridge.api:RegisterCompatibility(definition)
return definition
