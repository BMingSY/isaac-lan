-- One ordinary-sandbox pair: card/book visuals and local room audio.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local owner = { Name = "Guest presentation and room audio regression" }
local function report(value)
    Isaac.DebugString("LAN_NETWORK " .. value)
end
local linked, chosen, ended, renders = false, false, false, 0
local uses, snapshots, visuals, soundChecks, musicChecks = 0, 0, 0, 0, 0
local origin, other, boss
local checkPresentation
local textEvents, textSerial = {}, 0
local soundBaselines = {}
local soundObserved = {}
local continuousMusic, continuityChecks = nil, 0
local continuityObserved = {}
local function soundCount(id)
    return string.unpack(">I4", native.audio_state(id), 21)
end
local function checkText(bytes)
    if bytes == "" then
        return
    end
    local count, pos = string.unpack(">I1", bytes)
    for _ = 1, count do
        local serial, _, _, _, _, kind
        serial, _, _, _, _, kind, pos = string.unpack(">I4I4I4I1I1I1", bytes, pos)
        if kind == 3 or kind == 4 then
            local title, subtitle
            title, subtitle, pos = string.unpack(">s2s2", bytes, pos)
            if kind == 4 then
                for _ = 1, 4 do
                    local ignored
                    ignored, pos = string.unpack(">s2", bytes, pos)
                end
            end
            if serial > textSerial then
                textSerial = serial
                textEvents[title] = true
                report("TEXT title=" .. title .. " subtitle=" .. subtitle)
            end
        else
            pos = pos + 8 + (kind == 1 and 1 or 0)
        end
    end
    assert(pos == #bytes + 1)
end
local function player(slot, call)
    assert(native.rooms_with_player(slot, function()
        for index = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(index)
            if p.ControllerIndex == slot + 1 then
                call(p)
                return
            end
        end
        error("Missing presentation owner")
    end))
end
local function audio()
    local audible, virtual, played, filtered, last =
        string.unpack(">I4I4I4I4I4", native.audio_state())
    return audible, virtual, played, filtered, last
end
Isaac.AddCallback(owner, ModCallbacks.MC_USE_ITEM, function(_, item)
    if item == CollectibleType.COLLECTIBLE_MONSTER_MANUAL then
        assert(host, "Replica ran an item effect at an animation marker")
        uses = uses + 1
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_CARD, function()
    assert(host, "Replica used the card again")
    uses = uses + 1
end)
local frame = _IsaacLanFrame
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
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    local tick = status.verified
    if status.prepared then
        assert(native.api_with_local_view(function()
            checkPresentation(native.api_info().tick)
        end))
    end
    local card = not host and (tick >= 120 and tick < 126 or tick >= 240 and tick < 246)
    local active = not host and (tick >= 360 and tick < 366 or tick >= 760 and tick < 766)
        or host and tick >= 480 and tick < 486
        or tick >= 1120 and tick < 1126
    native.test_gamepad(card and 512 or 0, active and 255 or 0)
    if status.prepared and tick >= 1420 and not ended then
        ended = true
        assert(musicChecks > 30 and soundChecks > 2, "Room audio was not checked")
        assert(continuityChecks == 2, "Same-track room changes were not checked")
        report(
            "COUNTS uses="
                .. uses
                .. " snapshots="
                .. snapshots
                .. " visuals="
                .. visuals
                .. " music="
                .. musicChecks
                .. " sounds="
                .. soundChecks
        )
        if host then
            assert(uses == 7, "Authoritative use count=" .. uses)
        else
            assert(snapshots > 50 and visuals > 20, "Complete visual state was not checked")
            assert(textEvents["0 - The Fool"], "Complete Fool card title missing")
        end
        report("PASS guest complete animations and local audio")
    end
    return status
end
local function move(slot, index)
    assert(native.rooms_move(slot, index, 0, -1))
    player(slot, function(p)
        p.Position = Game():GetRoom():GetCenterPos()
        p:SetMinDamageCooldown(10000)
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:IsActiveEnemy(false) then
                e:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                e.MaxHitPoints = 100000
                e.HitPoints = 100000
            end
        end
    end)
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if t == 30 then
            origin = Game():GetLevel():GetCurrentRoomIndex()
            for i = 0, Game():GetLevel():GetRooms().Size - 1 do
                local d = Game():GetLevel():GetRooms():Get(i)
                if d.SafeGridIndex ~= origin and d.Data.Type == RoomType.ROOM_DEFAULT then
                    other = d.SafeGridIndex
                elseif d.Data.Type == RoomType.ROOM_BOSS then
                    boss = d.SafeGridIndex
                end
            end
            assert(origin and other and boss)
            for i = 0, 1 do
                Isaac.GetPlayer(i):SetMinDamageCooldown(10000)
                Isaac.GetPlayer(i).Position = Vector(180 + 120 * i, 180)
            end
            report("VISUAL_READY")
        elseif t == 50 then
            player(1, function(p)
                Isaac.Spawn(
                    EntityType.ENTITY_PICKUP,
                    PickupVariant.PICKUP_TAROTCARD,
                    Card.CARD_FOOL,
                    p.Position,
                    Vector.Zero,
                    nil
                )
            end)
        elseif t == 110 then
            player(1, function(p)
                assert(p:GetCard(0) == Card.CARD_FOOL, "Guest did not pick up Fool card")
            end)
        elseif t == 200 then
            player(1, function(p)
                p:SetCard(0, Card.CARD_EMPRESS)
            end)
        elseif t == 320 or t == 440 or t == 720 or t == 1080 then
            for slot = 0, 1 do
                player(slot, function(p)
                    if p:GetActiveItem() ~= CollectibleType.COLLECTIBLE_MONSTER_MANUAL then
                        p:AddCollectible(CollectibleType.COLLECTIBLE_MONSTER_MANUAL, 6)
                    end
                    p:SetActiveCharge(6)
                end)
            end
        elseif t == 590 then
            move(1, boss)
        elseif t == 810 then
            move(1, other)
        elseif t == 840 then
            move(1, origin)
        elseif t == 880 then
            move(1, other)
        elseif t == 920 then
            move(0, boss)
        elseif t == 1060 then
            move(1, boss)
        elseif t == 1230 then
            move(1, other)
        end
        if t == 560 or t == 800 or t == 1160 then
            for slot = 0, 1 do
                player(slot, function()
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e.Type == EntityType.ENTITY_FAMILIAR then
                            e:Remove()
                        end
                    end
                end)
            end
        end
        if t == 670 or t == 990 then
            player(0, function()
                SFXManager():Play(SoundEffect.SOUND_BEEP, 1)
            end)
            player(1, function()
                SFXManager():Play(SoundEffect.SOUND_BUTTON_PRESS, 1)
            end)
            report("SOUND_SPLIT tick=" .. t)
        elseif t == 1170 then
            player(1, function()
                SFXManager():Play(SoundEffect.SOUND_BEEP, 1)
            end)
            report("SOUND_SHARED tick=" .. t)
        end
        if t == 1280 or t == 1400 then
            player(1, function(p)
                if t == 1280 then
                    p:UseActiveItem(CollectibleType.COLLECTIBLE_MEGA_MUSH, 0, -1)
                else
                    assert(p.Visible, "Mega Mush animation did not restore player visibility")
                end
            end)
        end
    end, function(slot, t)
        local bytes = collect(slot, t)
        if t % 30 == 0 and t >= 100 then
            local p = native.item_presentation_state(slot)
            local s = native.item_presentation_sprite(slot, Isaac.GetPlayer(0):GetSprite(), 0)
            report(
                "OVERLAY_AUTH slot="
                    .. slot
                    .. " tick="
                    .. t
                    .. " state="
                    .. p.overlayState
                    .. " id="
                    .. p.overlayID
                    .. " sprite="
                    .. (s and s:GetFilename() or "none")
            )
        end
        return bytes
    end, function(bytes, t, ack)
        local applied = restore(bytes, t, ack)
        if applied and not host then
            local value = _IsaacLanState.decode(bytes)[16]
            checkText(value[1])
            assert(
                native.item_presentation_pose(1) == value[4],
                "Overlay pose differs from authority"
            )
            if value[3] then
                local s =
                    assert(native.item_presentation_sprite(1, Isaac.GetPlayer(0):GetSprite(), 0))
                assert(s:GetFilename() == value[3][1] and s:GetFrame() == value[3][3])
                assert(
                    native.sprite_state(s) == value[3][12],
                    "Overlay layers differ from authority"
                )
                snapshots = snapshots + 1
            end
        end
        return applied
    end, present, beginFloor)
end
function checkPresentation(t)
    if t >= 820 and t < 840 then
        continuousMusic = string.unpack(">I4", native.audio_state(), 21)
    end
    for _, checkpoint in ipairs({ 860, 900 }) do
        if t >= checkpoint and t < checkpoint + 10 and not continuityObserved[checkpoint] then
            local plays = string.unpack(">I4", native.audio_state(), 21)
            assert(plays == continuousMusic, "Same-track room change restarted native music")
            continuityObserved[checkpoint] = true
            continuityChecks = continuityChecks + 1
            report("MUSIC_CONTINUOUS tick=" .. t .. " native_plays=" .. plays)
        end
    end
    if t >= 650 and (t < 660 or t >= 950 and t < 980 or t >= 1240 and t < 1270) then
        local inBoss = t < 670 and not host or t >= 950 and host
        local expected = Music.MUSIC_BASEMENT
        local audible = audio()
        local bossOver = false
        if inBoss and Game():GetRoom():IsClear() then
            for name, id in pairs(Music) do
                if name:match("^MUSIC_BOSS_OVER") and id == audible then
                    bossOver = true
                end
            end
        end
        assert(
            inBoss
                    and (audible == Music.MUSIC_BOSS or audible == Music.MUSIC_BOSS2 or audible == Music.MUSIC_BOSS3 or bossOver)
                or not inBoss and audible == expected,
            "Wrong audible room music tick="
                .. t
                .. " expected="
                .. expected
                .. " actual="
                .. audible
        )
        musicChecks = musicChecks + 1
    end
    local beep, button = SoundEffect.SOUND_BEEP, SoundEffect.SOUND_BUTTON_PRESS
    for _, trigger in ipairs({ 670, 990, 1170 }) do
        if t >= trigger - 20 and t < trigger then
            soundBaselines[trigger] = { soundCount(beep), soundCount(button) }
        end
    end
    for _, trigger in ipairs({ 670, 990, 1170 }) do
        if t >= trigger + 5 and t < trigger + 15 and not soundObserved[trigger] then
            local baseline = assert(soundBaselines[trigger])
            local b, p = soundCount(beep), soundCount(button)
            report(
                "SOUND_CHECK tick="
                    .. t
                    .. " beep="
                    .. b
                    .. " button="
                    .. p
                    .. " baseline="
                    .. baseline[1]
                    .. ","
                    .. baseline[2]
            )
            assert(
                b == baseline[1] + ((host or trigger == 1170) and 1 or 0),
                "Beep audience crossed rooms"
            )
            assert(
                p == baseline[2] + ((not host and trigger ~= 1170) and 1 or 0),
                "Button audience crossed rooms"
            )
            soundObserved[trigger] = true
            soundChecks = soundChecks + 1
        end
    end
    local p = native.item_presentation_state()
    if p.overlayState == 2 and p.bookLoaded == 1 then
        local s = assert(
            native.item_presentation_sprite(host and 0 or 1, Isaac.GetPlayer(0):GetSprite(), 0)
        )
        assert(s:GetAnimation() ~= "", "Book animation did not advance")
        visuals = visuals + 1
    end
    if t % 30 == 0 and t >= 100 then
        local audible, virtual, played, filtered, last = audio()
        report(
            "PRESENT tick="
                .. t
                .. " overlay="
                .. p.overlayState
                .. " id="
                .. p.overlayID
                .. " music="
                .. audible
                .. " virtual="
                .. virtual
                .. " sounds="
                .. played
                .. " filtered="
                .. filtered
                .. " last="
                .. last
        )
    end
end
