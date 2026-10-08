local native, codec = assert(_IsaacLan), assert(_IsaacLanModules)["api/codec"]
return function(bridge)
    local actions = {}
    local definitions, capabilities, pending, queue, running, ledgers, outbox =
        {}, {}, {}, {}, {}, {}, {}
    local sequence, capabilitySignature = 0, nil
    local nonce = native.api_nonce()
    local operationTag = {}
    local executing
    local function key(id, name)
        assert(
            type(name) == "string" and #name <= 32 and name:match("^[%w_.%-]+$"),
            "invalid_action_name"
        )
        return id .. "/" .. name
    end
    local function send(slot, message)
        local ok, bytes = pcall(codec.encode, message)
        if not ok then
            bridge.log("action_encode_error=" .. tostring(bytes))
            return false
        end
        if native.api_send(slot, bytes) then
            return true
        end
        if #outbox < 64 then
            outbox[#outbox + 1] = { slot = slot, bytes = bytes }
        end
        return false
    end
    local function resolve(entry, result)
        pending[entry.requestId] = nil
        if entry.callback then
            local ok, reason = pcall(function()
                if bridge.ready() then
                    bridge.withView(function()
                        entry.callback(bridge.copy(result))
                    end)
                else
                    entry.callback(bridge.copy(result))
                end
            end)
            if not ok then
                bridge.log(entry.key .. " result_callback_error=" .. tostring(reason))
            end
        end
    end
    local function resultFor(message, status, code)
        return {
            kind = "result",
            requestId = message.requestId,
            runId = message.runId,
            worldEpoch = message.worldEpoch,
            status = status,
            code = code,
        }
    end
    local function complete(request, status, code)
        local result = resultFor(request.message, status, code)
        if request.record then
            request.record.result = result
        end
        send(request.sender, result)
    end
    function actions.register(id, name, definition)
        local actionKey = key(id, name)
        assert(
            type(definition) == "table"
                and math.type(definition.version) == "integer"
                and definition.version >= 1
                and definition.version <= 65535
                and type(definition.validate) == "function"
                and type(definition.execute) == "function",
            "invalid_action_definition"
        )
        assert(
            definition.cooldownTicks == nil
                or (
                    math.type(definition.cooldownTicks) == "integer"
                    and definition.cooldownTicks >= 1
                    and definition.cooldownTicks <= 1800
                ),
            "invalid_action_cooldown"
        )
        assert(not definitions[actionKey], "duplicate_action")
        local count = 0
        for _ in pairs(definitions) do
            count = count + 1
        end
        assert(count < 16, "action_limit")
        local record = { id = id, definition = bridge.copy(definition), enabled = true, last = {} }
        definitions[actionKey], capabilitySignature = record, nil
        return function()
            if definitions[actionKey] == record then
                record.enabled = false
                definitions[actionKey], capabilitySignature = nil, nil
            end
        end
    end
    function actions.enable(id, name, enabled)
        assert(type(enabled) == "boolean", "invalid_enabled")
        local record = definitions[key(id, name)]
        if not record then
            return false, "action_not_registered"
        end
        record.enabled, capabilitySignature = enabled, nil
        return true
    end
    function actions.has(id, name, version)
        if not bridge.active() then
            return false
        end
        local actionKey = key(id, name)
        if bridge.info().authority == 1 then
            local record = definitions[actionKey]
            return record ~= nil and record.enabled and record.definition.version == version
        end
        return capabilities[actionKey] == version
    end
    function actions.request(id, name, payload, callback)
        if not bridge.ready() then
            return nil, "view_not_ready"
        end
        assert(callback == nil or type(callback) == "function", "invalid_result_callback")
        local info, actionKey = bridge.info(), key(id, name)
        local version = info.authority == 1
                and definitions[actionKey]
                and definitions[actionKey].enabled
                and definitions[actionKey].definition.version
            or capabilities[actionKey]
        if not version then
            return nil, "action_unavailable"
        end
        local count = 0
        for _ in pairs(pending) do
            count = count + 1
        end
        if count >= 8 then
            return nil, "request_queue_full"
        end
        sequence = sequence + 1
        local requestId = nonce .. ":" .. sequence
        local message = {
            kind = "request",
            key = actionKey,
            version = version,
            payload = payload,
            nonce = nonce,
            sequence = sequence,
            requestId = requestId,
            runId = info.runId,
            worldEpoch = info.worldEpoch,
            source = bridge.copy(bridge.context.room),
        }
        local ok, bytes = pcall(codec.encode, message)
        if not ok then
            return nil, "invalid_payload"
        end
        local entry = {
            requestId = requestId,
            key = actionKey,
            callback = callback,
            message = message,
            at = info.nowMs,
        }
        pending[requestId] = entry
        if not native.api_send(0, bytes) then
            pending[requestId] = nil
            return nil, "transport_unavailable"
        end
        return requestId
    end
    function actions.operation(definition)
        assert(
            type(definition) == "table"
                and type(definition.poll) == "function"
                and (definition.cancel == nil or type(definition.cancel) == "function"),
            "invalid_operation"
        )
        return { tag = operationTag, poll = definition.poll, cancel = definition.cancel }
    end
    function actions.move(context, destination)
        local task = context and running[context.ownerId - 1]
        assert(executing == context or (task and task.context == context), "move_outside_action")
        if bridge.info().worldEpoch ~= context.worldEpoch then
            return nil, "stale_world"
        end
        if
            type(destination) ~= "table"
            or math.type(destination.index) ~= "integer"
            or destination.index < -20
            or destination.index >= 169
            or math.type(destination.dimension) ~= "integer"
            or destination.dimension < 0
            or destination.dimension > 2
        then
            return nil, "invalid_destination"
        end
        local slot = context.ownerId - 1
        if not native.api_move(slot, destination.index, destination.dimension) then
            return nil, "move_rejected"
        end
        local at = bridge.info().nowMs
        return actions.operation({
            poll = function()
                local position = native.rooms_positions()[tostring(slot)]
                if
                    position
                    and position.index == destination.index
                    and position.dimension == destination.dimension
                then
                    return { status = "applied", code = "arrived" }
                end
                if bridge.info().nowMs - at >= 3000 then
                    return { status = "unknown", code = "arrival_unconfirmed" }
                end
            end,
            cancel = function()
                if bridge.info().worldEpoch == context.worldEpoch then
                    native.api_cancel_move(slot, destination.index, destination.dimension)
                end
            end,
        })
    end
    local function receive(sender, message, bytes)
        if type(message) ~= "table" then
            return
        end
        local info = bridge.info()
        if message.kind == "capabilities" and sender == 0 and info.authority ~= 1 then
            if
                message.runId ~= info.runId
                or message.worldEpoch ~= info.worldEpoch
                or type(message.actions) ~= "table"
            then
                return
            end
            local nextCapabilities = {}
            if #message.actions > 16 then
                return
            end
            for _, action in ipairs(message.actions) do
                if
                    type(action) ~= "table"
                    or type(action[1]) ~= "string"
                    or #action[1] > 97
                    or math.type(action[2]) ~= "integer"
                    or action[2] < 1
                    or action[2] > 65535
                then
                    return
                end
                nextCapabilities[action[1]] = action[2]
            end
            capabilities = nextCapabilities
        elseif message.kind == "result" and sender == 0 then
            local entry = pending[message.requestId]
            if
                entry
                and message.runId == entry.message.runId
                and message.worldEpoch == entry.message.worldEpoch
                and (message.status == "applied" or message.status == "rejected" or message.status == "cancelled" or message.status == "unknown")
                and type(message.code) == "string"
            then
                resolve(entry, message)
            end
        elseif message.kind == "request" and info.authority == 1 and info.active == 1 then
            if
                type(message.nonce) ~= "string"
                or #message.nonce ~= 32
                or math.type(message.sequence) ~= "integer"
                or message.sequence < 1
                or message.sequence > 0xffffffff
                or message.requestId ~= message.nonce .. ":" .. message.sequence
                or type(message.key) ~= "string"
                or type(message.source) ~= "table"
            then
                return
            end
            local request = { sender = sender, message = message }
            if message.runId ~= info.runId or message.worldEpoch ~= info.worldEpoch then
                complete(request, "cancelled", "stale_world")
                return
            end
            local owner = ledgers[sender] or { nonces = {}, count = 0 }
            ledgers[sender] = owner
            local ledger = owner.nonces[message.nonce]
            if not ledger then
                if owner.count >= 8 then
                    complete(request, "rejected", "generation_limit")
                    return
                end
                ledger = { high = 0, records = {} }
                owner.nonces[message.nonce], owner.count = ledger, owner.count + 1
            end
            local record = ledger.records[message.sequence]
            if record then
                if record.bytes ~= bytes then
                    complete(request, "rejected", "request_id_reused")
                elseif record.result then
                    send(sender, record.result)
                end
                return
            end
            if message.sequence <= ledger.high then
                complete(request, "rejected", "dedupe_expired")
                return
            end
            ledger.high = message.sequence
            for seq, old in pairs(ledger.records) do
                if seq <= ledger.high - 64 and old.result then
                    ledger.records[seq] = nil
                end
            end
            record = { bytes = bytes }
            ledger.records[message.sequence], request.record = record, record
            local count = 0
            for _, queued in ipairs(queue) do
                if queued.sender == sender then
                    count = count + 1
                end
            end
            if count >= 8 then
                complete(request, "rejected", "request_queue_full")
            else
                queue[#queue + 1] = request
            end
        end
    end
    function actions.poll()
        local info = bridge.info()
        if info.authority == 1 then
            local available = {}
            for actionKey, record in pairs(definitions) do
                if record.enabled then
                    available[#available + 1] = { actionKey, record.definition.version }
                end
            end
            table.sort(available, function(a, b)
                return a[1] < b[1]
            end)
            local signature =
                codec.encode({ available, info.runId, info.worldEpoch, info.connected })
            -- Resend on admission/reconnect and periodically when an earlier send was congested.
            if
                signature ~= capabilitySignature
                or not actions.lastCapabilities
                or info.nowMs - actions.lastCapabilities >= 1000
            then
                capabilitySignature, actions.lastCapabilities = signature, info.nowMs
                for slot = 1, info.players - 1 do
                    send(slot, {
                        kind = "capabilities",
                        runId = info.runId,
                        worldEpoch = info.worldEpoch,
                        actions = available,
                    })
                end
            end
        end
        for _ = 1, 128 do
            local sender, bytes = native.api_receive()
            if sender == nil then
                break
            end
            local ok, message = pcall(codec.decode, bytes)
            if ok then
                receive(sender, message, bytes)
            else
                bridge.log("invalid_action_packet sender=" .. sender)
            end
        end
        local retained = {}
        for _, packet in ipairs(outbox) do
            if not native.api_send(packet.slot, packet.bytes) then
                retained[#retained + 1] = packet
            end
        end
        outbox = retained
        local expired = {}
        for _, entry in pairs(pending) do
            if info.nowMs - entry.at >= 5000 then
                expired[#expired + 1] = entry
            end
        end
        for _, entry in ipairs(expired) do
            resolve(entry, resultFor(entry.message, "unknown", "timeout"))
        end
    end
    function actions.step()
        actions.poll()
        local info = bridge.info()
        if info.authority ~= 1 or info.ready ~= 1 then
            return
        end
        local requests = queue
        queue = {}
        for _, request in ipairs(requests) do
            local message, record = request.message, definitions[request.message.key]
            local position = native.rooms_positions()[tostring(request.sender)]
            local code
            if message.runId ~= info.runId or message.worldEpoch ~= info.worldEpoch then
                code = "stale_world"
            elseif
                not record
                or not record.enabled
                or record.definition.version ~= message.version
            then
                code = "action_unavailable"
            elseif
                not position
                or position.index ~= message.source.index
                or position.dimension ~= message.source.dimension
            then
                code = "source_changed"
            elseif running[request.sender] then
                code = "operation_busy"
            elseif
                record.last[request.sender]
                and info.tick - record.last[request.sender]
                    < math.max(1, record.definition.cooldownTicks or 15)
            then
                code = "rate_limited"
            end
            if code then
                complete(request, "rejected", code)
            else
                local ok, valid = pcall(record.definition.validate, message.payload)
                if not ok or valid ~= true then
                    complete(request, "rejected", "invalid_payload")
                else
                    record.last[request.sender] = info.tick
                    local result
                    local success, reason = pcall(function()
                        assert(
                            native.api_with_owner(request.sender, function()
                                local player = Isaac.GetPlayer(0)
                                local context = {
                                    ownerId = request.sender + 1,
                                    playerId = "p" .. (request.sender + 1) .. ":1",
                                    player = player,
                                    room = bridge.copy(position),
                                    runId = info.runId,
                                    worldEpoch = info.worldEpoch,
                                    requestId = message.requestId,
                                }
                                request.context = context
                                executing = context
                                result = record.definition.execute(context, message.payload)
                                executing = nil
                            end),
                            "owner_unavailable"
                        )
                    end)
                    executing = nil
                    if not success then
                        record.enabled, capabilitySignature = false, nil
                        bridge.log(message.key .. " execute_error=" .. tostring(reason))
                        complete(request, "unknown", "handler_error")
                    elseif type(result) == "table" and result.tag == operationTag then
                        running[request.sender] = {
                            request = request,
                            context = request.context,
                            operation = result,
                            at = info.nowMs,
                        }
                    elseif
                        type(result) == "table"
                        and (result.status == "applied" or result.status == "rejected" or result.status == "cancelled" or result.status == "unknown")
                        and type(result.code) == "string"
                    then
                        complete(request, result.status, result.code)
                    else
                        complete(request, "unknown", "invalid_handler_result")
                    end
                end
            end
        end
    end
    function actions.commit()
        actions.poll()
        local info = bridge.info()
        for sender, task in pairs(running) do
            local record = definitions[task.request.message.key]
            local ok, result = true, nil
            if not record or not record.enabled then
                result = { status = "cancelled", code = "action_disabled" }
            elseif info.worldEpoch ~= task.request.message.worldEpoch then
                result = { status = "cancelled", code = "stale_world" }
            else
                ok, result = pcall(function()
                    local value
                    local available = native.api_with_owner(sender, function()
                        value = task.operation.poll()
                    end)
                    if not available then
                        return { status = "cancelled", code = "owner_unavailable" }
                    end
                    return value
                end)
                if not ok then
                    result = { status = "unknown", code = "operation_error" }
                elseif result ~= nil and type(result) ~= "table" then
                    result = { status = "unknown", code = "invalid_operation_result" }
                elseif not result and info.nowMs - task.at >= 5000 then
                    result = { status = "unknown", code = "operation_timeout" }
                end
            end
            if result then
                running[sender] = nil
                if task.operation.cancel then
                    pcall(task.operation.cancel)
                end
                local status = result.status
                if
                    status ~= "applied"
                    and status ~= "rejected"
                    and status ~= "cancelled"
                    and status ~= "unknown"
                then
                    status = "unknown"
                end
                complete(
                    task.request,
                    status,
                    type(result.code) == "string" and result.code or "invalid_operation_result"
                )
            end
        end
    end
    function actions.reset(reason)
        for sender, task in pairs(running) do
            if task.operation.cancel then
                pcall(task.operation.cancel)
            end
            complete(task.request, "cancelled", reason)
            running[sender] = nil
        end
        for _, request in ipairs(queue) do
            complete(request, "cancelled", reason)
        end
        queue, ledgers, capabilities, capabilitySignature = {}, {}, {}, nil
        local entries = {}
        for _, entry in pairs(pending) do
            entries[#entries + 1] = entry
        end
        for _, entry in ipairs(entries) do
            resolve(entry, resultFor(entry.message, "unknown", reason))
        end
        outbox = {}
        for _, record in pairs(definitions) do
            record.last = {}
        end
    end
    function actions.remove(id)
        for actionKey, record in pairs(definitions) do
            if record.id == id then
                definitions[actionKey] = nil
            end
        end
        capabilitySignature = nil
    end
    return actions
end
