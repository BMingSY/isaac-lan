local UNRESTRICTED_CHARACTER = 65535
-- Menu decisions and actions are independent of fonts, sprites and mouse geometry.
return function(Phase, Command)
    local CHALLENGE_MODE, MODE_COUNT = 4, 5
    local function idle(phase)
        return phase == Phase.idle or phase == Phase.failed or phase == Phase.closed
    end
    local function validPort(ui)
        local number = tonumber(ui.port)
        if number and number % 1 == 0 and number >= 1 and number <= 65535 then
            ui.port = tostring(number)
            ui.errorText = ""
            return true
        end
        ui.errorText = "端口范围：1–65535"
        return false
    end
    local function remember(ui, native)
        if validPort(ui) then
            native.menu_connection_save(ui.ip, tonumber(ui.port))
        end
    end
    local function rows(ui, status, characterChoices, challenges, deps)
        local phase = status.phase or Phase.idle
        local modes = ui.page == "modes"
        local challenge = challenges[tostring(status.challenge or 0)]
        local notice
        local localSlot = status.slot or 0
        -- No seat exists until the host has accepted the connection. Default
        -- session values must not appear as a joined P1 after a failed attempt.
        local count = (
            phase == Phase.lobby
            or phase == Phase.running
            or phase == Phase.loading
            or phase == Phase.waiting
            or phase == Phase.returning
        )
                and (status.players or 0)
            or 0
        local host = status.hosting == 1
        local ready = status["ready" .. localSlot] == 1
        local choice = status["choice" .. localSlot] or 0
        local rows = {}
        local function row(label, action, enabled, change, field, color)
            rows[#rows + 1] = {
                label = label,
                action = action,
                enabled = enabled ~= false,
                change = change,
                field = field,
                color = color,
            }
        end
        local function command(action, value)
            local ok, reason = pcall(deps.command, action, value or "")
            ui.errorText = ok and "" or tostring(reason):gsub("^.-:%d+: ", "")
            return ok
        end
        if status.pendingSave == 1 then
            row("重试保存联机存档", function()
                command("retry_save")
            end)
            row("返回", deps.hide)
        elseif not host and (status.recovering or phase == Phase.running) then
            local busy = status.recovering and (phase ~= Phase.failed or status.prepared)
            notice = status.recovering and (busy and "reconnecting" or "reconnect_failed") or nil
            row("重连游戏", function()
                command("reconnect")
            end, not busy)
            row("离开游戏", function()
                command("leave")
            end)
        elseif modes then
            row("官方联机", function()
                if command("close") then
                    deps.native.menu_official()
                    deps.hide()
                end
            end)
            row("局域网联机", function()
                ui.page = "lan"
                ui.selection = 1
            end)
            row("返回", function()
                deps.hide()
            end)
        elseif idle(phase) then
            row("创建房间", function()
                if validPort(ui) then
                    remember(ui, deps.native)
                    command("host", ui.port)
                end
            end)
            row(ui.ip == "" and "输入房主的 IP" or ui.ip, function()
                ui.editing = "ip"
                deps.native.menu_text_begin(ui.ip, "ip")
            end, true, nil, "ip")
            row("端口：" .. ui.port, function()
                ui.editing = "port"
                deps.native.menu_text_begin(ui.port, "port")
            end, true, nil, "port")
            row("加入房间", function()
                if validPort(ui) then
                    remember(ui, deps.native)
                    command("join", ui.ip .. ":" .. ui.port)
                end
            end, ui.ip ~= "")
            row("返回", function()
                ui.page = "modes"
                ui.selection = 2
            end)
        elseif phase == Phase.lobby and ui.page == "challenges" and host then
            local ids = {}
            for id in pairs(challenges) do
                ids[#ids + 1] = tonumber(id)
            end
            table.sort(ids)
            for _, id in ipairs(ids) do
                local definition = challenges[tostring(id)]
                row(id .. " " .. definition.name, function()
                    if command("challenge", tostring(id)) then
                        ui.difficulty = definition.difficulty
                        ui.page, ui.selection = "lan", 3
                    end
                end, definition.team_available, nil, nil, deps.accent)
            end
            row("返回", function()
                ui.page, ui.selection = "lan", 3
            end)
            local preview = challenges[tostring(ids[ui.selection] or ids[1])]
            if preview and not preview.team_available then
                notice = "unavailable"
            end
        elseif phase == Phase.lobby then
            local choices = characterChoices
            local function cycle(delta)
                if #choices == 0 then
                    return
                end
                local index = 1
                for i, v in ipairs(choices) do
                    if v == choice then
                        index = i
                        break
                    end
                end
                command("choose", choices[(index - 1 + delta) % #choices + 1] .. ":0")
            end
            row(
                deps.character(choice),
                function()
                    cycle(1)
                end,
                not ready
                    and (not challenge or challenge.character == UNRESTRICTED_CHARACTER)
                    and #choices > 0,
                cycle
            )
            row(ready and "取消准备" or "准备", function()
                command("choose", choice .. (ready and ":0" or ":1"))
            end, ready or status["eligible" .. localSlot] == true)
            if host then
                local function changeMode(delta)
                    local nextMode = ((challenge and CHALLENGE_MODE or ui.difficulty) + delta)
                        % MODE_COUNT
                    if nextMode == CHALLENGE_MODE then
                        ui.page, ui.selection = "challenges", 1
                    elseif command("challenge", "0") then
                        ui.difficulty = nextMode
                    end
                end
                row(
                    challenge and ("挑战：" .. challenge.id .. " " .. challenge.name)
                        or ({ "普通", "困难", "贪婪", "贪婪加强" })[ui.difficulty + 1],
                    function()
                        if challenge then
                            ui.page, ui.selection = "challenges", 1
                        else
                            changeMode(1)
                        end
                    end,
                    true,
                    changeMode,
                    nil,
                    challenge and deps.accent
                )
                row(ui.seed == "" and "种子：随机" or ui.seed, function()
                    ui.editing = "seed"
                    deps.native.menu_text_begin(ui.seed, "seed")
                end, true, nil, "seed")
                local allReady = count >= 2
                for i = 0, count - 1 do
                    allReady = allReady
                        and status["ready" .. i] == 1
                        and status["eligible" .. i] == true
                end
                row("开始游戏", function()
                    local settings = (ui.seed == "" and "RANDOM" or ui.seed)
                        .. ":"
                        .. (challenge and challenge.difficulty or ui.difficulty)
                    for i = 0, 3 do
                        settings = settings .. ":" .. (status["choice" .. i] or 0)
                    end
                    if command("start", settings) then
                        deps.hide()
                    end
                end, allReady)
                if not challenge and (status.savedPlayers or 0) >= 2 then
                    row("继续上次联机", function()
                        if command("resume") then
                            deps.hide()
                        end
                    end, allReady and count == status.savedPlayers)
                end
            end
            if not host and challenge then
                row(
                    "挑战：" .. challenge.id .. " " .. challenge.name,
                    function() end,
                    false,
                    nil,
                    nil,
                    deps.accent
                )
            end
            row("离开房间", function()
                command("close")
            end)
        elseif phase == Phase.running then
            if (status.pause or 0) == 0 then
                row("暂停全队", function()
                    command("control", tostring(Command.pause))
                end)
            else
                row("恢复游戏", function()
                    if command("control", tostring(Command.resume)) then
                        deps.hide()
                    end
                end, localSlot == status.pauseOwner)
            end
            row(challenge and "结束挑战（不保存）" or "保存并结束联机", function()
                command("control", tostring(Command.saveExit))
            end)
            row("返回游戏", function()
                deps.hide()
            end)
        else
            notice = phase == Phase.returning and "returning" or "waiting"
            if not status.prepared then
                row("离开房间", function()
                    command("close")
                end)
            end
        end
        return rows, notice
    end
    return { rows = rows, validPort = validPort, remember = remember, idle = idle }
end
