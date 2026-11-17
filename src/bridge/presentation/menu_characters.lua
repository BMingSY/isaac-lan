-- Random is a local menu entry. Ready publishes a concrete, eligible character.
return function()
    local RANDOM = -1
    local function pool(choices, catalog, tainted)
        local result = {}
        for _, id in ipairs(choices) do
            local entry = catalog[tostring(id)]
            if (entry and entry.tainted == true or false) == tainted then
                result[#result + 1] = id
            end
        end
        return result
    end
    local function contains(choices, id)
        for _, value in ipairs(choices) do
            if value == id then
                return true
            end
        end
        return false
    end
    local function selection(ui, choice, ready, editable, choices, catalog, command, random)
        local pending = ui.randomCharacter
        if pending and (not editable or pending.choice ~= choice) then
            ui.randomCharacter = nil
            pending = nil
        end
        local entry = catalog[tostring(choice)]
        local tainted = entry and entry.tainted == true or false
        if pending then
            tainted = pending.tainted
        end
        local current, alternate =
            pool(choices, catalog, tainted), pool(choices, catalog, not tainted)
        if #current == 0 then
            ui.randomCharacter, pending = nil, nil
            tainted = entry and entry.tainted == true or false
            current, alternate =
                pool(choices, catalog, tainted), pool(choices, catalog, not tainted)
        end
        local function select(id, group)
            if id == RANDOM then
                ui.randomCharacter = { choice = choice, tainted = group }
            elseif command("choose", id .. ":0") then
                ui.randomCharacter = nil
            end
        end
        local function cycle(delta)
            if not editable or #current == 0 then
                return
            end
            local index = 0
            if not pending then
                for i, id in ipairs(current) do
                    if id == choice then
                        index = i
                        break
                    end
                end
            end
            local nextIndex = (index + delta) % (#current + 1)
            select(current[nextIndex] or RANDOM, tainted)
        end
        local function toggle()
            if not editable or #alternate == 0 then
                return
            end
            local counterpart = not pending and entry and entry.counterpart
            select(contains(alternate, counterpart) and counterpart or RANDOM, not tainted)
        end
        local function prepare()
            local id = choice
            if pending and not ready then
                if #current == 0 then
                    return
                end
                id = contains(current, pending.resolved) and pending.resolved
                    or current[random(#current)]
            end
            if command("choose", id .. (ready and ":0" or ":1")) then
                if pending and not ready then
                    -- Guests receive their ready choice asynchronously. Repeated
                    -- confirmation before that acknowledgement must not reroll.
                    pending.resolved = id
                else
                    ui.randomCharacter = nil
                end
            end
        end
        return {
            id = pending and RANDOM or choice,
            label = pending and (tainted and "随机里角色" or "随机角色") or nil,
            enabled = editable and #current > 0,
            canPrepare = ready or #current > 0 and (pending ~= nil or contains(current, choice)),
            cycle = cycle,
            toggle = toggle,
            prepare = prepare,
        }
    end
    return { random = RANDOM, selection = selection }
end
