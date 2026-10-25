-- Command endpoints use brackets to distinguish IPv6 colons from the port.
local function format(host, port)
    if host:find(":", 1, true) and host:sub(1, 1) ~= "[" then
        host = "[" .. host .. "]"
    end
    return host .. ":" .. tostring(port)
end
local function parse(value)
    local host, port = value:match("^%[([%x:%.%%]+)%]:(%d+)$")
    if not host then
        host, port = value:match("^([a-zA-Z0-9%.%-]+):(%d+)$")
    elseif not host:find(":", 1, true) then
        return nil
    end
    port = tonumber(port)
    if host and port and port >= 1 and port <= 65535 then
        return host, port
    end
end
return { format = format, parse = parse }
