local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local json = require("json")
local base, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local tick, hitSource, damage, pillUses = 0, nil, 0, 0
local latestPrediction = {}
local observed = { hurt = 0, lockedHurt = 0, paralysis = 0, pillPoses = 0, pixelation = 0 }
local baselineTexts
local gamepad = { left = 4, right = 8, pill = 512 }
local function log(event, data)
    data = data or {}
    data.event, data.time, data.role, data.tick =
        event, Isaac.GetTime(), host and "host" or "client", tick
    Isaac.DebugString("LAN_HIT_PILL " .. json.encode(data))
end
local function actor(slot, fn)
    return native.rooms_with_player(slot, function()
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            if p.ControllerIndex == slot + 1 then
                return fn(p, Game():GetRoom(), i)
            end
        end
        error("Missing actor " .. slot)
    end, 1)
end
local function clear(room)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:ToNPC() then
            e:Remove()
        end
    end
    room:SetClear(true)
end
-- Normal native inputs, including repeated bad pills and a host-use control.
local cases = {
    { at = 280, effect = PillEffect.PILLEFFECT_SPEED_DOWN, slot = 1 },
    { at = 350, effect = PillEffect.PILLEFFECT_SPEED_DOWN, slot = 1 },
    { at = 480, effect = PillEffect.PILLEFFECT_BAD_TRIP, slot = 1 },
    { at = 610, effect = PillEffect.PILLEFFECT_I_FOUND_PILLS, slot = 1 },
    { at = 740, effect = PillEffect.PILLEFFECT_RETRO_VISION, slot = 1 },
    { at = 870, effect = PillEffect.PILLEFFECT_PARALYSIS, slot = 1 },
    { at = 1000, effect = PillEffect.PILLEFFECT_SPEED_UP, slot = 0 },
    { at = 1140, effect = PillEffect.PILLEFFECT_I_FOUND_PILLS, slot = 1, horse = true },
}
local owner = { Name = "Owned feedback damage and pill observation" }
local function onDamage(_, e, amount, flags, source)
    local p = e:ToPlayer()
    if p then
        damage = damage + 1
        log("damage", {
            controller = p.ControllerIndex,
            amount = amount,
            flags = flags,
            sourceType = source.Type,
            sourceVariant = source.Variant,
        })
    end
end
local function onPill(_, effect, p, flags)
    pillUses = pillUses + 1
    log("pill_use", { controller = p.ControllerIndex, effect = effect, flags = flags })
end
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, onDamage)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_PILL, onPill)
local makePrediction = _IsaacLanPrediction.new
_IsaacLanPrediction.new = function(position)
    local model = makePrediction(position)
    local step = model.step
    model.step = function(self, direction, sequence, speed, dt, locked, ...)
        local result = step(self, direction, sequence, speed, dt, locked, ...)
        latestPrediction = {
            locked = locked,
            vx = self.velocity.X,
            vy = self.velocity.Y,
            pending = #self.pending,
            x = result.X,
            y = result.Y,
        }
        return result
    end
    return model
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = base()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    tick = s.verified
    local buttons = not host and (tick >= 70 and tick < 110) and gamepad.right or 0
    if not host and tick >= 205 and tick < 245 then
        buttons = gamepad.left
    end
    for _, case in ipairs(cases) do
        if host == (case.slot == 0) and tick >= case.at and tick < case.at + 5 then
            buttons = buttons | gamepad.pill
        end
    end
    native.test_gamepad(buttons)
    if s.prepared and tick >= 30 then
        local players, bySlot = {}, {}
        for slot = 0, 1 do
            actor(slot, function(p, room, index)
                local sprite = p:GetSprite()
                local extra = assert(native.actor_sprites(index, sprite))[1]
                local pose = not host and _IsaacLanState.actorPose(p)
                local _, _, _, pixels, duration, dizzy, target, _, bloom, bloomDuration =
                    string.unpack(">BBI4I4I4fffI4I4f", native.item_presentation_pose(slot))
                players[#players + 1] = {
                    slot = slot,
                    x = p.Position.X,
                    y = p.Position.Y,
                    vx = p.Velocity.X,
                    vy = p.Velocity.Y,
                    body = sprite:GetAnimation(),
                    frame = sprite:GetFrame(),
                    extra = extra:GetAnimation(),
                    extraFrame = extra:GetFrame(),
                    controls = p.ControlsEnabled,
                    enabled = p:AreControlsEnabled(),
                    controlCooldown = p.ControlsCooldown,
                    damageCooldown = p:GetDamageCooldown(),
                    extraFinished = p:IsExtraAnimationFinished(),
                    hearts = p:GetHearts(),
                    pixels = pixels,
                    pixelDuration = duration,
                    dizzy = dizzy,
                    dizzyTarget = target,
                    bloom = bloom,
                    bloomDuration = bloomDuration,
                    room = Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex,
                    authority = pose or false,
                }
            end)
        end
        for _, p in ipairs(players) do
            bySlot[p.slot] = p
        end
        local presentation = native.item_presentation_state()
        if tick >= 250 and baselineTexts == nil then
            baselineTexts = presentation.texts
        end
        local guest = bySlot[1]
        if tick < 280 and guest and guest.body == "Hit" and guest.enabled and guest.controls then
            observed.hurt = observed.hurt + 1
            if not host and latestPrediction.locked then
                observed.lockedHurt = observed.lockedHurt + 1
            end
        end
        for ordinal, case in ipairs(cases) do
            if tick >= case.at + 10 and tick <= case.at + 14 then
                local expected = 0
                for previous = 1, ordinal do
                    if host == (cases[previous].slot == 0) then
                        expected = expected + 1
                    end
                end
                assert(
                    presentation.texts == baselineTexts + expected,
                    "Pill text crossed owners or replayed"
                )
                local own, other = assert(bySlot[case.slot]), assert(bySlot[1 - case.slot])
                local localScreen = bySlot[host and 0 or 1]
                assert(
                    (localScreen.bloom > 0) == (host == (case.slot == 0)),
                    "Pill bloom crossed viewports or failed to reach its owner"
                )
                if host then
                    assert(own.bloom > 0 and other.bloom == 0, "Authority bloom ownership differs")
                end
                if
                    case.effect == PillEffect.PILLEFFECT_SPEED_DOWN
                    or case.effect == PillEffect.PILLEFFECT_BAD_TRIP
                then
                    assert(
                        own.body == "Sad" and other.body ~= "Sad",
                        "Bad pill body animation crossed actors"
                    )
                elseif case.effect == PillEffect.PILLEFFECT_SPEED_UP then
                    assert(
                        own.body == "Happy" and other.body ~= "Happy",
                        "Good pill body animation crossed actors"
                    )
                else
                    assert(
                        own.extra == "UseItem" and other.extra == "",
                        "Pill extra animation crossed actors"
                    )
                end
                observed.pillPoses = observed.pillPoses + 1
                if case.effect == PillEffect.PILLEFFECT_RETRO_VISION then
                    assert(own.pixels > 0 and other.pixels == 0, "Retro Vision crossed viewports")
                    observed.pixelation = observed.pixelation + 1
                elseif case.effect == PillEffect.PILLEFFECT_PARALYSIS then
                    assert(not own.enabled, "Native paralysis did not lock movement")
                    if not host then
                        assert(latestPrediction.locked, "Hurt exception bypassed paralysis")
                    end
                    observed.paralysis = observed.paralysis + 1
                end
            end
        end
        log("render", {
            players = players,
            presentation = presentation,
            prediction = latestPrediction,
            ping = s.ping1,
        })
        if host then
            for _, case in ipairs(cases) do
                if tick == case.at + 10 then
                    for slot = 0, 1 do
                        local bytes = native.item_presentation_events(slot)
                        log("events", {
                            slot = slot,
                            effect = case.effect,
                            bytes = (bytes:gsub(".", function(c)
                                return string.format("%02x", c:byte())
                            end)),
                        })
                    end
                end
            end
        end
    end
    if tick >= 1300 and not finished then
        assert(observed.hurt >= 10, "Missing real contact and direct hurt animation coverage")
        assert(observed.lockedHurt == 0, "Hurt animation incorrectly locked local prediction")
        assert(
            observed.pillPoses >= #cases and observed.pixelation > 0 and observed.paralysis > 0,
            "Missing pill pose, viewport or control-lock coverage"
        )
        assert(
            host and pillUses == #cases or not host and pillUses == 0,
            "Pill effect executed on the wrong authority"
        )
        log("complete", { damage = damage, pillUses = pillUses, observed = observed })
        finished = true
        Isaac.DebugString("LAN_NETWORK PASS hurt movement and pill ownership")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, b)
        before(t, n, b)
        tick = t
        if t == 30 then
            Game():GetLevel():RemoveCurses(Game():GetLevel():GetCurses())
            actor(0, function(p, room)
                clear(room)
                p.Position = Vector(160, 180)
            end)
            actor(1, function(p)
                p.Position, p.Velocity = Vector(240, 280), Vector.Zero
                p:AddMaxHearts(18)
                p:AddHearts(24)
                log(
                    "original_pill",
                    { color = 10, effect = Game():GetItemPool():GetPillEffect(10, p) }
                )
            end)
        elseif t == 60 then
            actor(1, function()
                hitSource = Isaac.Spawn(
                    EntityType.ENTITY_ATTACKFLY,
                    0,
                    0,
                    Vector(340, 280),
                    Vector.Zero,
                    nil
                )
                hitSource:AddEntityFlags(EntityFlag.FLAG_FREEZE)
            end)
        elseif t == 125 then
            actor(1, function(_, room)
                clear(room)
            end)
        elseif t == 190 then
            actor(1, function(p)
                p.Position, p.Velocity = Vector(420, 280), Vector.Zero
            end)
        elseif t == 320 then
            local origin = native.rooms_positions()["0"].index
            for i = 0, Game():GetLevel():GetRooms().Size - 1 do
                local d = Game():GetLevel():GetRooms():Get(i)
                if d.SafeGridIndex ~= origin and d.Data.Type == RoomType.ROOM_DEFAULT then
                    assert(native.rooms_move(1, d.SafeGridIndex, 0, -1))
                    actor(1, function(_, room)
                        clear(room)
                    end)
                    break
                end
            end
        elseif t == 330 then
            -- The destination's first native update populates it after rooms_move.
            -- Remove those enemies before observing pill poses, as in the horse-pill case.
            actor(1, function(_, room)
                clear(room)
            end)
        elseif t == 450 then
            assert(native.rooms_move(1, native.rooms_positions()["0"].index, 0, -1))
        elseif t == 1090 then
            actor(1, function(_, room)
                clear(room)
            end)
        elseif t == 1070 then
            local origin = native.rooms_positions()["0"].index
            for i = 0, Game():GetLevel():GetRooms().Size - 1 do
                local d = Game():GetLevel():GetRooms():Get(i)
                if d.SafeGridIndex ~= origin and d.Data.Type == RoomType.ROOM_DEFAULT then
                    assert(native.rooms_move(1, d.SafeGridIndex, 0, -1))
                    break
                end
            end
        elseif t == 220 then
            actor(1, function(p)
                log("direct_damage", { accepted = p:TakeDamage(1, 0, EntityRef(p), 0) })
            end)
        end
        for _, case in ipairs(cases) do
            if t == case.at - 20 then
                actor(case.slot, function(p)
                    local color = Game():GetItemPool():ForceAddPillEffect(case.effect)
                    p:SetCard(0, 0)
                    p:SetPill(0, color | (case.horse and PillColor.PILL_GIANT_FLAG or 0))
                    p.Position, p.Velocity = Vector(case.slot == 0 and 180 or 400, 280), Vector.Zero
                    log(
                        "pill_setup",
                        { slot = case.slot, effect = case.effect, color = p:GetPill(0) }
                    )
                end)
            end
        end
    end, collect, restore, present, beginFloor)
end

return {
    done = function()
        return finished
    end,
    cleanup = function()
        _IsaacLanFrame, native.net_gate = base, gate
        _IsaacLanPrediction.new = makePrediction
        native.test_gamepad(0)
        Isaac.RemoveCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, onDamage)
        Isaac.RemoveCallback(owner, ModCallbacks.MC_USE_PILL, onPill)
    end,
}
