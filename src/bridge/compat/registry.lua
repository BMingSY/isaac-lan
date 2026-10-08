local bridge = assert(_IsaacLanModules)["api/public"]
local native, wrapping = assert(_IsaacLan), _IsaacLanModules["compat/wrapping"]
local registry = {}
bridge.registry = registry
local definitions, targets, exports, sourceCache = {}, {}, {}, {}
local function identify(source)
    if not sourceCache[source] then
        sourceCache[source] = native.api_mod_info(source) or false
    end
    return sourceCache[source] or nil
end
local function setState(entry, state, reason)
    if entry.state ~= state or entry.reason ~= reason then
        bridge.log(
            entry.definition.id
                .. " state="
                .. state
                .. " reason="
                .. (reason or "")
                .. (entry.target and " source=" .. entry.target.sourceHash or "")
        )
    end
    entry.state, entry.reason = state, reason
end
local function match(definition, target)
    for _, candidate in ipairs(definition.targets) do
        if
            candidate.workshopId == target.workshopId
            and candidate.metadataVersion == target.metadataVersion
            and candidate.sourceHash == target.sourceHash
        then
            return true
        end
    end
    return false
end
local function uninstall(entry)
    if entry.cleanup then
        local ok, reason = pcall(entry.cleanup)
        if not ok then
            bridge.log(entry.definition.id .. " cleanup_error=" .. tostring(reason))
        end
        entry.cleanup = nil
    end
end
local function probe(entry)
    if entry.state ~= "pending" or not entry.enabled then
        return
    end
    if bridge.modHandles[entry.target.mod] and not bridge.modHandles[entry.target.mod].builtin then
        setState(entry, "disabled", "native_integration")
        return
    end
    local ok, state, reason = pcall(entry.definition.probe, entry.target)
    if not ok then
        setState(entry, "error", tostring(state))
        return
    end
    if state == "unsupported" then
        setState(entry, state, reason)
        return
    end
    if state ~= "ready" then
        return
    end
    local cleanups = {}
    entry.target.addCleanup = function(fn)
        cleanups[#cleanups + 1] = fn
    end
    local previous = bridge.compatibilityInstalling
    bridge.compatibilityInstalling = entry
    local installed, cleanup = pcall(entry.definition.install, entry.target, bridge.api)
    bridge.compatibilityInstalling = previous
    if installed and type(cleanup) == "function" then
        cleanups[#cleanups + 1] = cleanup
        entry.cleanup = function()
            wrapping.cleanup(cleanups)
        end
        setState(entry, "active", "installed")
    else
        wrapping.cleanup(cleanups)
        setState(entry, "error", installed and "missing_cleanup" or tostring(cleanup))
    end
end
local function attach(entry, target)
    if entry.state == "error" then
        return
    end
    if entry.target then
        if entry.target.mod ~= target.mod then
            setState(entry, "unsupported", "duplicate_target_instance")
        end
        return
    end
    if not entry.enabled then
        setState(entry, "disabled", "configuration")
        return
    end
    if not match(entry.definition, target) then
        setState(entry, "unsupported", "source_or_version_mismatch")
        return
    end
    entry.target = target
    setState(entry, "pending", "initializing")
    if entry.definition.dispatch then
        entry.callbackCleanup = wrapping.callbacks(target, function(record, ...)
            probe(entry)
            if entry.state == "active" and entry.enabled and bridge.active() then
                return entry.definition.dispatch(target, record, ...)
            end
            return record.original(...)
        end)
    end
    probe(entry)
end
function registry.observeMod(mod, source)
    local info = identify(source)
    if not info then
        return
    end
    local target = bridge.copy(info)
    target.mod, target.modules = mod, exports[info.directory] or {}
    exports[info.directory] = target.modules
    targets[#targets + 1] = target
    for _, entry in pairs(definitions) do
        if entry.definition.modName == mod.Name then
            attach(entry, target)
        end
    end
end
function registry.observeRequire(source, name, value)
    local info = identify(source)
    if not info then
        return
    end
    local loaded = exports[info.directory] or {}
    exports[info.directory] = loaded
    loaded[name] = value
end
function registry.register(definition)
    assert(
        type(definition) == "table"
            and type(definition.id) == "string"
            and #definition.id <= 64
            and definition.id:match("^[%w_.%-]+$")
            and math.type(definition.adapterVersion) == "integer"
            and definition.adapterVersion >= 1
            and type(definition.modName) == "string"
            and type(definition.targets) == "table"
            and type(definition.probe) == "function"
            and type(definition.install) == "function",
        "invalid_compatibility_definition"
    )
    assert(not definitions[definition.id], "duplicate_compatibility_id")
    assert(
        (definition.authority == nil or type(definition.authority) == "function")
            and (definition.dispatch == nil or type(definition.dispatch) == "function"),
        "invalid_compatibility_handler"
    )
    for _, target in ipairs(definition.targets) do
        assert(
            type(target.workshopId) == "string"
                and #target.workshopId > 0
                and type(target.metadataVersion) == "string"
                and #target.metadataVersion > 0
                and type(target.sourceHash) == "string"
                and #target.sourceHash == 64
                and target.sourceHash:match("^[%da-f]+$"),
            "invalid_compatibility_target"
        )
    end
    definition = bridge.copy(definition)
    local entry = { definition = definition, enabled = native.api_setting(definition.id) ~= false }
    definitions[definition.id] = entry
    setState(
        entry,
        entry.enabled and "not_detected" or "disabled",
        entry.enabled and "waiting_for_mod" or "configuration"
    )
    if entry.enabled and definition.authority then
        local ok, cleanup = pcall(definition.authority, bridge.api)
        if ok and type(cleanup) == "function" then
            entry.authorityCleanup = cleanup
        else
            setState(entry, "error", tostring(cleanup))
        end
    end
    for _, target in ipairs(targets) do
        if target.mod.Name == definition.modName then
            attach(entry, target)
        end
    end
    return function()
        uninstall(entry)
        if entry.authorityCleanup then
            entry.authorityCleanup()
            entry.authorityCleanup = nil
        end
        entry.enabled = false
        setState(entry, "disabled", "unregistered")
    end
end
function registry.poll()
    for _, entry in pairs(definitions) do
        probe(entry)
    end
end
function registry.nativeIntegration(mod)
    for _, entry in pairs(definitions) do
        if entry.target and entry.target.mod == mod then
            uninstall(entry)
            entry.enabled = false
            setState(entry, "disabled", "native_integration")
        end
    end
end
function registry.enable(id, enabled)
    assert(type(enabled) == "boolean", "invalid_enabled")
    local entry = definitions[id]
    if not entry then
        return false, "compatibility_not_registered"
    end
    if not native.api_setting(id, enabled) then
        return false, "configuration_write_failed"
    end
    if entry.enabled == enabled then
        return true
    end
    entry.enabled = enabled
    if not enabled then
        uninstall(entry)
        if entry.authorityCleanup then
            entry.authorityCleanup()
            entry.authorityCleanup = nil
        end
        setState(entry, "disabled", "configuration")
    else
        setState(entry, entry.target and "pending" or "not_detected", "enabled")
        if entry.definition.authority then
            local ok, cleanup = pcall(entry.definition.authority, bridge.api)
            if not ok or type(cleanup) ~= "function" then
                setState(entry, "error", ok and "missing_authority_cleanup" or tostring(cleanup))
                return false, "authority_install_failed"
            end
            entry.authorityCleanup = cleanup
        end
        if not entry.target then
            for _, target in ipairs(targets) do
                if target.mod.Name == entry.definition.modName then
                    attach(entry, target)
                end
            end
        end
        probe(entry)
    end
    return true
end
function registry.isEnabled(id)
    local entry = definitions[id]
    return entry ~= nil and entry.enabled and entry.state == "active"
end
function registry.status()
    local result = {}
    for id, entry in pairs(definitions) do
        local target = entry.target
        result[#result + 1] = {
            id = id,
            adapterVersion = entry.definition.adapterVersion,
            state = entry.state,
            reason = entry.reason,
            authority = entry.authorityCleanup ~= nil,
            target = target and {
                workshopId = target.workshopId,
                metadataVersion = target.metadataVersion,
                sourceHash = target.sourceHash,
                directory = target.directory,
            } or nil,
        }
    end
    table.sort(result, function(a, b)
        return a.id < b.id
    end)
    return result
end
return registry
