local root = assert(arg[1])
local endpoint = dofile(root .. "/src/bridge/core/endpoint.lua")
for _, case in ipairs({
    { "127.0.0.1", "127.0.0.1:29506" },
    { "room.example.com", "room.example.com:29506" },
    { "::1", "[::1]:29506" },
    { "2001:db8::abcd", "[2001:db8::abcd]:29506" },
    { "[2001:db8::abcd]", "[2001:db8::abcd]:29506" },
    { "fe80::1%12", "[fe80::1%12]:29506" },
    { "::ffff:192.168.1.1", "[::ffff:192.168.1.1]:29506" },
}) do
    assert(endpoint.format(case[1], 29506) == case[2])
    local host, port = endpoint.parse(case[2])
    assert(host == (case[1]:match("^%[(.*)%]$") or case[1]) and port == 29506)
end
for _, invalid in ipairs({
    "",
    "::1:29506",
    "[::1]",
    "[::1]:0",
    "[::1]:65536",
    "[::1]:1.5",
    "[::1]:1:2",
    "[::1:29506",
    "[localhost]:29506",
    "[127.0.0.1]:29506",
    "bad host:29506",
    "host:29506\n",
    "https://host:29506",
}) do
    assert(not endpoint.parse(invalid), "Accepted malformed endpoint: " .. invalid)
end
print("PASS IPv4, domain, IPv6 and scoped command endpoints")
