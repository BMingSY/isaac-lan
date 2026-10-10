-- Native costume ownership stays in the engine; cached IDs belong to this view.
return function(native, costumeLookup, applySprite)
    local costumeIDs = {}
    local function costumeID(path)
        if costumeIDs[path] == nil then
            costumeIDs[path] = costumeLookup(path)
        end
        return costumeIDs[path]
    end
    local function actorSprites(p, actor)
        local sprites = assert(native.actor_sprites(actor[1], p:GetSprite()))
        local existing, desired = {}, {}
        for i = 11, #sprites do
            local path = sprites[i]:GetFilename()
            existing[path] = (existing[path] or 0) + 1
        end
        for i = 11, #actor[5] do
            local path = actor[5][i][1]
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
                end
            end
        end
        for path, count in pairs(desired) do
            local id = costumeID(path)
            if id >= 0 then
                for _ = 1, count - (existing[path] or 0) do
                    p:AddNullCostume(id)
                end
            end
        end
        -- Adding/removing a costume can reallocate the native vector; reacquire
        -- its non-owning Sprite references before applying any animation state.
        return assert(native.actor_sprites(actor[1], p:GetSprite()))
    end
    local function applyActorVisuals(p, actor)
        if not actor[6] then
            return
        end
        local sprites = actorSprites(p, actor)
        -- Costume changes can rebuild the base body layers as well.
        applySprite(p:GetSprite(), actor[3][10])
        local used = {}
        for i, v in ipairs(actor[5]) do
            if i <= 3 then
                applySprite(sprites[i], v)
            elseif i > 10 then
                for j = 11, #sprites do
                    if not used[j] and sprites[j]:GetFilename() == v[1] then
                        applySprite(sprites[j], v)
                        used[j] = true
                        break
                    end
                end
            end
        end
        -- Charge bars (4..10) are local UI. An offscreen authority does not render
        -- their Charging/Charged layers; copying those stale layers every frame
        -- erases the replica's own charge display after players separate rooms.
        -- Native Render derives them from the replicated weapon charge below.
        assert(native.actor_pose(p:GetSprite(), actor[6]))
    end
    return {
        apply = applyActorVisuals,
        reset = function()
            costumeIDs = {}
        end,
    }
end
