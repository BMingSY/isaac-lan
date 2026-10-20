-- /feedback: the native side packs recent logs and uploads them on a worker.
-- The result returns through poll() to the sink that issued the request.
return function(deps)
    local feedback = {}
    local reply
    function feedback.submit(description, sink)
        local ok, message =
            deps.submit(description, table.concat(deps.mods(), "\n"), deps.context())
        if ok then
            reply = sink
        end
        return message
    end
    function feedback.poll()
        if not reply then
            return
        end
        local _, message = deps.poll()
        if message == nil then
            return
        end
        local sink = reply
        reply = nil
        sink(message)
    end
    return feedback
end
