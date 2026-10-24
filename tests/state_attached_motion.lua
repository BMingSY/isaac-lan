-- Native attachments and released attacks observed through delayed transport.
local native, json = assert(_IsaacLan), require("json")
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local E, A, R = fields.entity, fields.actor, fields.room
local Phase = native.net_phases()
local cases = {
    {
        name = "forgotten",
        character = PlayerType.PLAYER_THEFORGOTTEN,
        weapon = "8:1:0",
        attached = true,
    },
    {
        name = "knife",
        item = CollectibleType.COLLECTIBLE_MOMS_KNIFE,
        weapon = "8:0:0",
        attached = true,
    },
    {
        name = "sword",
        item = CollectibleType.COLLECTIBLE_SPIRIT_SWORD,
        weapon = "8:10:0",
        attached = true,
    },
    {
        name = "brimstone",
        item = CollectibleType.COLLECTIBLE_BRIMSTONE,
        weapon = "7:1:0",
        attached = true,
    },
    {
        name = "technology",
        item = CollectibleType.COLLECTIBLE_TECHNOLOGY,
        weapon = "7:2:0",
        attached = false,
    },
    {
        name = "tech-x",
        item = CollectibleType.COLLECTIBLE_TECH_X,
        weapon = "7:2:2",
        attached = false,
    },
    {
        name = "maw",
        item = CollectibleType.COLLECTIBLE_MAW_OF_THE_VOID,
        weapon = "7:1:3",
        attached = true,
    },
}
local firstTick, duration = 60, 300
local tolerance, minimumSamples = 0.05, 5
local frame, gate = _IsaacLanFrame, native.net_gate
local owner = { Name = "Attached attack motion regression" }
local renders, verified, chosen, linked, finished = 0, 0, false, false, false
local latest, seen, details = nil, {}, {}
local pathSamples, maxPathError = 0, 0
local function phase(tick)
    local at = tick - firstTick
    if at < 0 then
        return nil, at
    end
    return cases[math.floor(at / duration) + 1], at % duration
end
local function report(message)
    Isaac.DebugString("LAN_NETWORK ATTACHED_MOTION " .. message)
end
local function guest(fn)
    assert(native.rooms_with_player(1, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()["1"])))
    end))
end
local function pathCoordinates(bytes)
    local _, x, y, ex, ey, shape, scale, samples, offset = string.unpack(">BffffffI4", bytes)
    local points = { x, y, ex, ey }
    for _ = 1, 2 do
        local count
        count, offset = string.unpack(">I2", bytes, offset)
        for _ = 1, count do
            x, y, offset = string.unpack(">ff", bytes, offset)
            points[#points + 1], points[#points + 2] = x, y
        end
    end
    return points, shape, scale, samples
end
local function observe(entity, actor, value, at, case)
    local parent = entity.Parent
    local key = case.name .. ":" .. entity.Type .. ":" .. entity.Variant .. ":" .. entity.SubType
    local record = seen[key] or { count = 0, maxError = 0 }
    seen[key] = record
    record.count = record.count + 1
    local relative = entity.Position - actor.Position
    if value then
        local expected = Vector(
            value[E.position][1] - latest.actor[E.position][1],
            value[E.position][2] - latest.actor[E.position][2]
        )
        record.maxError = math.max(record.maxError, (relative - expected):Length())
        if key == case.name .. ":" .. case.weapon and case.attached then
            local limit = tolerance
            if entity.Type == EntityType.ENTITY_KNIFE then
                -- Relative trajectories can lead the last accepted sample.
                -- Once authority holds a relative pose, they must settle back
                -- onto that pose instead of drifting with an old flight speed.
                if not record.expected or (expected - record.expected):Length() > tolerance then
                    record.changedAt = latest.tick
                end
                record.expected = expected
                limit = latest.tick - record.changedAt >= 6 and 0.5 or 96
                if
                    record.renderTick == latest.tick
                    and record.relative
                    and (relative - record.relative):Length() > tolerance
                then
                    record.subframes = (record.subframes or 0) + 1
                end
                record.renderTick, record.relative = latest.tick, relative
            end
            assert(
                (relative - expected):Length() < limit,
                "Weapon detached from predicted actor: " .. key
            )
        end
        if entity.Type == EntityType.ENTITY_LASER then
            local original, shape, scale, samples = pathCoordinates(value[E.laserPath])
            local actual, renderedShape, renderedScale, renderedSamples =
                pathCoordinates(assert(native.laser_path(entity:GetSprite())))
            assert(
                #original == #actual
                    and shape == renderedShape
                    and scale == renderedScale
                    and samples == renderedSamples,
                "Laser translation changed shape"
            )
            local delta = entity.Position - Vector(value[E.position][1], value[E.position][2])
            for index, coordinate in ipairs(original) do
                local error =
                    math.abs(actual[index] - coordinate - (index % 2 == 1 and delta.X or delta.Y))
                maxPathError = math.max(maxPathError, error)
                assert(error < tolerance, "Laser path detached from displayed origin")
            end
            local endpoint = Vector(value[E.laserEndPoint][1], value[E.laserEndPoint][2]) + delta
            assert(
                (entity:ToLaser().EndPoint - endpoint):Length() < tolerance,
                "Laser endpoint detached"
            )
            pathSamples = pathSamples + 1
        elseif
            entity.Type == EntityType.ENTITY_EFFECT
            and entity.Variant == EffectVariant.LASER_IMPACT
            and parent
        then
            local parentValue = latest.entities[value[E.parent]]
            if parentValue then
                local expectedDelta = parent.Position
                    - Vector(parentValue[E.position][1], parentValue[E.position][2])
                local actualDelta = entity.Position
                    - Vector(value[E.position][1], value[E.position][2])
                assert(
                    (actualDelta - expectedDelta):Length() < tolerance,
                    "Impact detached from displayed beam"
                )
            end
        end
    end
    if (details[key] or 0) < 8 or at % 20 == 0 then
        details[key] = (details[key] or 0) + 1
        local knife, laser, effect = entity:ToKnife(), entity:ToLaser(), entity:ToEffect()
        report("SAMPLE " .. json.encode({
            case = case.name,
            at = at,
            type = entity.Type,
            variant = entity.Variant,
            subtype = entity.SubType,
            parent = parent and parent.Type or -1,
            spawner = entity.SpawnerEntity and entity.SpawnerEntity.Type or -1,
            x = entity.Position.X,
            y = entity.Position.Y,
            px = actor.Position.X,
            py = actor.Position.Y,
            vx = entity.Velocity.X,
            vy = entity.Velocity.Y,
            pvx = actor.Velocity.X,
            pvy = actor.Velocity.Y,
            flying = knife and knife:IsFlying(),
            distance = knife and knife:GetKnifeDistance(),
            followDisabled = laser and laser.DisableFollowParent,
            parentOffset = effect and { effect.ParentOffset.X, effect.ParentOffset.Y },
            spriteOffset = { entity.SpriteOffset.X, entity.SpriteOffset.Y },
            visible = entity.Visible,
            error = record.maxError,
        }))
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    verified = status.verified
    assert(status.phase ~= Phase.waiting and status.phase ~= Phase.failed, status.error)
    if status.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == Phase.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    local case, at = phase(verified)
    local buttons = 0
    if not host and status.prepared and case and at >= 20 then
        buttons = at % 40 < 20 and 8 or 4
        if at < 70 and at % 12 < 3 or at >= 80 and at < 190 or at >= 220 and at < 250 then
            buttons = buttons | 0x1000
        end
    end
    native.test_gamepad(buttons)
    if verified >= firstTick + #cases * duration and not finished then
        for _, entry in ipairs(cases) do
            local record = seen[entry.name .. ":" .. entry.weapon]
            assert(
                record and record.count >= minimumSamples,
                "Missing native weapon coverage: " .. entry.name
            )
            if not host and not entry.attached then
                assert(
                    record.maxError > 3,
                    "Independent laser was bound to its owner: " .. entry.name
                )
            end
            if not host and entry.name == "knife" then
                assert(
                    (record.subframes or 0) >= 5,
                    "Returning knife still advances only on snapshots"
                )
            end
        end
        assert(host or pathSamples >= minimumSamples, "Missing rendered path checks")
        for _, record in pairs(seen) do
            record.expected, record.relative = nil, nil
        end
        report("OBSERVED " .. json.encode(seen))
        report("PATHS samples=" .. pathSamples .. " max_error=" .. maxPathError)
        finished = true
        report("PASS attached weapons and independent lasers")
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(tick, count, bytes)
            before(tick, count, bytes)
            local case, at = phase(tick)
            if tick == 0 then
                local room = Game():GetRoom()
                for index = 0, room:GetGridSize() - 1 do
                    local grid = room:GetGridEntity(index)
                    if
                        grid
                        and grid:GetType() ~= GridEntityType.GRID_DOOR
                        and room:GetGridCollision(index) ~= GridCollisionClass.COLLISION_WALL
                    then
                        room:RemoveGridEntity(index, 0, false)
                    end
                end
                room:SetClear(true)
            end
            if case and at == 0 then
                guest(function(player)
                    for _, entry in ipairs(cases) do
                        if entry.item and player:HasCollectible(entry.item) then
                            player:RemoveCollectible(entry.item)
                        end
                    end
                    player:ChangePlayerType(case.character or PlayerType.PLAYER_ISAAC)
                    player.Position, player.Velocity = Vector(260, 220), Vector.Zero
                    player:SetMinDamageCooldown(10000)
                    if case.item then
                        player:AddCollectible(case.item, 0, false)
                    end
                end)
                Isaac.GetPlayer(0).Position, Isaac.GetPlayer(0).Velocity =
                    Vector(100, 100), Vector.Zero
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity.Type ~= EntityType.ENTITY_PLAYER then
                        entity:Remove()
                    end
                end
                report("BEGIN " .. case.name)
            end
            if host and case and at > 20 then
                guest(function(player)
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        if
                            entity.Type == EntityType.ENTITY_KNIFE
                            or entity.Type == EntityType.ENTITY_LASER
                            or entity.Type == EntityType.ENTITY_EFFECT
                        then
                            observe(entity, player, nil, at, case)
                        end
                    end
                end)
            end
        end,
        collect,
        function(bytes, tick, ack, betweenUpdates, stable)
            if restore(bytes, tick, ack, betweenUpdates, stable) == false then
                return false
            end
            local value = worldSchema.unpack(_IsaacLanState.decode(bytes, stable), tick)
            latest = { entities = {}, tick = tick }
            for _, actor in ipairs(value.actors) do
                if
                    actor[A.controller] == 2
                    and actor[A.inventory][fields.inventory.type] ~= PlayerType.PLAYER_THESOUL
                then
                    latest.actor = actor[A.entity]
                end
            end
            for _, entity in ipairs(value.room[R.entities]) do
                latest.entities[entity[E.id]] = entity
            end
        end,
        present,
        beginFloor
    )
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_RENDER, function()
    if host or finished or not latest or not latest.actor or not _IsaacLanStatus().prepared then
        return
    end
    local case, at = phase(latest.tick)
    if not case or at < 20 then
        return
    end
    local player
    for index = 0, Game():GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(index)
        if p.ControllerIndex == 2 and p:GetPlayerType() ~= PlayerType.PLAYER_THESOUL then
            player = p
            break
        end
    end
    if not player then
        return
    end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local value = latest.entities[entity:GetData().__isaac_lan_replica]
        if
            value
            and (
                entity.Type == EntityType.ENTITY_KNIFE
                or entity.Type == EntityType.ENTITY_LASER
                or entity.Type == EntityType.ENTITY_EFFECT
            )
        then
            observe(entity, player, value, at, case)
        end
    end
end)
return {
    done = function()
        return finished
    end,
    cleanup = function()
        native.test_gamepad(0)
    end,
}
