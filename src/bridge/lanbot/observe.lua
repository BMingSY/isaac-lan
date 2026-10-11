return function(native, bridge, nav, terrain, items, actorPose, networkStatus)
    local observe = {}
    terrain = terrain()
    local observedTick, observedAt
    local contactWorld, contactRoom, contactSpeeds = nil, nil, {}
    local claimWorld, claimRoom, claims = nil, nil, {}
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
        local actors, localPlayers, roomPlayers, remotePlayers = native.api_actors(), {}, {}, {}
        local teammates, localActor = {}, nil
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
                roomPlayers[#roomPlayers + 1] = player
            elseif
                (info.connected & (1 << (actor.owner - 1))) ~= 0
                and not player:IsCoopGhost()
                and not player:IsDead()
            then
                local at = locations[tostring(actor.owner - 1)]
                if not at or at.dimension ~= position.dimension then
                    partyReady = false
                else
                    remotePlayers[#remotePlayers + 1] = { player = player, index = at.index }
                end
            end
            local at = locations[tostring(actor.owner - 1)]
            if
                (info.connected & (1 << (actor.owner - 1))) ~= 0
                and at
                and at.dimension == position.dimension
                and not player:IsCoopGhost()
                and not player:IsDead()
            then
                local teammate = { player = player, id = actor.owner .. ":" .. actor.index }
                teammates[#teammates + 1] = teammate
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
        for _, teammate in ipairs(teammates) do
            if teammate.player == player then
                localActor = teammate.id
            end
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
        if game.Challenge ~= 0 then
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
            if info.authority == 0 and actorPose then
                local pose = actorPose(player)
                if not pose then
                    return
                end
                p.x, p.y, p.vx, p.vy = pose.x, pose.y, pose.vx, pose.vy
            end
            p.speed = math.max(0.1, player.MoveSpeed) * 264.705882
            p.keys, p.items = player:GetNumKeys(), player:GetCollectibleCount()
            p.coins = player:GetNumCoins()
            p.needsHeal = player:CanPickRedHearts()
                and player:GetHearts() < player:GetEffectiveMaxHearts()
            p.redDeficit = math.max(0, player:GetEffectiveMaxHearts() - player:GetHearts())
            p.health = player:GetHearts() + player:GetSoulHearts()
            p.range = math.max(60, math.min(600, player.TearRange))
            p.homing = player:HasCollectible(CollectibleType.COLLECTIBLE_SACRED_HEART)
                or player:HasCollectible(CollectibleType.COLLECTIBLE_SPOON_BENDER)
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
            local level = game:GetLevel()
            local function roomKey(index)
                local descriptor = index >= 0 and level:GetRoomByIdx(index, position.dimension)
                return position.dimension
                    .. ":"
                    .. (descriptor and descriptor.Data and descriptor.SafeGridIndex or index)
            end
            for _, entry in ipairs(remotePlayers) do
                if roomKey(entry.index) == roomKey(position.index) then
                    roomPlayers[#roomPlayers + 1] = entry.player
                else
                    partyReady = false
                end
            end
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
                controlDelay = 1 / 30,
                world = info.runId .. ":" .. info.worldEpoch,
                room = roomKey(position.index),
                clear = room:IsClear(),
                boss = room:GetType() == RoomType.ROOM_BOSS,
                actor = p,
                map = map,
                enemies = {},
                dangers = {},
                pickups = {},
                shopOffers = {},
                doors = {},
                buttons = {},
                breakables = {},
                exits = {},
                partyReady = partyReady,
                shotLine = function(from, to)
                    local origin, destination = Vector(from.x, from.y), Vector(to.x, to.y)
                    if to.attackable and not to.breakable and not to.clearable then
                        -- Wall crawlers expose a body while their center lies
                        -- inside the wall. Test the first tear/body contact,
                        -- not a ray that must continue through the NPC to wall.
                        local dx, dy = from.x - to.x, from.y - to.y
                        local length = math.sqrt(dx ^ 2 + dy ^ 2)
                        if length > 0 then
                            local inset = math.min(length, (to.radius or 0) + 8)
                            destination =
                                Vector(to.x + dx / length * inset, to.y + dy / length * inset)
                        end
                    end
                    local clear, hit = room:CheckLine(origin, destination, 3, 0, false, false)
                    if not to.breakable or clear or not hit then
                        return clear
                    end
                    -- J460 can return the final free position just before the
                    -- blocked cell. Inspect at most the next cell along that
                    -- ray; never skip a rock or another poop to reach a target.
                    local dx, dy = to.x - hit.X, to.y - hit.Y
                    local length = math.sqrt(dx ^ 2 + dy ^ 2)
                    local reach = math.min(map.step, length)
                    local steps = math.max(1, math.ceil(reach / 4))
                    for i = 0, steps do
                        local distance = reach * i / steps
                        local index = room:GetGridIndex(
                            Vector(
                                hit.X + (length > 0 and dx / length * distance or 0),
                                hit.Y + (length > 0 and dy / length * distance or 0)
                            )
                        )
                        local collision = room:GetGridCollision(index)
                        if
                            collision ~= GridCollisionClass.COLLISION_NONE
                            and collision ~= GridCollisionClass.COLLISION_PIT
                        then
                            return index == to.cell - 1
                        end
                    end
                    return false
                end,
            }
            if game:IsGreedMode() then
                result.greed = {
                    stage = level:GetStage(),
                    wave = level.GreedModeWave,
                    bossWave = game.Difficulty == 3 and 11 or 10,
                }
            end
            if claimWorld ~= result.world or claimRoom ~= result.room then
                claimWorld, claimRoom, claims = result.world, result.room, {}
            end
            local party = {}
            if result.greed then
                for _, teammate in ipairs(teammates) do
                    local peer = teammate.player
                    party[#party + 1] = {
                        id = teammate.id,
                        player = peer,
                        items = peer:GetCollectibleCount(),
                        keys = peer:GetNumKeys(),
                        coins = peer:GetNumCoins(),
                        needsHeal = peer:CanPickRedHearts()
                            and peer:GetHearts() < peer:GetEffectiveMaxHearts(),
                        redDeficit = math.max(0, peer:GetEffectiveMaxHearts() - peer:GetHearts()),
                        available = peer:CanPickupItem(),
                    }
                end
            end
            local nextClaims = {}
            result.shop = room:GetType() == RoomType.ROOM_SHOP
            if info.authority == 0 then
                local status = networkStatus and networkStatus() or {}
                local ping = status["ping" .. info.slot]
                result.controlDelay = result.controlDelay
                    + math.min(0.25, math.max(0, ping and ping >= 0 and ping / 1000 or 0.1))
            end
            if contactWorld ~= result.world or contactRoom ~= result.room then
                contactWorld, contactRoom, contactSpeeds = result.world, result.room, {}
            end
            local nextSpeeds = {}
            terrain:reset(result.world, result.room, p.id)
            local tick = room:GetFrameCount()
            result.simulationTick = info.tick
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
                    if not result.exit or value.kind == "bigchest" then
                        result.exit = value
                    end
                end
            end
            for index = 0, room:GetGridSize() - 1 do
                local grid, collision = room:GetGridEntity(index), room:GetGridCollision(index)
                -- Empty grid cells can sit outside the physical room (including
                -- cutouts of L-shaped rooms). Collision alone is not a boundary.
                map.walk[index + 1] = room:IsPositionInRoom(room:GetGridPosition(index), 0)
                    and (
                        collision == GridCollisionClass.COLLISION_NONE
                        or collision == GridCollisionClass.COLLISION_WALL_EXCEPT_PLAYER
                        or player.CanFly
                            and (collision == GridCollisionClass.COLLISION_PIT or collision == GridCollisionClass.COLLISION_OBJECT)
                    )
                if grid then
                    local kind, pos = grid:GetType(), room:GetGridPosition(index)
                    if kind == GridEntityType.GRID_POOP and grid.State < 1000 then
                        result.breakables[#result.breakables + 1] = {
                            id = "poop:" .. index,
                            x = pos.X,
                            y = pos.Y,
                            radius = 20,
                            cell = index + 1,
                            breakable = true,
                            attackable = true,
                        }
                    elseif
                        kind == GridEntityType.GRID_TRAPDOOR
                        or kind == GridEntityType.GRID_STAIRS
                    then
                        local usable, radius = false, 24
                        if kind == GridEntityType.GRID_TRAPDOOR then
                            usable, radius = terrain:trapdoor(grid, result.clear)
                        end
                        addExit({
                            x = pos.X,
                            y = pos.Y,
                            cell = index + 1,
                            radius = radius,
                            closed = kind == GridEntityType.GRID_TRAPDOOR and not usable,
                        }, usable)
                    elseif kind == GridEntityType.GRID_PRESSURE_PLATE then
                        local value = { id = "button:" .. index, x = pos.X, y = pos.Y, radius = 12 }
                        if terrain:button(grid, result.greed, result.clear) then
                            value.greed = result.greed ~= nil and grid:GetVariant() == 2
                            result.buttons[#result.buttons + 1] = value
                        elseif result.greed and grid:GetVariant() == 2 then
                            -- Avoid accidentally stopping a live wave or
                            -- starting the optional bonus round while kiting.
                            value.radius = 24
                            map.zones[#map.zones + 1] = value
                            result.dangers[#result.dangers + 1] = value
                        end
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
                        to = roomKey(door.TargetRoomIndex),
                        open = door:IsOpen(),
                        locked = door:IsLocked(),
                        cost = door:IsLocked(),
                        boss = targetType == RoomType.ROOM_BOSS,
                        treasure = targetType == RoomType.ROOM_TREASURE,
                        shop = targetType == RoomType.ROOM_SHOP,
                        greedExit = result.greed ~= nil and targetType == RoomType.ROOM_GREED_EXIT,
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
                    if npc and e.Type == EntityType.ENTITY_FIREPLACE then
                        -- Vanilla keeps the extinguished fireplace at 1 HP;
                        -- replica collision flags cannot distinguish its ash.
                        if e.HitPoints > 1 then
                            value.id = "fire:" .. value.id
                            value.radius = math.max(18, value.radius)
                            value.clearable = e.Variant == 0 or e.Variant == 1
                            value.attackable = value.clearable
                            map.zones[#map.zones + 1] = value
                            result.dangers[#result.dangers + 1] = value
                            if value.clearable then
                                result.breakables[#result.breakables + 1] = value
                            end
                        end
                    elseif
                        npc
                        and e:IsActiveEnemy(false)
                        and e.HitPoints > 0
                        and not friendly(e)
                    then
                        value.attackable = (e:GetEntityFlags() & EntityFlag.FLAG_NO_TARGET) == 0
                            and not e:IsInvincible()
                            and (info.authority == 0 or e:IsVulnerableEnemy())
                        value.threat = e:IsBoss() and 2 or 1
                        value.health = e.HitPoints
                        -- Replica collision classes are deliberately disabled;
                        -- the synchronized damage value still describes danger.
                        value.contact = (e.CollisionDamage or 1) > 0
                        local speed = math.sqrt(value.vx ^ 2 + value.vy ^ 2)
                        local peak = math.max(speed, contactSpeeds[value.id] or 0)
                        nextSpeeds[value.id] = peak
                        value.chaseSpeed = math.min(p.speed * 1.5, math.max(p.speed * 0.6, peak))
                        result.enemies[#result.enemies + 1] = value
                        -- Harmless bodies are not damage hazards. Their emitted
                        -- projectiles remain independent dangers below.
                        if value.contact then
                            result.dangers[#result.dangers + 1] = value
                        end
                    elseif e.Type == EntityType.ENTITY_PROJECTILE and not friendly(e) then
                        result.dangers[#result.dangers + 1] = value
                    elseif laser and not friendly(e) then
                        local endpoint = laser:GetEndPoint()
                        value.bx, value.by, value.radius =
                            endpoint.X, endpoint.Y, math.max(8, e.Size)
                        result.dangers[#result.dangers + 1] = value
                    elseif e:ToBomb() then
                        -- Vanilla exposes SetExplosionCountdown but no read
                        -- property. Treat live bombs as ready to explode.
                        value.at, value.radius = 0, 85 * (e:ToBomb().RadiusMultiplier or 1)
                        result.dangers[#result.dangers + 1] = value
                    elseif e.Type == EntityType.ENTITY_SLOT then
                        -- Machines have entity collision rather than grid
                        -- collision. Avoid touching/operating them incidentally.
                        value.id, value.radius =
                            "machine:" .. value.id, math.max(24, value.radius) + 8
                        map.zones[#map.zones + 1] = value
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
                        value.kind = "bigchest"
                        value.cell = nav.cell(map, value.x, value.y)
                        -- Vanilla has a separate collision drop delay that its
                        -- Lua Wait property does not expose. Contact during the
                        -- delay refreshes it: let every nearby actor leave first.
                        value.contactWait = pickup.State == 0
                        value.contactRadius = math.max(60, value.radius * 2)
                        for _, candidate in ipairs(roomPlayers) do
                            local accepted = info.authority == 0 and actorPose
                            local pose = accepted and actorPose(candidate)
                                or not accepted
                                    and { x = candidate.Position.X, y = candidate.Position.Y }
                            if
                                not candidate:IsCoopGhost()
                                and not candidate:IsDead()
                                and (
                                    not pose
                                    or nav.distance(pose, value)
                                        < value.contactRadius + candidate.Size + 12
                                )
                            then
                                value.contactBlocked = true
                            end
                        end
                        addExit(value, result.clear and pickup.Wait <= 0)
                    elseif pickup then
                        local variant = pickup.Variant
                        value.id = "pickup:" .. value.id
                        value.collectible = variant == PickupVariant.PICKUP_COLLECTIBLE
                        local config = value.collectible
                            and pickup.SubType > 0
                            and Isaac.GetItemConfig():GetCollectible(pickup.SubType)
                        local activeSwap = config
                            and config.Type == ItemType.ITEM_ACTIVE
                            and player:GetActiveItem() ~= 0
                        if config then
                            local flags = config.CacheFlags or 0
                            local meta = {
                                quality = config.Quality or 1,
                                active = config.Type == ItemType.ITEM_ACTIVE,
                                quest = config.QuestItem,
                                maxHearts = config.AddMaxHearts or 0,
                                hearts = config.AddHearts or 0,
                                soulHearts = config.AddSoulHearts or 0,
                                damage = (flags & CacheFlag.CACHE_DAMAGE) ~= 0,
                                fireRate = (flags & CacheFlag.CACHE_FIREDELAY) ~= 0,
                                owned = player:HasCollectible(pickup.SubType),
                            }
                            value.itemScore = items.score(meta, p)
                            if result.greed and value.itemScore and pickup.Price >= 0 then
                                for _, peer in ipairs(party) do
                                    peer.owned = peer.player:HasCollectible(pickup.SubType)
                                end
                                local recipient = items.recipient(meta, party, pickup.Price)
                                local first = claims[value.id] or info.tick
                                nextClaims[value.id] = first
                                -- Do not reserve forever for a peer that cannot
                                -- reach/collect it. The floor FSM also bounds loot.
                                value.reserved = recipient
                                    and recipient.id ~= localActor
                                    and info.tick - first < 600
                                value.recipient = recipient and recipient.id
                            end
                        end
                        value.key = variant == PickupVariant.PICKUP_KEY
                        value.recovery = variant == PickupVariant.PICKUP_HEART
                            and pickup.SubType ~= HeartSubType.HEART_GOLDEN
                            and pickup.SubType ~= HeartSubType.HEART_ETERNAL
                        value.heal = variant == PickupVariant.PICKUP_HEART
                            and usefulHeart(player, pickup.SubType)
                        local useful = value.heal
                            or value.collectible and not activeSwap and pickup.SubType > 0 and player:CanPickupItem()
                            or variant == PickupVariant.PICKUP_COIN and player:GetNumCoins() < 99
                            or variant == PickupVariant.PICKUP_KEY and p.keys < 99
                            or variant == PickupVariant.PICKUP_BOMB
                                and player:GetNumBombs() < 99
                        if
                            result.greed
                            and result.shop
                            and pickup.Wait <= 0
                            and pickup.Price > 0
                            and (value.key or value.recovery or value.itemScore)
                        then
                            value.price = pickup.Price
                            result.shopOffers[#result.shopOffers + 1] = value
                        end
                        local paid = result.greed
                            and result.shop
                            and pickup.Price > 0
                            and pickup.Price <= p.coins
                            and (
                                value.key and p.keys < 1
                                or value.recovery and value.heal and p.needsHeal
                                or value.collectible
                                    and items.affordable(value.itemScore, pickup.Price, p)
                            )
                        if pickup.Price ~= 0 or activeSwap or value.reserved then
                            -- Walking across an ignored item still purchases
                            -- or swaps it natively. Open only the chosen paid
                            -- resource's zone, while protecting other pickups.
                            map.zones[#map.zones + 1] = {
                                id = value.id,
                                x = value.x,
                                y = value.y,
                                radius = math.max(20, value.radius) + 12,
                                purchase = true,
                            }
                        end
                        if
                            useful
                            and not value.reserved
                            and pickup.Wait <= 0
                            and (pickup.Price == 0 or paid)
                        then
                            value.paid, value.price = pickup.Price > 0, pickup.Price
                            result.pickups[#result.pickups + 1] = value
                        end
                    end
                end
            end
            claims = nextClaims -- Bound reservations to items still in this view.
            if result.clear and #result.exits > 0 then
                -- Defeated bosses can remain as a positive-HP statue. Replica
                -- collision disables its native vulnerability query; a clear
                -- room with an available ending/exit must not restart combat.
                for _, enemy in ipairs(result.enemies) do
                    enemy.attackable = false
                    enemy.chaseSpeed = 0
                end
            end
            contactSpeeds = nextSpeeds -- Bound history to enemies still in this view.
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
        return result, not result and "view_not_ready" or nil
    end
    return observe
end
