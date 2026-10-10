return function(native, bridge, nav, terrain)
    local observe = {}
    terrain = terrain()
    local observedTick, observedAt
    local outward = { { -1, 0 }, { 0, -1 }, { 1, 0 }, { 0, 1 } }
    local function entity(e)
        return {
            id = tostring(e.InitSeed) .. ":" .. e.Type .. ":" .. e.Variant,
            x = e.Position.X,
            y = e.Position.Y,
            vx = e.Velocity.X * 30,
            vy = e.Velocity.Y * 30,
            radius = math.max(4, e.Size),
        }
    end
    local function friendly(e)
        return (e:GetEntityFlags() & (EntityFlag.FLAG_FRIENDLY | EntityFlag.FLAG_CHARM)) ~= 0
            or e.SpawnerType == EntityType.ENTITY_PLAYER
            or e.SpawnerType == EntityType.ENTITY_FAMILIAR
    end
    local function usefulHeart(player, subtype)
        if subtype == HeartSubType.HEART_SOUL or subtype == HeartSubType.HEART_HALF_SOUL then
            return player:CanPickSoulHearts()
        elseif subtype == HeartSubType.HEART_BLACK then
            return player:CanPickBlackHearts()
        elseif subtype == HeartSubType.HEART_BONE then
            return player:CanPickBoneHearts()
        elseif subtype == HeartSubType.HEART_GOLDEN then
            return player:CanPickGoldenHearts()
        elseif subtype == HeartSubType.HEART_ROTTEN then
            return player:CanPickRottenHearts()
        elseif subtype == HeartSubType.HEART_ETERNAL then
            return true
        end
        return player:CanPickRedHearts()
    end
    function observe.read(frame, info)
        if info.ready ~= 1 or not bridge.ready() then
            return nil, "view_not_ready"
        end
        local actors, localPlayers = native.api_actors(), {}
        local locations = native.rooms_positions()
        local position = locations[tostring(info.slot)]
        if not position then
            return nil, "view_not_ready"
        end
        local partyReady = true
        for _, actor in ipairs(actors) do
            local player = Isaac.GetPlayer(actor.index)
            if actor.owner == info.slot + 1 then
                localPlayers[#localPlayers + 1] = player
            elseif
                (info.connected & (1 << (actor.owner - 1))) ~= 0
                and not player:IsCoopGhost()
                and not player:IsDead()
            then
                local at = locations[tostring(actor.owner - 1)]
                if not at or at.index ~= position.index or at.dimension ~= position.dimension then
                    partyReady = false
                end
            end
        end
        local player
        for _, candidate in ipairs(localPlayers) do
            if not candidate:IsCoopGhost() and not candidate:IsDead() then
                player = candidate
                break
            end
        end
        if not player then
            return nil, "dead"
        end
        local game = Game()
        if
            game:IsPaused()
            or not player.ControlsEnabled
            or not player:AreControlsEnabled()
            or player.ControlsCooldown > 0
        then
            return nil, "interface_or_transition"
        end
        if game:IsGreedMode() or game.Challenge ~= 0 then
            return nil, "unsupported_run"
        end
        local age = 0
        if info.authority == 0 then
            local tick = info.runId .. ":" .. info.worldEpoch .. ":" .. info.tick
            if tick ~= observedTick then
                observedTick, observedAt = tick, info.nowMs
            end
            age = math.max(0, (info.nowMs - observedAt) / 1000)
            if age > 0.25 then
                return nil, "stale_view"
            end
        end
        local result
        bridge.withView(function()
            local room = game:GetRoom()
            local p = entity(player)
            -- Players integrate movement at 60 Hz; NPC/projectile velocities
            -- belong to the ordinary 30 Hz simulation updates.
            p.vx, p.vy = player.Velocity.X * 60, player.Velocity.Y * 60
            p.speed = math.max(0.1, player.MoveSpeed) * 264.705882
            p.keys, p.items = player:GetNumKeys(), player:GetCollectibleCount()
            p.health = player:GetHearts() + player:GetSoulHearts()
            p.range = math.max(60, math.min(600, player.TearRange))
            if player:GetPlayerType() == PlayerType.PLAYER_AZAZEL then
                p.range = math.min(p.range, 120)
            end
            if
                player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE)
                or player:HasWeaponType(WeaponType.WEAPON_KNIFE)
                or player:HasWeaponType(WeaponType.WEAPON_TECH_X)
                or player:HasCollectible(CollectibleType.COLLECTIBLE_CHOCOLATE_MILK)
            then
                p.charge = math.max(30, math.ceil((player.MaxFireDelay + 1) * 6))
            end
            local origin = room:GetGridPosition(0)
            local map = {
                x = origin.X,
                y = origin.Y,
                step = 40,
                width = room:GetGridWidth(),
                height = math.ceil(room:GetGridSize() / room:GetGridWidth()),
                walk = {},
                zones = {},
                exitCells = {},
                speed = p.speed * 0.7,
            }
            result = {
                frame = frame,
                age = age,
                world = info.runId .. ":" .. info.worldEpoch,
                room = position.dimension .. ":" .. position.index,
                clear = room:IsClear(),
                boss = room:GetType() == RoomType.ROOM_BOSS,
                actor = p,
                map = map,
                enemies = {},
                dangers = {},
                pickups = {},
                doors = {},
                buttons = {},
                exits = {},
                partyReady = partyReady,
                shotLine = function(from, to)
                    return room:CheckLine(
                        Vector(from.x, from.y),
                        Vector(to.x, to.y),
                        3,
                        0,
                        false,
                        false
                    )
                end,
            }
            terrain:reset(result.world, result.room, p.id)
            local tick = room:GetFrameCount()
            local function addExit(value, usable)
                value.id = value.id or "exit:" .. tostring(value.cell)
                value.radius = math.max(24, value.radius or 0)
                value.exit = true
                map.zones[#map.zones + 1] = value
                if value.cell then
                    map.walk[value.cell], map.exitCells[value.cell] = false, true
                end
                if usable then
                    result.exits[#result.exits + 1] = value
                    result.exit = result.exit or value
                end
            end
            for index = 0, room:GetGridSize() - 1 do
                local grid, collision = room:GetGridEntity(index), room:GetGridCollision(index)
                map.walk[index + 1] = collision == GridCollisionClass.COLLISION_NONE
                    or collision == GridCollisionClass.COLLISION_WALL_EXCEPT_PLAYER
                    or player.CanFly
                        and (collision == GridCollisionClass.COLLISION_PIT or collision == GridCollisionClass.COLLISION_OBJECT)
                if grid then
                    local kind, pos = grid:GetType(), room:GetGridPosition(index)
                    if
                        kind == GridEntityType.GRID_TRAPDOOR
                        or kind == GridEntityType.GRID_STAIRS
                    then
                        addExit(
                            { x = pos.X, y = pos.Y, cell = index + 1 },
                            result.clear and kind == GridEntityType.GRID_TRAPDOOR
                        )
                    elseif kind == GridEntityType.GRID_PRESSURE_PLATE and terrain:button(grid) then
                        result.buttons[#result.buttons + 1] = {
                            id = "button:" .. index,
                            x = pos.X,
                            y = pos.Y,
                            radius = 12,
                        }
                    elseif
                        (
                            kind == GridEntityType.GRID_SPIKES
                            or kind == GridEntityType.GRID_SPIKES_ONOFF
                        ) and not player.CanFly
                    then
                        local timed = kind == GridEntityType.GRID_SPIKES_ONOFF
                        local spikes = timed and grid:ToSpikes()
                        -- Cleared vanilla rooms leave alternating spikes down
                        -- with no scheduled transition; no cycle can be learned.
                        local disabled = result.clear and spikes and spikes.Timeout < 0
                        local safeFor = timed and terrain:spikes(index, grid.State, tick, disabled)
                            or 0
                        map.zones[#map.zones + 1] = {
                            id = "spikes:" .. index,
                            x = pos.X,
                            y = pos.Y,
                            radius = 19,
                            timed = timed,
                            safeFor = safeFor,
                        }
                        map.timed = map.timed or timed
                        if safeFor <= 0 then
                            result.dangers[#result.dangers + 1] =
                                { x = pos.X, y = pos.Y, radius = 19 }
                        end
                    end
                end
            end
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door then
                    local cell = nav.cell(map, door.Position.X, door.Position.Y)
                    if cell then
                        map.walk[cell] = false
                    end
                    local direction = outward[slot % 4 + 1]
                    local targetType = door.TargetRoomType
                    result.doors[#result.doors + 1] = {
                        slot = slot,
                        x = door.Position.X,
                        y = door.Position.Y,
                        dx = direction[1],
                        dy = direction[2],
                        to = position.dimension .. ":" .. door.TargetRoomIndex,
                        open = door:IsOpen(),
                        locked = door:IsLocked(),
                        cost = door:IsLocked(),
                        boss = targetType == RoomType.ROOM_BOSS,
                        treasure = targetType == RoomType.ROOM_TREASURE,
                        skip = door.TargetRoomIndex < 0
                            or targetType == RoomType.ROOM_CURSE
                            or targetType == RoomType.ROOM_SACRIFICE
                            or targetType == RoomType.ROOM_SECRET
                            or targetType == RoomType.ROOM_SUPERSECRET
                            or targetType == RoomType.ROOM_CHALLENGE,
                    }
                end
            end
            for index, e in ipairs(Isaac.GetRoomEntities()) do
                if index > 1024 then
                    break
                end
                if e:Exists() and not e:IsDead() then
                    local value = entity(e)
                    local npc, pickup, laser = e:ToNPC(), e:ToPickup(), e:ToLaser()
                    if npc and e:IsActiveEnemy(false) and e.HitPoints > 0 and not friendly(e) then
                        value.attackable = not e:IsInvincible()
                            and (info.authority == 0 or e:IsVulnerableEnemy())
                        value.threat = e:IsBoss() and 2 or 1
                        result.enemies[#result.enemies + 1] = value
                        result.dangers[#result.dangers + 1] = value
                    elseif e.Type == EntityType.ENTITY_PROJECTILE and not friendly(e) then
                        result.dangers[#result.dangers + 1] = value
                    elseif laser and not friendly(e) then
                        local endpoint = laser:GetEndPoint()
                        value.bx, value.by, value.radius =
                            endpoint.X, endpoint.Y, math.max(8, e.Size)
                        result.dangers[#result.dangers + 1] = value
                    elseif e:ToBomb() then
                        value.at, value.radius =
                            math.max(0, e:ToBomb().ExplosionCountdown / 30 - 0.15), 85
                        result.dangers[#result.dangers + 1] = value
                    elseif e.Type == EntityType.ENTITY_EFFECT then
                        local variant = e.Variant
                        if variant == EffectVariant.HEAVEN_LIGHT_DOOR then
                            value.cell = nav.cell(map, value.x, value.y)
                            addExit(value, result.clear)
                        elseif
                            not friendly(e)
                            and not player.CanFly
                            and (
                                variant == EffectVariant.CREEP_RED
                                or variant == EffectVariant.CREEP_GREEN
                                or variant == EffectVariant.CREEP_YELLOW
                                or variant == EffectVariant.CREEP_WHITE
                                or variant == EffectVariant.CREEP_BLACK
                            )
                        then
                            value.radius = math.max(20, value.radius)
                            result.dangers[#result.dangers + 1] = value
                            map.zones[#map.zones + 1] = value
                        end
                    elseif pickup and pickup.Variant == PickupVariant.PICKUP_BIGCHEST then
                        value.cell = nav.cell(map, value.x, value.y)
                        addExit(value, result.clear and pickup.Wait <= 0)
                    elseif pickup and pickup.Price == 0 and pickup.Wait <= 0 then
                        local variant = pickup.Variant
                        value.id = "pickup:" .. value.id
                        value.collectible = variant == PickupVariant.PICKUP_COLLECTIBLE
                        value.heal = variant == PickupVariant.PICKUP_HEART
                            and usefulHeart(player, pickup.SubType)
                        local useful = value.heal
                            or value.collectible and pickup.SubType > 0 and player:CanPickupItem()
                            or variant == PickupVariant.PICKUP_COIN and player:GetNumCoins() < 99
                            or variant == PickupVariant.PICKUP_KEY and p.keys < 99
                            or variant == PickupVariant.PICKUP_BOMB
                                and player:GetNumBombs() < 99
                        if useful then
                            result.pickups[#result.pickups + 1] = value
                        end
                    end
                end
            end
            table.sort(result.dangers, function(a, b)
                local function distance(danger)
                    if danger.bx then
                        return nav.segmentDistance(
                            p.x,
                            p.y,
                            danger.x,
                            danger.y,
                            danger.bx,
                            danger.by
                        )
                    end
                    return nav.distance(p, danger)
                        - math.sqrt((danger.vx or 0) ^ 2 + (danger.vy or 0) ^ 2) / 3
                end
                return distance(a) - a.radius < distance(b) - b.radius
            end)
            while #result.dangers > 64 do
                table.remove(result.dangers)
            end
            table.sort(result.pickups, function(a, b)
                return a.id < b.id
            end)
        end)
        return result
    end
    return observe
end
