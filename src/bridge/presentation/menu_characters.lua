-- Lobby random choices remain deferred until the runtime launches the game.
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
    local function selection(choice, ready, deferred, editable, choices, catalog, command)
        local entry = catalog[tostring(choice)]
        local tainted = entry and entry.tainted == true or false
        local current, alternate =
            pool(choices, catalog, tainted), pool(choices, catalog, not tainted)
        local function select(id, group)
            if id == RANDOM then
                command("choose_random", (group and "1" or "0") .. ":0")
            else
                command("choose", id .. ":0")
            end
        end
        local function cycle(delta)
            if not editable or #current == 0 then
                return
            end
            local index = 0
            if not deferred then
                for i, id in ipairs(current) do
                    if id == choice then
                        index = i
                        break
                    end
                end
            end
            select(current[(index + delta) % (#current + 1)] or RANDOM, tainted)
        end
        local function toggle()
            if not editable or #alternate == 0 then
                return
            end
            local counterpart = not deferred and entry and entry.counterpart
            select(contains(alternate, counterpart) and counterpart or RANDOM, not tainted)
        end
        local function prepare()
            if deferred then
                command("choose_random", (tainted and "1" or "0") .. (ready and ":0" or ":1"))
            else
                command("choose", choice .. (ready and ":0" or ":1"))
            end
        end
        return {
            label = deferred and "?" or nil,
            enabled = editable and #current > 0,
            canToggle = editable and #alternate > 0,
            canPrepare = ready or #current > 0 and (deferred or contains(current, choice)),
            cycle = cycle,
            toggle = toggle,
            prepare = prepare,
        }
    end
    return { random = RANDOM, selection = selection }
end
