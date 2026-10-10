-- One ordinary-sandbox pair: pickup/pill text, shared resources and Ascent/Home.
local assert = assert
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame = _IsaacLanFrame
local linked, chosen, done, renders = false, false, false, 0
local phase, expectedTexts, phaseTick = 0, 0, 0
local observations, floorEvents, snapshots = {}, 0, 0
local other, pillColor, route, stageAt, waitTick, switched, ascent, bedroom, living
local resourceExpected, resourceChecks = nil, 0
local cardPress = false
local contacts = {}
local function report(s)
    Isaac.DebugString("LAN_NETWORK " .. s)
end
-- Exercise the real receiver with a Chinese host fallback and English fonts.
-- The native lookup keys are captured by gameplay, rather than invented here.
local presentationEvents = native.item_presentation_events
local chinese = {
    THE_FOOL_NAME = "0 - 愚者",
    THE_FOOL_DESCRIPTION = "冒险由此开始",
    THE_MAGICIAN_NAME = "I - 魔术师",
    THE_MAGICIAN_DESCRIPTION = "愿你百发百中",
    SPEED_UP_NAME = "速度提升",
    BAD_GAS_NAME = "臭屁",
    BALLS_OF_STEEL_NAME = "钢铁蛋蛋",
}
native.item_presentation_events = function(value)
    local bytes = presentationEvents(value)
    if not host or type(value) ~= "number" or value ~= 1 or #bytes == 0 then
        return bytes
    end
    local count, pos = string.unpack("B", bytes)
    local parts = { string.pack("B", count) }
    for _ = 1, count do
        local start = pos
        local serial, tick, epoch, owner, role, kind
        serial, tick, epoch, owner, role, kind, pos = string.unpack(">I4I4I4BBB", bytes, pos)
        if kind == 3 or kind == 4 then
            local title, subtitle
            title, subtitle, pos = string.unpack(">s2s2", bytes, pos)
            if kind == 4 then
                local a, b, c, d
                a, b, c, d, pos = string.unpack(">s2s2s2s2", bytes, pos)
                title, subtitle = chinese[b] or title, chinese[d] or subtitle
                parts[#parts + 1] = string.pack(
                    ">I4I4I4BBBs2s2s2s2s2s2",
                    serial,
                    tick,
                    epoch,
                    owner,
                    role,
                    kind,
                    title,
                    subtitle,
                    a,
                    b,
                    c,
                    d
                )
            else
                parts[#parts + 1] = bytes:sub(start, pos - 1)
            end
        else
            pos = pos + (kind == 1 and 9 or 8)
            parts[#parts + 1] = bytes:sub(start, pos - 1)
        end
    end
    return table.concat(parts)
end
local seenText = {}
local function inspectText(slot)
    local bytes = native.item_presentation_events(slot)
    if #bytes == 0 then
        return
    end
    local count, pos = string.unpack("B", bytes)
    for _ = 1, count do
        local serial, tick, epoch, owner, role, kind
        serial, tick, epoch, owner, role, kind, pos = string.unpack(">I4I4I4BBB", bytes, pos)
        if kind == 3 or kind == 4 then
            local title, subtitle
            title, subtitle, pos = string.unpack(">s2s2", bytes, pos)
            local keys = ""
            if kind == 4 then
                local a, b, c, d
                a, b, c, d, pos = string.unpack(">s2s2s2s2", bytes, pos)
                keys = " keys=" .. a .. "/" .. b .. " " .. c .. "/" .. d
            end
            if not seenText[serial] then
                seenText[serial] = true
                report(
                    "TEXT serial="
                        .. serial
                        .. " title="
                        .. title
                        .. " subtitle="
                        .. subtitle
                        .. keys
                )
            end
        elseif kind == 1 then
            pos = pos + 9
        else
            pos = pos + 8
        end
    end
end
local function actor(slot, call)
    assert(native.rooms_with_player(slot, function()
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            if p.ControllerIndex == slot + 1 then
                call(p)
                return
            end
        end
        error("Missing controller " .. slot)
    end, 1))
end
local function clear()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:IsActiveEnemy(false) then
            e:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function protect(p)
    p:SetMinDamageCooldown(10000)
    p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
end
local function spawn(slot, variant, subtype)
    actor(slot, function(p)
        protect(p)
        local pickup = Isaac.Spawn(5, variant, subtype, p.Position, Vector.Zero, nil):ToPickup()
        pickup.Wait = 0
        contacts[#contacts + 1] = { slot, EntityPtr(pickup) }
    end)
end
local function mark(p, items)
    phase, expectedTexts, phaseTick = p, items or expectedTexts, native.api_info().tick
    report("PHASE " .. phase .. " tick=" .. phaseTick)
end
function _IsaacLanFrame()
    renders = renders + 1
    if EID and EID.Config then
        EID.Config.DisableStartOfRunWarnings = true
    end
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    local t = s.verified
    cardPress = not host and (t >= 210 and t < 216 or t >= 510 and t < 516)
    native.test_gamepad(cardPress and 512 or 0)
    if s.prepared and phase == 220 and t - phaseTick > 80 and not done then
        done = true
        if not host then
            for _, p in ipairs({ 1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 201, 210, 220 }) do
                assert((observations[p] or 0) >= 2, "Unobserved phase " .. p)
            end
            assert(floorEvents >= 8 and resourceChecks > 50 and snapshots > 300)
        end
        report(
            "COUNTS floors="
                .. floorEvents
                .. " snapshots="
                .. snapshots
                .. " resources="
                .. resourceChecks
        )
        report("PASS card pill text shared resources Ascent Home Dogma")
    end
    return s
end
local function allResources()
    local heads = native.rooms_heads()
    local values = {}
    for slot = 0, 1 do
        local p = Isaac.GetPlayer(assert(heads[tostring(slot)]))
        values[slot + 1] = { p:GetNumCoins(), p:GetNumBombs(), p:GetNumKeys() }
    end
    for i = 1, 3 do
        assert(values[1][i] == values[2][i], "Split resource pool " .. i)
    end
    return values[1]
end
local function transition(same, animation)
    local head = assert(native.rooms_heads()["1"])
    Game():StartStageTransition(same, animation or 0, Isaac.GetPlayer(head))
    waitTick = native.api_info().tick
end
local function move(slot, index)
    assert(native.rooms_move(slot, index, 0, -1))
    actor(slot, function(p)
        clear()
        protect(p)
        p.Position = Game():GetRoom():GetCenterPos()
    end)
end
local function advance(t)
    if not native.rooms_ready() then
        return
    end
    local level = Game():GetLevel()
    local s, ty = level:GetStage(), level:GetStageType()
    if route == "down" and t - waitTick > 130 and Game():GetRoom():GetFrameCount() > 45 then
        if s < 6 then
            report("DESCEND stage=" .. s .. " type=" .. ty)
            transition(false)
        elseif not switched then
            switched = true
            report("SWITCH_MAUSOLEUM assert=" .. type(_G.assert))
            Game():SetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH_INIT, true)
            level:SetStage(6, 4)
            report("AFTER_SET_STAGE assert=" .. type(_G.assert))
            transition(true)
        else
            route = "note"
            local boss
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                if d.Data.Type == RoomType.ROOM_BOSS then
                    boss = d.SafeGridIndex
                end
            end
            assert(boss, "Missing Mausoleum boss room")
            move(1, boss)
            waitTick = t
        end
    elseif route == "note" and t - waitTick > 110 then
        actor(1, function(p)
            local note
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == 5 and entity.Variant == 100 and entity.SubType == 668 then
                    note = entity
                end
            end
            assert(note, "Ascent initialization did not generate Dad's Note")
            contacts[#contacts + 1] = { 1, EntityPtr(note) }
            p.Position, p.Velocity = note.Position, Vector.Zero
        end)
        route, waitTick = "note-wait", t
        report("NATIVE_DADS_NOTE")
    elseif
        route == "note-wait"
        and Game():GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH)
        and t - waitTick > 150
    then
        route, waitTick, stageAt = "ascent-enter", t, s
        local rooms = {}
        for i = 0, level:GetRooms().Size - 1 do
            local d = level:GetRooms():Get(i)
            if
                d.SafeGridIndex ~= level:GetCurrentRoomIndex()
                and d.Data.Type == RoomType.ROOM_DEFAULT
            then
                rooms[#rooms + 1] = d.SafeGridIndex
            end
        end
        assert(#rooms > 0, "No first Ascent room")
        move(1, rooms[1])
        mark(201)
        report("ASCENT_FIRST_ROOM stage=" .. s .. " type=" .. ty)
    elseif route == "ascent-enter" and t - waitTick > 110 then
        route = "ascent-wait"
        transition(false, 6)
    elseif route == "ascent-wait" and t - waitTick > 130 then
        if s == 13 then
            route, waitTick = "home-enter", t
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                report(
                    "HOME_ROOM index="
                        .. d.SafeGridIndex
                        .. " type="
                        .. d.Data.Type
                        .. " variant="
                        .. d.Data.Variant
                        .. " name="
                        .. (d.Data.Name or "")
                )
                if d.Data.Type == RoomType.ROOM_DEFAULT and d.Data.Variant == 3 then
                    bedroom = d.SafeGridIndex
                end
                if d.Data.Type == RoomType.ROOM_DEFAULT and d.Data.Variant == 4 then
                    living = d.SafeGridIndex
                end
            end
            assert(bedroom and living, "Missing Home bedroom/TV room")
            move(1, bedroom)
        else
            assert(s <= stageAt, "Ascent advanced downwards")
            stageAt = s
            report("ASCENT_FLOOR stage=" .. s .. " type=" .. ty)
            route, waitTick = "ascent-enter", t
            local nextRoom
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                if
                    d.SafeGridIndex ~= level:GetCurrentRoomIndex()
                    and d.Data.Type == RoomType.ROOM_DEFAULT
                then
                    nextRoom = d.SafeGridIndex
                    break
                end
            end
            if nextRoom then
                move(1, nextRoom)
            end
        end
    elseif route == "home-enter" and t - waitTick > 110 then
        actor(1, function(p)
            local bed
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == 5 and e.Variant == PickupVariant.PICKUP_BED then
                    bed = e
                    report("BED subtype=" .. e.SubType)
                end
            end
            assert(bed, "Missing native Home bed")
            p.Position = bed.Position
            p.Velocity = Vector.Zero
            protect(p)
        end)
        route, waitTick = "sleep", t
        report("NATIVE_HOME_SLEEP guest")
    elseif route == "sleep" and ty == 1 then
        mark(210)
        route, waitTick = "night", t
        report("HOME_NIGHT")
    elseif route == "night" and t - waitTick > 180 then
        assert(native.rooms_move(1, living, 0, -1))
        route, waitTick = "tv", t
    elseif route == "tv" then
        local found = false
        actor(1, function(p)
            protect(p)
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == EntityType.ENTITY_DOGMA then
                    found = true
                end
            end
            if t - waitTick > 100 then
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == 960 and e.Variant == 4 then
                        p.Position = e.Position + Vector(0, 36)
                    end
                end
                p.Velocity = Vector.Zero
            end
        end)
        if found then
            mark(220)
            route, waitTick = "complete", t
            report("NATIVE_DOGMA_SPAWN")
        end
    end
    if route ~= "complete" then
        assert(t - waitTick < 650, "Route stalled: " .. route .. " stage=" .. s .. " type=" .. ty)
    end
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, b)
            before(t, n, b)
            if t == 30 then
                for i = 0, 1 do
                    actor(i, function(p)
                        clear()
                        protect(p)
                        p.Position = Vector(180 + 150 * i, 220)
                    end)
                end
                report("VISUAL_READY")
            elseif t == 60 then
                spawn(1, PickupVariant.PICKUP_TAROTCARD, Card.CARD_FOOL)
                mark(1, 1)
            elseif t == 185 then
                actor(1, function(p)
                    local pool = Game():GetItemPool()
                    for c = 1, 13 do
                        local effect = pool:GetPillEffect(c, p)
                        if
                            effect == PillEffect.PILLEFFECT_BAD_GAS
                            or effect == PillEffect.PILLEFFECT_BALLS_OF_STEEL
                            or effect == PillEffect.PILLEFFECT_SPEED_UP
                        then
                            pillColor = c
                            break
                        end
                    end
                    assert(pillColor, "No harmless pill fixture")
                    pool:IdentifyPill(pillColor)
                    p:SetPill(0, pillColor)
                    report(
                        "PILL effect=" .. pool:GetPillEffect(pillColor, p) .. " color=" .. pillColor
                    )
                end)
            elseif t == 210 then
                mark(2, 2)
            elseif t == 350 then
                actor(1, function(p)
                    p:SetCard(0, 0)
                    p:SetPill(0, 0)
                end)
                spawn(1, PickupVariant.PICKUP_TAROTCARD, Card.CARD_MAGICIAN)
                mark(3, 3)
            elseif t == 485 then
                actor(1, function(p)
                    p:SetPill(0, pillColor | 2048)
                end)
            elseif t == 510 then
                mark(4, 4)
            elseif t == 650 then
                spawn(0, PickupVariant.PICKUP_TAROTCARD, Card.CARD_FOOL)
                mark(5, 4)
            elseif t == 800 then
                local level = Game():GetLevel()
                for i = 0, level:GetRooms().Size - 1 do
                    local d = level:GetRooms():Get(i)
                    if d.Data.Type == 1 and d.SafeGridIndex ~= level:GetCurrentRoomIndex() then
                        other = d.SafeGridIndex
                        break
                    end
                end
                assert(other)
                move(1, other)
            elseif t == 850 then
                actor(0, function(p)
                    p:AddCoins(20 - p:GetNumCoins())
                    p:AddBombs(4 - p:GetNumBombs())
                    p:AddKeys(3 - p:GetNumKeys())
                    p:AddHearts(-1)
                end)
                resourceExpected = { 20, 4, 3 }
                mark(10)
            elseif t == 930 then
                spawn(1, PickupVariant.PICKUP_COIN, 2)
                resourceExpected = { 25, 4, 3 }
                mark(11)
            elseif t == 1020 then
                actor(1, function(p)
                    p:AddCoins(-7)
                    p:AddBombs(-1)
                    p:AddKeys(-1)
                end)
                resourceExpected = { 18, 3, 2 }
                mark(12)
            elseif t == 1110 then
                spawn(0, PickupVariant.PICKUP_BOMB, 1)
                spawn(1, PickupVariant.PICKUP_KEY, 1)
                resourceExpected = { 18, 4, 3 }
                mark(13)
            elseif t == 1210 then
                actor(0, function(p)
                    p:AddCollectible(CollectibleType.COLLECTIBLE_DEEP_POCKETS)
                end)
                actor(1, function(p)
                    p:AddCoins(200)
                end)
                resourceExpected = { 218, 4, 3 }
                mark(14)
            elseif t == 1330 then
                route, waitTick = "down", t
                resourceExpected = nil
                mark(100)
            end
            if route then
                advance(t)
            end
            if native.rooms_ready() then
                for i = #contacts, 1, -1 do
                    local contact = contacts[i]
                    local pickup = contact[2].Ref
                    if not pickup or not pickup:Exists() or pickup:IsDead() then
                        table.remove(contacts, i)
                    else
                        actor(contact[1], function(p)
                            p.Position, p.Velocity = pickup.Position, Vector.Zero
                        end)
                    end
                end
            end
        end,
        function(slot, t)
            local bytes = collect(slot, t)
            if slot == 1 then
                inspectText(slot)
            end
            if not bytes then
                return bytes
            end
            return string.pack(">s4", bytes)
                .. _IsaacLanState.encode({
                    phase,
                    expectedTexts,
                    phaseTick,
                    resourceExpected or false,
                })
        end,
        function(bytes, t, ack)
            local body, pos = string.unpack(">s4", bytes)
            local meta = _IsaacLanState.decode(bytes:sub(pos))
            local ok = restore(body, t, ack)
            if ok == false then
                return false
            end
            phase, phaseTick = meta[1], meta[3]
            snapshots = snapshots + 1
            if t - meta[3] > 35 then
                observations[phase] = (observations[phase] or 0) + 1
                if phase >= 1 and phase <= 5 then
                    local p = native.item_presentation_state()
                    assert(
                        p.texts == meta[2],
                        "Pickup/pill text missing or duplicated: phase="
                            .. phase
                            .. " texts="
                            .. p.texts
                            .. " wanted="
                            .. meta[2]
                    )
                end
                if meta[4] then
                    local counts = allResources()
                    for i = 1, 3 do
                        assert(
                            counts[i] == meta[4][i],
                            "Shared count mismatch phase="
                                .. phase
                                .. " resource="
                                .. i
                                .. " value="
                                .. counts[i]
                        )
                    end
                    resourceChecks = resourceChecks + 1
                end
                if phase == 210 then
                    assert(
                        Game():GetLevel():GetStage() == 13 and Game():GetLevel():GetStageType() == 1
                    )
                end
                if phase == 220 then
                    local found = false
                    assert(native.api_with_local_view(function()
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e.Type == 950 then
                                found = true
                            end
                        end
                    end))
                    assert(found, "Guest did not receive native Dogma")
                end
            end
            return ok
        end,
        present,
        function(...)
            floorEvents = floorEvents + 1
            report("FLOOR_EVENT " .. floorEvents)
            return beginFloor(...)
        end
    )
end
