-- Measure key-to-display independently from host attack confirmation at 80 ms RTT.
local native, json = assert(_IsaacLan), require("json")
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local fields, schema = _IsaacLanModules["sync/fields"], _IsaacLanModules["sync/world_schema"]
local pose = _IsaacLanModules["sync/weapon_pose"]
local A, E, R = fields.actor, fields.entity, fields.room
local cases = {
    { name = "tears", kind = WeaponType.WEAPON_TEARS },
    {
        name = "brimstone",
        item = CollectibleType.COLLECTIBLE_BRIMSTONE,
        kind = WeaponType.WEAPON_BRIMSTONE,
        cap = 32,
    },
    {
        name = "knife",
        item = CollectibleType.COLLECTIBLE_MOMS_KNIFE,
        kind = WeaponType.WEAPON_KNIFE,
        cap = 40,
    },
    {
        name = "tech-x",
        item = CollectibleType.COLLECTIBLE_TECH_X,
        kind = WeaponType.WEAPON_TECH_X,
        cap = 30,
    },
    {
        name = "multishot",
        item = CollectibleType.COLLECTIBLE_INNER_EYE,
        kind = WeaponType.WEAPON_TEARS,
    },
    {
        name = "sword",
        item = CollectibleType.COLLECTIBLE_SPIRIT_SWORD,
        kind = WeaponType.WEAPON_SPIRIT_SWORD,
    },
}
local firstTick, duration = 60, 220
local mirror = _IsaacLanTest.attackMirror == true
if mirror then
    firstTick, cases = 800, { cases[1] }
end
local frame, gate, counter = _IsaacLanFrame, native.net_gate, native.diagnostics_counter
local renders, verified, linked, chosen, finished = 0, 0, false, false, false
local current, lastButtons, edge = nil, 0, nil
local measurements, metrics, authorityTears = {}, {}, {}
local headSamples, chargeSamples, releaseSamples, entitySamples = 0, 0, 0, 0
local function report(label, value)
    Isaac.DebugString("LAN_NETWORK ATTACK_RESPONSE " .. label .. " " .. json.encode(value))
end
local function phase(tick)
    local at = tick - firstTick
    if at < 0 then
        return nil, at
    end
    return cases[math.floor(at / duration) + 1], at % duration
end
local function guest(fn)
    assert(native.rooms_with_player(1, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()["1"])))
    end))
end
native.diagnostics_counter = function(name, value)
    if current and name == "attack.previews" and value > (metrics[name] or 0) then
        local m = measurements[current.name]
        m.previews = (m.previews or 0) + value - (metrics[name] or 0)
        if not m.firstPreview then
            m.firstPreview = Isaac.GetTime()
        end
    end
    metrics[name] = value
    return counter(name, value)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    verified = s.verified
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    local case, at = phase(verified)
    if case and current ~= case then
        current = case
        measurements[case.name] = { aim = {}, charge = {}, release = {} }
        lastButtons, edge = 0, nil
    end
    local buttons, aiming = 0, nil
    if not host and s.prepared and case then
        if at >= 20 and at < 50 then
            buttons, aiming = 0x2000, "HeadRight"
        elseif at >= 50 and at < 80 then
            buttons, aiming = 0x4000, "HeadLeft"
        elseif at >= 80 and at < 140 then
            buttons, aiming = 0x8000, "HeadUp"
        elseif at >= 160 and at < 190 then
            buttons, aiming = 0x1000, "HeadDown"
        end
        if buttons ~= lastButtons then
            if mirror then
                if aiming == "HeadRight" then
                    aiming = "HeadLeft"
                elseif aiming == "HeadLeft" then
                    aiming = "HeadRight"
                end
            end
            edge = { name = aiming, time = Isaac.GetTime(), at = at }
            if at == 20 then
                measurements[case.name].pressed = edge.time
            end
            lastButtons = buttons
        end
        if case.name == "tears" and at >= 30 and at < 70 then
            buttons = buttons | (at < 50 and 8 or 4)
        end
    end
    native.test_gamepad(buttons)
    if verified >= firstTick + #cases * duration and not finished then
        if not host then
            local plain = measurements.tears
            assert(
                plain.firstPreview and plain.firstAuthority and plain.pressed,
                "Missing first-shot observations"
            )
            plain.previewMs, plain.authorityMs =
                plain.firstPreview - plain.pressed, plain.firstAuthority - plain.pressed
            assert(
                plain.previewMs >= 0 and plain.previewMs < 50,
                "First tear did not respond locally"
            )
            assert(
                plain.authorityMs > plain.previewMs + 40,
                "Latency relay did not separate preview from confirmation"
            )
            assert((metrics["attack.confirmed"] or 0) > 5, "Insufficient tear handoffs")
            assert(
                mirror or (measurements.multishot.previews or 0) == 0,
                "Multi-shot attacks generated false single tears"
            )
            assert(
                headSamples >= (mirror and 4 or 24)
                    and (mirror or (chargeSamples > 5 and releaseSamples > 3))
                    and entitySamples > 20,
                "Missing aim, charge, release or entity ownership coverage"
            )
            for _, caseValue in ipairs(cases) do
                if caseValue.cap then
                    assert(
                        measurements[caseValue.name].maximum >= caseValue.cap - 0.01,
                        "Charge never reached its native cap"
                    )
                end
            end
            report("MEASURED", measurements)
            report("COUNTS", {
                aim = headSamples,
                charge = chargeSamples,
                release = releaseSamples,
                entities = entitySamples,
                confirmed = metrics["attack.confirmed"],
                expired = metrics["attack.expired"],
            })
        end
        finished = true
        report("PASS", "local aim, tears, charge/release and authoritative ownership")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(tick, count, bytes)
            before(tick, count, bytes)
            local case, at = phase(tick)
            if mirror and tick == 30 then
                Game():GetLevel():SetStage(2, StageType.STAGETYPE_REPENTANCE)
                Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
                return
            elseif mirror and tick == 630 then
                local level = Game():GetLevel()
                local index = level:GetCurrentRoomIndex()
                assert(native.rooms_ready() and level:GetRoomByIdx(index, 1).Data)
                assert(native.rooms_move(1, index, 1, -1))
            end
            if case and at == 0 then
                guest(function(player)
                    for _, entry in ipairs(cases) do
                        if entry.item and player:HasCollectible(entry.item) then
                            player:RemoveCollectible(entry.item)
                        end
                    end
                    if case.item then
                        player:AddCollectible(case.item, 0, false)
                    end
                    player.Position, player.Velocity = Vector(260, 220), Vector.Zero
                    player:SetMinDamageCooldown(0)
                    Options.ChargeBars = true
                    local room = Game():GetRoom()
                    assert(
                        not mirror or room:IsMirrorWorld(),
                        "Attack fixture missed the mirror room"
                    )
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        if entity.Type ~= EntityType.ENTITY_PLAYER then
                            entity:Remove()
                        end
                    end
                    for index = 0, room:GetGridSize() - 1 do
                        local grid = room:GetGridEntity(index)
                        if
                            grid
                            and grid:GetType() ~= GridEntityType.GRID_DOOR
                            and room:GetGridCollision(index)
                                ~= GridCollisionClass.COLLISION_WALL
                        then
                            room:RemoveGridEntity(index, 0, false)
                        end
                    end
                    room:SetClear(true)
                end)
                Isaac.GetPlayer(0).Position = Vector(150, 140)
                report("BEGIN", case.name)
            end
        end,
        collect,
        function(bytes, tick, ack, betweenUpdates, stable)
            if restore(bytes, tick, ack, betweenUpdates, stable) == false then
                return false
            end
            local value = schema.unpack(_IsaacLanState.decode(bytes, stable), tick)
            local owner
            for _, actor in ipairs(value.actors) do
                if actor[A.controller] == 2 then
                    owner = actor[A.entity][E.id]
                end
            end
            authorityTears = {}
            for _, entity in ipairs(value.room[R.entities]) do
                if entity[E.type] == EntityType.ENTITY_TEAR then
                    authorityTears[entity[E.id]] = true
                    if entity[E.spawner] == owner and current and current.name == "tears" then
                        measurements.tears.firstAuthority = measurements.tears.firstAuthority
                            or Isaac.GetTime()
                    end
                end
            end
            local count = 0
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_TEAR then
                    assert(
                        authorityTears[entity:GetData().__isaac_lan_replica],
                        "Speculative shot entered the native entity graph"
                    )
                    count = count + 1
                end
            end
            if count > 0 then
                entitySamples = entitySamples + 1
            end
            return true
        end,
        function(input, sequence)
            present(input, sequence)
            if host or not current or not edge then
                return
            end
            local elapsed = Isaac.GetTime() - edge.time
            local player = Isaac.GetPlayer(1)
            local m = measurements[current.name]
            if
                edge.name
                and not edge.aimed
                and player:GetSprite():GetOverlayAnimation() == edge.name
            then
                edge.aimed = true
                m.aim[#m.aim + 1] = elapsed
                headSamples = headSamples + 1
                assert(elapsed < 50, "Aiming waited for host confirmation")
            end
            if current.cap then
                local weapon = pose.read(assert(native.actor_pose(player:GetSprite())))[2]
                -- A newly applied view can precede the next frontend status poll.
                if not weapon or weapon.kind ~= current.kind then
                    return
                end
                m.maximum = math.max(m.maximum or 0, weapon.charge)
                assert(weapon.charge <= current.cap + 0.01, "Predicted charge exceeded native cap")
                if
                    edge.name
                    and (edge.at == 20 or edge.at == 160)
                    and not edge.charged
                    and weapon.charge > 0
                then
                    edge.charged = true
                    m.charge[#m.charge + 1] = elapsed
                    chargeSamples = chargeSamples + 1
                    assert(elapsed < 50, "Charge start waited for the host")
                elseif not edge.name and not edge.released and weapon.charge == 0 then
                    edge.released = true
                    m.release[#m.release + 1] = elapsed
                    releaseSamples = releaseSamples + 1
                    assert(elapsed < 50, "Charge release waited for the host")
                end
            end
        end,
        beginFloor
    )
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        native.diagnostics_counter = counter
    end,
}
