return function(fields)
    local Actor, ActorSprites = fields.actor, fields.actorSprites
    local Sprite = fields.sprite
    local Entity = fields.entity
    -- Native costume ownership stays in the engine; cached IDs belong to this view.
    return function(native, costumeLookup, applySprite)
        local costumeIDs = {}
        local function costumeID(path)
            if costumeIDs[path] == nil then
                costumeIDs[path] = costumeLookup(path)
            end
            return costumeIDs[path]
        end
        local function indexCostumes(sprites)
            local byPath = {}
            for i = ActorSprites.firstCostume, #sprites do
                local path = sprites[i]:GetFilename()
                local entries = byPath[path]
                if not entries then
                    entries = { next = 1 }
                    byPath[path] = entries
                end
                entries[#entries + 1] = sprites[i]
            end
            return byPath
        end
        local function actorSprites(p, actor)
            local sprites = assert(native.actor_sprites(actor[Actor.index], p:GetSprite()))
            local existing, desired = indexCostumes(sprites), {}
            local changed = false
            for i = ActorSprites.firstCostume, #actor[Actor.visuals] do
                local path = actor[Actor.visuals][i][Sprite.path]
                desired[path] = (desired[path] or 0) + 1
            end
            -- Replica-side callbacks can add a null costume based on a provisional
            -- room before its authoritative contents arrive. The host owns actor
            -- appearance too; discard those stale costumes, not only ones we added.
            for path in pairs(existing) do
                if not desired[path] then
                    local id = costumeID(path)
                    if id >= 0 then
                        p:TryRemoveNullCostume(id)
                        changed = true
                    end
                end
            end
            for path, count in pairs(desired) do
                local id = costumeID(path)
                if id >= 0 then
                    for _ = 1, count - (existing[path] and #existing[path] or 0) do
                        p:AddNullCostume(id)
                        changed = true
                    end
                end
            end
            -- Adding/removing a costume can reallocate the native vector; reacquire
            -- its non-owning Sprite references before applying any animation state.
            if changed then
                sprites = assert(native.actor_sprites(actor[Actor.index], p:GetSprite()))
                existing = indexCostumes(sprites)
            end
            return sprites, existing
        end
        local function applyActorVisuals(p, actor)
            if not actor[Actor.pose] then
                return
            end
            local sprites, byPath = actorSprites(p, actor)
            -- Costume changes can rebuild the base body layers as well.
            applySprite(p:GetSprite(), actor[Actor.entity][Entity.sprite])
            for i, v in ipairs(actor[Actor.visuals]) do
                if i <= ActorSprites.baseCount then
                    applySprite(sprites[i], v)
                elseif i >= ActorSprites.firstCostume then
                    local entries = byPath[v[Sprite.path]]
                    if entries and entries[entries.next] then
                        applySprite(entries[entries.next], v)
                        entries.next = entries.next + 1
                    end
                end
            end
            -- Charge bars (4..10) are local UI. An offscreen authority does not render
            -- their Charging/Charged layers; copying those stale layers every frame
            -- erases the replica's own charge display after players separate rooms.
            -- Native Render derives them from the replicated weapon charge below.
            assert(native.actor_pose(p:GetSprite(), actor[Actor.pose]))
        end
        local function walk(p, actor, model, direction, dt, controls)
            local body = p:GetSprite()
            local prefix = body:GetAnimation():match("^(PickupWalk)")
                or body:GetAnimation():match("^(Walk)")
            if not controls or not prefix or p:IsCoopGhost() then
                model.walk = nil
                return
            end
            local moving = direction:LengthSquared() > 0
            local velocity = model.prediction.velocity
            if not moving and velocity:LengthSquared() > 1 then
                direction, moving = velocity, true
            end
            if not moving then
                model.walk = nil
                return
            end
            local name = prefix
                .. (
                    math.abs(direction.X) > math.abs(direction.Y)
                        and (direction.X < 0 and "Left" or "Right")
                    or (direction.Y < 0 and "Up" or "Down")
                )
            local walking = model.walk
            if not walking or walking.name ~= name then
                walking = { name = name, frames = {} }
                model.walk = walking
            end
            local function advance(sprite, key)
                -- Only locomotion layers are predicted. Extra actions and head
                -- overlays retain their authority/aiming clocks.
                if not sprite:GetAnimation():match("^" .. prefix) then
                    return
                end
                sprite:Play(name, true)
                if sprite:GetAnimation() ~= name then
                    return
                end
                local length = assert(native.sprite_animation_length(sprite))
                if length == 0 then
                    return
                end
                -- Native locomotion advances at 30 Hz. Keep fractional
                -- frames locally: SetFrame/GetFrame round them away.
                local phase = ((walking.frames[key] or 0) + dt * 30 * sprite.PlaybackSpeed) % length
                sprite:SetFrame(name, math.floor(phase))
                walking.frames[key] = phase
            end
            advance(body, "body")
            local sprites = assert(native.actor_sprites(actor[Actor.index], body))
            for i = ActorSprites.firstCostume, #sprites do
                advance(sprites[i], i .. ":" .. sprites[i]:GetFilename())
            end
        end
        return {
            apply = applyActorVisuals,
            walk = walk,
            reset = function()
                costumeIDs = {}
            end,
        }
    end
end
