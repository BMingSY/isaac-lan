-- Restart and animation consent share the reliable lifecycle transport.
return function(send, receive)
    local ports = {}
    local function port(id)
        local queue, first = {}, 1
        local value = {
            send = function(slot, bytes)
                return send(slot, string.char(id) .. bytes)
            end,
            receive = function()
                local message = queue[first]
                if not message then
                    return
                end
                first = first + 1
                if first > #queue then
                    queue, first = {}, 1
                end
                return message[1], message[2]
            end,
            accept = function(slot, bytes)
                queue[#queue + 1] = { slot, bytes }
            end,
        }
        ports[id] = value
        return value
    end
    local restart, animation = port(1), port(2)
    return {
        restart = restart,
        animation = animation,
        poll = function()
            while true do
                local sender, bytes = receive()
                if sender == nil then
                    return
                end
                local destination = type(bytes) == "string" and ports[bytes:byte(1)]
                if destination then
                    destination.accept(sender, bytes:sub(2))
                end
            end
        end,
    }
end
