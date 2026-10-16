-- Portable state wire format; shared by the engine and offline tests.
local pack, unpack = string.pack, string.unpack
local maxBytes, maxNodes = 2 * 1024 * 1024, 250000
-- Optional memo entries explicitly mark immutable shared tuples with false;
-- after validation, their complete encoded fragments can be reused this tick.
local function encode(value, memo)
    local pieces, path = {}, {}
    local nodes, size = 0, 0
    local function append(bytes)
        size = size + #bytes
        assert(size <= maxBytes, "State size exceeded")
        pieces[#pieces + 1] = bytes
    end
    local function put(v, depth)
        nodes = nodes + 1
        assert(depth < 12 and nodes < maxNodes, "State structure exceeded")
        local deepest = depth
        local t = type(v)
        if t == "boolean" then
            append(v and "\1" or "\0")
        elseif t == "number" then
            if math.type(v) == "integer" then
                if v >= -2147483648 and v <= 2147483647 then
                    append(pack(">Bi4", 2, v))
                else
                    append(pack(">Bi8", 3, v))
                end
            else
                assert(
                    v == v and math.abs(v) < math.huge,
                    "Non-finite state value at [" .. table.concat(path, "][") .. "]"
                )
                local bytes = pack(">Bf", 4, v)
                assert(
                    math.abs(unpack(">f", bytes, 2)) < math.huge,
                    "Float32 state overflow at [" .. table.concat(path, "][") .. "]"
                )
                append(bytes)
            end
        elseif t == "string" then
            assert(#v <= 65535)
            append(pack(">Bs2", 5, v))
        elseif t == "table" then
            local cached = memo and memo[v]
            if type(cached) == "table" then
                assert(depth + cached.depth < 12, "State nesting exceeded")
                nodes = nodes + cached.nodes - 1
                assert(nodes < maxNodes, "State structure exceeded")
                append(cached.bytes)
                return depth + cached.depth
            end
            assert(#v <= 65535)
            local first = #pieces + 1
            local firstNode = nodes
            append(pack(">BI2", 6, #v))
            for i = 1, #v do
                path[depth + 1] = i
                local childDepth = put(v[i], depth + 1)
                if childDepth > deepest then
                    deepest = childDepth
                end
                path[depth + 1] = nil
            end
            if cached == false then
                local fragment = table.concat(pieces, "", first)
                for index = #pieces, first, -1 do
                    pieces[index] = nil
                end
                pieces[first] = fragment
                memo[v] =
                    { bytes = fragment, depth = deepest - depth, nodes = nodes - firstNode + 1 }
            end
        else
            error("Unsupported state value: " .. t .. " at [" .. table.concat(path, "][") .. "]")
        end
        return deepest
    end
    put(value, 0)
    return table.concat(pieces)
end
local function decode(bytes)
    assert(#bytes <= maxBytes, "State size exceeded")
    local cursor, nodes = 1, 0
    local function read(format)
        local value
        value, cursor = unpack(">" .. format, bytes, cursor)
        return value
    end
    local function get(depth)
        nodes = nodes + 1
        assert(depth < 12 and nodes < maxNodes, "State structure exceeded")
        local tag = read("B")
        if tag == 0 then
            return false
        elseif tag == 1 then
            return true
        elseif tag == 2 then
            return read("i4")
        elseif tag == 3 then
            return read("i8")
        elseif tag == 4 then
            local n = read("f")
            assert(n == n and math.abs(n) < math.huge)
            return n
        elseif tag == 5 then
            return read("s2")
        elseif tag == 6 then
            local t = {}
            local count = read("I2")
            for i = 1, count do
                t[i] = get(depth + 1)
            end
            return t
        end
        error("Unknown state value tag")
    end
    local result = get(0)
    assert(cursor == #bytes + 1, "Trailing state bytes")
    return result
end
return { encode = encode, decode = decode }
