-- Dense combat views expose a sequence of identity-keyed tuples to the byte
-- compressor. The header and every row belong to the same immutable tick.
return function(fields)
    local entityField = fields.room.entities
    local signature, header = "IRF\1", ">I4"
    local denseRows, maximumRows, maximumBytes = 64, 4096, 2 * 1024 * 1024
    local headerBytes = #signature + string.packsize(header)
    local function encode(view, schema, codec, memo)
        local rows = view.room[entityField]
        if #rows < denseRows or #rows > maximumRows then
            return codec(schema.pack(view), memo)
        end
        local headRoom = table.move(view.room, 1, #view.room, 1, {})
        headRoom[entityField] = false
        local head = setmetatable({ room = headRoom }, { __index = view })
        local prefix = codec(schema.pack(head), memo)
        local data = codec(rows, memo)
        if #prefix + #data + headerBytes > maximumBytes then
            return codec(schema.pack(view), memo)
        end
        return signature .. string.pack(header, #prefix) .. prefix .. data
    end
    local function decode(bytes, schema, codec)
        if bytes:sub(1, #signature) ~= signature then
            return codec(bytes)
        end
        local size, start = string.unpack(header, bytes, #signature + 1)
        assert(
            #bytes <= maximumBytes and size > 0 and start + size <= #bytes,
            "Invalid combat frame"
        )
        local packed = codec(bytes:sub(start, start + size - 1))
        local view = schema.unpack(packed, packed[2])
        assert(view.room[entityField] == false, "Duplicate combat records")
        local rows = codec(bytes:sub(start + size))
        assert(
            type(rows) == "table" and #rows >= denseRows and #rows <= maximumRows,
            "Invalid combat rows"
        )
        view.room[entityField] = rows
        return packed
    end
    return { encode = encode, decode = decode }
end
