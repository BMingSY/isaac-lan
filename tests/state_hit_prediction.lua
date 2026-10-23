-- Real 80 ms RTT regression: predicted hits, confirmed events and Mod veto.
-- Retains the exact curse pills and all six preceding combat cases in one pair.
-- Run through run_network_engine.py in protected, owned host/client labs.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local json = require("json")
local base, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local tick, uses, checks = 0, 0, 0
local damages, noFlashDamages, early, seenEnemy, retired = 0, 0, {}, {}, {}
local hitCounts, noFlashBaseline = {}, nil
local counter = native.diagnostics_counter
function native.diagnostics_counter(name, value)
    if name:sub(1, 4) == "hit." then
        if hitCounts[name] ~= value then
            Isaac.DebugString("LAN_HIT_COUNTER " .. json.encode({
                name = name,
                value = value,
                time = Isaac.GetTime(),
                tick = tick,
            }))
        end
        hitCounts[name] = value
    end
    return counter(name, value)
end
local gamepadPill = 512
local cases = {
    { at = 120, slot = 1, natural = 10 },
    { at = 300, slot = 1, effect = PillEffect.PILLEFFECT_TELEPILLS },
    { at = 480, slot = 1, effect = PillEffect.PILLEFFECT_QUESTIONMARK },
}

local function log(event, data)
    data = data or {}
    data.event, data.time, data.role, data.tick =
        event, Isaac.GetTime(), host and "host" or "client", tick
    Isaac.DebugString("LAN_CURSE_PILL " .. json.encode(data))
end
local function actor(slot, fn)
    return native.rooms_with_player(slot, function()
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            if p.ControllerIndex == slot + 1 then
                return fn(p, Game():GetRoom(), i)
            end
        end
        error("Missing actor")
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
local owner = { Name = "Curse pill exact trigger audit" }
Isaac.AddCallback(owner, ModCallbacks.MC_USE_PILL, function(_, effect, p, flags)
    uses = uses + 1
    log("use", { controller = p.ControllerIndex, effect = effect, flags = flags })
end)
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, e, amount, flags, source)
    if e:ToNPC() then
        assert(host, "Replica executed monster damage")
        if tick >= 1780 and tick < 1960 then
            log(
                "veto",
                { source = source.Entity and native.combat_identity(source.Entity:GetSprite()) }
            )
            return false
        end
        assert(tick < 1240 or tick >= 1600, "An invulnerable target or missed shot took damage")
        damages = damages + 1
        if tick >= 1960 then
            noFlashDamages = noFlashDamages + 1
        end
        log("damage", {
            id = e:GetData().__isaac_lan_entity,
            type = e.Type,
            hp = e.HitPoints,
            amount = amount,
            source = source.Type,
        })
    end
end)
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
    local buttons = 0
    for _, case in ipairs(cases) do
        if host == (case.slot == 0) and tick >= case.at and tick < case.at + 5 then
            buttons = gamepadPill
        end
    end
    if
        not host
        and (
            tick >= 730 and tick < 810
            or tick >= 910 and tick < 990
            or tick >= 1090 and tick < 1170
            or tick >= 1270 and tick < 1350
            or tick >= 1450 and tick < 1530
            or tick >= 1630 and tick < 1710
            or tick >= 1810 and tick < 1890
            or tick >= 1990 and tick < 2070
        )
    then
        buttons = 0x2000
    end
    native.test_gamepad(buttons)
    if s.prepared and tick >= 700 then
        actor(1, function()
            local entities = {}
            local case = math.floor((tick - 700) / 180) + 1
            local found = false
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:ToNPC() or e:ToTear() or e:ToEffect() then
                    local sc = e:GetSprite().Color
                    entities[#entities + 1] = {
                        id = e:GetData().__isaac_lan_entity or e:GetData().__isaac_lan_replica,
                        type = e.Type,
                        variant = e.Variant,
                        hp = e.HitPoints,
                        maxHP = e.MaxHitPoints,
                        visible = e.Visible,
                        size = e.Size,
                        vulnerable = e:IsVulnerableEnemy(),
                        x = e.Position.X,
                        y = e.Position.Y,
                        vx = e.Velocity.X,
                        vy = e.Velocity.Y,
                        animation = e:GetSprite():GetAnimation(),
                        frame = e:GetSprite():GetFrame(),
                        spriteColor = { sc.R, sc.G, sc.B, sc.RO, sc.GO, sc.BO },
                    }
                    if e:ToNPC() then
                        found, seenEnemy[case] = true, true
                        assert(sc.RO < 0.8, "Native hurt color was compounded")
                        if not host and e.HitPoints == e.MaxHitPoints then
                            if sc.RO > 0.5 then
                                early[case] = (early[case] or 0) + 1
                            end
                        end
                    end
                end
            end
            if seenEnemy[case] and not found then
                retired[case] = true
            end
            log("combat", { entities = entities })
        end)
    end
    if s.prepared and tick >= 30 and tick < 650 then
        local actors = {}
        for slot = 0, 1 do
            actor(slot, function(p, room, i)
                local extra = native.actor_sprites(i, p:GetSprite())[1]
                actors[#actors + 1] = {
                    slot = slot,
                    body = p:GetSprite():GetAnimation(),
                    frame = p:GetSprite():GetFrame(),
                    extra = extra:GetAnimation(),
                    extraFrame = extra:GetFrame(),
                    room = Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex,
                    x = p.Position.X,
                    y = p.Position.Y,
                    pill = p:GetPill(0),
                }
            end)
        end
        local presentation = native.item_presentation_state()
        if tick >= 520 then
            assert(
                presentation.texts == (host and 0 or #cases),
                "Pill banner reached the wrong viewport"
            )
        end
        log("render", {
            actors = actors,
            presentation = presentation,
            curses = Game():GetLevel():GetCurses(),
            hallucination = Game():HasHallucination(),
            shake = Game():GetScreenShakeCountdown(),
            ping = s.ping1,
        })
        for _, case in ipairs(cases) do
            if tick >= case.at + 20 and tick < case.at + 25 then
                assert(
                    (Game():GetLevel():GetCurses() & LevelCurse.CURSE_OF_MAZE) ~= 0,
                    "Missing original floor curse"
                )
                checks = checks + 1
                if host then
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
    if not host and tick >= 1960 and not noFlashBaseline then
        noFlashBaseline = hitCounts["hit.predicted"]
    end
    if tick >= 2150 and not finished then
        if host then
            assert(damages > 5, "No actual monster damage")
            assert(noFlashDamages >= 3, "No-flash case did not receive actual tear hits")
        else
            assert(damages == 0, "Replica executed authoritative damage")
            assert(
                noFlashBaseline == hitCounts["hit.predicted"],
                "No-flash NPC received speculative hurt presentation"
            )
            assert((hitCounts["hit.predicted"] or 0) > 10, "No local contact prediction")
            assert((hitCounts["hit.confirmed"] or 0) > 5, "No exact hit confirmations")
            assert((hitCounts["hit.rejected"] or 0) >= 3, "Mod veto did not reject predictions")
            assert(
                hitCounts["hit.expired"] == 0,
                "Prediction timed out instead of matching a result"
            )
            assert(
                hitCounts["hit.predicted"] == hitCounts["hit.confirmed"] + hitCounts["hit.rejected"],
                "Unresolved predicted contact"
            )
        end
        assert(retired[3], "Lethal ordinary tears did not retire the monster")
        assert(not retired[4] and not retired[5], "An invulnerable or missed monster disappeared")
        log(
            "combat_complete",
            {
                damages = damages,
                noFlashDamages = noFlashDamages,
                early = early,
                retired = retired,
                hitCounts = hitCounts,
            }
        )
        assert(
            checks >= #cases and uses == (host and #cases or 0),
            "Missing actual curse pill coverage"
        )
        log("complete", { uses = uses, checks = checks })
        finished = true
        Isaac.DebugString("LAN_NETWORK PASS feedback observation complete")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, b)
        before(t, n, b)
        tick = t
        if t >= 30 and t < 650 then
            for slot = 0, 1 do
                actor(slot, function(p, room)
                    clear(room)
                end)
            end
        end
        if t == 30 then
            actor(1, function(p)
                local mapping = {}
                for color = 1, 13 do
                    mapping[#mapping + 1] =
                        { color = color, effect = Game():GetItemPool():GetPillEffect(color, p) }
                end
                log("natural_pool", { mapping = mapping })
            end)

            for slot = 0, 1 do
                actor(slot, function(p, room)
                    clear(room)
                    p.Position, p.Velocity = Vector(180 + slot * 220, 280), Vector.Zero
                    p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                    p:SetMinDamageCooldown(10000)
                end)
            end
        elseif t == 570 then
            local origin = native.rooms_positions()["0"].index
            for i = 0, Game():GetLevel():GetRooms().Size - 1 do
                local d = Game():GetLevel():GetRooms():Get(i)
                if d.SafeGridIndex ~= origin and d.Data.Type == RoomType.ROOM_DEFAULT then
                    assert(native.rooms_move(1, d.SafeGridIndex, 0, -1))
                    break
                end
            end
        elseif t == 600 then
            actor(1, function(_, room)
                clear(room)
            end)
        end
        if t == 675 then
            Game():GetLevel():RemoveCurses(Game():GetLevel():GetCurses())
            assert(native.rooms_move(1, native.rooms_positions()["0"].index, 0, -1))
        elseif t == 860 then
            local origin = native.rooms_positions()["0"].index
            local list = Game():GetLevel():GetRooms()
            for i = 0, list.Size - 1 do
                local d = list:Get(i)
                if d.SafeGridIndex ~= origin and d.Data.Type == RoomType.ROOM_DEFAULT then
                    assert(native.rooms_move(1, d.SafeGridIndex, 0, -1))
                    break
                end
            end
        end
        if
            t == 700
            or t == 880
            or t == 1060
            or t == 1240
            or t == 1420
            or t == 1600
            or t == 1780
            or t == 1960
        then
            actor(1, function(p, room)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type ~= 1 then
                        e:Remove()
                    end
                end
                p.Position, p.Velocity = Vector(260, 280), Vector.Zero
                local e = Isaac.Spawn(
                    EntityType.ENTITY_HORF,
                    0,
                    0,
                    Vector(t == 700 and 310 or 400, t == 1420 and 360 or 280),
                    Vector.Zero,
                    nil
                )
                if t ~= 1060 then
                    e.HitPoints, e.MaxHitPoints = 100, 100
                end
                if t == 1780 then
                    p.MaxFireDelay = 10
                end
                if t == 1600 then
                    p.MaxFireDelay = 2
                    e.HitPoints, e.MaxHitPoints = 1000, 1000
                end
                if t == 1960 then
                    e:AddEntityFlags(EntityFlag.FLAG_NO_FLASH_ON_DAMAGE)
                end
                if t == 1240 then
                    e.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
                end
                log("enemy_setup", {
                    case = t,
                    seed = e.InitSeed,
                    x = e.Position.X,
                    y = e.Position.Y,
                    hp = e.HitPoints,
                    vulnerable = e:IsVulnerableEnemy(),
                })
            end)
            actor(0, function(p)
                p.Position, p.Velocity = Vector(200, 400), Vector.Zero
            end)
        end
        for _, case in ipairs(cases) do
            if t == case.at - 30 then
                actor(case.slot, function(p)
                    local pool = Game():GetItemPool()
                    local color = case.natural or pool:ForceAddPillEffect(case.effect)
                    if case.natural then
                        case.effect = pool:GetPillEffect(color, p)
                    end
                    assert(
                        pool:GetPillEffect(color, p) == case.effect,
                        "Wrong pill effect selected"
                    )
                    p:SetCard(0, 0)
                    p:SetPill(0, color | (case.horse and PillColor.PILL_GIANT_FLAG or 0))
                    log("setup", {
                        slot = case.slot,
                        effect = case.effect,
                        color = p:GetPill(0),
                        mask = case.mask,
                    })
                end)
            end
        end
    end, collect, restore, present, beginFloor)
end
