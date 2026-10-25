return function(deps)
    local native = _IsaacLan
    local owner = RegisterMod("Isaac LAN PvP item fixture", 1)
    local observed = {}
    Isaac.AddCallback(owner, ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, effect)
        if not deps.host or effect.Variant ~= EffectVariant.CRACK_THE_SKY then
            return
        end
        local id = tostring(GetPtrHash(effect)) .. ":" .. tostring(effect.InitSeed)
        if not observed[id] then
            observed[id] = true
            local listed = false
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                listed = listed or GetPtrHash(entity) == GetPtrHash(effect)
            end
            deps.report("sky_beam", {
                listed = listed,
                frame = Game():GetFrameCount(),
                x = effect.Position.X,
                y = effect.Position.Y,
                damage = effect.CollisionDamage,
                owner = effect.SpawnerEntity and effect.SpawnerEntity.InitSeed,
            })
        end
    end)
    local function use(item)
        deps.actor(0, function(player)
            player:UseActiveItem(item, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
        end)
    end
    local function active(item)
        deps.add("active_" .. item, function(at)
            if at == 0 then
                use(item)
            end
        end, function()
            deps.report("active_health", { item = item, health = deps.health(1) })
            assert(
                deps.health(1) == (deps.enabled and 22 or 24),
                "Active PvP damage differs for item " .. item
            )
            if item == CollectibleType.COLLECTIBLE_BLOOD_RIGHTS then
                assert(deps.health(0) < 24, "Blood Rights lost its native self cost")
            elseif item ~= CollectibleType.COLLECTIBLE_MONSTROS_TOOTH or deps.enabled then
                assert(deps.health(0) == 24, "Active hurt its owner")
            end
        end, 90)
    end
    for _, item in ipairs({
        CollectibleType.COLLECTIBLE_NECRONOMICON,
        CollectibleType.COLLECTIBLE_BLOOD_RIGHTS,
        CollectibleType.COLLECTIBLE_MONSTROS_TOOTH,
    }) do
        active(item)
    end
    deps.add("bean_radius", function(at)
        if at == 0 then
            deps.actor(1, function(p)
                p.Position = Vector(210, 200)
            end)
            use(CollectibleType.COLLECTIBLE_BEAN)
        end
    end, function()
        assert(deps.health(1) == (deps.enabled and 23 or 24), "Bean poison did not settle")
        assert(deps.health(0) == 24)
    end, 90)
    deps.add("bean_outside", function(at)
        if at == 0 then
            use(CollectibleType.COLLECTIBLE_BEAN)
        end
    end, function()
        assert(deps.health(1) == 24, "Bean poisoned a distant opponent")
    end, 90)
    local origin, visited = nil, {}
    local function room()
        local selected
        deps.actor(0, function()
            local rooms = Game():GetLevel():GetRooms()
            for i = 0, rooms.Size - 1 do
                local value = rooms:Get(i)
                if
                    value.Data
                    and value.Data.Type == RoomType.ROOM_DEFAULT
                    and value.SafeGridIndex >= 0
                    and not visited[value.SafeGridIndex]
                then
                    selected = value.SafeGridIndex
                    break
                end
            end
        end)
        assert(selected, "Missing unvisited fixture room")
        visited[selected] = true
        return selected
    end
    local function move(index)
        assert(native.rooms_move(1, index, 0, -1))
        assert(native.rooms_move(0, index, 0, -1))
        deps.clear(0)
    end
    local destination
    deps.add("toxic_entry_and_reentry", function(at)
        if at == 0 then
            origin = native.rooms_positions()["0"].index
            visited[origin] = true
            deps.actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_TOXIC_SHOCK)
            end)
            destination = room()
            move(destination)
        elseif at == 75 then
            assert(
                deps.health(1) == (deps.enabled and 23 or 24),
                "Toxic Shock did not settle on entry"
            )
            move(origin)
        elseif at == 95 then
            move(destination)
        end
    end, function()
        assert(
            deps.health(1) == (deps.enabled and 23 or 24),
            "Toxic Shock retriggered by door hopping"
        )
        assert(deps.health(0) == 24, "Toxic Shock hurt its owner")
        deps.actor(0, function(p)
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_TOXIC_SHOCK)
        end)
    end, 180)
    deps.add("toxic_leave_room", function(at)
        if at == 0 then
            deps.actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_TOXIC_SHOCK)
            end)
            move(room())
        elseif at == 20 then
            assert(native.rooms_move(1, origin, 0, -1))
            deps.clear(1)
        end
    end, function()
        assert(deps.health(1) == 24, "Poison followed an opponent into another room")
        deps.actor(0, function(p)
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_TOXIC_SHOCK)
        end)
        move(origin)
    end, 90)
    deps.add("toxic_defense", function(at)
        if at == 0 then
            deps.actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_TOXIC_SHOCK)
                p.Damage = 1000
            end)
            move(room())
        elseif at == 5 then
            -- rooms_move queues the native transition. Apply the defense
            -- after arrival, before the first poison slice.
            deps.actor(1, function(p)
                p:UseActiveItem(
                    CollectibleType.COLLECTIBLE_BOOK_OF_SHADOWS,
                    UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER
                )
                assert(p:IsInvincible() or p:HasInvincibility(), "Missing native item defense")
            end)
        elseif at == 15 or at == 30 or at == 45 or at == 60 then
            deps.actor(1, function(p)
                assert(p:IsInvincible() or p:HasInvincibility(), "Native defense expired early")
            end)
        end
    end, function()
        assert(deps.health(1) == 24, "Poison bypassed item invincibility")
        deps.actor(0, function(p)
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_TOXIC_SHOCK)
        end)
    end, 90)
    active(CollectibleType.COLLECTIBLE_CRACK_THE_SKY)
end
