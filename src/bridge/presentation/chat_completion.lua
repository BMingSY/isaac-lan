-- Local suggestions only; command execution remains owned by the chat service.
return function(roomDefinitions, maxBytes)
    assert(maxBytes, "Chat command byte limit is required")
    local commands = {
        { names = { "help", "h" }, detail = "查看命令" },
        { names = { "c", "console" }, detail = "原版控制台", usage = "<原版命令>" },
        { names = { "tp" }, detail = "传送", usage = "<房间/玩家/坐标>" },
        { names = { "lanbot" }, detail = "本机托管", usage = "<操作>" },
        { names = { "opacity" }, detail = "玩家不透明度", usage = "<玩家> <0～100>" },
        { names = { "feedback", "fb" }, detail = "提交反馈", usage = "<反馈内容>" },
        { names = { "e", "echo" }, detail = "本机输出", usage = "<文字>" },
        { names = { "d6" }, detail = "掷六面骰" },
        { names = { "2d6" }, detail = "掷两颗六面骰" },
        { names = { "d20" }, detail = "掷二十面骰" },
        { names = { "d100" }, detail = "掷百分骰" },
        { names = { "d100b" }, detail = "奖励骰" },
        { names = { "d100p" }, detail = "惩罚骰" },
    }
    local nativeCommands = {
        { names = { "help" }, detail = "原版命令帮助" },
        { names = { "giveitem", "g" }, detail = "给予道具", usage = "<道具ID>" },
        { names = { "remove" }, detail = "移除道具", usage = "<道具ID>" },
        { names = { "debug" }, detail = "调试开关", usage = "<编号>" },
        { names = { "stage" }, detail = "切换楼层", usage = "<楼层编号>" },
        { names = { "goto" }, detail = "进入房间", usage = "<房间标识>" },
        { names = { "spawn" }, detail = "生成实体", usage = "<类型.变种.子类型>" },
        { names = { "seed" }, detail = "种子", usage = "<种子>" },
        { names = { "restart" }, detail = "重新开始" },
        { names = { "clear" }, detail = "清空原版控制台" },
        { names = { "lua" }, detail = "执行 Lua", usage = "<代码>" },
        { names = { "luarun" }, detail = "执行 Lua 文件", usage = "<文件名>" },
    }
    local botCommands = {
        { names = { "on" }, detail = "开启托管" },
        { names = { "pause" }, detail = "暂停托管" },
        { names = { "resume" }, detail = "恢复托管" },
        { names = { "off" }, detail = "关闭托管" },
        { names = { "status" }, detail = "查看状态" },
        { names = { "next" }, detail = "前往下一层" },
        { names = { "mode" }, detail = "行动模式", usage = "<run|explore|hold>" },
        { names = { "style" }, detail = "战斗风格", usage = "<aggressive|balanced|cautious>" },
        { names = { "help" }, detail = "托管帮助" },
    }
    local modes = {
        { names = { "run" }, detail = "推进路线" },
        { names = { "explore" }, detail = "探索当前层" },
        { names = { "hold" }, detail = "留在当前房间" },
    }
    local styles = {
        { names = { "aggressive" }, detail = "激进" },
        { names = { "balanced" }, detail = "均衡" },
        { names = { "cautious" }, detail = "谨慎" },
    }
    local players = {}
    for slot = 1, 4 do
        players[#players + 1] = { names = { slot .. "p" }, detail = slot .. "P 玩家" }
    end
    local targets = {
        { names = { "start", "st" }, detail = "起始房" },
        { names = { "list", "l" }, detail = "列出房间" },
        { names = { "room", "r" }, detail = "地图坐标", usage = "<x> <y>" },
        { names = { "help", "h" }, detail = "传送帮助" },
    }
    for _, definition in ipairs(roomDefinitions) do
        if definition.aliases then
            targets[#targets + 1] = { names = definition.aliases, detail = definition.name }
        end
    end
    local opacityTargets = {
        { names = { "others" }, detail = "其他玩家" },
        { names = { "reset" }, detail = "恢复默认值" },
        { names = { "help" }, detail = "不透明度帮助" },
    }
    for _, player in ipairs(players) do
        targets[#targets + 1] = player
        opacityTargets[#opacityTargets + 1] = player
    end
    local percentages = {}
    for _, value in ipairs({ 0, 25, 50, 75, 100 }) do
        percentages[#percentages + 1] = { names = { tostring(value) }, detail = value .. "%" }
    end
    local function named(definitions, name)
        for _, definition in ipairs(definitions) do
            for _, alias in ipairs(definition.names) do
                if alias == name then
                    return definition
                end
            end
        end
    end
    local function suggestions(definitions, prefix, fragment)
        local exact, partial = {}, {}
        for _, definition in ipairs(definitions) do
            local match
            for _, alias in ipairs(definition.names) do
                if alias == fragment then
                    match = alias
                    break
                elseif not match and alias:sub(1, #fragment) == fragment then
                    match = alias
                end
            end
            if match then
                local value = prefix .. match .. " "
                if #value <= maxBytes then
                    local rows = match == fragment and exact or partial
                    rows[#rows + 1] = { value = value, label = match, detail = definition.detail }
                end
            end
        end
        for _, row in ipairs(partial) do
            exact[#exact + 1] = row
        end
        return exact
    end
    local function query(text)
        local leading, name, space, args = text:match("^(%s*)/([^%s]*)(%s*)(.*)$")
        if not name then
            return {}, nil
        end
        if space == "" then
            local rows = suggestions(commands, leading .. "/", name:lower())
            for _, row in ipairs(rows) do
                row.label = "/" .. row.label
            end
            return rows
        end
        local command = named(commands, name:lower())
        if not command then
            return {}, nil
        end
        local usage = "/" .. name .. (command.usage and " " .. command.usage or "")
        local words = {}
        for word in args:gmatch("%S+") do
            words[#words + 1] = word:lower()
        end
        local argument = #words + (text:match("%s$") and 1 or 0)
        local definitions
        if command.names[1] == "c" then
            if argument == 1 then
                definitions = nativeCommands
            else
                local nativeCommand = named(nativeCommands, words[1])
                if nativeCommand then
                    usage = "/"
                        .. name
                        .. " "
                        .. words[1]
                        .. (nativeCommand.usage and " " .. nativeCommand.usage or "")
                else
                    usage = nil
                end
            end
        elseif command.names[1] == "tp" then
            if argument == 1 then
                definitions = targets
            elseif words[1] == "r" or words[1] == "room" then
                usage = "/" .. name .. " " .. words[1] .. " <x> <y>"
            end
        elseif command.names[1] == "lanbot" then
            if argument == 1 then
                definitions = botCommands
            elseif words[1] == "mode" then
                usage = "/" .. name .. " mode <run|explore|hold>"
                definitions = argument == 2 and modes or nil
            elseif words[1] == "style" then
                usage = "/" .. name .. " style <aggressive|balanced|cautious>"
                definitions = argument == 2 and styles or nil
            end
        elseif command.names[1] == "opacity" then
            if argument == 1 then
                definitions = opacityTargets
            elseif argument == 2 and (words[1] == "others" or words[1]:match("^[1-4]p$")) then
                usage = "/" .. name .. " " .. words[1] .. " <0～100>"
                definitions = percentages
            end
        end
        if not definitions then
            return {}, usage
        end
        local prefix, fragment = text:match("^(.-)([^%s]*)$")
        return suggestions(definitions, prefix, fragment:lower()), usage
    end
    local model = { rows = {}, selected = 1 }
    function model.reset()
        model.rows, model.selected, model.usage = {}, 1, nil
        model.text, model.applied = nil, nil
    end
    function model.update(input)
        if
            not input.open
            or input.composing
            or (input.composition and input.composition ~= "")
            or input.cursor ~= #input.text
            or input.anchor ~= input.cursor
            or #input.text > maxBytes
        then
            model.reset()
        elseif input.text ~= model.text then
            if input.text ~= model.applied or #model.rows <= 1 then
                model.rows, model.usage = query(input.text)
                model.selected, model.applied = 1, nil
            end
            model.text = input.text
        end
    end
    function model.advance(input)
        model.update(input)
        if #model.rows == 0 then
            return
        end
        if model.applied then
            model.selected = model.selected % #model.rows + 1
        end
        model.applied = model.rows[model.selected].value
        return model.applied
    end
    return model
end
