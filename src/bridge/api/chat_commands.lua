-- One directory for built-in names, Mod handlers, help and local completion.
return function(maxBytes)
    local rebirth = {
        names = { "rebirth" },
        detail = "让自己或队友重生",
        usage = "[1p-4p]",
    }
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
        rebirth,
    }
    local registry = { entries = commands, byName = {}, revision = 0 }
    for _, entry in ipairs(commands) do
        for _, name in ipairs(entry.names) do
            registry.byName[name] = entry
        end
    end

    local function singleLine(value)
        return type(value) == "string" and value ~= "" and utf8.len(value) and not value:find("%c")
    end
    function registry.register(namespace, def)
        assert(type(def) == "table" and type(def.execute) == "function", "invalid_chat_command")
        assert(
            singleLine(def.description) and (def.usage == nil or singleLine(def.usage)),
            "invalid_chat_command_help"
        )
        local aliases = def.aliases
        assert(aliases == nil or type(aliases) == "table", "invalid_chat_aliases")
        local names, claimed = {}, {}
        local function add(value)
            assert(type(value) == "string" and #value <= 32, "invalid_chat_command_name")
            local name = value:lower()
            assert(
                name:match("^[a-z][a-z0-9_.%-]*$") and name ~= "d" and not name:match("^d%d"),
                "invalid_chat_command_name"
            )
            assert(not registry.byName[name] and not claimed[name], "duplicate_chat_command")
            names[#names + 1], claimed[name] = name, true
        end
        add(def.name)
        if aliases then
            for k in pairs(aliases) do
                assert(
                    math.type(k) == "integer" and k >= 1 and k <= #aliases,
                    "invalid_chat_aliases"
                )
            end
            for i = 1, #aliases do
                add(aliases[i])
            end
        end
        local help = "/"
            .. table.concat(names, " /")
            .. (def.usage and " " .. def.usage or "")
            .. "　"
            .. def.description
        assert(#help <= maxBytes, "chat_command_help_too_long")
        local entry = {
            names = names,
            detail = def.description,
            usage = def.usage,
            help = help,
            execute = def.execute,
            namespace = namespace,
        }
        for _, name in ipairs(names) do
            registry.byName[name] = entry
        end
        commands[#commands + 1] = entry
        registry.revision = registry.revision + 1
        return function()
            if registry.byName[names[1]] ~= entry then
                return
            end
            for _, name in ipairs(names) do
                registry.byName[name] = nil
            end
            for i, item in ipairs(commands) do
                if item == entry then
                    table.remove(commands, i)
                    break
                end
            end
            registry.revision = registry.revision + 1
        end
    end
    return registry
end
