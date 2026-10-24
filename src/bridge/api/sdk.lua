-- This file can also be copied into a third-party Mod and loaded with include().
-- The embedded API and standalone fallback share the same integration facade.
---@class IsaacLANView
---@field players EntityPlayer[] This machine's controlled bodies; refresh after a view reset.
---@field ownerId integer Stable participant ID, starting at 1.
---@field networked boolean
---@field tick integer Authoritative tick in LAN; game frame in solo.
---@field runId? string
---@field worldEpoch? integer
---@field revision? integer Local commit sequence, not a render-frame counter.
---@field room? table LAN room identity: runId, worldEpoch, index, dimension.
---@field playerSignature? string Opaque identity-change marker.
---@class IsaacLANResult
---@field status 'applied'|'rejected'|'cancelled'|'unknown'
---@field code string
---@field data? any Serializable business result; never an entity or function over LAN.
---@field requestId? string
---@class IsaacLANRequest
---@field status 'pending'|'applied'|'rejected'|'cancelled'|'unknown'
---@field id? string
---@field code? string
---@field result? IsaacLANResult
---@class IsaacLANActionContext
---@field player EntityPlayer The selected body, resolved by the authority.
---@field playerId string
---@field ownerId integer
---@field room? table
---@field runId? string
---@field worldEpoch? integer
---@field requestId? string
---@field MoveTo fun(self: IsaacLANActionContext, destination: table): table?, string? LAN only; return the operation from execute.
---@field Wait fun(self: IsaacLANActionContext, definition: table): table LAN only; poll until a final result.
---@class IsaacLANActionDefinition
---@field version? integer Business contract version; defaults to 1.
---@field validate? fun(payload: any): boolean Defaults to accepting nil only.
---@field execute? fun(context: IsaacLANActionContext, payload: any): IsaacLANResult|table
---@field solo? fun(context: IsaacLANActionContext, payload: any): IsaacLANResult Overrides execute outside LAN.
---@field cooldownTicks? integer Host-side per-participant cooldown; defaults to 15.
---@class IsaacLANAction
---@field IsAvailable fun(self: IsaacLANAction): boolean
---@field Request fun(self: IsaacLANAction, payload?: any, options?: {player?: EntityPlayer, onResult?: fun(result: IsaacLANResult)}): IsaacLANRequest
---@field Close fun(self: IsaacLANAction)
---@class IsaacLANHandle
---@field IsAttached fun(self: IsaacLANHandle): boolean
---@field IsActive fun(self: IsaacLANHandle): boolean
---@field IsReady fun(self: IsaacLANHandle): boolean
---@field IsAuthority fun(self: IsaacLANHandle): boolean
---@field View fun(self: IsaacLANHandle): IsaacLANView?
---@field GetLocalPlayers fun(self: IsaacLANHandle): EntityPlayer[]
---@field GetOwnerId fun(self: IsaacLANHandle, player: EntityPlayer): integer?
---@field GetPlayerId fun(self: IsaacLANHandle, player: EntityPlayer): string?
---@field IsLocalPlayer fun(self: IsaacLANHandle, player: EntityPlayer): boolean
---@field GetLocalRoom fun(self: IsaacLANHandle): table?
---@field WithLocalView fun(self: IsaacLANHandle, fn: function): any
---@field On fun(self: IsaacLANHandle, event: string, fn: fun(context: table)): function LAN lifecycle subscription.
---@field OnLocalRender fun(self: IsaacLANHandle, fn: fun(view: IsaacLANView)): function Per-render callback in the local view.
---@field Action fun(self: IsaacLANHandle, name: string, definition?: IsaacLANActionDefinition): IsaacLANAction
---@field Close fun(self: IsaacLANHandle)
local SDK = {}
local soloHandles, soloIds = {}, {}
local function soloView()
    local game, players = Game(), {}
    for index = 0, game:GetNumPlayers() - 1 do
        players[#players + 1] = Isaac.GetPlayer(index)
    end
    if #players == 0 then
        return nil
    end
    return { players = players, ownerId = 1, tick = game:GetFrameCount(), networked = false }
end
local function validId(id)
    return type(id) == "string" and #id <= 64 and id:match("^[%w_.%-]+$")
end
local function noPayload(value)
    return value == nil
end
function SDK.create(mod, id, backend)
    assert(type(mod) == "table" and validId(id), "invalid_registration")
    local handle = { id = id, mod = mod }
    local closed, cleanups, actions = false, {}, {}
    local cleanupSequence = 0
    local function own(cleanup)
        cleanupSequence = cleanupSequence + 1
        local token = cleanupSequence
        local function release()
            if cleanups[token] then
                cleanups[token] = nil
                local fn = cleanup
                cleanup = nil
                fn()
            end
        end
        cleanups[token] = release
        return release
    end
    local function attached()
        assert(not closed, "integration_closed")
    end
    function handle:IsAttached()
        return not closed
    end
    function handle:IsActive()
        return not closed and backend ~= nil and backend.active()
    end
    function handle:IsReady()
        if closed then
            return false
        end
        if self:IsActive() then
            return backend.ready()
        end
        if backend and not backend.solo() then
            return false
        end
        return soloView() ~= nil
    end
    function handle:IsAuthority()
        if closed then
            return false
        end
        if self:IsActive() then
            return backend.authority()
        end
        return not backend or backend.solo()
    end
    function handle:View()
        if closed then
            return nil
        end
        if self:IsActive() then
            return backend.view()
        end
        if backend and not backend.solo() then
            return nil
        end
        return soloView()
    end
    function handle:GetLocalPlayers()
        local view = self:View()
        return view and view.players or {}
    end
    function handle:GetOwnerId(player)
        if self:IsActive() then
            return backend.owner(player)
        end
        for _, value in ipairs(self:GetLocalPlayers()) do
            if value == player then
                return 1
            end
        end
    end
    function handle:IsLocalPlayer(player)
        local view = self:View()
        return view ~= nil and self:GetOwnerId(player) == view.ownerId
    end
    function handle:GetPlayerId(player)
        if self:IsActive() then
            return backend.playerId(player)
        end
        for index, value in ipairs(self:GetLocalPlayers()) do
            if value == player then
                return "p1:" .. index
            end
        end
    end
    function handle:GetLocalRoom()
        local view = self:View()
        return view and view.room
    end
    function handle:WithLocalView(fn)
        assert(type(fn) == "function", "invalid_view_function")
        if not self:IsReady() then
            return nil, "view_not_ready"
        end
        if self:IsActive() then
            return backend.withView(fn)
        end
        return fn()
    end
    function handle:On(event, fn)
        attached()
        assert(type(fn) == "function", "invalid_subscription")
        -- Session lifecycle notifications exist only when LAN is installed.
        return own(backend and backend.on(event, fn) or function() end)
    end
    function handle:OnLocalRender(fn)
        attached()
        assert(
            type(fn) == "function"
                and type(mod.AddCallback) == "function"
                and type(mod.RemoveCallback) == "function",
            "invalid_render_subscription"
        )
        local active, cancel = true
        local function render()
            if active and self:IsReady() then
                local ok, reason = pcall(function()
                    self:WithLocalView(function()
                        return fn(self:View())
                    end)
                end)
                if not ok then
                    cancel()
                    Isaac.DebugString(
                        "ISAAC_LAN integration " .. id .. " render_disabled=" .. tostring(reason)
                    )
                end
            end
        end
        mod:AddCallback(ModCallbacks.MC_POST_RENDER, render)
        cancel = own(function()
            if active then
                active = false
                mod:RemoveCallback(ModCallbacks.MC_POST_RENDER, render)
            end
        end)
        return cancel
    end
    function handle:Action(name, definition)
        attached()
        assert(
            type(name) == "string" and #name <= 32 and name:match("^[%w_.%-]+$"),
            "invalid_action_name"
        )
        if actions[name] then
            assert(definition == nil, "duplicate_action")
            return actions[name]
        end
        definition = definition or {}
        assert(type(definition) == "table", "invalid_action_definition")
        local version = definition.version or 1
        assert(
            math.type(version) == "integer" and version >= 1 and version <= 65535,
            "invalid_action_version"
        )
        assert(
            definition.execute == nil or type(definition.execute) == "function",
            "invalid_action_definition"
        )
        assert(
            definition.solo == nil or type(definition.solo) == "function",
            "invalid_action_definition"
        )
        local validate = definition.validate or noPayload
        assert(type(validate) == "function", "invalid_action_definition")
        local remove
        if backend and definition.execute then
            remove = backend.register(name, {
                version = version,
                validate = validate,
                execute = definition.execute,
                cooldownTicks = definition.cooldownTicks,
            })
        end
        local action, disposed, pending = {}, false, {}
        actions[name] = action
        function action:IsAvailable()
            if closed or disposed or not handle:IsReady() then
                return false
            end
            if handle:IsActive() then
                return backend.has(name, version)
            end
            return definition.solo ~= nil or definition.execute ~= nil
        end
        function action:Request(payload, options)
            options = options or {}
            assert(
                type(options) == "table"
                    and (options.onResult == nil or type(options.onResult) == "function"),
                "invalid_request_options"
            )
            local request, done = { status = "pending" }, false
            local function finish(result)
                if done then
                    return
                end
                done = true
                pending[request] = nil
                request.status, request.code, request.result = result.status, result.code, result
                request.id = result.requestId or request.id
                if options.onResult then
                    local ok, reason = pcall(options.onResult, result)
                    if not ok then
                        Isaac.DebugString(
                            "ISAAC_LAN integration "
                                .. id
                                .. " result_callback_error="
                                .. tostring(reason)
                        )
                    end
                end
            end
            local function reject(code)
                finish({ status = "rejected", code = code })
                return request
            end
            if closed or disposed then
                return reject("integration_closed")
            end
            if not handle:IsReady() then
                return reject("view_not_ready")
            end
            if not self:IsAvailable() then
                return reject("action_unavailable")
            end
            local player = options.player or handle:GetLocalPlayers()[1]
            if not handle:IsLocalPlayer(player) then
                return reject("player_not_local")
            end
            if handle:IsActive() then
                local requestId, code =
                    backend.request(name, version, payload, handle:GetPlayerId(player), finish)
                if not requestId then
                    return reject(code)
                end
                request.id = requestId
                pending[request] = finish
            else
                local ok, valid = pcall(validate, payload)
                if not ok or valid ~= true then
                    return reject("invalid_payload")
                end
                local context = handle:View()
                context.player, context.playerId = player, handle:GetPlayerId(player)
                local success, result =
                    pcall(definition.solo or definition.execute, context, payload)
                if not success then
                    finish({ status = "unknown", code = "handler_error" })
                elseif
                    type(result) ~= "table"
                    or type(result.code) ~= "string"
                    or not ({ applied = true, rejected = true, cancelled = true, unknown = true })[result.status]
                then
                    finish({ status = "unknown", code = "invalid_handler_result" })
                else
                    finish(result)
                end
            end
            return request
        end
        action.Close = own(function()
            if not disposed then
                disposed = true
                local waiting = pending
                pending = {}
                for _, finish in pairs(waiting) do
                    finish({ status = "unknown", code = "integration_closed" })
                end
                if remove then
                    remove()
                end
                if actions[name] == action then
                    actions[name] = nil
                end
            end
        end)
        return action
    end
    function handle:Close()
        if closed then
            return
        end
        closed = true
        local tokens = {}
        for token in pairs(cleanups) do
            tokens[#tokens + 1] = token
        end
        table.sort(tokens, function(a, b)
            return a > b
        end)
        for _, token in ipairs(tokens) do
            local ok, reason = true, nil
            if cleanups[token] then
                ok, reason = pcall(cleanups[token])
            end
            if not ok then
                Isaac.DebugString(
                    "ISAAC_LAN integration " .. id .. " cleanup_error=" .. tostring(reason)
                )
            end
        end
        cleanups, actions = {}, {}
        if backend then
            backend.close()
        elseif soloHandles[mod] == self then
            soloHandles[mod], soloIds[id] = nil, nil
        end
    end
    return handle
end
---@param mod table The instance returned by RegisterMod.
---@param id string Stable namespace shared by all peers running this integration.
---@return IsaacLANHandle
function SDK.attach(mod, id)
    local api = rawget(_G, "IsaacLAN")
    if api then
        assert(api.API_VERSION == 2 and type(api.Attach) == "function", "unsupported_isaac_lan_api")
        return api:Attach(mod, id)
    end
    local previous = soloHandles[mod]
    if previous then
        assert(previous.id == id, "mod_already_registered")
        return previous
    end
    assert(not soloIds[id], "duplicate_integration_id")
    local handle = SDK.create(mod, id)
    soloHandles[mod], soloIds[id] = handle, handle
    return handle
end
return SDK
