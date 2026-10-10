-- Portable state wire format; shared by the engine and offline tests.
local pack, unpack = string.pack, string.unpack
local function encode(value)
    local pieces, path = {}, {}
    local function put(v, depth)
        assert(depth < 12, "State nesting exceeded")
        local t = type(v)
        if t == "boolean" then
            pieces[#pieces + 1] = v and "\1" or "\0"
        elseif t == "number" then
            if math.type(v) == "integer" then
                if v >= -2147483648 and v <= 2147483647 then
                    pieces[#pieces + 1] = pack(">Bi4", 2, v)
                else
                    pieces[#pieces + 1] = pack(">Bi8", 3, v)
                end
            else
                assert(
                    v == v and math.abs(v) < math.huge,
                    "Non-finite state value at [" .. table.concat(path, "][") .. "]"
                )
                pieces[#pieces + 1] = pack(">Bf", 4, v)
            end
        elseif t == "string" then
            assert(#v <= 65535)
            pieces[#pieces + 1] = pack(">Bs2", 5, v)
        elseif t == "table" then
            assert(#v <= 65535)
            pieces[#pieces + 1] = pack(">BI2", 6, #v)
            for i = 1, #v do
                path[depth + 1] = i
                put(v[i], depth + 1)
                path[depth + 1] = nil
            end
        else
            error("Unsupported state value: " .. t .. " at [" .. table.concat(path, "][") .. "]")
        end
    end
    put(value, 0)
    return table.concat(pieces)
end
local function decode(bytes)
    assert(#bytes <= 2 * 1024 * 1024, "State size exceeded")
    local cursor, nodes = 1, 0
    local function read(format)
        local value
        value, cursor = unpack(">" .. format, bytes, cursor)
        return value
    end
    local function get(depth)
        nodes = nodes + 1
        assert(depth < 12 and nodes < 250000, "State structure exceeded")
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
