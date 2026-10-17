-- A scenario owns its callbacks and cleanup, including callbacks added while
-- running. It returns { done = function, cleanup = optional function }.
return function(load, active, dispatch)
    local callbacks, owners, cleaned, contract, loading = {}, {}, false, nil, true
    local originalAdd, originalRemove = Isaac.AddCallback, Isaac.RemoveCallback
    local options = {}
    for key, value in pairs(_IsaacLanTest or {}) do
        options[key] = value
    end
    local scope = {}
    function scope.call(fn, ...)
        local previousAdd, previousRemove, previousOptions =
            Isaac.AddCallback, Isaac.RemoveCallback, _IsaacLanTest
        _IsaacLanTest = options
        Isaac.AddCallback = function(owner, id, callback, ...)
            if not loading and not owners[owner] then
                return originalAdd(owner, id, callback, ...)
            end
            owners[owner] = true
            local wrapped = function(...)
                if not cleaned and (not active or active()) then
                    if dispatch then
                        return dispatch(callback, ...)
                    end
                    return scope.call(callback, ...)
                end
            end
            callbacks[#callbacks + 1] = { owner, id, wrapped, callback }
            return originalAdd(owner, id, wrapped, ...)
        end
        Isaac.RemoveCallback = function(owner, id, callback)
            for index = #callbacks, 1, -1 do
                local entry = callbacks[index]
                if entry[1] == owner and entry[2] == id and entry[4] == callback then
                    originalRemove(owner, id, entry[3])
                    table.remove(callbacks, index)
                    return
                end
            end
            return originalRemove(owner, id, callback)
        end
        local values = table.pack(pcall(fn, ...))
        Isaac.AddCallback, Isaac.RemoveCallback, _IsaacLanTest =
            previousAdd, previousRemove, previousOptions
        if not values[1] then
            if contract and not cleaned then
                local ok, message = pcall(scope.cleanup)
                if not ok then
                    values[2] = tostring(values[2]) .. "; cleanup: " .. tostring(message)
                end
            end
            error(values[2], 0)
        end
        return table.unpack(values, 2, values.n)
    end
    function scope.cleanup()
        if cleaned then
            return
        end
        cleaned = true
        local errors = {}
        local function attempt(fn, ...)
            local ok, message = pcall(fn, ...)
            if not ok then
                errors[#errors + 1] = tostring(message)
            end
        end
        if contract and contract.cleanup then
            attempt(scope.call, contract.cleanup)
        end
        for _, callback in ipairs(callbacks) do
            attempt(originalRemove, callback[1], callback[2], callback[3])
        end
        attempt(_IsaacLan.test_gamepad, 0)
        assert(#errors == 0, table.concat(errors, "; "))
    end
    local ok, value = pcall(scope.call, load)
    loading = false
    if not ok then
        local cleanedOk, cleanupError = pcall(scope.cleanup)
        error(tostring(value) .. (cleanedOk and "" or "; cleanup: " .. tostring(cleanupError)), 0)
    end
    contract = value
    if type(contract) ~= "table" or type(contract.done) ~= "function" then
        contract = nil
        scope.cleanup()
        error("Scenario must return a done function", 0)
    end
    function scope.done()
        local value = scope.call(contract.done)
        if type(value) ~= "boolean" then
            scope.cleanup()
            error("Scenario done must return a boolean", 0)
        end
        return value
    end
    return scope
end
