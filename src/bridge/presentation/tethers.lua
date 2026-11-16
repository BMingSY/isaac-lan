-- Native rope geometry is presentation state; replica familiar AI never runs.
return function(native, Vector, Sprite, types, pointer)
    local records, generation = {}, 0
    local function shifted(record, entity)
        local value, owner = record.value, record.owner and record.owner.Ref
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
        apply = function(entity, value, applySprite, identifier)
            if not value then
                records[identifier] = nil
                return
            end
            local record = records[identifier] or { sprite = Sprite() }
            record.entity = pointer(entity)
            record.value = value
            record.generation = generation
            applySprite(record.sprite, value[2])
            records[identifier] = record
        end,
        link = function(_, value, ref, identifier)
            local record = records[identifier]
            if record then
                local owner = ref(value[3])
                record.owner = owner and pointer(owner)
            end
        end,
        render = function()
            for identifier, record in pairs(records) do
                local entity = record.entity.Ref
                if not entity or not entity:Exists() then
                    records[identifier] = nil
                elseif entity.Visible then
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
        reset = function()
            records, generation = {}, 0
        end,
        beginView = function()
            generation = generation + 1
        end,
        endView = function()
            for identifier, record in pairs(records) do
                if record.generation ~= generation then
                    records[identifier] = nil
                end
            end
        end,
    }
end
