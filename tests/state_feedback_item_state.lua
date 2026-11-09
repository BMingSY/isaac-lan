-- November feedback: real EID renders, fed Blood Puppy, Beelzebub and a passed jar.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, route = config.host, config.route
local frame, gate = _IsaacLanFrame, native.net_gate
local phases = native.net_phases()
local renders, linked, chosen, finished, tick = 0, false, false, false, 0
local itemHeld = false
local checks, inventories, puppyIds = {}, {}, {}
local failure, hostAlternative, jarSeed
local suspectFlashes, lastCombatEvent, combatFacts = 0, 0, {}
local friendlyIds, confirmedFlashes = {}, {}
local owner = { Name = "November item feedback regression" }
local function report(message)
    Isaac.DebugString("LAN_NETWORK SIDE " .. route .. " tick=" .. tick .. " " .. message)
end
local function checked(name)
    checks[name] = (checks[name] or 0) + 1
    if checks[name] == 1 then
        report(name)
    end
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end, 1))
end
local function clear(room)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:ToNPC() or e:ToPickup() or e:ToTear() or e:ToProjectile() then
            e:Remove()
        end
    end
    room:SetClear(true)
end
local function inventory(p)
    local result = {}
    for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
        local item = Isaac.GetItemConfig():GetCollectible(id)
        if item and item.Type ~= ItemType.ITEM_ACTIVE then
            local count = p:GetCollectibleNum(id, true)
            if count > 0 then
                result[#result + 1] = id .. ":" .. count
            end
        end
    end
    return table.concat(result, ",")
end
local function puppy()
    local body, familiar, count = nil, nil, 0
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type == EntityType.ENTITY_BLOOD_PUPPY then
            body, count = e, count + 1
        elseif
            e.Type == EntityType.ENTITY_FAMILIAR and e.Variant == FamiliarVariant.BLOOD_PUPPY
        then
            familiar = e
        end
    end
    assert(count <= 1, "Blood Puppy duplicated")
    return body, familiar
end
local addDescription, eidOptions
if route == "feedback-eid" then
    assert(EID, "Run this scenario with the unchanged EID Mod")
    addDescription, eidOptions = EID.addDescriptionToPrint, {}
    for name, value in pairs({
        DisableOnCurse = true,
        DisplayAllNearby = false,
        MaxDistance = 5,
        DisableStartOfRunWarnings = true,
    }) do
        eidOptions[name] = EID.Config[name]
        EID.Config[name] = value
    end
    EID.addDescriptionToPrint = function(self, desc, ...)
        if
            (tick >= 120 and tick < 500 or tick >= 580 and tick < 750)
            and desc.Entity
            and desc.Entity.Type == EntityType.ENTITY_PICKUP
        then
            local ok, message = pcall(function()
                local expected = host and CollectibleType.COLLECTIBLE_SAD_ONION
                    or CollectibleType.COLLECTIBLE_INNER_EYE
                assert(
                    desc.Entity.SubType == expected,
                    "EID described a pickup in the other player's room"
                )
                local localEntity = false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    localEntity = localEntity or GetPtrHash(e) == GetPtrHash(desc.Entity)
                end
                assert(localEntity, "EID description escaped the local render room")
                if tick >= 380 and tick < 500 then
                    assert(
                        not desc.Name and (desc.Description or "") == "",
                        "EID revealed a hidden collectible"
                    )
                    checked("hidden-description")
                elseif tick < 330 or tick >= 580 then
                    assert(desc.Name and desc.Name ~= "", "EID lost the visible local description")
                    checked(
                        tick < 250 and "split-description"
                            or tick < 330 and "reordered-description"
                            or "revisited-description"
                    )
                end
            end)
            if not ok then
                failure = message
            end
        end
        return addDescription(self, desc, ...)
    end
end
local combatPresent = native.combat_present
if route == "feedback-flies" then
    native.combat_present = function(sprite)
        if sprite == nil then
            return combatPresent()
        end
        if sprite and tick >= 150 and tick <= 750 then
            local target = sprite:GetFilename()
            actor(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToNPC() and e:GetSprite():GetFilename() == target then
                        if e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
                            local id = e:GetData().__isaac_lan_replica
                            if (confirmedFlashes[id] or 0) >= Isaac.GetTime() then
                                checked("friendly-confirmed-presentation")
                            else
                                suspectFlashes = suspectFlashes + 1
                                if suspectFlashes <= 3 then
                                    report("unconfirmed-friendly-flash type=" .. e.Type)
                                end
                            end
                        else
                            checked("hostile-hit-presentation")
                        end
                    end
                end
            end)
        end
        return combatPresent(sprite)
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, e, amount, flags, source)
    if e:ToPlayer() then
        return false
    end
    if route == "feedback-flies" then
        assert(host, "Replica applied authoritative enemy damage")
        if e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            report(
                "friendly-damage source="
                    .. source.Type
                    .. ":"
                    .. source.Variant
                    .. " flags="
                    .. flags
                    .. " amount="
                    .. amount
            )
            assert(source.Type ~= EntityType.ENTITY_TEAR, "Player tear damaged a converted fly")
            checked("friendly-native-damage")
        else
            checked("hostile-native-damage")
        end
    end
end)
local function inspect(t)
    tick = t
    if route == "feedback-puppy" then
        local small = t >= 930 and t < 980 or t >= 1030 and t < 1080 or t >= 1130 and t < 1180
        local big = t >= 2130 and t < 2180 or t >= 2230 and t < 2280 or t >= 2330 and t < 2380
        if small or big or t >= 2650 and t < 2750 then
            actor(1, function()
                local body, familiar = puppy()
                assert(body and familiar, "Angry Blood Puppy was lost after travel")
                assert(body.Variant == (small and 0 or 1), "Blood Puppy lost its fed growth stage")
                assert(
                    body.Parent and GetPtrHash(body.Parent) == GetPtrHash(familiar),
                    "Angry body lost its familiar owner"
                )
                assert(
                    familiar:ToFamiliar().Player.ControllerIndex == 2,
                    "Blood Puppy changed owner"
                )
                if t >= 2500 then
                    assert(
                        Game():GetLevel():GetStage() == 2,
                        "Blood Puppy floor transition did not complete"
                    )
                end
                if t < 2500 then
                    local form = small and "small" or "big"
                    -- Travel changes the room-local Index and combat/sync ID.
                    -- Check the native seed and authority object instead.
                    puppyIds[form] = puppyIds[form]
                        or { seed = body.InitSeed, pointer = GetPtrHash(body) }
                    assert(
                        body.InitSeed == puppyIds[form].seed
                            and (not host or GetPtrHash(body) == puppyIds[form].pointer),
                        "Room travel replaced the fed Blood Puppy"
                    )
                end
                checked(
                    t >= 2500 and "puppy-floor"
                        or small and "puppy-small-" .. math.floor(t / 100)
                        or "puppy-big-" .. math.floor(t / 100)
                )
            end)
        end
    elseif route == "feedback-flies" and t >= 170 and t <= 750 then
        actor(1, function(p)
            assert(
                not host or p:HasPlayerForm(PlayerForm.PLAYERFORM_LORD_OF_THE_FLIES),
                "Beelzebub transformation missing"
            )
            local count = 0
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:ToNPC() and e.Type ~= EntityType.ENTITY_GAPER then
                    assert(
                        e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY),
                        "Native Beelzebub did not convert the fly"
                    )
                    count = count + 1
                end
            end
            assert(count == 1, "Converted fly disappeared")
            checked("friendly-fly")
        end)
    elseif route == "feedback-esau" then
        if t >= 90 and t <= 120 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    inventories[slot] = inventory(p)
                end)
            end
            checked("initial-inventories")
        elseif t >= 220 and t <= 260 then
            actor(0, function(p)
                hostAlternative = inventory(p)
                assert(
                    hostAlternative ~= inventories[0],
                    "Host jar did not create its alternative body"
                )
                checked("host-alternative")
            end)
        elseif t >= 620 and t <= 680 or t >= 800 and t <= 860 then
            actor(0, function(p)
                assert(
                    inventory(p) == hostAlternative,
                    "Passing the jar modified the host's current inventory"
                )
            end)
            actor(1, function(p)
                assert(
                    inventory(p) == inventories[t < 700 and 0 or 1],
                    "Passed jar did not exchange the stored body and restore the guest"
                )
                checked(t < 700 and "passed-backup-body" or "guest-body-restored")
            end)
        end
    end
end
local function prepare(t)
    tick = t
    if t == 30 then
        Game():GetLevel():RemoveCurses(Game():GetLevel():GetCurses())
        for slot = 0, 1 do
            actor(slot, function(p, room)
                clear(room)
                p.Position, p.Velocity = Vector(280, 280), Vector.Zero
                p:SetMinDamageCooldown(10000)
                p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                local active = p:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
                if active ~= 0 then
                    p:RemoveCollectible(active)
                end
            end)
        end
        if route == "feedback-eid" or route == "feedback-puppy" or route == "feedback-flies" then
            assert(native.rooms_move(1, 71, 0, -1))
        end
    end
    -- rooms_move queues the transfer. Position after the destination commits,
    -- otherwise its arrival placement overwrites the fixture's center point.
    if t == 50 and route ~= "feedback-esau" then
        actor(1, function(p, room)
            clear(room)
            p.Position, p.Velocity = Vector(280, 280), Vector.Zero
        end)
    end
    if route == "feedback-eid" then
        if t == 60 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        slot == 0 and CollectibleType.COLLECTIBLE_SAD_ONION
                            or CollectibleType.COLLECTIBLE_INNER_EYE,
                        p.Position + Vector(slot == 0 and 60 or 40, 0),
                        Vector.Zero,
                        nil
                    )
                end)
            end
        elseif t == 250 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:ToPickup() then
                            e.Position = p.Position + Vector(slot == 0 and 40 or 60, 0)
                        end
                    end
                end)
            end
        elseif t == 350 then
            Game():GetLevel():AddCurse(LevelCurse.CURSE_OF_BLIND, false)
        elseif t == 520 then
            Game():GetLevel():RemoveCurses(LevelCurse.CURSE_OF_BLIND)
            assert(native.rooms_move(1, 84, 0, -1))
        elseif t == 540 then
            assert(native.rooms_move(1, 71, 0, -1))
        elseif t == 545 then
            actor(1, function(p)
                p.Position, p.Velocity = Vector(280, 280), Vector.Zero
            end)
        end
    elseif route == "feedback-puppy" then
        if t == 60 then
            actor(1, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_BLOOD_PUPPY, 0, false)
            end)
        end
        if t >= 90 and t < 900 or t >= 1200 and t < 2100 then
            actor(1, function()
                local body, familiar = puppy()
                local fed = t < 900 and body or body and body.Variant == 1
                if not fed and t % 6 == 0 then
                    local source = assert(body or familiar, "Blood Puppy did not spawn")
                    local food = Isaac.Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        0,
                        source.Position,
                        Vector.Zero,
                        nil
                    )
                    food.HitPoints, food.MaxHitPoints = 1, 1
                    food:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                end
                if t % 150 == 0 then
                    report("feeding variant=" .. (body and body.Variant or -1))
                end
            end)
        end
        if t == 1000 or t == 2200 then
            assert(native.rooms_move(1, 84, 0, -1))
        elseif t == 1100 or t == 2300 then
            assert(native.rooms_move(1, 71, 0, -1))
        elseif t == 2500 then
            Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
        end
        if t == 1005 or t == 1105 or t == 2205 or t == 2305 then
            actor(1, function(p)
                p.Position, p.Velocity = Vector(280, 280), Vector.Zero
            end)
        end
    elseif route == "feedback-flies" then
        if t == 60 then
            actor(1, function(p)
                for _, id in ipairs({
                    CollectibleType.COLLECTIBLE_HALO_OF_FLIES,
                    CollectibleType.COLLECTIBLE_DISTANT_ADMIRATION,
                    CollectibleType.COLLECTIBLE_FOREVER_ALONE,
                }) do
                    p:AddCollectible(id, 0, true)
                end
            end)
        elseif t == 120 then
            actor(1, function(p, room)
                assert(p:HasPlayerForm(PlayerForm.PLAYERFORM_LORD_OF_THE_FLIES))
                for index = 0, room:GetGridSize() - 1 do
                    local grid = room:GetGridEntity(index)
                    if
                        grid
                        and grid:GetType() ~= GridEntityType.GRID_WALL
                        and grid:GetType() ~= GridEntityType.GRID_DOOR
                        and room:GetGridCollision(index) ~= GridCollisionClass.COLLISION_WALL
                    then
                        room:RemoveGridEntity(index, 0, false)
                    end
                end
                p.Position, p.Velocity = Vector(240, 280), Vector.Zero
                -- Suckers remain friendly NPCs after the native transformation;
                -- weak attack flies instead become blue-fly familiars.
                for _, type in ipairs({ EntityType.ENTITY_SUCKER, EntityType.ENTITY_GAPER }) do
                    local e = Isaac.Spawn(
                        type,
                        0,
                        0,
                        Vector(type == EntityType.ENTITY_GAPER and 410 or 310, 280),
                        Vector.Zero,
                        nil
                    )
                    e.HitPoints, e.MaxHitPoints = 1000, 1000
                    if type == EntityType.ENTITY_GAPER then
                        e:AddFreeze(EntityRef(p), 1000)
                    end
                end
            end)
        elseif t == 150 then
            actor(1, function()
                local selected
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToNPC() and e.Type ~= EntityType.ENTITY_GAPER then
                        report(
                            "native-fly type="
                                .. e.Type
                                .. " friendly="
                                .. tostring(e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY))
                        )
                        if
                            not selected
                            and e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
                            and e:IsVulnerableEnemy()
                        then
                            selected = e
                        else
                            e:Remove()
                        end
                    elseif e.Type == EntityType.ENTITY_FAMILIAR then
                        -- Retain the transformation items but remove orbitals
                        -- so only the player's ordinary tears reach the lane.
                        e:Remove()
                    end
                end
                assert(selected, "Native Beelzebub did not leave a vulnerable friendly fly")
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == EntityType.ENTITY_GAPER then
                        assert(
                            selected:GetSprite():GetFilename() ~= e:GetSprite():GetFilename(),
                            "The presentation observer requires distinct NPC sprite resources"
                        )
                        report(
                            "sprite-pair friendly="
                                .. selected:GetSprite():GetFilename()
                                .. " hostile="
                                .. e:GetSprite():GetFilename()
                        )
                    end
                end
                report("selected-friendly-fly type=" .. selected.Type)
            end)
        end
        if t >= 150 and t < 780 then
            actor(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToNPC() and e.Type ~= EntityType.ENTITY_GAPER then
                        e.Position, e.Velocity = Vector(310, 280), Vector.Zero
                    elseif e.Type == EntityType.ENTITY_GAPER then
                        e.Position, e.Velocity = Vector(410, 280), Vector.Zero
                    end
                end
            end)
        end
    elseif route == "feedback-esau" then
        local esau = CollectibleType.COLLECTIBLE_ESAU_JR
        if t == 60 then
            actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION, 0, false)
                p:AddCollectible(esau, 1, false)
                p.Position = Vector(280, 280)
            end)
            actor(1, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_PENTAGRAM, 0, false)
                p.Position = Vector(180, 400)
            end)
        elseif t == 140 then
            actor(0, function(p)
                p:FullCharge(ActiveSlot.SLOT_PRIMARY)
            end)
        elseif t == 300 then
            actor(0, function(p)
                local pickup = Isaac.Spawn(
                    EntityType.ENTITY_PICKUP,
                    PickupVariant.PICKUP_COLLECTIBLE,
                    CollectibleType.COLLECTIBLE_SUPLEX,
                    p.Position,
                    Vector.Zero,
                    nil
                ):ToPickup()
                pickup.Wait = 0
            end)
        elseif t == 380 then
            actor(0, function(p)
                assert(
                    p:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == CollectibleType.COLLECTIBLE_SUPLEX,
                    "Host did not exchange the used jar at a pedestal"
                )
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToPickup() and e.SubType == esau then
                        jarSeed = e.InitSeed
                        report("dropped-jar seed=" .. jarSeed)
                    end
                end
                assert(jarSeed, "Used jar pedestal missing")
                p.Position, p.Velocity = Vector(180, 400), Vector.Zero
            end)
        elseif t == 450 then
            actor(1, function(p)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToPickup() and e.InitSeed == jarSeed then
                        p.Position, p.Velocity = e.Position, Vector.Zero
                    end
                end
            end)
        elseif t == 540 or t == 720 then
            actor(1, function(p)
                assert(
                    p:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == esau,
                    "Guest did not pick up the same used jar"
                )
                p:FullCharge(ActiveSlot.SLOT_PRIMARY)
            end)
        end
        if t >= 310 and t <= 360 or t >= 450 and t <= 500 then
            local slot = t < 400 and 0 or 1
            local wanted = slot == 0 and CollectibleType.COLLECTIBLE_SUPLEX or esau
            actor(slot, function(p)
                if p:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == wanted then
                    p.Position, p.Velocity = Vector(180 + slot * 160, 400), Vector.Zero
                    return
                end
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if
                        e:ToPickup()
                        and e.SubType == wanted
                        and (slot == 0 or e.InitSeed == jarSeed)
                    then
                        p.Position, p.Velocity = e.Position, Vector.Zero
                    end
                end
            end)
        end
    end
end
local required = {
    ["feedback-eid"] = {
        "split-description",
        "reordered-description",
        "hidden-description",
        "revisited-description",
    },
    ["feedback-puppy"] = {
        "puppy-small-9",
        "puppy-small-10",
        "puppy-small-11",
        "puppy-big-21",
        "puppy-big-22",
        "puppy-big-23",
        "puppy-floor",
    },
    ["feedback-flies"] = {
        "friendly-fly",
        "friendly-excluded",
        host and "hostile-native-damage" or "hostile-hit-presentation",
    },
    ["feedback-esau"] = {
        "initial-inventories",
        "host-alternative",
        "passed-backup-body",
        "guest-body-restored",
    },
}
local function inspectCombat(bytes, stable, t)
    if route ~= "feedback-flies" or t < 150 or t > 750 then
        return
    end
    local fields = _IsaacLanModules["sync/fields"]
    local E = fields.entity
    local value =
        _IsaacLanModules["sync/world_schema"].unpack(_IsaacLanState.decode(bytes, stable), t)
    for _, e in ipairs(value.room[fields.room.entities]) do
        if e[E.type] == EntityType.ENTITY_SUCKER then
            assert(e[E.combat] == fields.combat.none, "Friendly fly permits speculative hits")
            friendlyIds[e[E.id]] = true
            checked("friendly-excluded")
        end
        if e[E.type] == EntityType.ENTITY_SUCKER or e[E.type] == EntityType.ENTITY_GAPER then
            local fact = "type=" .. e[E.type] .. " id=" .. e[E.id] .. " combat=" .. e[E.combat]
            if combatFacts[e[E.id]] ~= fact then
                combatFacts[e[E.id]] = fact
                report("combat-fact " .. fact)
            end
        end
    end
    for _, event in ipairs(_IsaacLanModules["sync/combat_events"](value.combat)) do
        if event.serial > lastCombatEvent then
            lastCombatEvent = event.serial
            -- Charmed NPCs can legitimately hurt each other. Match those
            -- flashes to native confirmations instead of suppressing them.
            if friendlyIds[event.target] and event.accepted and event.duration > 0 then
                confirmedFlashes[event.target] = Isaac.GetTime()
                    + math.max(0, event.duration - (t - event.tick) / 30) * 1000
            end
            if lastCombatEvent <= 10 then
                report(
                    "combat-event target="
                        .. event.target
                        .. " accepted="
                        .. tostring(event.accepted)
                        .. " duration="
                        .. event.duration
                )
            end
        end
    end
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
    local status = frame()
    assert(status.phase ~= phases.failed and status.phase ~= phases.recovering, status.error)
    assert(not failure, failure)
    if status.phase == phases.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == phases.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "1XJTX49A:0:0:0:0:0")
    end
    tick = status.verified
    native.test_gamepad(
        route == "feedback-flies" and not host and tick >= 180 and tick < 750 and 0x2000 or 0
    )
    if status.prepared and tick >= (route == "feedback-puppy" and 2800 or 900) and not finished then
        assert(
            suspectFlashes == 0,
            "Friendly fly flashed without native damage: " .. suspectFlashes
        )
        for _, name in ipairs(assert(required[route])) do
            assert((checks[name] or 0) >= 5, "Missing repeated native observations: " .. name)
        end
        finished = true
        report("PASS")
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local function controls(...)
        if route ~= "feedback-esau" then
            return capture(...)
        end
        local held = host and tick >= 150 and tick < 155
            or not host and (tick >= 560 and tick < 565 or tick >= 740 and tick < 745)
        local mask = 1 << ButtonAction.ACTION_ITEM
        local triggered = held and not itemHeld and mask or 0
        itemHeld = held
        return _IsaacLanTestInput.buttons(held and mask or 0, triggered)
    end
    return gate(controls, function(t, n, bytes)
        before(t, n, bytes)
        prepare(t)
    end, function(slot, t)
        if slot == 1 then
            inspect(t)
        end
        local bytes, stable = collect(slot, t)
        if slot == 1 then
            inspectCombat(bytes, stable, t)
        end
        return bytes, stable
    end, function(bytes, t, ...)
        local applied = restore(bytes, t, ...)
        if applied ~= false then
            inspect(t)
            local _, _, stable = ...
            inspectCombat(bytes, stable, t)
        end
        return applied
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        native.combat_present = combatPresent
        if addDescription then
            EID.addDescriptionToPrint = addDescription
            for name, value in pairs(eidOptions) do
                EID.Config[name] = value
            end
        end
    end,
}
