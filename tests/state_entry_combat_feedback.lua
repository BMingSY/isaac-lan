-- Fixed-seed native regressions for key entry, returning knives, Boss HUD ownership and descent.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local fields = assert(_IsaacLanModules["sync/fields"])
local schema = assert(_IsaacLanModules["sync/world_schema"])
local json = require("json")
local host, frame, gate = config.host, _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local boss, source, keySource, keyTarget, dungeonSource, keyButton, negativeSource, negativeTarget, negativeButton
local tick, latest, renderCount = 0, nil, 0
local seen = {
    knifeSubframes = 0,
    classification = false,
    jump = false,
    key = false,
    crawlspace = false,
    denied = false,
    keyPause = 0,
    keySamples = 0,
}
local priorKnife, priorKey, keyPause = nil, nil, 0
local function report(name, data)
    data = data or {}
    data.event, data.role, data.time, data.tick =
        name, host and "host" or "client", Isaac.GetTime(), tick
    Isaac.DebugString("LAN_ISSUES " .. json.encode(data))
end
local function actor(slot, fn)
    return native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end, 1)
end
local function clear(room)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:ToNPC() then
            e:Remove()
        end
    end
    for i = 0, room:GetGridSize() - 1 do
        local g = room:GetGridEntity(i)
        if
            g
            and g:GetType() ~= GridEntityType.GRID_DOOR
            and room:GetGridCollision(i) ~= GridCollisionClass.COLLISION_WALL
        then
            room:RemoveGridEntity(i, 0, false)
        end
    end
    room:SetClear(true)
end
local function phase(t)
    if t < 330 then
        return "knife"
    elseif t < 2000 then
        return "boss"
    elseif t < 2400 then
        return "floor"
    elseif t < 2800 then
        return "key"
    elseif t < 3000 then
        return "keyless"
    else
        return "crawlspace"
    end
end
local function buttons()
    if host then
        return 0
    end
    if tick >= 70 and tick < 320 and (tick - 70) % 75 < 30 then
        return 0x2000
    end
    if tick >= 2040 and tick < 2160 then
        return 8
    end
    if tick >= 2500 and tick < 2650 then
        if keyButton then
            return keyButton
        end
        local room = Game():GetRoom()
        for slot = 0, 7 do
            local d = room:GetDoor(slot)
            if d and d.TargetRoomType == RoomType.ROOM_TREASURE then
                keyButton = ({ 4, 1, 8, 2 })[slot % 4 + 1]
                return keyButton
            end
        end
    end
    if tick >= 2840 and tick < 2940 then
        if not negativeButton then
            for slot = 0, 7 do
                local d = Game():GetRoom():GetDoor(slot)
                if d and d.TargetRoomType == RoomType.ROOM_SHOP then
                    negativeButton = ({ 4, 1, 8, 2 })[slot % 4 + 1]
                    break
                end
            end
        end
        assert(negativeButton, "Missing native shop approach")
        return negativeButton
    end
    if tick >= 3040 and tick < 3160 then
        return 4
    end
    return 0
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    tick = s.verified
    native.test_gamepad(buttons())
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    if s.prepared and tick >= 3500 and not finished then
        assert(
            seen.classification and seen.jump,
            "Missing native Boss classification or floor departure"
        )
        assert(
            seen.key and seen.crawlspace and seen.denied,
            "Missing paid entry, crawlspace or keyless denial"
        )
        if not host then
            assert(seen.knifeSubframes >= 20, "Returning knife did not advance between snapshots")
            assert(
                seen.keySamples >= 3 and seen.keyPause < 3,
                "Key approach stalled before the doorway"
            )
        end
        report("ASSERTIONS", seen)
        finished = true
        report(
            "COMPLETE",
            { stage = Game():GetLevel():GetStage(), room = Game():GetLevel():GetCurrentRoomIndex() }
        )
        Isaac.DebugString("LAN_NETWORK PASS user four issue observations")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, b)
            before(t, n, b)
            tick = t
            if t == 30 then
                source = Game():GetLevel():GetCurrentRoomIndex()
                for i = 0, Game():GetLevel():GetRooms().Size - 1 do
                    local d = Game():GetLevel():GetRooms():Get(i)
                    if d.Data.Type == RoomType.ROOM_BOSS then
                        boss = d.SafeGridIndex
                    end
                end
                assert(boss)
                actor(0, function(p, r)
                    clear(r)
                    p.Position = Vector(100, 120)
                    p:SetMinDamageCooldown(100000)
                end)
                actor(1, function(p, r)
                    p.Position = Vector(260, 220)
                    p.Velocity = Vector.Zero
                    p:AddCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
                    p:SetMinDamageCooldown(100000)
                end)
                report("KNIFE_BEGIN", {
                    boss = boss,
                    dontCountBossHP = EntityFlag.FLAG_DONT_COUNT_BOSS_HP,
                    renderFloor = EntityFlag.FLAG_RENDER_FLOOR,
                    renderWall = EntityFlag.FLAG_RENDER_WALL,
                })
            elseif t == 330 then
                actor(1, function(p)
                    p:RemoveCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
                end)
                for slot = 0, 1 do
                    assert(native.rooms_move(slot, boss, 0, -1))
                end
                report("BOSS_BEGIN", { boss = boss })
            elseif t >= 650 and t < 1900 and t % 60 == 0 then
                actor(1, function(p, r)
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsVulnerableEnemy() and e:IsBoss() then
                            e:TakeDamage(12, 0, EntityRef(p), 0)
                        end
                    end
                end)
            elseif t == 2000 then
                actor(1, function(p, r)
                    clear(r)
                    local i = r:GetGridIndex(r:GetCenterPos() + Vector(80, 0))
                    assert(r:SpawnGridEntity(i, GridEntityType.GRID_TRAPDOOR, 0, 187, 0))
                    local g = assert(r:GetGridEntity(i))
                    g.State = 2
                    p.Position = g.Position - Vector(90, 0)
                    p.Velocity = Vector.Zero
                    report("TRAPDOOR_BEGIN", { x = g.Position.X, y = g.Position.Y })
                end)
            elseif t == 2400 then
                assert(Game():GetLevel():GetStage() == 2, "Physical floor transition did not occur")
                local level = Game():GetLevel()
                for i = 0, level:GetRooms().Size - 1 do
                    local d = level:GetRooms():Get(i)
                    if d.Data.Type == RoomType.ROOM_TREASURE then
                        keyTarget = d.SafeGridIndex
                    end
                end
                assert(keyTarget)
                for _, delta in ipairs({ -1, -13, 1, 13 }) do
                    local d = level:GetRoomByIdx(keyTarget + delta, 0)
                    if d and d.Data and d.Data.Type == RoomType.ROOM_DEFAULT then
                        keySource = d.SafeGridIndex
                        break
                    end
                end
                assert(keySource)
                assert(native.rooms_move(1, keySource, 0, -1))
                report("KEY_SOURCE", { source = keySource, target = keyTarget })
            elseif t == 2450 then
                actor(1, function(p, r)
                    clear(r)
                    p:AddKeys(3)
                    local door, slot
                    for s = 0, 7 do
                        local d = r:GetDoor(s)
                        if d and d.TargetRoomType == RoomType.ROOM_TREASURE then
                            door, slot = d, s
                            break
                        end
                    end
                    assert(door, "No native treasure door at selected source")
                    local inward = ({ Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) })[slot % 4 + 1]
                    p.Position = door.Position + inward * 55
                    p.Velocity = Vector.Zero
                    report(
                        "KEY_BEGIN",
                        { locked = door:IsLocked(), keys = p:GetNumKeys(), slot = slot }
                    )
                end)
            elseif t == 2800 then
                actor(1, function(p, r)
                    dungeonSource = Game():GetLevel():GetCurrentRoomIndex()
                    assert(
                        dungeonSource == keyTarget and p:GetNumKeys() == 2,
                        "Paid native doorway did not consume exactly one key"
                    )
                    seen.key = true
                    report(
                        "KEY_RESULT",
                        { room = dungeonSource, target = keyTarget, keys = p:GetNumKeys() }
                    )
                end)
                local level = Game():GetLevel()
                for i = 0, level:GetRooms().Size - 1 do
                    local d = level:GetRooms():Get(i)
                    if d.Data.Type == RoomType.ROOM_SHOP then
                        negativeTarget = d.SafeGridIndex
                    end
                end
                assert(negativeTarget)
                for _, delta in ipairs({ -1, -13, 1, 13 }) do
                    local d = level:GetRoomByIdx(negativeTarget + delta, 0)
                    if d and d.Data and d.Data.Type == RoomType.ROOM_DEFAULT then
                        negativeSource = d.SafeGridIndex
                        break
                    end
                end
                assert(negativeSource and native.rooms_move(1, negativeSource, 0, -1))
            elseif t == 2820 then
                actor(1, function(p, r)
                    clear(r)
                    p:AddKeys(-p:GetNumKeys())
                    local door, slot
                    for i = 0, 7 do
                        local d = r:GetDoor(i)
                        if d and d.TargetRoomType == RoomType.ROOM_SHOP then
                            door, slot = d, i
                            break
                        end
                    end
                    assert(
                        door and door:IsLocked() and not door:IsOpen() and not p:HasGoldenKey(),
                        "Keyless test requires an untouched native key lock"
                    )
                    local inward = ({ Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) })[slot % 4 + 1]
                    p.Position = door.Position + inward * 55
                    p.Velocity = Vector.Zero
                    report("KEYLESS_BEGIN", {
                        keys = p:GetNumKeys(),
                        room = Game():GetLevel():GetCurrentRoomIndex(),
                        target = negativeTarget,
                    })
                end)
            elseif t == 3000 then
                actor(1, function(p, r)
                    assert(
                        Game():GetLevel():GetCurrentRoomIndex() == negativeSource
                            and p:GetNumKeys() == 0,
                        "Keyless actor crossed an unopened native shop door"
                    )
                    seen.denied = true
                    report("KEYLESS_RESULT", { room = negativeSource, keys = p:GetNumKeys() })
                    clear(r)
                    local i = r:GetGridIndex(Vector(240, 280))
                    r:RemoveGridEntity(i, 0, false)
                    r:Update()
                    assert(r:SpawnGridEntity(i, GridEntityType.GRID_STAIRS, 0, 123, 0))
                    p.Position = r:GetGridPosition(i) + Vector(60, 0)
                    p.Velocity = Vector.Zero
                    report("CRAWLSPACE_BEGIN", { source = negativeSource })
                end)
            elseif t == 3300 then
                actor(1, function(p, r)
                    assert(r:GetType() == RoomType.ROOM_DUNGEON, "Missing native crawlspace")
                    seen.crawlspace = true
                end)
            end
            if t >= 30 and (t % 10 == 0 or (t >= 2490 and t < 2540)) then
                actor(1, function(p, r)
                    local data = {
                        phase = phase(t),
                        room = Game():GetLevel():GetCurrentRoomIndex(),
                        stage = Game():GetLevel():GetStage(),
                        x = p.Position.X,
                        y = p.Position.Y,
                        vx = p.Velocity.X,
                        vy = p.Velocity.Y,
                        body = p:GetSprite():GetAnimation(),
                        bodyFrame = p:GetSprite():GetFrame(),
                        extraFinished = p:IsExtraAnimationFinished(),
                        controls = p:AreControlsEnabled(),
                        keys = p:GetNumKeys(),
                        npcs = {},
                    }
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:ToNPC() then
                            data.npcs[#data.npcs + 1] = {
                                type = e.Type,
                                variant = e.Variant,
                                hp = e.HitPoints,
                                max = e.MaxHitPoints,
                                boss = e:IsBoss(),
                                bossID = e:ToNPC():GetBossID(),
                                flags = tostring(e:GetEntityFlags()),
                            }
                        end
                    end
                    data.doors = {}
                    for slot = 0, 7 do
                        local d = r:GetDoor(slot)
                        if d then
                            data.doors[#data.doors + 1] = {
                                slot = slot,
                                open = d:IsOpen(),
                                locked = d:IsLocked(),
                                state = d.State,
                                collision = d.CollisionClass,
                                x = d.Position.X,
                                y = d.Position.Y,
                                target = d.TargetRoomIndex,
                                animation = d:GetSprite():GetAnimation(),
                                frame = d:GetSprite():GetFrame(),
                            }
                        end
                    end
                    report("AUTHORITY", data)
                end)
            end
        end,
        collect,
        function(bytes, t, ack, between, stable)
            local result = restore(bytes, t, ack, between, stable)
            if result == false then
                return false
            end
            latest = schema.unpack(_IsaacLanState.decode(bytes, stable), t)
            return result
        end,
        present,
        beginFloor
    )
end
Isaac.AddCallback({ Name = "User four issue observation" }, ModCallbacks.MC_POST_RENDER, function()
    local s = _IsaacLanStatus()
    if finished or not s.prepared then
        return
    end
    renderCount = renderCount + 1
    local p
    for i = 0, Game():GetNumPlayers() - 1 do
        local q = Isaac.GetPlayer(i)
        if q.ControllerIndex == 2 then
            p = q
            break
        end
    end
    if not p then
        return
    end
    local data = {
        time = Isaac.GetTime(),
        phase = phase(tick),
        render = renderCount,
        nativeFrame = Game():GetFrameCount(),
        stage = Game():GetLevel():GetStage(),
        room = Game():GetLevel():GetCurrentRoomIndex(),
        x = p.Position.X,
        y = p.Position.Y,
        body = p:GetSprite():GetAnimation(),
        bodyFrame = p:GetSprite():GetFrame(),
        extraFinished = p:IsExtraAnimationFinished(),
        controls = p:AreControlsEnabled(),
        knives = {},
    }
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        local knife = e:ToKnife()
        if knife then
            data.knives[#data.knives + 1] = {
                x = e.Position.X,
                y = e.Position.Y,
                vx = e.Velocity.X,
                vy = e.Velocity.Y,
                distance = knife:GetKnifeDistance(),
                flying = knife:IsFlying(),
                parentType = e.Parent and e.Parent.Type or -1,
                spawnerType = e.SpawnerEntity and e.SpawnerEntity.Type or -1,
            }
        end
    end
    if tick >= 330 and tick < 2000 and renderCount % 6 == 0 then
        data.npcs = {}
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:ToNPC() then
                data.npcs[#data.npcs + 1] = {
                    type = e.Type,
                    variant = e.Variant,
                    hp = e.HitPoints,
                    max = e.MaxHitPoints,
                    boss = e:IsBoss(),
                    bossID = e:ToNPC():GetBossID(),
                    flags = tostring(e:GetEntityFlags()),
                }
            end
        end
    end
    if data.body == "Trapdoor" then
        seen.jump = true
    end
    if not host and tick < 330 and data.knives[1] then
        local k = data.knives[1]
        if priorKnife and priorKnife.tick == tick and math.abs(priorKnife.x - k.x) > 0.05 then
            seen.knifeSubframes = seen.knifeSubframes + 1
        end
        priorKnife = { tick = tick, x = k.x }
    end
    if data.npcs and tick >= 400 then
        local main, ghost
        for _, npc in ipairs(data.npcs) do
            if npc.type == 79 and npc.variant == 2 then
                main = npc
            end
            if npc.type == 79 and npc.variant == 12 then
                ghost = npc
            end
        end
        if main and ghost then
            assert(
                main.boss and not ghost.boss,
                "Native Boss classification includes the invulnerable twin"
            )
            seen.classification = true
        end
    end
    if not host then
        if tick > 2550 and tick < 2800 and Game():GetRoom():GetType() == RoomType.ROOM_TREASURE then
            assert(p:GetNumKeys() == 2)
            seen.key = true
        end
        if tick > 3100 and Game():GetRoom():GetType() == RoomType.ROOM_DUNGEON then
            seen.crawlspace = true
        end
        if tick > 2970 and tick < 3000 then
            assert(Game():GetRoom():GetType() == RoomType.ROOM_DEFAULT and p:GetNumKeys() == 0)
            seen.denied = true
        end
    end
    if tick >= 2450 and tick < 2700 then
        data.inputX = p:GetMovementInput().X
        data.inputY = p:GetMovementInput().Y
        data.doors = {}
        for slot = 0, 7 do
            local d = Game():GetRoom():GetDoor(slot)
            if d then
                data.doors[#data.doors + 1] = {
                    slot = slot,
                    open = d:IsOpen(),
                    locked = d:IsLocked(),
                    state = d.State,
                    collision = d.CollisionClass,
                    x = d.Position.X,
                    y = d.Position.Y,
                    target = d.TargetRoomIndex,
                    animation = d:GetSprite():GetAnimation(),
                    frame = d:GetSprite():GetFrame(),
                }
            end
        end
    end
    if not host and tick >= 2500 and tick < 2600 then
        for _, door in ipairs(data.doors or {}) do
            if door.slot == 3 and door.target == 95 then
                local along = door.y - p.Position.Y
                if
                    priorKey
                    and priorKey.room == data.room
                    and data.time - priorKey.time >= 12
                    and data.time - priorKey.time <= 25
                    and along > 20
                    and along < 40
                    and priorKey.along > 20
                    and priorKey.along < 40
                    and data.inputY > 0
                then
                    seen.keySamples = seen.keySamples + 1
                    keyPause = priorKey.along - along < 1 and keyPause + 1 or 0
                    seen.keyPause = math.max(seen.keyPause, keyPause)
                else
                    keyPause = 0
                end
                priorKey = { room = data.room, time = data.time, along = along }
            end
        end
    end
    if latest then
        for _, a in ipairs(latest.actors) do
            if a[fields.actor.controller] == 2 then
                data.authorityX = a[fields.actor.entity][fields.entity.position][1]
                data.authorityY = a[fields.actor.entity][fields.entity.position][2]
                data.extra =
                    a[fields.actor.visuals][fields.actorSprites.extra][fields.sprite.animation]
            end
        end
    end
    if tick < 340 or tick > 1980 or renderCount % 6 == 0 then
        report("RENDER", data)
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
