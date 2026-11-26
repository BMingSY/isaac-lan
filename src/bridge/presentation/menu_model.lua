local UNRESTRICTED_CHARACTER = 65535
local challengeUnlockHints = {
    [1001] = "全员需解锁底片与里该隐",
    [1004] = "全员需解锁子宫",
}
-- Menu decisions and actions are independent of fonts, sprites and mouse geometry.
return function(Phase, Command, endpoint, characters, text)
    local CHALLENGE_MODE, MODE_COUNT = 4, 5
    local function challengeName(definition)
        local name = text(definition.name)
        return definition.route == "external" and name or definition.id .. " " .. name
    end
    local function idle(phase)
        return phase == Phase.idle or phase == Phase.failed or phase == Phase.closed
    end
    local function compatibilityError(status)
        local failure = status.compatibilityError
        if status.phase ~= Phase.failed or not failure then
            return nil
        end
        local reasons = {
            version = "无法加入：Isaac LAN 版本不一致",
            fingerprint = "无法加入：版本号相同，但构建不一致",
            protocol = "无法加入：联机协议不一致",
            unavailable = "无法加入：未能核对房主版本",
        }
        local remote = failure.remoteVersion
        return {
            text(reasons[failure.reason] or reasons.unavailable),
            text(
                "房主：%s　你的版本：%s",
                remote and remote ~= "" and remote or text("未知"),
                failure.localVersion
            ),
            text("请确认双方使用相同版本和构建的 Isaac LAN。"),
        }
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
    local function back(ui)
        if ui.page == "autoTeleport" then
            ui.page, ui.selection, ui.listScroll = "rules", ui.autoReturn or 1, ui.autoScroll or 1
            ui.autoReturn, ui.autoScroll = nil, nil
            return true
        elseif ui.page == "rules" then
            ui.page, ui.selection = "lan", ui.ruleReturn or 1
            ui.ruleReturn, ui.listScroll = nil, nil
            return true
        elseif ui.page == "modSettings" then
            ui.page, ui.selection, ui.listScroll = "lan", ui.modReturn or 1, nil
            ui.modReturn = nil
            return true
        elseif ui.page == "challenges" then
            ui.page, ui.selection, ui.listScroll = "lan", 3, nil
            return true
        end
        return false
    end
    local function rows(ui, status, characterChoices, challenges, deps)
        local phase = status.phase or Phase.idle
        local modes = ui.page == "modes"
        local challenge = challenges[tostring(status.challenge or 0)]
        local notice, ruleCount
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
        local rulesLocked = challenge and challenge.roomOptionsLocked
        local rulesEditable = host and not rulesLocked
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
        local selectedRules, firstRule = 0, nil
        for _, definition in ipairs(deps.options or {}) do
            if ((status.roomOptions or 0) & definition.flag) ~= 0 then
                selectedRules = selectedRules + 1
                firstRule = firstRule or definition.shortName or definition.name
            end
        end
        local function ruleEntry()
            local summary = text(firstRule or "无")
            if selectedRules > 1 then
                summary = summary .. " +" .. (selectedRules - 1)
            end
            local index = #rows + 1
            row(text("房间规则：%s", summary), function()
                if not rulesLocked then
                    ui.page, ui.selection, ui.listScroll, ui.ruleReturn = "rules", 1, 1, index
                end
            end, not rulesLocked, nil, nil, not host and not rulesLocked and deps.accent or nil)
        end
        local teleport, roomChoices, selectedRooms = nil, {}, 0
        for _, definition in ipairs(deps.options or {}) do
            if definition.key == "autoTeleport" then
                teleport = definition
                for _, group in ipairs(definition.groups) do
                    local checked = ((status.roomOptions or 0) & group.flag) ~= 0
                    roomChoices[#roomChoices + 1] =
                        { name = text(group.name), flag = group.flag, checked = checked }
                    if checked then
                        selectedRooms = selectedRooms + 1
                    end
                end
            end
        end
        local settings = deps.modSettings or {}
        if ui.page == "modSettings" and #settings == 0 then
            back(ui)
        end
        if status.pendingSave == 1 then
            row(text("重新保存"), function()
                command("retry_save")
            end)
            row(text("返回"), deps.hide)
        elseif not host and (status.recovering or phase == Phase.running) then
            local busy = status.recovering and (phase ~= Phase.failed or status.prepared)
            notice = status.recovering and (busy and "reconnecting" or "reconnect_failed") or nil
            row(text("重连游戏"), function()
                command("reconnect")
            end, not busy)
            row(text("离开游戏"), function()
                command("leave")
            end)
        elseif modes then
            if deps.native.menu_official then
                row(text("官方联机"), function()
                    if command("close") then
                        deps.native.menu_official()
                        deps.hide()
                    end
                end)
            end
            row(text("局域网联机"), function()
                ui.page = "lan"
                ui.selection = 1
            end)
            row(text("返回"), function()
                deps.hide()
            end)
        elseif idle(phase) then
            row(text("创建房间"), function()
                if validPort(ui) then
                    remember(ui, deps.native)
                    command("host", ui.port)
                end
            end)
            row(ui.ip == "" and text("输入房主的 IP") or ui.ip, function()
                ui.editing = "ip"
                deps.native.menu_text_begin(ui.ip, "ip")
            end, true, nil, "ip")
            row(text("端口：%s", ui.port), function()
                ui.editing = "port"
                deps.native.menu_text_begin(ui.port, "port")
            end, true, nil, "port")
            row(text("加入房间"), function()
                if validPort(ui) then
                    remember(ui, deps.native)
                    command("join", endpoint.format(ui.ip, ui.port))
                end
            end, ui.ip ~= "")
            row(text("返回"), function()
                if deps.native.menu_official then
                    ui.page = "modes"
                    ui.selection = 2
                else
                    deps.hide()
                end
            end)
        elseif phase == Phase.lobby and ui.page == "modSettings" then
            for _, setting in ipairs(settings) do
                row(text("%s：%s", setting.name, setting.value), function()
                    setting.change(1)
                end, true, setting.change)
            end
            row(text("返回"), function()
                back(ui)
            end)
        elseif phase == Phase.lobby and ui.page == "autoTeleport" and teleport then
            ruleCount = selectedRooms
            local function setRooms(mask)
                if rulesEditable then
                    command(
                        "room_options",
                        tostring(((status.roomOptions or 0) & ~teleport.flag) | mask)
                    )
                end
            end
            row(text("全选"), function()
                setRooms(teleport.flag)
            end, rulesEditable)
            row(text("清空"), function()
                setRooms(0)
            end, rulesEditable)
            for _, room in ipairs(roomChoices) do
                row(room.name, function()
                    if rulesEditable then
                        local current = status.roomOptions or 0
                        command(
                            "room_options",
                            tostring(
                                room.checked and (current & ~room.flag) or (current | room.flag)
                            )
                        )
                    end
                end, rulesEditable)
                rows[#rows].checked = room.checked
            end
            row(text("返回"), function()
                back(ui)
            end)
        elseif phase == Phase.lobby and ui.page == "rules" then
            ruleCount = selectedRules
            for _, definition in ipairs(deps.options or {}) do
                if definition == teleport then
                    local index = #rows + 1
                    row(
                        text(
                            "自动传送：%s >",
                            selectedRooms == 0 and text("关闭") or text("%d 类", selectedRooms)
                        ),
                        function()
                            ui.autoReturn, ui.autoScroll = index, ui.listScroll
                            ui.page, ui.selection, ui.listScroll = "autoTeleport", 1, 1
                        end,
                        not rulesLocked,
                        nil,
                        nil,
                        not host and deps.accent or nil
                    )
                else
                    row(text(definition.name), function()
                        if rulesEditable then
                            command(
                                "room_options",
                                tostring((status.roomOptions or 0) ~ definition.flag)
                            )
                        end
                    end, rulesEditable)
                    rows[#rows].checked = ((status.roomOptions or 0) & definition.flag) ~= 0
                end
            end
            row(text("返回"), function()
                back(ui)
            end)
        elseif phase == Phase.lobby and ui.page == "challenges" and host then
            local ids = {}
            for id in pairs(challenges) do
                ids[#ids + 1] = tonumber(id)
            end
            table.sort(ids)
            for _, id in ipairs(ids) do
                local definition = challenges[tostring(id)]
                row(
                    challengeName(definition),
                    function()
                        if command("challenge", tostring(id)) then
                            ui.difficulty = definition.difficulty
                            back(ui)
                        end
                    end,
                    definition.team_available,
                    nil,
                    nil,
                    definition.team_available and deps.accent or nil
                )
                if not definition.team_available then
                    rows[#rows].unlockHint = definition.route == "external"
                            and "全员需启用兼容版本的挑战"
                        or challengeUnlockHints[id]
                        or "队伍尚未解锁此挑战"
                end
            end
            row(text("返回"), function()
                back(ui)
            end)
        elseif phase == Phase.lobby then
            local selection = characters.selection(
                choice,
                ready,
                status["random" .. localSlot] == true,
                not ready and (not challenge or challenge.character == UNRESTRICTED_CHARACTER),
                characterChoices,
                deps.catalog or {},
                command
            )
            row(selection.label or deps.character(choice), function()
                selection.cycle(1)
            end, selection.enabled, selection.cycle)
            rows[#rows].toggle = selection.toggle
            rows[#rows].canToggle = selection.canToggle
            row(
                text(ready and "取消准备" or "准备"),
                selection.prepare,
                ready or status["eligible" .. localSlot] == true and selection.canPrepare
            )
            if host then
                local function changeMode(delta)
                    local nextMode = ((challenge and CHALLENGE_MODE or ui.difficulty) + delta)
                        % MODE_COUNT
                    if nextMode == CHALLENGE_MODE then
                        ui.page, ui.selection, ui.listScroll = "challenges", 1, 1
                    elseif command("challenge", "0") then
                        ui.difficulty = nextMode
                    end
                end
                row(
                    challenge and text("挑战：%s", challengeName(challenge))
                        or text(
                            ({ "普通", "困难", "贪婪", "贪婪加强" })[ui.difficulty + 1]
                        ),
                    function()
                        if challenge then
                            ui.page, ui.selection, ui.listScroll = "challenges", 1, 1
                        else
                            changeMode(1)
                        end
                    end,
                    true,
                    changeMode,
                    nil,
                    challenge and deps.accent
                )
                row(ui.seed == "" and text("种子：随机") or ui.seed, function()
                    ui.editing = "seed"
                    deps.native.menu_text_begin(ui.seed, "seed")
                end, true, nil, "seed")
                ruleEntry()
                local required = challenge and challenge.requiredPlayers or 0
                local enough = required == 0 or required == count
                local allReady = count >= 2 and enough
                for i = 0, count - 1 do
                    allReady = allReady
                        and status["ready" .. i] == 1
                        and status["eligible" .. i] == true
                end
                row(
                    enough and text("开始游戏") or text("需要 %d 名玩家", required),
                    function()
                        local settings = (ui.seed == "" and "RANDOM" or ui.seed)
                            .. ":"
                            .. (challenge and challenge.difficulty or ui.difficulty)
                        for i = 0, 3 do
                            settings = settings .. ":" .. (status["choice" .. i] or 0)
                        end
                        if command("start", settings) then
                            deps.hide()
                        end
                    end,
                    allReady
                )
                if not challenge and (status.savedPlayers or 0) >= 2 then
                    if (status.savedOptions or 0) ~= (status.roomOptions or 0) then
                        row(text("载入上次规则"), function()
                            command("room_options", tostring(status.savedOptions or 0))
                        end, count == status.savedPlayers)
                    else
                        row(text("继续上次联机"), function()
                            if command("resume") then
                                deps.hide()
                            end
                        end, allReady and count == status.savedPlayers)
                    end
                end
            end
            if not host and (challenge or status.challenge == -1) then
                row(
                    challenge and text("挑战：%s", challengeName(challenge))
                        or text("缺少房主所选挑战或版本不兼容"),
                    function() end,
                    false,
                    nil,
                    nil,
                    deps.accent
                )
            end
            if not host then
                ruleEntry()
            end
            if #settings > 0 then
                local index = #rows + 1
                row(text("Mod 设置"), function()
                    ui.page, ui.selection, ui.listScroll, ui.modReturn = "modSettings", 1, 1, index
                end)
            end
            row(text("离开房间"), function()
                command("close")
            end)
        elseif phase == Phase.running then
            if (status.pause or 0) == 0 then
                row(text("暂停全队"), function()
                    command("control", tostring(Command.pause))
                end)
            else
                row(text("解除暂停"), function()
                    if command("control", tostring(Command.resume)) then
                        deps.hide()
                    end
                end, localSlot == status.pauseOwner)
            end
            row(text(challenge and "结束挑战" or "保存并退出"), function()
                command("control", tostring(Command.saveExit))
            end)
            row(text("关闭菜单"), function()
                deps.hide()
            end)
        else
            notice = phase == Phase.returning and "returning" or "waiting"
            if not status.prepared then
                row(text("离开房间"), function()
                    command("close")
                end)
            end
        end
        return rows, notice, ruleCount
    end
    return {
        rows = rows,
        validPort = validPort,
        remember = remember,
        idle = idle,
        back = back,
        compatibilityError = compatibilityError,
    }
end
