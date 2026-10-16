return function(wire)
    local Entity, Sprite, Spritesheet = wire.entity, wire.sprite, wire.spritesheet
    local FLOOR_DEPTH_BIAS = 10000
    -- Engine values become explicit portable fields; this component owns no room or transport.
    return function(native, schemas, npcState, visualCompatibility, entityLinks)
        local function localEffect(e)
            return e.Type == schemas.types.ENTITY_EFFECT
                and native.presentation_local_effect(e.Type, e.Variant, e.SubType)
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
        local function id(e)
            if not e or not e:Exists() or localEffect(e) then
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
        local types = schemas.types
        local function typed(e)
            if e.Type == types.ENTITY_PLAYER then
                return e:ToPlayer(), schema[types.ENTITY_PLAYER]
            elseif e.Type == types.ENTITY_TEAR then
                return e:ToTear(), schema[types.ENTITY_TEAR]
            elseif e.Type == types.ENTITY_FAMILIAR then
                return e:ToFamiliar(), schema[types.ENTITY_FAMILIAR]
            elseif e.Type == types.ENTITY_BOMB then
                return e:ToBomb(), schema[types.ENTITY_BOMB]
            elseif e.Type == types.ENTITY_PICKUP then
                return e:ToPickup(), schema[types.ENTITY_PICKUP]
            elseif e.Type == types.ENTITY_LASER then
                return e:ToLaser(), schema[types.ENTITY_LASER]
            elseif e.Type == types.ENTITY_KNIFE then
                return e:ToKnife(), schema[types.ENTITY_KNIFE]
            elseif e.Type == types.ENTITY_PROJECTILE then
                return e:ToProjectile(), schema[types.ENTITY_PROJECTILE]
            elseif e.Type == types.ENTITY_EFFECT then
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
            if v[Sprite.animation] ~= "" then
                s:SetFrame(v[Sprite.animation], v[Sprite.frame])
            end
            if v[Sprite.overlay] ~= "" then
                s:SetOverlayFrame(v[Sprite.overlay], v[Sprite.overlayFrame])
            else
                s:RemoveOverlay()
            end
            s.FlipX, s.FlipY, s.Rotation = v[Sprite.flipX], v[Sprite.flipY], v[Sprite.rotation]
            s.Scale = vec(v[Sprite.scale])
            s.Offset = vec(v[Sprite.offset])
            s.Color = col(v[Sprite.color])
            local changed = assert(native.sprite_state(s, v[Sprite.native]))
            for _, layer in ipairs(changed) do
                s:ReplaceSpritesheet(layer[Spritesheet.layer], layer[Spritesheet.path])
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
            -- Preserve Lua array preallocation; positions follow sync/fields.
            return {
                id(e), -- Entity.id
                e.Type, -- Entity.type
                e.Variant, -- Entity.variant
                e.SubType, -- Entity.subtype
                e.InitSeed, -- Entity.seed
                vector(e.Position), -- Entity.position
                vector(e.Velocity), -- Entity.velocity
                fields(e, common), -- Entity.common
                fields(object, names), -- Entity.typed
                visual and sprite(e:GetSprite()) or false, -- Entity.sprite
                id(e.Parent), -- Entity.parent
                id(e.SpawnerEntity), -- Entity.spawner
                id(e.Child), -- Entity.child
                id(e.Target), -- Entity.target
                vector(e.SpriteOffset), -- Entity.offset
                vector(e.SpriteScale), -- Entity.scale
                color(e.Color), -- Entity.color
                e.FrameCount, -- Entity.frame
                e:GetEntityFlags(), -- Entity.flags
                e.Type == types.ENTITY_LASER and assert(native.laser_path(e:GetSprite())) or false, -- Entity.laserPath
                e.Type == types.ENTITY_LASER and vector(e:ToLaser().EndPoint) or false, -- Entity.laserEndPoint
                visual and assert(native.entity_shadow(e:GetSprite())) or false, -- Entity.shadow
                npcState.capture(e:ToNPC()), -- Entity.npc
                visual and visualCompatibility and visualCompatibility.capture(e, id) or false, -- Entity.compatibility
                visual and entityLinks.capture(e, id) or 0, -- Entity.minecart
            }
        end
        local function applyEntity(e, v)
            e.Variant, e.SubType = v[Entity.variant], v[Entity.subtype]
            e.Position = vec(v[Entity.position])
            e.Velocity = vec(v[Entity.velocity])
            writeFields(e, common, v[Entity.common])
            local object, names = typed(e)
            writeFields(object, names, v[Entity.typed])
            e.SpriteOffset = vec(v[Entity.offset])
            e.SpriteScale = vec(v[Entity.scale])
            e.Color = col(v[Entity.color])
            -- Entity.Color resets the Sprite color (including alpha/colorize). Apply
            -- the complete native visual state last so fading creep stays faded.
            if v[Entity.sprite] then
                applySprite(e:GetSprite(), v[Entity.sprite])
            end
            if v[Entity.shadow] then
                assert(native.entity_shadow(e:GetSprite(), v[Entity.shadow]))
            end
            if v[Entity.npc] then
                local npc = assert(e:ToNPC())
                npcState.apply(npc, v[Entity.npc])
            end
            -- Floor/wall flags tell EntityList::Update to bake and retire a sprite.
            -- Replicas instead keep receiving its pose/lifetime from the host. Baking
            -- an earlier death pose leaves a permanent silhouette in their backdrop.
            local floor, wall = EntityFlag.FLAG_RENDER_FLOOR, EntityFlag.FLAG_RENDER_WALL
            if e.Type == types.ENTITY_PLAYER then
                -- Actor lifecycle/persistence flags belong to this native allocation.
                -- Copying the authority's lifecycle bits can retire a live actor when
                -- temporary forms change. Only the visual blink override is replicated.
                local blink = EntityFlag.FLAG_NO_DAMAGE_BLINK
                e:ClearEntityFlags(blink)
                e:AddEntityFlags(v[Entity.flags] & blink)
            else
                e:ClearEntityFlags(e:GetEntityFlags())
                e:AddEntityFlags(v[Entity.flags] & ~(floor | wall))
            end
            if (v[Entity.flags] & floor) ~= 0 then
                e.DepthOffset = e.DepthOffset - FLOOR_DEPTH_BIAS
            end
            if e.Type == types.ENTITY_LASER then
                assert(native.laser_path(e:GetSprite(), v[Entity.laserPath]))
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
                entityLinks.apply(e, v[Entity.minecart], ref)
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
