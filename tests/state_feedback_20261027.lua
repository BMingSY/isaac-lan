-- Rerolls, familiar UI, captured room returns and delayed boss introductions.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, json = config.host, require("json")
local frame, gate, events = _IsaacLanFrame, native.net_gate, native.presentation_events
local renders, linked, chosen, finished = 0, false, false, false
local tick, boss, bossStart, finishTick = 0, nil, 1950, 2450
local checks, captured, introSeen = {}, {}, false
local function report(kind, value)
    value = value or {}
    value.kind, value.tick, value.host = kind, tick, host
    Isaac.DebugString("LAN_FEEDBACK_OCTOBER " .. json.encode(value))
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end, 1))
end
local function clear(room)
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type ~= EntityType.ENTITY_PLAYER then
            entity:Remove()
        end
    end
    room:SetClear(true)
end
local function returnCheck(name)
    actor(1, function(p)
        assert(native.rooms_positions()["1"].index == 84, name .. ": victim did not return")
        assert(p.Visible and p.ControlsEnabled, name .. ": victim stayed hidden or disabled")
    end)
    checks[name] = true
end
local function spawnHand()
    actor(1, function(p, room)
        clear(room)
        p.Position = Vector(320, 280)
        p.Visible, p.ControlsEnabled = true, true
        local hand = Isaac.Spawn(EntityType.ENTITY_MOMS_HAND, 0, 0, p.Position, Vector.Zero, nil)
            :ToNPC()
        hand.Target = p
    end)
end
local function inspect()
    actor(host and 0 or 1, function(p)
        local pickups, familiars, hands = {}, {}, {}
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if
                e.Type == EntityType.ENTITY_PICKUP
                and e.Variant == PickupVariant.PICKUP_COLLECTIBLE
            then
                pickups[#pickups + 1] = {
                    id = e.SubType,
                    habit = native.sprite_state(e:GetSprite()):find("156", 1, true) ~= nil,
                }
            elseif e.Type == EntityType.ENTITY_FAMILIAR then
                familiars[#familiars + 1] =
                    { variant = e.Variant, cooldown = e:ToFamiliar().FireCooldown }
            elseif e.Type == EntityType.ENTITY_MOMS_HAND then
                hands[#hands + 1] = { state = e:ToNPC().State, anim = e:GetSprite():GetAnimation() }
            end
        end
        if tick >= 150 and tick < 220 then
            assert(#pickups == 3, "Spindown pedestal count changed")
            for _, item in ipairs(pickups) do
                assert(
                    item.id == CollectibleType.COLLECTIBLE_HABIT and item.habit,
                    "Spindown result or sprite differs"
                )
            end
            checks.spindown = true
        end
        if tick >= 360 and tick <= 420 then
            for _, familiar in ipairs(familiars) do
                if familiar.variant == FamiliarVariant.LIL_ABADDON and familiar.cooldown < 10 then
                    checks.familiar = true
                end
            end
        end
        if native.presentation_active() and tick >= bossStart then
            introSeen = true
        end
        report("sample", {
            pickups = pickups,
            familiars = familiars,
            hands = hands,
            positions = native.rooms_positions(),
            visible = p.Visible,
            enabled = p.ControlsEnabled,
            x = p.Position.X,
            y = p.Position.Y,
            intro = native.presentation_active(),
        })
    end)
    if tick >= 1000 and tick < 1080 then
        returnCheck("together")
    end
    if tick >= 1460 and tick < 1500 then
        returnCheck("separate")
    end
    if tick >= 1880 and tick < 1900 then
        returnCheck("origin")
    end
    if tick >= 2380 then
        actor(1, function(p)
            assert(p.ControlsEnabled and p.Position.X > 150, "Guest cannot move after boss intro")
        end)
        if host then
            assert(native.rooms_positions()["1"].updates > 100, "Boss room stayed paused")
        else
            assert(introSeen, "Delayed guest intro was never played")
        end
        checks.boss = true
    end
end
native.presentation_events = function(...)
    local value = events(...)
    -- Drop the first 120 ticks of intro delivery while room views arrive.
    -- The authority must retry after the old 90-tick presentation window.
    if host and tick >= bossStart and tick < bossStart + 120 then
        return ""
    end
    return value
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
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "04QHQ43B:0:0:0:0:0")
    end
    local t, buttons = s.verified, 0
    if not host and t >= 330 and t < 430 then
        buttons = 0x2000
    end
    if not host and t >= 2260 and t < 2340 then
        buttons = 8
    end
    native.test_gamepad(buttons, not host and t >= 120 and t < 126 and 255 or 0)
    if s.prepared and t >= finishTick and not finished then
        for _, name in ipairs({ "spindown", "familiar", "together", "separate", "origin", "boss" }) do
            assert(checks[name], "Unverified feedback scenario: " .. name)
        end
        if host then
            for _, name in ipairs({ "together", "separate", "origin" }) do
                assert(captured[name], "Mom's Hand did not actually grab: " .. name)
            end
        end
        finished = true
        Isaac.DebugString("LAN_NETWORK PASS October feedback regressions")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        tick = t
        if t == 30 then
            actor(0, function(p, room)
                clear(room)
                p.Position = Vector(160, 360)
                p:SetMinDamageCooldown(10000)
                local rooms = Game():GetLevel():GetRooms()
                for i = 0, rooms.Size - 1 do
                    local d = rooms:Get(i)
                    if d.Data.Type == RoomType.ROOM_BOSS then
                        boss = d.SafeGridIndex
                    end
                end
            end)
            actor(1, function(p)
                p.Position = Vector(400, 360)
                p:AddCollectible(CollectibleType.COLLECTIBLE_SPINDOWN_DICE, 6, false)
                for i = 1, 3 do
                    local pickup = Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        CollectibleType.COLLECTIBLE_BLOODY_LUST,
                        Vector(200 + i * 80, 200),
                        Vector.Zero,
                        nil
                    ):ToPickup()
                    if i > 1 then
                        pickup.Price, pickup.AutoUpdatePrice = PickupPrice.PRICE_SPIKES, false
                    end
                    pickup.Touched = i == 3
                end
            end)
        elseif t == 240 then
            actor(1, function(p, room)
                clear(room)
                p:AddCollectible(CollectibleType.COLLECTIBLE_LIL_ABADDON, 0, false)
                p:AddCollectible(CollectibleType.COLLECTIBLE_TWISTED_PAIR, 0, false)
                p:AddCollectible(CollectibleType.COLLECTIBLE_NEPTUNUS, 0, false)
            end)
            Options.ChargeBars = true
        elseif t == 450 then
            actor(1, function(p)
                p.Position = Vector(500, 340)
            end)
        elseif t == 550 then
            assert(native.rooms_move(0, 71, 0, -1))
            assert(native.rooms_move(1, 71, 0, -1))
        elseif t == 580 then
            actor(0, function(p, room)
                clear(room)
                p.Position = Vector(100, 380)
            end)
            actor(1, function(p)
                p:RemoveCollectible(CollectibleType.COLLECTIBLE_LIL_ABADDON)
                p:RemoveCollectible(CollectibleType.COLLECTIBLE_TWISTED_PAIR)
            end)
            spawnHand()
        elseif t == 1100 then
            assert(native.rooms_move(1, 71, 0, -1))
        elseif t == 1120 then
            spawnHand()
        elseif t == 1500 then
            assert(native.rooms_move(0, 71, 0, -1))
        elseif t == 1520 then
            spawnHand()
        elseif t == 1900 then
            actor(0, function(_, room)
                clear(room)
            end)
            actor(1, function(_, room)
                clear(room)
            end)
            assert(native.rooms_move(0, 84, 0, -1))
        elseif t == bossStart then
            assert(boss)
            assert(native.rooms_move(1, boss, 0, -1))
            assert(native.rooms_move(0, boss, 0, -1))
        end
        local phase = t >= 580 and t < 1000 and "together"
            or t >= 1120 and t < 1460 and "separate"
            or t >= 1520 and t < 1880 and "origin"
        if phase then
            actor(1, function(p)
                if not p.Visible and not p.ControlsEnabled then
                    captured[phase] = true
                end
            end)
        end
    end, function(slot, t)
        tick = t
        if slot == 1 and t % 20 == 0 then
            inspect()
        end
        return collect(slot, t)
    end, function(bytes, t, ...)
        local result = restore(bytes, t, ...)
        tick = t
        Options.ChargeBars = true
        if result ~= false then
            inspect()
        end
        return result
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        native.presentation_events = events
    end,
}
