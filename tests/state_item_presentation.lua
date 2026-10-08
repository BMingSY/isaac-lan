-- Native pickups/physical item presses must present only on the acting peer.
local native = assert(_IsaacLan)
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local owner = { Name = "Item presentation ownership regression" }
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local frame = _IsaacLanFrame
local renders, linked, chosen, finished = 0, false, false, false
local uses = { 0, 0 }
local pills, cards = 0, 0
local observations = {
    card = 0,
    cardUse = 0,
    pill = 0,
    guestBook = 0,
    hostBook = 0,
    splitBook = 0,
    simultaneous = 0,
}
local baseline
Isaac.AddCallback(owner, ModCallbacks.MC_USE_ITEM, function(_, item, _, p)
    if item == CollectibleType.COLLECTIBLE_MONSTER_MANUAL then
        assert(host, "Replica executed the authoritative item effect")
        uses[p.ControllerIndex] = uses[p.ControllerIndex] + 1
        report("USE controller=" .. p.ControllerIndex)
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_PILL, function()
    assert(host, "Replica executed the authoritative pill effect")
    pills = pills + 1
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_CARD, function()
    assert(host, "Replica executed the authoritative card effect")
    cards = cards + 1
end)
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = frame()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    local active = not host
            and (s.verified >= 310 and s.verified < 316 or s.verified >= 610 and s.verified < 616)
        or host and s.verified >= 460 and s.verified < 466
        or s.verified >= 1100 and s.verified < 1106
    local pill = not host
        and (s.verified >= 180 and s.verified < 186 or s.verified >= 250 and s.verified < 256)
    native.test_gamepad(pill and 512 or 0, active and 255 or 0)
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.prepared then
        local p = native.item_presentation_state()
        if host and p.overlayState == 2 then
            assert(p.globalOverlayState == 0, "Local book globally paused peer item input")
        end
        if not baseline and s.verified >= 50 then
            baseline = p
            report(
                "BASELINE texts=" .. p.texts .. " items=" .. p.items .. " overlays=" .. p.overlays
            )
        end
        if s.verified == 110 or s.verified == 210 or s.verified == 330 then
            report(
                "PRESENT tick="
                    .. s.verified
                    .. " texts="
                    .. p.texts
                    .. " items="
                    .. p.items
                    .. " overlays="
                    .. p.overlays
                    .. " state="
                    .. p.overlayState
                    .. " id="
                    .. p.overlayID
            )
        end
        if s.verified >= 110 and s.verified < 140 then
            if host then
                assert(
                    p.texts == baseline.texts and p.items == baseline.items,
                    "Guest card pickup appeared on host"
                )
            elseif p.texts + p.items > baseline.texts + baseline.items then
                observations.card = observations.card + 1
            end
        end
        if s.verified >= 210 and s.verified < 250 then
            if host then
                assert(p.texts == baseline.texts, "Guest pill message appeared on host")
            elseif p.texts > baseline.texts + 1 then
                observations.pill = observations.pill + 1
            end
        end
        if s.verified >= 315 and s.verified < 370 then
            if host then
                assert(
                    p.overlayState == 0 and p.overlays == baseline.overlays,
                    "Guest book took host viewport"
                )
            elseif p.overlayState == 2 then
                observations.guestBook = observations.guestBook + 1
            end
        end
        if s.verified >= 255 and s.verified < 290 then
            if host then
                assert(p.overlays == baseline.overlays, "Guest card use appeared on host")
            elseif p.overlayState == 2 then
                observations.cardUse = observations.cardUse + 1
            end
        end
        if s.verified >= 465 and s.verified < 520 then
            if host and p.overlayState == 2 then
                observations.hostBook = observations.hostBook + 1
            elseif not host then
                assert(
                    p.overlayState == 0 and p.overlays == baseline.overlays + 2,
                    "Host book took guest viewport"
                )
            end
        end
        if s.verified >= 615 and s.verified < 675 then
            if host then
                assert(
                    p.overlayState == 0 and p.overlays == baseline.overlays + 1,
                    "Split-room book took host viewport"
                )
            elseif p.overlayState == 2 then
                observations.splitBook = observations.splitBook + 1
            end
        end
        if s.verified >= 1110 and s.verified < 1160 and p.overlayState == 2 then
            assert(
                p.overlays == baseline.overlays + (host and 2 or 5),
                "Simultaneous books crossed owners or replayed"
            )
            observations.simultaneous = observations.simultaneous + 1
        end
    end
    if s.verified >= 1220 and not finished then
        if host then
            assert(uses[1] == 2 and uses[2] == 3, "Physical book presses did not execute once")
            assert(pills == 1, "Physical pill press did not execute once")
            assert(cards == 1, "Physical card press did not execute once")
            assert(observations.hostBook > 3, "Host native book animation missing")
            assert(
                native.item_presentation_state().items == baseline.items + 1,
                "Host collectible pickup did not present once"
            )
        else
            for _, name in ipairs({ "card", "cardUse", "pill", "guestBook", "splitBook" }) do
                assert(observations[name] > 3, "Guest native presentation missing: " .. name)
            end
            assert(
                native.item_presentation_state().overlays == baseline.overlays + 5,
                "Snapshots replayed an item overlay"
            )
            assert(
                native.item_presentation_state().items == baseline.items,
                "Host collectible pickup appeared on guest"
            )
        end
        assert(observations.simultaneous > 3, "Simultaneous native book animation missing")
        finished = true
        report("PASS item presentation ownership")
    end
    return s
end
local function player(slot, call)
    assert(native.rooms_with_player(slot, function()
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            if p.ControllerIndex == slot + 1 then
                call(p)
                return
            end
        end
        error("Scoped room is missing the requested controller")
    end))
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, b)
        before(t, n, b)
        if t == 30 then
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:IsActiveEnemy(false) then
                    e:Remove()
                end
            end
            Isaac.GetPlayer(0).Position = Vector(180, 160)
            Isaac.GetPlayer(1).Position = Vector(360, 260)
            for i = 0, 1 do
                Isaac.GetPlayer(i):AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
            end
        end
        if t == 80 then
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
            report("GUEST_CARD")
        end
        if t == 150 then
            assert(Isaac.GetPlayer(1):GetCard(0) == Card.CARD_FOOL, "Guest did not pick up card")
            player(1, function(p)
                p:SetCard(0, 0)
                p:AddPill(PillColor.PILL_BLUE_BLUE)
            end)
        end
        if t == 240 then
            player(1, function(p)
                p:SetCard(0, Card.CARD_EMPRESS)
            end)
        end
        if t == 270 or t == 420 or t == 570 then
            local slot = t == 420 and 0 or 1
            player(slot, function(p)
                if p:GetActiveItem() ~= CollectibleType.COLLECTIBLE_MONSTER_MANUAL then
                    p:AddCollectible(CollectibleType.COLLECTIBLE_MONSTER_MANUAL, 6)
                end
                p:SetActiveCharge(6)
            end)
        end
        if t == 540 then
            local level = Game():GetLevel()
            local origin = native.rooms_positions()["0"].index
            local destination
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                if d.SafeGridIndex ~= origin and d.Data.Type == RoomType.ROOM_DEFAULT then
                    destination = d.SafeGridIndex
                    break
                end
            end
            assert(destination and native.rooms_move(1, destination, 0, -1))
        end
        if t == 380 then
            player(0, function(p)
                Isaac.Spawn(
                    EntityType.ENTITY_PICKUP,
                    PickupVariant.PICKUP_COLLECTIBLE,
                    CollectibleType.COLLECTIBLE_SAD_ONION,
                    p.Position,
                    Vector.Zero,
                    nil
                )
            end)
        end
        if t == 560 then
            player(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Remove()
                    end
                end
            end)
        end
        if t == 700 then
            player(1, function(p)
                p:UseActiveItem(CollectibleType.COLLECTIBLE_MEGA_MUSH, 0, -1)
            end)
        end
        if t == 735 or t == 795 then
            local p = native.item_presentation_state(1)
            report(
                "MEGA tick="
                    .. t
                    .. " state="
                    .. p.overlayState
                    .. " id="
                    .. p.overlayID
                    .. " loaded="
                    .. p.megaLoaded
                    .. " playing="
                    .. p.megaPlaying
                    .. " frame="
                    .. p.megaFrame
                    .. " visible="
                    .. tostring(Isaac.GetPlayer(1).Visible)
            )
        end
        if t == 795 then
            assert(
                Isaac.GetPlayer(1).Visible,
                "Remote Mega Mush overlay never restored native visibility"
            )
        end
        -- Allow Mega Mush's native item-use cooldown to finish before
        -- exercising simultaneous physical presses of Monster Manual.
        if t == 1070 then
            for slot = 0, 1 do
                player(slot, function(p)
                    p:SetActiveCharge(6)
                end)
            end
        end
    end, collect, restore, present, beginFloor)
end
