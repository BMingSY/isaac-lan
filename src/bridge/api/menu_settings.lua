return function(log)
    local byKey, ordered = {}, {}
    local function label(value)
        return type(value) == "string" and value ~= "" and not value:find("%c")
    end
    local function register(namespace, def)
        assert(
            type(def) == "table"
                and type(def.id) == "string"
                and #def.id <= 64
                and def.id:match("^[%w_.%-]+$")
                and label(def.name),
            "invalid_menu_setting"
        )
        local key = namespace .. ":" .. def.id
        assert(not byKey[key], "duplicate_menu_setting")
        assert(type(def.choices) == "table" and #def.choices >= 2, "invalid_menu_choices")
        local choices = {}
        for i = 1, #def.choices do
            assert(label(def.choices[i]), "invalid_menu_choice")
            choices[i] = def.choices[i]
        end
        local selected = def.selected == nil and 1 or def.selected
        assert(math.type(selected) == "integer" and choices[selected], "invalid_menu_selection")
        assert(type(def.onChange) == "function", "invalid_menu_handler")
        local entry = { key = key, name = def.name, value = choices[selected] }
        local onChange = def.onChange
        local function remove()
            if byKey[key] == entry then
                byKey[key] = nil
                for i, value in ipairs(ordered) do
                    if value == entry then
                        table.remove(ordered, i)
                        break
                    end
                end
            end
        end
        function entry.change(delta)
            if byKey[key] ~= entry then
                return
            end
            local nextIndex = (selected - 1 + delta) % #choices + 1
            local ok, reason = pcall(onChange, nextIndex)
            if ok then
                selected, entry.value = nextIndex, choices[nextIndex]
            else
                remove()
                log(key .. " menu_setting_disabled=" .. tostring(reason))
            end
        end
        byKey[key] = entry
        ordered[#ordered + 1] = entry
        table.sort(ordered, function(a, b)
            return a.key < b.key
        end)
        return remove
    end
    return { register = register, entries = ordered }
end
