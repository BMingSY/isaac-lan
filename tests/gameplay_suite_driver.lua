-- Test-only composition. Gameplay/network ticks stay absolute; fixture clocks
-- are relative to their phase. One menu connection and one native game start.
local native = assert(_IsaacLan)
local realFrame, realStatus, realCommand = _IsaacLanFrame, _IsaacLanStatus, _IsaacLanCommand
local realGate, realDebug = native.net_gate, Isaac.DebugString
local modules = {
    -- BUNDLED_FIXTURES
}
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local current, core
local function cleanupAll()
    local errors = {}
    for _, context in ipairs(modules) do
        if context.scope then
            local ok, message = pcall(context.scope.cleanup)
            context.closed = true
            if not ok then
                errors[#errors + 1] = context.name .. ": " .. tostring(message)
            end
        end
    end
    assert(#errors == 0, table.concat(errors, "; "))
end
local function statusFor(context)
    local status = {}
    for k, v in pairs(realStatus()) do
        status[k] = v
    end
    status.verified = (status.verified or 0) - context.start
    return status
end
local function invoke(context, fn, ...)
    local command, status, debug = _IsaacLanCommand, _IsaacLanStatus, Isaac.DebugString
    _IsaacLanCommand = function() end -- Fixture bootstrap is owned by this driver.
    _IsaacLanStatus = function()
        return statusFor(context)
    end
    Isaac.DebugString = function(text)
        realDebug("LAN_SUITE " .. context.name .. " " .. text)
    end
    local values = table.pack(pcall(context.scope.call, fn, ...))
    _IsaacLanCommand, _IsaacLanStatus, Isaac.DebugString = command, status, debug
    if values[1] then
        local ok, complete = pcall(context.scope.done)
        if ok then
            context.completed = complete
        else
            values = { false, complete }
        end
    end
    if not values[1] then
        local ok, message = pcall(cleanupAll)
        error(
            "Suite "
                .. context.name
                .. ": "
                .. tostring(values[2])
                .. (ok and "" or "; cleanup: " .. tostring(message))
        )
    end
    return table.unpack(values, 2, values.n)
end
for _, context in ipairs(modules) do
    _IsaacLanFrame = function()
        return statusFor(context)
    end
    native.net_gate = function(...)
        context.handlers = { ... }
        return true
    end
    local ok, scope = pcall(createScenario, context.load, function()
        return current == context and not context.closed
    end, function(fn, ...)
        return invoke(context, fn, ...)
    end)
    if not ok then
        local clean, message = pcall(cleanupAll)
        error(tostring(scope) .. (clean and "" or "; cleanup: " .. tostring(message)))
    end
    context.scope = scope
    context.frame = _IsaacLanFrame
    context.bind = native.net_gate
end
_IsaacLanFrame = realFrame
local function prepare(context)
    if host then
        local first = Game():GetLevel():GetStartingRoomIndex()
        local config = Isaac.GetItemConfig()
        for i = 0, 1 do
            local p = Isaac.GetPlayer(i)
            assert(
                not p:IsDead() and not p:IsCoopGhost(),
                "Previous fixture left controller "
                    .. p.ControllerIndex
                    .. " dead before "
                    .. context.name
            )
            for id = 1, config:GetCollectibles().Size - 1 do
                if config:GetCollectible(id) then
                    for _ = 1, p:GetCollectibleNum(id, true) do
                        p:RemoveCollectible(id, true)
                    end
                end
            end
            p:AddMaxHearts(6 - p:GetMaxHearts())
            p:AddHearts(6 - p:GetHearts())
            p:AddSoulHearts(-p:GetSoulHearts())
            p:AddCoins(-p:GetNumCoins())
            p:ResetDamageCooldown()
            p.Visible = true
            p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
            if context.name == "peer-intro" then
                p:SetMinDamageCooldown(2000)
            end
            assert(native.rooms_move(i, first, 0, -1))
            assert(native.rooms_with_player(i, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type ~= 1 then
                        e:Remove()
                    end
                end
                Game():GetRoom():SetClear(true)
            end))
        end
    end
    -- Every fixture calls the real bridge through these wrappers; wire tick
    -- numbers, acknowledgement sequences and native state remain untouched.
    invoke(context, context.bind, core[1], function(t, n, b)
        return core[2](t + context.start, n, b)
    end, function(slot, t)
        return core[3](slot, t + context.start)
    end, function(bytes, t, ack, betweenUpdates)
        return core[4](bytes, t + context.start, ack, betweenUpdates)
    end, core[5], core[6])
    assert(context.handlers, "Fixture did not install its callbacks")
    realDebug("LAN_SUITE BEGIN " .. context.name .. " tick=" .. context.start)
end
local function selectPhase(tick)
    local next
    for _, context in ipairs(modules) do
        if tick >= context.start then
            next = context
        end
    end
    if next and current ~= next then
        if current then
            if not current.completed then
                cleanupAll()
                error("Suite phase did not finish: " .. current.name)
            end
            current.scope.cleanup()
            current.closed = true
        end
        current = next
        local ok, message = pcall(prepare, current)
        if not ok then
            local clean, cleanupError = pcall(cleanupAll)
            error(tostring(message) .. (clean and "" or "; cleanup: " .. tostring(cleanupError)))
        end
    end
    return current and not current.closed and current or nil
end
native.net_gate = function(...)
    core = { ... }
    return realGate(function()
        return current and not current.closed and invoke(current, current.handlers[1]) or core[1]()
    end, function(t, n, b)
        local context = selectPhase(t)
        if context then
            return invoke(context, context.handlers[2], t - context.start, n, b)
        end
        return core[2](t, n, b)
    end, function(slot, t)
        local context = selectPhase(t)
        if context then
            return invoke(context, context.handlers[3], slot, t - context.start)
        end
        return core[3](slot, t)
    end, function(bytes, t, ack, betweenUpdates)
        local context = selectPhase(t)
        if context then
            return invoke(
                context,
                context.handlers[4],
                bytes,
                t - context.start,
                ack,
                betweenUpdates
            )
        end
        return core[4](bytes, t, ack, betweenUpdates)
    end, function(...)
        if current and not current.closed then
            return invoke(current, current.handlers[5], ...)
        end
        return core[5](...)
    end, function(...)
        if current and not current.closed then
            return invoke(current, current.handlers[6], ...)
        end
        return core[6](...)
    end)
end
local renders, linked, chosen, finished = 0, false, false, false
function _IsaacLanFrame()
    renders = renders + 1
    local status = realFrame()
    if not linked and status.scene == 1 and renders >= (host and 300 or 360) then
        linked = true
        realCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        realDebug("LAN_NETWORK MENU_READY")
    end
    if status.phase == 2 and not chosen then
        realCommand("choose", "0:1")
        chosen = true
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        realCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    if status.phase == 4 or status.phase == 9 then
        realDebug("LAN_NETWORK FAILED " .. status.error)
    end
    if current and not current.closed and status.prepared then
        invoke(current, current.frame)
    end
    -- Keep a completed fixture's grace period from killing an idle actor.
    -- The next preparation resets this; its native cooldown checks still run.
    if host and current and current.completed then
        for i = 0, Game():GetNumPlayers() - 1 do
            Isaac.GetPlayer(i):SetMinDamageCooldown(10000)
        end
    end
    local last = modules[#modules]
    if status.verified >= last.start + last.duration + 30 and not finished then
        for _, context in ipairs(modules) do
            if not context.completed then
                cleanupAll()
                error("Unfinished phase: " .. context.name)
            end
        end
        cleanupAll()
        finished = true
        realDebug("LAN_NETWORK PASS continuous gameplay suite")
    end
    return status
end
