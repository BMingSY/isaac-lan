return function(deps)
    local slots, maximum = 4, 100
    local overrides, others, applied = {}, deps.default, nil
    local help = "/opacity 1p～4p 0～100：玩家不透明度\n"
        .. "/opacity others 0～100：其他玩家不透明度\n"
        .. "/opacity reset：恢复配置默认值"
    local function step()
        local slot = deps.info().slot
        local active = slot and slot >= 0 and slot < slots
        local values = {}
        local changed = not applied
        for owner = 0, slots - 1 do
            local value = maximum
            if active then
                value = overrides[owner] or (owner == slot and maximum or others)
            end
            values[owner + 1] = value
            changed = changed or applied[owner + 1] ~= value
        end
        if changed then
            assert(deps.apply(table.unpack(values)), "无法应用玩家不透明度")
            applied = values
        end
    end
    local function reset()
        overrides, others = {}, deps.default
        step()
    end
    return {
        step = step,
        reset = reset,
        command = function(args)
            args = args:lower():match("^%s*(.-)%s*$")
            if args == "" or args == "help" then
                return help
            end
            if args == "reset" then
                reset()
                return "玩家不透明度已恢复配置默认值"
            end
            local target, text = args:match("^(%S+)%s+(%d+)$")
            local value = text and tonumber(text)
            if not value or value > maximum then
                return help
            end
            local slot = deps.info().slot
            if not slot or slot < 0 or slot >= slots then
                return "请先创建或加入联机会话"
            end
            if target == "others" then
                others = value
                for owner = 0, slots - 1 do
                    if owner ~= slot then
                        overrides[owner] = nil
                    end
                end
            else
                local owner = target:match("^([1-4])p$")
                if not owner then
                    return help
                end
                overrides[tonumber(owner) - 1] = value
            end
            step()
            return (target == "others" and "其他玩家" or target:upper())
                .. "不透明度："
                .. value
                .. "%"
        end,
    }
end
