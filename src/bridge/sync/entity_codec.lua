-- Engine values become explicit portable fields; this component owns no room or transport.
return function(native, schemas, npcState, visualCompatibility)
    local function vector(v)
        return { v.X, v.Y }
    end
    local function vec(v)
        return Vector(v[1], v[2])
    end
    local function color(c)
        return { c.R, c.G, c.B, c.A, c.RO, c.GO, c.BO }
    end
    local function col(c)
        return Color(table.unpack(c))
    end
    local nextID = 1
    local function id(e)
        if not e or not e:Exists() then
            return 0
        end
        local d = e:GetData()
        if not d.__isaac_lan_entity then
            d.__isaac_lan_entity = nextID
            nextID = nextID + 1
        end
        return d.__isaac_lan_entity
    end
    local common, schema = schemas.common, schemas.byType
    local function typed(e)
        if e.Type == 1 then
            return e:ToPlayer(), schema[1]
        elseif e.Type == 2 then
            return e:ToTear(), schema[2]
        elseif e.Type == 3 then
            return e:ToFamiliar(), schema[3]
        elseif e.Type == 4 then
            return e:ToBomb(), schema[4]
        elseif e.Type == 5 then
            return e:ToPickup(), schema[5]
        elseif e.Type == 7 then
            return e:ToLaser(), schema[7]
        elseif e.Type == 8 then
            return e:ToKnife(), schema[8]
        elseif e.Type == 9 then
            return e:ToProjectile(), schema[9]
        elseif e.Type == 1000 then
            return e:ToEffect(), schema[1000]
        elseif e:ToNPC() then
            return e:ToNPC(), schema.npc
        end
        return e, {}
    end
    local function fields(object, names)
        local result = {}
        for i, name in ipairs(names) do
            local v = object[name]
            if type(v) ~= "number" and type(v) ~= "boolean" then
                error(
                    "Unsupported entity field "
                        .. object.Type
                        .. "."
                        .. object.Variant
                        .. "."
                        .. object.SubType
                        .. "."
                        .. name
                        .. ": "
                        .. type(v)
                )
            end
            if type(v) == "number" then
                assert(
                    v == v and math.abs(v) < math.huge,
                    "Non-finite entity field "
                        .. object.Type
                        .. "."
                        .. object.Variant
                        .. "."
                        .. object.SubType
                        .. "."
                        .. name
                )
            end
            result[i] = v
        end
        return result
    end
    local function writeFields(object, names, values)
        assert(#names == #values, "Entity schema mismatch")
        for i, name in ipairs(names) do
            object[name] = values[i]
        end
    end
    local function sprite(s)
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
            assert(native.sprite_state(s)),
        }
    end
    local function applySprite(s, v)
        if s:GetFilename() ~= v[1] then
            if v[1] == "" then
                s:Reset()
            else
                s:Load(v[1], true)
            end
        end
        if v[2] ~= "" then
            s:SetFrame(v[2], v[3])
        end
        if v[4] ~= "" then
            s:SetOverlayFrame(v[4], v[5])
        else
            s:RemoveOverlay()
        end
        s.FlipX, s.FlipY, s.Rotation = v[6], v[7], v[8]
        s.Scale = vec(v[9])
        s.Offset = vec(v[10])
        s.Color = col(v[11])
        local changed = assert(native.sprite_state(s, v[12]))
        for _, layer in ipairs(changed) do
            s:ReplaceSpritesheet(layer[1], layer[2])
        end
        if #changed > 0 then
            s:LoadGraphics()
        end
    end
    local function entity(e, visual)
        if visual == nil then
            visual = true
        end
        local object, names = typed(e)
        if visual then
            assert(native.entity_prepare(e:GetSprite()))
        end
        return {
            id(e),
            e.Type,
            e.Variant,
            e.SubType,
            e.InitSeed,
            vector(e.Position),
            vector(e.Velocity),
            fields(e, common),
            fields(object, names),
            visual and sprite(e:GetSprite()) or false,
            id(e.Parent),
            id(e.SpawnerEntity),
            id(e.Child),
            id(e.Target),
            vector(e.SpriteOffset),
            vector(e.SpriteScale),
            color(e.Color),
            e.FrameCount,
            e:GetEntityFlags(),
            e.Type == 7 and assert(native.laser_path(e:GetSprite())) or false,
            e.Type == 7 and vector(e:ToLaser().EndPoint) or false,
            visual and assert(native.entity_shadow(e:GetSprite())) or false,
            npcState.capture(e:ToNPC()),
            visual and visualCompatibility and visualCompatibility.capture(e) or false,
        }
    end
    local function applyEntity(e, v)
        e.Variant, e.SubType = v[3], v[4]
        e.Position = vec(v[6])
        e.Velocity = vec(v[7])
        writeFields(e, common, v[8])
        local object, names = typed(e)
        writeFields(object, names, v[9])
        e.SpriteOffset = vec(v[15])
        e.SpriteScale = vec(v[16])
        e.Color = col(v[17])
        -- Entity.Color resets the Sprite color (including alpha/colorize). Apply
        -- the complete native visual state last so fading creep stays faded.
        if v[10] then
            applySprite(e:GetSprite(), v[10])
        end
        if v[22] then
            assert(native.entity_shadow(e:GetSprite(), v[22]))
        end
        if v[23] then
            local npc = assert(e:ToNPC())
            npcState.apply(npc, v[23])
        end
        -- Floor/wall flags tell EntityList::Update to bake and retire a sprite.
        -- Replicas instead keep receiving its pose/lifetime from the host. Baking
        -- an earlier death pose leaves a permanent silhouette in their backdrop.
        local floor, wall = EntityFlag.FLAG_RENDER_FLOOR, EntityFlag.FLAG_RENDER_WALL
        if e.Type == 1 then
            -- Actor lifecycle/persistence flags belong to this native allocation.
            -- Copying the authority's lifecycle bits can retire a live actor when
            -- temporary forms change. Only the visual blink override is replicated.
            local blink = EntityFlag.FLAG_NO_DAMAGE_BLINK
            e:ClearEntityFlags(blink)
            e:AddEntityFlags(v[19] & blink)
        else
            e:ClearEntityFlags(e:GetEntityFlags())
            e:AddEntityFlags(v[19] & ~(floor | wall))
        end
        if (v[19] & floor) ~= 0 then
            e.DepthOffset = e.DepthOffset - 10000
        end
        if e.Type == 7 then
            assert(native.laser_path(e:GetSprite(), v[20]))
            e:ToLaser().EndPoint = vec(v[21])
        end
        if visualCompatibility then
            visualCompatibility.apply(e, v[24])
        end
        e.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        e.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    end
    return {
        capture = entity,
        apply = applyEntity,
        sprite = sprite,
        applySprite = applySprite,
        vector = vector,
        vec = vec,
        reset = function()
            nextID = 1
        end,
    }
end
