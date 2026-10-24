-- Native rendering also queries TemporaryEffects (for example, IsHeadless).
-- Replicate the actual effect set, without replaying the originating item use.
return function(fields)
    local Effect = fields.temporaryEffect
    local kinds = { "Collectible", "Trinket", "Null" }
    local MAX_EFFECTS, MAX_COUNT, MAX_ID = 4096, 65535, 0x7fffffff
    local function capture(p)
        local result, list = {}, p:GetEffects():GetEffectsList()
        for i = 0, list.Size - 1 do
            local effect = list:Get(i)
            if effect.Count > 0 then
                local item, kind = assert(effect.Item)
                for index, name in ipairs(kinds) do
                    if item["Is" .. name](item) then
                        kind = index
                        break
                    end
                end
                assert(kind, "Unknown temporary effect kind")
                result[#result + 1] = { kind, item.ID, effect.Count } -- kind, id, count
            end
        end
        table.sort(result, function(a, b)
            return a[Effect.kind] < b[Effect.kind]
                or (a[Effect.kind] == b[Effect.kind] and a[Effect.id] < b[Effect.id])
        end)
        return result
    end
    local function apply(p, records)
        assert(type(records) == "table" and #records <= MAX_EFFECTS, "Invalid temporary effects")
        local desired = { {}, {}, {} }
        -- Validate everything before invoking any native setter.
        for _, value in ipairs(records) do
            assert(type(value) == "table" and #value == 3, "Invalid temporary effect record")
            local kind, id, count = value[Effect.kind], value[Effect.id], value[Effect.count]
            assert(type(kind) == "number" and kinds[kind], "Invalid effect kind")
            assert(
                type(id) == "number" and id % 1 == 0 and id >= -MAX_ID - 1 and id <= MAX_ID,
                "Invalid effect ID"
            )
            assert(
                type(count) == "number" and count % 1 == 0 and count > 0 and count <= MAX_COUNT,
                "Invalid effect count"
            )
            assert(not desired[kind][id], "Duplicate temporary effect")
            desired[kind][id] = count
        end
        local effects = p:GetEffects()
        -- Copy scalar identities first: setters can invalidate EffectList references.
        local current = capture(p)
        for _, value in ipairs(current) do
            local kind, id, count = value[Effect.kind], value[Effect.id], value[Effect.count]
            local target = desired[kind][id] or 0
            if count > target then
                effects["Remove" .. kinds[kind] .. "Effect"](effects, id, count - target)
            end
        end
        for _, value in ipairs(records) do
            local kind, id, count = value[Effect.kind], value[Effect.id], value[Effect.count]
            local name = kinds[kind]
            local delta = count - effects["Get" .. name .. "EffectNum"](effects, id)
            if delta > 0 then
                effects["Add" .. name .. "Effect"](effects, id, true, delta)
            end
        end
    end
    return { capture = capture, apply = apply }
end
