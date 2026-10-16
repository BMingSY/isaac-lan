-- audit/exportCatalog are supplied by tools/item_audit.py. Test code only.
-- Each case gets a fresh native run; processes are reused across cases.
local native, json = assert(_IsaacLan), require("json")
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local Phase, Command = native.net_phases(), native.net_commands()
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
local owner = { Name = "Isolated item compatibility audit" }
local index, renders, linked, chosen, started = 1, 0, false, false, false
local prepared, used, moved, exiting, finished = false, false, false, false, false
local beganAt, sampleAt, relinkAt, useCount = nil, 0, 0, 0
local catalogued, seen, lastTick, lastPhase = false, 0, 0, nil
local placed, damaged = false, false
local case = audit.cases[index]
local journal = assert(io.open(audit.journal[host and "host" or "client"], "a"))
local function report(event, values)
    values = values or {}
    values.event, values.key = event, values.key or (case and case.key)
    values.role, values.now_ms = host and "host" or "client", native.api_info().nowMs
    local line = "LAN_ITEM_AUDIT " .. json.encode(values)
    journal:write(line .. "\n")
    journal:flush()
    Isaac.DebugString(line)
end
local stress = createStress(report)
local lastRender
local function actor(slot, fn)
    local found = false
    local ok = native.rooms_with_player(slot, function()
        local head = native.rooms_heads()[tostring(slot)]
        if head ~= nil then
            found = true
            fn(Isaac.GetPlayer(head), Game():GetRoom())
        end
    end)
    assert(ok or not found, "Audit actor callback failed")
    return ok and found
end
local function otherRoom(origin)
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= origin then
            return d.SafeGridIndex
        end
    end
    error("Audit seed has no ordinary second room")
end
local function sample(label, tick)
    if not native.rooms_ready() then
        return
    end
    local records = {}
    for slot = 0, 1 do
        local available = actor(slot, function(p, room)
            local count, tears, projectiles, effects = 0, 0, 0, 0
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                count = count + 1
                tears = tears + (e.Type == EntityType.ENTITY_TEAR and 1 or 0)
                projectiles = projectiles + (e.Type == EntityType.ENTITY_PROJECTILE and 1 or 0)
                effects = effects + (e.Type == EntityType.ENTITY_EFFECT and 1 or 0)
            end
            records[#records + 1] = {
                slot = slot,
                type = p:GetPlayerType(),
                damage = p.Damage,
                delay = p.MaxFireDelay,
                speed = p.MoveSpeed,
                range = p.TearRange,
                shot_speed = p.ShotSpeed,
                luck = p.Luck,
                hearts = p:GetHearts(),
                max_hearts = p:GetMaxHearts(),
                soul = p:GetSoulHearts(),
                visible = p.Visible,
                dead = p:IsDead(),
                ghost = p:IsCoopGhost(),
                size = p.Size,
                scale_x = p.SpriteScale.X,
                scale_y = p.SpriteScale.Y,
                active = p:GetActiveItem(),
                charge = p:GetActiveCharge(),
                item_count = p:GetCollectibleCount(),
                target_count = case.kind == "collectible" and p:GetCollectibleNum(case.id, true)
                    or nil,
                trinket = p:GetTrinket(0),
                card = p:GetCard(0),
                pill = p:GetPill(0),
                room = native.rooms_positions()[tostring(slot)].index,
                clear = room:IsClear(),
                entities = count,
                tears = tears,
                projectiles = projectiles,
                effects = effects,
            }
        end)
        if not available then
            records[#records + 1] = { slot = slot, missing = true }
        end
    end
    seen = seen + 1
    report("sample", { label = label, tick = tick, players = records, uses = useCount })
end
local function observedUse(kind, id, p)
    if case and case.kind == kind and case.id == id then
        useCount = useCount + 1
        report("use_callback", { kind = kind, id = id, controller = p and p.ControllerIndex })
        if not host then
            report(
                "problem",
                { category = "non_native", detail = "replica executed authoritative use callback" }
            )
        end
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_USE_ITEM, function(_, id, _, p)
    observedUse("collectible", id, p)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_CARD, function(_, id, p)
    observedUse("card", id, p)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_PILL, function(_, id, p)
    observedUse("pill", id, p)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    if not prepared and seen == 0 then
        return
    end
    if case.kind == "stress" then
        stress.finish()
    end
    local expected = host and exiting
        or not host and lastTick >= ((case.mega or case.kind == "stress") and 1095 or 145)
    report(
        expected and "case_end" or "case_aborted",
        { samples = seen, uses = useCount, expected_exit = expected }
    )
    index = index + 1
    case = audit.cases[index]
    prepared, used, moved, exiting = false, false, false, false
    placed, damaged = false, false
    linked, chosen, started = false, false, false
    beganAt, sampleAt, useCount, seen, lastTick = nil, 0, 0, 0, 0
    lastRender = nil
    relinkAt = native.api_info().nowMs + (host and 300 or 1000)
    if not case then
        finished = true
    end
end)
local function prepare(tick)
    prepared, beganAt = true, native.api_info().nowMs
    report("case_begin", { kind = case.kind, id = case.id, slot = case.slot, split = case.split })
    for slot = 0, 1 do
        actor(slot, function(p, room)
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type ~= EntityType.ENTITY_PLAYER then
                    e:Remove()
                end
            end
            room:SetClear(true)
            if case.kind == "stress" then
                p:SetMinDamageCooldown(100000)
            end
            p.Position, p.Velocity =
                room:GetCenterPos() + Vector(slot == case.slot and -65 or 65, 60), Vector.Zero
        end)
    end
    if case.kind ~= "stress" and not case.mega then
        actor(case.slot, function(p, room)
            -- Rerolls/consumption get a real inventory and pedestal target;
            -- attack/kill effects get an ordinary native enemy.
            p:AddCollectible(CollectibleType.COLLECTIBLE_BREAKFAST, 0, false)
            Isaac.Spawn(
                EntityType.ENTITY_PICKUP,
                PickupVariant.PICKUP_COLLECTIBLE,
                CollectibleType.COLLECTIBLE_BREAKFAST,
                room:GetCenterPos() + Vector(120, -60),
                Vector.Zero,
                nil
            )
            Isaac.Spawn(
                EntityType.ENTITY_GAPER,
                0,
                0,
                p.Position - Vector(0, 110),
                Vector.Zero,
                nil
            )
            room:SetClear(false)
        end)
    end
    sample("before", tick)
    actor(case.slot, function(p, room)
        report("give_begin")
        if case.kind == "collectible" then
            local config = assert(Isaac.GetItemConfig():GetCollectible(case.id))
            p:AddCollectible(case.id, config.MaxCharges, true)
        elseif case.kind == "trinket" then
            p:AddTrinket(case.id, true)
        elseif case.kind == "card" then
            p:SetCard(0, case.id)
        elseif case.kind == "stress" then
            stress.prepare(case, p, room)
        end
        report("give_end")
    end)
    sample("acquired", tick)
end
local function activate(tick)
    used = true
    actor(case.slot, function(p)
        report("use_begin", { tick = tick })
        if case.kind == "collectible" then
            local config = assert(Isaac.GetItemConfig():GetCollectible(case.id))
            if config.Type == ItemType.ITEM_ACTIVE and not case.physical then
                p:UseActiveItem(case.id, 0, ActiveSlot.SLOT_PRIMARY)
            end
        elseif case.kind == "card" and not case.physical then
            p:UseCard(case.id, 0)
        elseif case.kind == "pill" then
            local color = PillColor.PILL_BLUE_BLUE | (case.horse and PillColor.PILL_GIANT_FLAG or 0)
            p:UsePill(case.id, color, 0)
        end
        report("use_return", { tick = tick })
    end)
end
local function advance(tick)
    lastTick = tick
    if not native.rooms_ready() or not case or exiting then
        return
    end
    if not catalogued then
        catalogued = true
        exportCatalog(report)
    end
    if not placed and tick >= 20 then
        placed = true
        if case.split then
            assert(native.rooms_move(1, otherRoom(native.rooms_positions()["0"].index), 0, -1))
        end
        return
    end
    if not prepared and tick >= 30 then
        prepare(tick)
    end
    if not prepared then
        return
    end
    local elapsed = native.api_info().nowMs - beganAt
    if not used and tick >= 60 then
        activate(tick)
    end
    if used and tick % 30 == 0 then
        sample("observe", tick)
    end
    if not damaged and tick >= 120 and case.kind ~= "stress" and not case.mega then
        damaged = true
        actor(case.slot, function(p)
            if not p:IsDead() and not p:IsCoopGhost() and p:GetHearts() + p:GetSoulHearts() > 1 then
                report("damage_probe")
                p:ResetDamageCooldown()
                p:TakeDamage(1, 0, EntityRef(p), 0)
            end
        end)
    end
    if case.mega and not moved and tick >= 240 then
        sample("before_room", tick)
        moved = true
        local target = otherRoom(native.rooms_positions()[tostring(case.slot)].index)
        assert(native.rooms_move(case.slot, target, 0, -1))
        report("room_changed", { target = target })
    end
    local endTick = (case.mega or case.kind == "stress") and 1100 or 150
    local deadline = (case.mega or case.kind == "stress") and 65000 or 16000
    if used and (tick >= endTick or elapsed >= deadline) then
        sample("after", tick)
        if elapsed >= deadline and tick < endTick then
            report(
                "problem",
                { category = "incomplete", detail = "case exceeded its native tick deadline" }
            )
        end
        exiting = true
        report("exit_requested")
        assert(native.net_command(Command.saveExit))
    end
end
function _IsaacLanBotFrame()
    local s = _IsaacLanStatus()
    local mask = 0
    if case and s.slot == case.slot and native.api_info().ready == 1 then
        if s.verified >= 85 and s.verified < 140 then
            mask = 1 << ButtonAction.ACTION_SHOOTUP
        end
    end
    native.input_bot(mask ~= 0 and 1 or 0, mask)
end
function _IsaacLanFrame()
    renders = renders + 1
    Options.FoundHUD, Options.ExtraHUDStyle = true, 1
    local s = baseFrame()
    local now = native.api_info().nowMs
    if case and case.kind == "stress" and s.prepared and s.verified >= 150 then
        local measured = Isaac.GetTime()
        if lastRender then
            stress.record("render", measured - lastRender)
        end
        lastRender = measured
    else
        lastRender = nil
    end
    if finished then
        if s.scene == 1 and not s.prepared then
            Isaac.DebugString("LAN_NETWORK PASS item audit batch")
        end
        return s
    end
    if
        not linked
        and s.scene == 1
        and (relinkAt > 0 and now >= relinkAt or relinkAt == 0 and renders >= (host and 300 or 360))
    then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if s.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and not started
        and s.phase == Phase.lobby
        and s.players == 2
        and s.ready0 == 1
        and s.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if (s.phase == Phase.waiting or s.phase == Phase.failed) and s.phase ~= lastPhase then
        report("problem", { category = "reconnect", detail = s.error, phase = s.phase })
    end
    lastPhase = s.phase
    local active = case
        and case.physical
        and s.slot == case.slot
        and s.verified >= 60
        and s.verified < 66
    native.test_gamepad(
        active and case.kind == "card" and 512 or 0,
        active and case.kind == "collectible" and 255 or 0
    )
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(capture, function(tick, ...)
        before(tick, ...)
        if host then
            advance(tick)
        end
    end, function(...)
        local began = Isaac.GetTime()
        local bytes = collect(...)
        if case.kind == "stress" and lastTick >= 150 then
            stress.record("capture", Isaac.GetTime() - began)
            stress.record("raw_bytes", #bytes)
        end
        return bytes
    end, function(bytes, tick, ...)
        local began = Isaac.GetTime()
        local result = restore(bytes, tick, ...)
        if case.kind == "stress" and tick >= 150 then
            stress.record("apply", Isaac.GetTime() - began)
            stress.record("raw_bytes", #bytes)
        end
        if result ~= false then
            lastTick = tick
            if not prepared then
                prepared = true
                report(
                    "case_begin",
                    { kind = case.kind, id = case.id, slot = case.slot, split = case.split }
                )
            end
            if tick - sampleAt >= 30 then
                sampleAt = tick
                sample("replica", tick)
            end
        end
        return result
    end, present, beginFloor)
end
