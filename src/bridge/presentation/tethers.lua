-- Native rope geometry is presentation state; replica familiar AI never runs.
return function(native, Vector, Sprite, types, entities)
    local key = "__isaac_lan_tether"
    local function shifted(record, entity)
        local value, owner = record.value, record.owner
        local head = owner and owner:Exists() and owner.Position - Vector(value[4][1], value[4][2])
            or Vector(0, 0)
        local tail = entity.Position - Vector(value[5][1], value[5][2])
        local count, cursor = string.unpack(">I2", value[1])
        local points = {}
        for i = 1, count do
            local x, y, z
            x, y, z, cursor = string.unpack(">fff", value[1], cursor)
            points[i] = { x, y, z }
        end
        if count < 2 then
            return value[1]
        end
        local function distance(p)
            return (p[1] - value[4][1]) ^ 2 + (p[2] - value[4][2]) ^ 2
        end
        if distance(points[1]) > distance(points[count]) then
            head, tail = tail, head
        end
        local bytes = { string.pack(">I2", count) }
        for i, point in ipairs(points) do
            local t = (i - 1) / (count - 1)
            local delta = head * (1 - t) + tail * t
            bytes[#bytes + 1] =
                string.pack(">fff", point[1] + delta.X, point[2] + delta.Y, point[3])
        end
        return table.concat(bytes)
    end
    return {
        capture = function(entity, id, sprite)
            if entity.Type ~= types.ENTITY_FAMILIAR then
                return false
            end
            local bytes, texture = native.familiar_tether(entity:GetSprite())
            if not bytes then
                return false
            end
            local owner = entity:ToFamiliar().Player
            if not owner then
                return false
            end
            return {
                bytes,
                sprite(texture),
                id(owner),
                { owner.Position.X, owner.Position.Y },
                { entity.Position.X, entity.Position.Y },
            }
        end,
        apply = function(entity, value, applySprite)
            local data = entity:GetData()
            if not value then
                data[key] = nil
                return
            end
            local record = data[key] or { sprite = Sprite() }
            record.value = value
            applySprite(record.sprite, value[2])
            data[key] = record
        end,
        link = function(entity, value, ref)
            local record = entity:GetData()[key]
            if record then
                record.owner = ref(value[3])
            end
        end,
        render = function()
            for _, entity in ipairs(entities()) do
                local record = entity:GetData()[key]
                if record and entity.Visible then
                    assert(
                        native.familiar_tether_render(
                            entity:GetSprite(),
                            record.sprite,
                            shifted(record, entity)
                        )
                    )
                end
            end
        end,
    }
end
