local wrapping = {}
local debug = (_IsaacLan and _IsaacLan.debug) or debug
function wrapping.patch(cleanups, object, name, makeWrapper)
    local original = assert(object[name], "missing_method:" .. name)
    local wrapper = makeWrapper(original)
    object[name] = wrapper
    cleanups[#cleanups + 1] = function()
        if object[name] == wrapper then
            object[name] = original
        end
    end
    return wrapper
end
function wrapping.cleanup(cleanups)
    for i = #cleanups, 1, -1 do
        pcall(cleanups[i])
    end
end
-- Inspect only closures belonging to the fingerprinted Mod, with bounded depth.
function wrapping.find(fn, predicate)
    local seen, budget = {}, 600
    local priority = { self = 1, boundArgs = 1, callbackFn = 1, record = 1, fn = 2 }
    local function visit(value, depth)
        if budget == 0 or depth > 10 or seen[value] then
            return
        end
        budget = budget - 1
        if type(value) == "table" then
            seen[value] = true
            if predicate(value) then
                return value
            end
            if value.original then
                local found = visit(value.original, depth + 1)
                if found then
                    return found
                end
            end
            for key, child in pairs(value) do
                if type(key) == "number" then
                    local found = visit(child, depth + 1)
                    if found then
                        return found
                    end
                end
            end
        elseif type(value) == "function" then
            seen[value] = true
            local upvalues = {}
            for i = 1, 64 do
                local name, child = debug.getupvalue(value, i)
                if not name then
                    break
                end
                if name ~= "_ENV" then
                    upvalues[#upvalues + 1] = { name = name, child = child }
                end
            end
            table.sort(upvalues, function(a, b)
                return (priority[a.name] or 10) < (priority[b.name] or 10)
            end)
            for _, upvalue in ipairs(upvalues) do
                local found = visit(upvalue.child, depth + 1)
                if found then
                    return found
                end
            end
        end
    end
    return visit(fn, 0)
end
function wrapping.callbacks(target, dispatch)
    local cleanups, records = {}, {}
    target.callbacks = records
    local function wrap(id, fn, param, priority)
        local record = { id = id, original = fn, param = param, priority = priority }
        record.wrapper = function(...)
            return dispatch(record, ...)
        end
        records[#records + 1] = record
        return record.wrapper
    end
    if Isaac.GetCallbacks and ModCallbacks then
        local seenIds = {}
        for _, id in pairs(ModCallbacks) do
            if type(id) == "number" and not seenIds[id] then
                seenIds[id] = true
                for _, callback in ipairs(Isaac.GetCallbacks(id)) do
                    if callback.Mod == target.mod then
                        callback.Function =
                            wrap(id, callback.Function, callback.Param, callback.Priority)
                    end
                end
            end
        end
    end
    wrapping.patch(cleanups, target.mod, "AddCallback", function(original)
        return function(mod, id, fn, param)
            return original(mod, id, wrap(id, fn, param), param)
        end
    end)
    wrapping.patch(cleanups, target.mod, "AddPriorityCallback", function(original)
        return function(mod, id, priority, fn, param)
            return original(mod, id, priority, wrap(id, fn, param, priority), param)
        end
    end)
    wrapping.patch(cleanups, target.mod, "RemoveCallback", function(original)
        return function(mod, id, fn)
            for i = #records, 1, -1 do
                local record = records[i]
                if record.id == id and (record.original == fn or record.wrapper == fn) then
                    original(mod, id, record.wrapper)
                    table.remove(records, i)
                end
            end
            return original(mod, id, fn)
        end
    end)
    -- Dispatch can be disabled without removing/readding callbacks and changing order.
    return function()
        wrapping.cleanup(cleanups)
    end
end
return wrapping
