-- A bounded value codec, separate from the array-only native world schema.
local codec = { MAX_BYTES = 2048 }
function codec.encode(value)
    local chunks, seen, entries = {}, {}, 0
    local function write(v, depth)
        assert(depth <= 6, "payload_depth")
        local kind = type(v)
        if kind == "boolean" then
            chunks[#chunks + 1] = v and "T" or "F"
        elseif kind == "number" then
            assert(v == v and math.abs(v) < math.huge, "payload_number")
            chunks[#chunks + 1] = math.type(v) == "integer" and ("I" .. string.pack(">i8", v))
                or ("N" .. string.pack(">d", v))
        elseif kind == "string" then
            assert(#v <= 512, "payload_string")
            chunks[#chunks + 1] = "S" .. string.pack(">I2", #v) .. v
        elseif kind == "table" then
            assert(not getmetatable(v) and not seen[v], "payload_table")
            seen[v] = true
            local keys, array = {}, true
            for k in pairs(v) do
                keys[#keys + 1] = k
                array = array and type(k) == "number" and math.type(k) == "integer" and k >= 1
            end
            entries = entries + #keys
            assert(entries <= 128, "payload_entries")
            if array then
                table.sort(keys)
                for i, k in ipairs(keys) do
                    assert(i == k, "payload_array")
                end
            else
                for _, k in ipairs(keys) do
                    assert(type(k) == "string" and #k <= 64, "payload_key")
                end
                table.sort(keys)
            end
            chunks[#chunks + 1] = (array and "A" or "R") .. string.pack(">I2", #keys)
            for _, k in ipairs(keys) do
                if not array then
                    write(k, depth + 1)
                end
                write(v[k], depth + 1)
            end
            seen[v] = nil
        else
            error("payload_type")
        end
    end
    write(value, 0)
    local bytes = table.concat(chunks)
    assert(#bytes <= codec.MAX_BYTES, "payload_size")
    return bytes
end
function codec.decode(bytes)
    assert(type(bytes) == "string" and #bytes <= codec.MAX_BYTES, "payload_size")
    local offset, entries = 1, 0
    local function read(depth)
        assert(depth <= 6 and offset <= #bytes, "payload_depth_or_truncated")
        local tag = bytes:sub(offset, offset)
        offset = offset + 1
        if tag == "T" then
            return true
        end
        if tag == "F" then
            return false
        end
        if tag == "I" then
            local value
            value, offset = string.unpack(">i8", bytes, offset)
            return value
        end
        if tag == "N" then
            local value
            value, offset = string.unpack(">d", bytes, offset)
            assert(value == value and math.abs(value) < math.huge, "payload_number")
            return math.tointeger(value) or value
        end
        local count
        count, offset = string.unpack(">I2", bytes, offset)
        if tag == "S" then
            assert(count <= 512 and offset + count - 1 <= #bytes, "payload_string")
            local value = bytes:sub(offset, offset + count - 1)
            offset = offset + count
            return value
        end
        assert(tag == "A" or tag == "R", "payload_tag")
        entries = entries + count
        assert(entries <= 128, "payload_entries")
        local result = {}
        for i = 1, count do
            local key = tag == "A" and i or read(depth + 1)
            assert(
                tag == "A" or (type(key) == "string" and #key <= 64 and result[key] == nil),
                "payload_key"
            )
            result[key] = read(depth + 1)
        end
        return result
    end
    local value = read(0)
    assert(offset == #bytes + 1, "payload_trailing")
    return value
end
return codec
