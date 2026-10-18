return function(deps, wire)
    local limits = deps.limits
    local chat = { messages = {}, bubbles = {}, emotes = {}, revision = 0 }
    local nonce, sequence, outputSequence = deps.nonce(), 0, 0
    local executingOwner
    local seen, outputSeen, commands, outbox = {}, {}, {}, {}
    local function length(text)
        if type(text) ~= "string" or text:find("[%z\1-\8\11\12\14-\31\127]") then
            return nil
        end
        return utf8.len(text)
    end
    local function append(value)
        value.time = deps.clock()
        chat.messages[#chat.messages + 1] = value
        if #chat.messages > limits.history then
            table.remove(chat.messages, 1)
        end
        chat.revision = chat.revision + 1
        if value.bubble then
            chat.bubbles[value.owner] = value
        end
    end
    local function send(slot, bytes)
        local queued = false
        for _, item in ipairs(outbox) do
            queued = queued or item.slot == slot
        end
        if not queued and deps.send(slot, bytes) then
            return true
        end
        if #outbox >= 64 then
            return false
        end
        outbox[#outbox + 1] = { slot = slot, bytes = bytes, expires = deps.clock() + 5000 }
        return true
    end
    -- Visibility and bubble presentation are independent. Host output may be
    -- addressed to the command's owner or shared with the entire party.
    function chat.output(text, options)
        options = options or {}
        assert(options.audience == nil or options.audience == "self" or options.audience == "party")
        local info = deps.info()
        local count = length(text)
        if not count or #text > limits.commandBytes or text == "" then
            return false
        end
        local owner = options.owner or executingOwner or info.slot
        if type(owner) ~= "number" or owner % 1 ~= 0 or owner < 0 or owner >= info.players then
            return false
        end
        local party = options.audience == "party"
        if (party or owner ~= info.slot) and info.hosting ~= 1 then
            return false
        end
        local value = {
            text = text,
            owner = owner,
            kind = options.kind or "system",
            bubble = options.bubble == true,
        }
        if party or owner == info.slot then
            append(value)
        end
        if party or owner ~= info.slot then
            outputSequence = outputSequence + 1
            value.sequence, value.nonce = outputSequence, nonce
            local bytes = wire.encodeOutput(value)
            for slot = 1, info.players - 1 do
                if (party or slot == owner) and (info.connected & (1 << slot)) ~= 0 then
                    send(slot, bytes)
                end
            end
        end
        return true
    end
    local function errorTo(text, owner)
        return chat.output(text, { owner = owner, audience = "self" })
    end
    function chat.parse(text)
        local count = length(text)
        if not count or #text > limits.commandBytes then
            return nil, "输入无效或命令过长"
        end
        text = text:gsub("[\r\n\t]", " ")
        if text:match("^%s*$") then
            return nil, "请输入内容"
        end
        if text:sub(1, 1) ~= "/" then
            if count > limits.characters then
                return nil, "每条聊天最多 " .. limits.characters .. " 字"
            end
            return { kind = "text", text = text }
        end
        local name, args = text:match("^/([^%s]+)%s?(.*)$")
        if not name then
            return nil, "请输入命令"
        end
        local lower = name:lower()
        if lower == "h" or lower == "help" then
            return { kind = "help" }
        end
        if lower == "e" or lower == "echo" then
            return { kind = "echo", text = args }
        end
        local dice = lower:match("^d(%d+)$")
        if dice then
            local sides = tonumber(dice)
            if
                not sides
                or sides < 1
                or sides > limits.dice
                or sides % 1 ~= 0
                or args:match("%S")
            then
                return nil, "用法：/dN，N 为 1～" .. limits.dice .. " 的整数"
            end
            return { kind = "dice", sides = sides }
        end
        if lower == "lanbot" then
            return { kind = "bot", text = args }
        end
        if lower == "console" or lower == "c" then
            args = args:gsub("^%s+", "")
            if args == "" then
                return nil, "用法：/console 原版命令，例如 /c giveitem c1"
            end
            return { kind = "native", text = args }
        end
        return nil, "未知聊天命令；原版命令请使用 /console 命令"
    end
    local function accept(sender, request)
        local ledger = seen[sender]
        if not ledger or ledger.nonce ~= request.nonce then
            -- A new connection may have a new Lua environment; transport owns
            -- sender identity. Retain old nonces to reject delayed replays.
            ledger = ledger or { retired = {} }
            if ledger.retired[request.nonce] then
                return
            end
            if ledger.nonce then
                ledger.retired[ledger.nonce] = true
            end
            ledger.nonce, ledger.sequence = request.nonce, 0
            seen[sender] = ledger
        end
        if request.sequence <= ledger.sequence then
            return
        end
        ledger.sequence = request.sequence
        if request.id then
            if request.id < 1 or request.id > deps.emotes then
                return
            end
            local value = { owner = sender, id = request.id, time = deps.clock() }
            chat.emotes[sender] = value
            outputSequence = outputSequence + 1
            value.sequence, value.nonce = outputSequence, nonce
            local info, bytes = deps.info(), wire.encodeEmote(value)
            for slot = 1, info.players - 1 do
                if (info.connected & (1 << slot)) ~= 0 then
                    send(slot, bytes)
                end
            end
            return
        end
        local parsed, reason = chat.parse(request.text)
        if not parsed then
            errorTo(reason, sender)
        elseif parsed.kind == "text" then
            chat.output(
                parsed.text,
                { owner = sender, audience = "party", bubble = true, kind = "team" }
            )
        elseif parsed.kind == "dice" then
            local result = deps.roll(parsed.sides)
            if not result then
                errorTo("掷骰失败，请重试", sender)
                return
            end
            chat.output(
                (sender + 1) .. "P掷出 D" .. parsed.sides .. " : " .. result,
                { owner = sender, audience = "party", bubble = true }
            )
        elseif parsed.kind == "native" then
            if deps.info().ready ~= 1 then
                errorTo("命令未执行：游戏尚未就绪", sender)
                return
            end
            if #commands >= 16 then
                errorTo("命令队列已满", sender)
                return
            end
            request.owner, request.command = sender, parsed.text
            commands[#commands + 1] = request
        else
            errorTo("此命令在本机执行", sender)
        end
    end
    function chat.submit(text)
        local parsed, reason = chat.parse(text)
        local info = deps.info()
        if not parsed then
            errorTo(reason)
            return false
        end
        if parsed.kind ~= "text" then
            -- Keep the submitted command locally, even when native execution is silent.
            append({
                text = text:gsub("[\r\n\t]", " "),
                owner = info.slot,
                kind = "system",
                command = true,
                bubble = false,
            })
        end
        if parsed.kind == "help" then
            for _, line in ipairs({
                "/h /help：命令帮助",
                "/e /echo 文字：仅自己可见",
                "/dN：全队掷骰，N 为 1～" .. limits.dice,
                "/c /console 命令：原版控制台",
                "/c help：原版命令列表",
                "/lanbot help：托管命令",
            }) do
                chat.output(line, { audience = "self" })
            end
            return true
        elseif parsed.kind == "echo" then
            chat.output(parsed.text, { audience = "self" })
            return true
        elseif parsed.kind == "bot" then
            chat.output(deps.bot(parsed.text), { audience = "self" })
            return true
        end
        local context = deps.context(info.slot) or {}
        sequence = sequence + 1
        local request = {
            sequence = sequence,
            nonce = nonce,
            run = info.runId or "",
            epoch = info.worldEpoch or 0,
            room = context.index or 0,
            dimension = context.dimension or 0,
            text = text,
        }
        if info.hosting == 1 then
            accept(info.slot, request)
            return true
        end
        if deps.send(0, wire.encodeRequest(request)) then
            return true
        end
        errorTo("消息未发送，连接尚未就绪")
        return false
    end
    function chat.sendEmote(id)
        if type(id) ~= "number" or id % 1 ~= 0 or id < 1 or id > deps.emotes then
            return false
        end
        sequence = sequence + 1
        local request = { sequence = sequence, owner = 255, id = id, nonce = nonce }
        local info = deps.info()
        if info.hosting == 1 then
            accept(info.slot, request)
            return true
        end
        return deps.send(0, wire.encodeEmote(request))
    end
    function chat.poll()
        local info = deps.info()
        for _ = 1, 32 do
            local sender, bytes = deps.receive()
            if sender == nil then
                break
            end
            local ok, value = pcall(wire.decode, bytes)
            if ok then
                if
                    info.hosting == 1
                    and (
                        value.packet == wire.request
                        or (value.packet == wire.emote and value.owner == 255)
                    )
                then
                    accept(sender, value)
                elseif
                    info.hosting ~= 1
                    and sender == 0
                    and (
                        (
                            value.packet == wire.output
                            and length(value.text)
                            and #value.text <= limits.commandBytes
                        )
                        or (
                            value.packet == wire.emote
                            and value.owner < 4
                            and value.id >= 1
                            and value.id <= deps.emotes
                        )
                    )
                then
                    local last = outputSeen[value.nonce] or 0
                    if value.sequence > last then
                        outputSeen[value.nonce] = value.sequence
                        if value.packet == wire.emote then
                            value.time = deps.clock()
                            chat.emotes[value.owner] = value
                        else
                            append(value)
                        end
                    end
                end
            end
        end
        local pending = outbox
        outbox = {}
        local blocked = {}
        for _, item in ipairs(pending) do
            if item.expires > deps.clock() and (info.connected & (1 << item.slot)) ~= 0 then
                if blocked[item.slot] or not deps.send(item.slot, item.bytes) then
                    blocked[item.slot] = true
                    outbox[#outbox + 1] = item
                end
            end
        end
    end
    function chat.step()
        if #commands == 0 then
            return
        end
        local request = table.remove(commands, 1)
        local info, context = deps.info(), deps.context(request.owner)
        if
            info.ready ~= 1
            or (info.connected & (1 << request.owner)) == 0
            or info.runId ~= request.run
            or info.worldEpoch ~= request.epoch
            or not context
            or context.index ~= request.room
            or context.dimension ~= request.dimension
        then
            errorTo("命令未执行：角色或房间已变化", request.owner)
            return
        end
        executingOwner = request.owner
        local ok, result = pcall(deps.execute, request.owner, request.command)
        executingOwner = nil
        if not ok then
            result = "命令执行失败：" .. tostring(result)
        end
        result = result or "命令未执行：游戏尚未就绪"
        -- Keep native multiline output readable without exceeding wire bounds.
        for line in result:gmatch("[^\r\n]+") do
            while #line > limits.commandBytes do
                local ending = limits.commandBytes
                while line:byte(ending + 1) and line:byte(ending + 1) & 0xc0 == 0x80 do
                    ending = ending - 1
                end
                errorTo(line:sub(1, ending), request.owner)
                line = line:sub(ending + 1)
            end
            errorTo(line, request.owner)
        end
    end
    function chat.reset()
        chat.messages, chat.bubbles, chat.emotes = {}, {}, {}
        chat.revision = chat.revision + 1
        seen, outputSeen, commands, outbox = {}, {}, {}, {}
        nonce, sequence, outputSequence = deps.nonce(), 0, 0
    end
    function chat.clearBubbles()
        chat.bubbles, chat.emotes = {}, {}
    end
    return chat
end
