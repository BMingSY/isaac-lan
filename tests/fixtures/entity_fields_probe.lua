-- Compare the production batch adapter with the game's public Lua properties.
-- Called before stress sampling; it does not replace the production codec.
return function(native, reference, schemas, host)
    local plans, checked, sprites = {}, {}, {}
    local function object(entity)
        return entity:ToTear() or entity:ToFamiliar() or entity:ToEffect()
    end
    local function fields(entity, names)
        local result = {}
        for i, name in ipairs(names) do
            result[i] = entity[name]
        end
        return result
    end
    local function vector(value)
        return { value.X, value.Y }
    end
    local function color(value)
        return { value.R, value.G, value.B, value.A, value.RO, value.GO, value.BO }
    end
    local spritePlan = native.sprite_fields_plan
        and native.sprite_fields_plan({
            "Filename",
            "Animation",
            "Frame",
            "OverlayAnimation",
            "OverlayFrame",
            "FlipX",
            "FlipY",
            "Rotation",
            "Scale",
            "Offset",
            "Color",
            false,
        })
    local function readSprite(s)
        return {
            s:GetFilename(),
            s:GetAnimation(),
            s:GetFrame(),
            s:GetOverlayAnimation(),
            s:GetOverlayFrame(),
            s.FlipX,
            s.FlipY,
            s.Rotation,
            vector(s.Scale),
            vector(s.Offset),
            color(s.Color),
            false,
        }
    end
    local function writeSprite(s, value)
        s.FlipX, s.FlipY, s.Rotation = value[6], value[7], value[8]
        s.Scale, s.Offset = Vector(table.unpack(value[9])), Vector(table.unpack(value[10]))
        s.Color = Color(table.unpack(value[11]))
    end
    local function verifySprite(s)
        local original = readSprite(s)
        local bytes = reference.encode(original)
        assert(
            reference.encode(native.sprite_fields_capture(s, spritePlan)) == bytes,
            "Native sprite capture differs"
        )
        if not host then
            local state = assert(native.sprite_state(s))
            if original[2] ~= "" then
                -- Advance real layer/attachment cursors and event state, then
                -- restore both directions without calling SetFrame again.
                s:Update()
                local advanced = assert(native.sprite_state(s))
                local advancedFields = reference.encode(readSprite(s))
                assert(native.sprite_state(s, state))
                assert(native.sprite_state(s) == state, "Animation rewind differs")
                assert(native.sprite_state(s, advanced))
                assert(
                    native.sprite_state(s) == advanced
                        and reference.encode(readSprite(s)) == advancedFields,
                    "Complete animation restore differs"
                )
                assert(native.sprite_state(s, state))
            end
            local changed = reference.decode(bytes)
            changed[6], changed[7], changed[8] = not changed[6], not changed[7], 17.25
            changed[9], changed[10], changed[11] =
                { 1.25, 0.75 }, { 3, -2 }, { 0.3, 0.4, 0.5, 0.6, 0.1, 0.2, 0.3 }
            local ok, message = pcall(function()
                writeSprite(s, changed)
                local expected, expectedNative =
                    reference.encode(readSprite(s)), native.sprite_state(s)
                writeSprite(s, original)
                assert(native.sprite_state(s, state))
                assert(native.sprite_fields_apply(s, spritePlan, changed))
                assert(
                    reference.encode(readSprite(s)) == expected
                        and native.sprite_state(s) == expectedNative,
                    "Native sprite apply differs"
                )
                local invalid = reference.decode(bytes)
                invalid[6], invalid[11] = not invalid[6], {}
                assert(not pcall(native.sprite_fields_apply, s, spritePlan, invalid))
                assert(
                    reference.encode(readSprite(s)) == expected,
                    "Rejected sprite changed fields"
                )
            end)
            writeSprite(s, original)
            assert(native.sprite_state(s, state))
            assert(ok, message)
        end
    end
    local function read(entity)
        local typed = assert(object(entity))
        return {
            vector(entity.Position),
            vector(entity.Velocity),
            fields(entity, schemas.common),
            fields(typed, schemas.byType[entity.Type]),
            vector(entity.SpriteOffset),
            vector(entity.SpriteScale),
            entity.FrameCount,
            entity:GetEntityFlags(),
            color(entity.Color),
        }
    end
    local function write(entity, value)
        entity.Position, entity.Velocity =
            Vector(table.unpack(value[1])), Vector(table.unpack(value[2]))
        for i, name in ipairs(schemas.common) do
            entity[name] = value[3][i]
        end
        local typed = assert(object(entity))
        for i, name in ipairs(schemas.byType[entity.Type]) do
            typed[name] = value[4][i]
        end
        entity.SpriteOffset, entity.SpriteScale =
            Vector(table.unpack(value[5])), Vector(table.unpack(value[6]))
        entity.Color = Color(table.unpack(value[9]))
    end
    return function()
        if not native.entity_fields_plan then
            return {}
        end
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local kind = entity.Type
            if entity:Exists() and spritePlan and not sprites[kind] then
                verifySprite(entity:GetSprite())
                sprites[kind] = true
            end
            if entity:Exists() and schemas.byType[kind] and not checked[kind] then
                local plan = plans[kind]
                if plan == nil then
                    plan = native.entity_fields_plan(kind, {
                        "Position",
                        "Velocity",
                        schemas.common,
                        schemas.byType[kind],
                        "SpriteOffset",
                        "SpriteScale",
                        "FrameCount",
                        "EntityFlags",
                        "Color",
                    })
                    plans[kind] = plan
                end
                if plan then
                    local sprite = entity:GetSprite()
                    local original = read(entity)
                    local expected = reference.encode(original)
                    assert(
                        reference.encode(native.entity_fields_capture(sprite, plan)) == expected,
                        "Batch capture differs for entity type " .. kind
                    )
                    assert(
                        native.entity_fields_encode(sprite, plan) == expected,
                        "Packed capture differs"
                    )
                    if not host then
                        local originalSprite = assert(native.sprite_state(sprite))
                        local value = reference.decode(expected)
                        value[1][1], value[1][2] = value[1][1] + 3, value[1][2] - 2
                        value[3][4] = not value[3][4] -- Visible
                        value[9] = { 0.3, 0.4, 0.5, 0.6, 0.1, 0.2, 0.3 }
                        local ok, message = pcall(function()
                            write(entity, value)
                            local viaLua = reference.encode(read(entity))
                            local viaLuaSprite = native.sprite_state(sprite)
                            write(entity, original)
                            assert(native.sprite_state(sprite, originalSprite))
                            assert(native.entity_fields_apply(sprite, plan, value))
                            assert(
                                reference.encode(read(entity)) == viaLua
                                    and native.sprite_state(sprite) == viaLuaSprite,
                                "Batch application differs for entity type " .. kind
                            )
                            write(entity, original)
                            assert(native.sprite_state(sprite, originalSprite))
                            local packed = reference.encode(value)
                            assert(native.entity_fields_apply(sprite, plan, packed))
                            assert(
                                reference.encode(read(entity)) == viaLua
                                    and native.sprite_state(sprite) == viaLuaSprite,
                                "Packed application differs for entity type " .. kind
                            )
                            for size = 0, #packed - 1 do
                                assert(
                                    not pcall(
                                        native.entity_fields_apply,
                                        sprite,
                                        plan,
                                        packed:sub(1, size)
                                    )
                                )
                            end
                            assert(
                                not pcall(native.entity_fields_apply, sprite, plan, packed .. "\0")
                            )
                            -- Reject the complete bad shape before changing any field.
                            local broken = reference.decode(expected)
                            broken[1][1], broken[4] = broken[1][1] + 100, {}
                            assert(not pcall(native.entity_fields_apply, sprite, plan, broken))
                            assert(
                                not pcall(
                                    native.entity_fields_apply,
                                    sprite,
                                    plan,
                                    reference.encode(broken)
                                )
                            )
                            assert(
                                reference.encode(read(entity)) == viaLua,
                                "Rejected batch changed the entity"
                            )
                        end)
                        write(entity, original)
                        assert(native.sprite_state(sprite, originalSprite))
                        assert(ok, message)
                    end
                    checked[kind] = true
                end
            end
        end
        local result = {}
        for kind in pairs(checked) do
            result[#result + 1] = kind
        end
        table.sort(result)
        return result
    end
end
