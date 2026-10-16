-- Portable state wire format; shared by the engine and offline tests.
local pack, unpack = string.pack, string.unpack
local Tag =
    { falseValue = 0, trueValue = 1, int32 = 2, int64 = 3, float32 = 4, string = 5, array = 6 }
local FALSE_BYTE, TRUE_BYTE = string.char(Tag.falseValue), string.char(Tag.trueValue)
local MAX_DEPTH, MAX_NODES = 12, 250000
local MAX_LENGTH, MAX_STATE_BYTES = 65535, 2 * 1024 * 1024
local MIN_INT32, MAX_INT32 = -2147483648, 2147483647
-- Optional memo entries explicitly mark immutable shared tuples with false;
-- after validation, their complete encoded fragments can be reused this tick.
local function encode(value, memo)
    local pieces, path = {}, {}
    local nodes, size = 0, 0
    local function append(bytes)
        size = size + #bytes
        assert(size <= MAX_STATE_BYTES, "State size exceeded")
        pieces[#pieces + 1] = bytes
    end
    local function put(v, depth)
        nodes = nodes + 1
        assert(depth < MAX_DEPTH and nodes < MAX_NODES, "State structure exceeded")
        local deepest = depth
        local t = type(v)
        if t == "boolean" then
            append(v and TRUE_BYTE or FALSE_BYTE)
        elseif t == "number" then
            if math.type(v) == "integer" then
                if v >= MIN_INT32 and v <= MAX_INT32 then
                    append(pack(">Bi4", Tag.int32, v))
                else
                    append(pack(">Bi8", Tag.int64, v))
                end
            else
                assert(
                    v == v and math.abs(v) < math.huge,
                    "Non-finite state value at [" .. table.concat(path, "][") .. "]"
                )
                local bytes = pack(">Bf", Tag.float32, v)
                assert(
                    math.abs(unpack(">f", bytes, 2)) < math.huge,
                    "Float32 state overflow at [" .. table.concat(path, "][") .. "]"
                )
                append(bytes)
            end
        elseif t == "string" then
            assert(#v <= MAX_LENGTH)
            append(pack(">Bs2", Tag.string, v))
        elseif t == "table" then
            local cached = memo and memo[v]
            if type(cached) == "table" then
                assert(depth + cached.depth < MAX_DEPTH, "State nesting exceeded")
                nodes = nodes + cached.nodes - 1
                assert(nodes < MAX_NODES, "State structure exceeded")
                append(cached.bytes)
                return depth + cached.depth
            end
            assert(#v <= MAX_LENGTH)
            local first = #pieces + 1
            local firstNode = nodes
            append(pack(">BI2", Tag.array, #v))
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
    assert(#bytes <= MAX_STATE_BYTES, "State size exceeded")
    local cursor, nodes = 1, 0
    local function read(format)
        local value
        value, cursor = unpack(">" .. format, bytes, cursor)
        return value
    end
    local function get(depth)
        nodes = nodes + 1
        assert(depth < MAX_DEPTH and nodes < MAX_NODES, "State structure exceeded")
        local tag = read("B")
        if tag == Tag.falseValue then
            return false
        elseif tag == Tag.trueValue then
            return true
        elseif tag == Tag.int32 then
            return read("i4")
        elseif tag == Tag.int64 then
            return read("i8")
        elseif tag == Tag.float32 then
            local n = read("f")
            assert(n == n and math.abs(n) < math.huge)
            return n
        elseif tag == Tag.string then
            return read("s2")
        elseif tag == Tag.array then
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
