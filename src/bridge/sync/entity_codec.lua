return function(wire)
    local Entity, Sprite, Spritesheet = wire.entity, wire.sprite, wire.spritesheet
    local FLOOR_DEPTH_BIAS = 10000
    -- Engine values become explicit portable fields; this component owns no room or transport.
    return function(native, schemas, npcState, visualCompatibility, entityLinks, tethers, combat)
        local function localEffect(e, kind)
            kind = kind or e.Type
            return kind == schemas.types.ENTITY_EFFECT
                and native.presentation_local_effect(kind, e.Variant, e.SubType)
        end
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
        local function id(e, kind)
            if not e or not e:Exists() or localEffect(e, kind) then
                return 0
            end
            if native.combat_identity then
                local identifier = assert(native.combat_identity(e:GetSprite()))
                e:GetData().__isaac_lan_entity = identifier
                return identifier
            end
            local d = e:GetData()
            if not d.__isaac_lan_entity then
                d.__isaac_lan_entity = nextID
                nextID = nextID + 1
            end
            return d.__isaac_lan_entity
        end
        local common, schema = schemas.common, schemas.byType
        local types = schemas.types
        local plans, packedPlans = {}, {}
        if native.entity_fields_plan then
            for kind, names in pairs(schema) do
                if type(kind) == "number" then
                    local template = {
                        false, -- Entity.id
                        "Type",
                        "Variant",
                        "SubType",
                        "InitSeed",
                        "Position",
                        "Velocity",
                        common,
                        names,
                        false, -- Entity.sprite
                        false, -- Entity.parent
                        false, -- Entity.spawner
                        false, -- Entity.child
                        false, -- Entity.target
                        "SpriteOffset",
                        "SpriteScale",
                        "Color",
                        "FrameCount",
                        "EntityFlags",
                        false, -- Entity.laserPath
                        false, -- Entity.laserEndPoint
                        false, -- Entity.shadow
                        false, -- Entity.npc
                        false, -- Entity.compatibility
                        false, -- Entity.minecart
                        false, -- Entity.nativeFields
                        false, -- Entity.held
                        false, -- Entity.tether
                        false, -- Entity.combat
                    }
                    if native.entity_fields_encode then
                        for _, field in ipairs({
                            Entity.common,
                            Entity.typed,
                            Entity.offset,
                            Entity.scale,
                            Entity.color,
                        }) do
                            template[field] = false
                        end
                    end
                    plans[kind] = native.entity_fields_plan(kind, template)
                    if plans[kind] and native.entity_fields_encode then
                        packedPlans[kind] = assert(native.entity_fields_plan(kind, {
                            common,
                            names,
                            "SpriteOffset",
                            "SpriteScale",
                            "Color",
                        }))
                    end
                end
            end
        end
        local function typed(e, kind)
            if kind == types.ENTITY_PLAYER then
                return e:ToPlayer(), schema[types.ENTITY_PLAYER]
            elseif kind == types.ENTITY_TEAR then
                return e:ToTear(), schema[types.ENTITY_TEAR]
            elseif kind == types.ENTITY_FAMILIAR then
                return e:ToFamiliar(), schema[types.ENTITY_FAMILIAR]
            elseif kind == types.ENTITY_BOMB then
                return e:ToBomb(), schema[types.ENTITY_BOMB]
            elseif kind == types.ENTITY_PICKUP then
                return e:ToPickup(), schema[types.ENTITY_PICKUP]
            elseif kind == types.ENTITY_LASER then
                return e:ToLaser(), schema[types.ENTITY_LASER]
            elseif kind == types.ENTITY_KNIFE then
                return e:ToKnife(), schema[types.ENTITY_KNIFE]
            elseif kind == types.ENTITY_PROJECTILE then
                return e:ToProjectile(), schema[types.ENTITY_PROJECTILE]
            elseif kind == types.ENTITY_EFFECT then
                return e:ToEffect(), schema[types.ENTITY_EFFECT]
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
                if type(v) == "number" and (v ~= v or math.abs(v) == math.huge) then
                    error(
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
        local function sprite(s)
            if spritePlan then
                local value = native.sprite_fields_capture(s, spritePlan)
                value[Sprite.native] = assert(native.sprite_state(s))
                return value
            end
            -- Preserve Lua array preallocation; positions follow sync/fields.
            return {
                s:GetFilename(), -- Sprite.path
                s:GetAnimation(), -- Sprite.animation
                s:GetFrame(), -- Sprite.frame
                s:GetOverlayAnimation(), -- Sprite.overlay
                s:GetOverlayFrame(), -- Sprite.overlayFrame
                s.FlipX, -- Sprite.flipX
                s.FlipY, -- Sprite.flipY
                s.Rotation, -- Sprite.rotation
                vector(s.Scale), -- Sprite.scale
                vector(s.Offset), -- Sprite.offset
                color(s.Color), -- Sprite.color
                assert(native.sprite_state(s)), -- Sprite.native
            }
        end
        local function applySprite(s, v)
            if s:GetFilename() ~= v[Sprite.path] then
                if v[Sprite.path] == "" then
                    s:Reset()
                else
                    s:Load(v[Sprite.path], true)
                end
            end
            if v[Sprite.animation] ~= "" and s:GetAnimation() ~= v[Sprite.animation] then
                s:SetFrame(v[Sprite.animation], v[Sprite.frame])
            end
            if v[Sprite.overlay] ~= "" then
                if s:GetOverlayAnimation() ~= v[Sprite.overlay] then
                    s:SetOverlayFrame(v[Sprite.overlay], v[Sprite.overlayFrame])
                end
            else
                s:RemoveOverlay()
            end
            if spritePlan then
                assert(native.sprite_fields_apply(s, spritePlan, v))
            else
                s.FlipX, s.FlipY, s.Rotation = v[Sprite.flipX], v[Sprite.flipY], v[Sprite.rotation]
                s.Scale = vec(v[Sprite.scale])
                s.Offset = vec(v[Sprite.offset])
                s.Color = col(v[Sprite.color])
            end
            local changed = assert(native.sprite_state(s, v[Sprite.native]))
            if changed ~= true then
                for _, layer in ipairs(changed) do
                    s:ReplaceSpritesheet(layer[Spritesheet.layer], layer[Spritesheet.path])
                end
                if #changed > 0 then
                    s:LoadGraphics()
                end
            end
        end
        local function entity(e, visual)
            if visual == nil then
                visual = true
            end
            local s = e:GetSprite()
            if visual then
                assert(native.entity_prepare(s))
            end
            local kind = e.Type
            local plan = plans[kind]
            local object, names
            if not plan then
                object, names = typed(e, kind)
            end
            -- Preserve Lua array preallocation; positions follow sync/fields.
            local value = plan and native.entity_fields_capture(s, plan)
                or {
                    false, -- Entity.id
                    kind, -- Entity.type
                    e.Variant, -- Entity.variant
                    e.SubType, -- Entity.subtype
                    e.InitSeed, -- Entity.seed
                    vector(e.Position), -- Entity.position
                    vector(e.Velocity), -- Entity.velocity
                    fields(e, common), -- Entity.common
                    fields(object, names), -- Entity.typed
                    false, -- Entity.sprite
                    false, -- Entity.parent
                    false, -- Entity.spawner
                    false, -- Entity.child
                    false, -- Entity.target
                    vector(e.SpriteOffset), -- Entity.offset
                    vector(e.SpriteScale), -- Entity.scale
                    false, -- Entity.color
                    e.FrameCount, -- Entity.frame
                    e:GetEntityFlags(), -- Entity.flags
                    kind == types.ENTITY_LASER and assert(native.laser_path(s)) or false, -- Entity.laserPath
                    kind == types.ENTITY_LASER and vector(e:ToLaser().EndPoint) or false, -- Entity.laserEndPoint
                    false, -- Entity.shadow
                    npcState.capture(e:ToNPC()), -- Entity.npc
                    false, -- Entity.compatibility
                    false, -- Entity.minecart
                    false, -- Entity.nativeFields
                    false, -- Entity.held
                    false, -- Entity.tether
                    false, -- Entity.combat
                }
            value[Entity.id] = id(e, kind)
            value[Entity.combat] = combat and combat(e) or 0
            value[Entity.sprite] = visual and sprite(s) or false
            value[Entity.parent], value[Entity.spawner] = id(e.Parent), id(e.SpawnerEntity)
            value[Entity.child], value[Entity.target] = id(e.Child), id(e.Target)
            if not plan then
                value[Entity.color] = color(e.Color)
            end
            value[Entity.shadow] = visual and assert(native.entity_shadow(s)) or false
            value[Entity.compatibility] = visual
                    and visualCompatibility
                    and visualCompatibility.capture(e, id)
                or false
            value[Entity.minecart] = visual and entityLinks.capture(e, id) or 0
            value[Entity.held] = visual and entityLinks.captureHeld(e, id) or 0
            value[Entity.tether] = visual and tethers and tethers.capture(e, id, sprite) or false
            value[Entity.nativeFields] = packedPlans[kind]
                    and assert(native.entity_fields_encode(s, packedPlans[kind]))
                or false
            return value
        end
        local function applyEntity(e, v)
            if tethers then
                tethers.apply(e, v[Entity.tether], applySprite)
            end
            local s = e:GetSprite()
            local kind = v[Entity.type]
            local plan = plans[kind]
            if plan then
                assert(native.entity_fields_apply(s, plan, v))
                if packedPlans[kind] then
                    assert(type(v[Entity.nativeFields]) == "string", "Missing packed entity fields")
                    assert(native.entity_fields_apply(s, packedPlans[kind], v[Entity.nativeFields]))
                end
            else
                e.Variant, e.SubType = v[Entity.variant], v[Entity.subtype]
                e.Position = vec(v[Entity.position])
                e.Velocity = vec(v[Entity.velocity])
                writeFields(e, common, v[Entity.common])
                local object, names = typed(e, kind)
                writeFields(object, names, v[Entity.typed])
                e.SpriteOffset = vec(v[Entity.offset])
                e.SpriteScale = vec(v[Entity.scale])
                e.Color = col(v[Entity.color])
            end
            -- Entity.Color resets the Sprite color (including alpha/colorize). Apply
            -- the complete native visual state last so fading creep stays faded.
            if v[Entity.sprite] then
                applySprite(s, v[Entity.sprite])
            end
            if v[Entity.shadow] then
                assert(native.entity_shadow(s, v[Entity.shadow]))
            end
            if v[Entity.npc] then
                local npc = assert(e:ToNPC())
                npcState.apply(npc, v[Entity.npc])
            end
            -- Floor/wall flags tell EntityList::Update to bake and retire a sprite.
            -- Replicas instead keep receiving its pose/lifetime from the host. Baking
            -- an earlier death pose leaves a permanent silhouette in their backdrop.
            local floor, wall = EntityFlag.FLAG_RENDER_FLOOR, EntityFlag.FLAG_RENDER_WALL
            if kind == types.ENTITY_PLAYER then
                -- Actor lifecycle/persistence flags belong to this native allocation.
                -- Copying the authority's lifecycle bits can retire a live actor when
                -- temporary forms change. Only the visual blink override is replicated.
                local blink = EntityFlag.FLAG_NO_DAMAGE_BLINK
                e:ClearEntityFlags(blink)
                e:AddEntityFlags(v[Entity.flags] & blink)
            else
                local current, desired = e:GetEntityFlags(), v[Entity.flags] & ~(floor | wall)
                if current ~= desired then
                    e:ClearEntityFlags(current)
                    e:AddEntityFlags(desired)
                end
            end
            if (v[Entity.flags] & floor) ~= 0 then
                e.DepthOffset = e.DepthOffset - FLOOR_DEPTH_BIAS
            end
            if kind == types.ENTITY_LASER then
                assert(native.laser_path(s, v[Entity.laserPath]))
                e:ToLaser().EndPoint = vec(v[Entity.laserEndPoint])
            end
            if visualCompatibility then
                visualCompatibility.apply(e, v[Entity.compatibility])
            end
            e.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
            e.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        end
        return {
            localEffect = localEffect,
            capture = entity,
            apply = applyEntity,
            link = function(e, v, ref)
                if tethers and v[Entity.tether] then
                    tethers.link(e, v[Entity.tether], ref)
                end
                entityLinks.apply(e, v[Entity.minecart], ref)
                entityLinks.applyHeld(e, v[Entity.held], ref)
                if visualCompatibility and visualCompatibility.link then
                    visualCompatibility.link(e, v[Entity.compatibility], ref)
                end
            end,
            sprite = sprite,
            applySprite = applySprite,
            vector = vector,
            vec = vec,
            reset = function()
                nextID = 1
            end,
        }
    end
end
