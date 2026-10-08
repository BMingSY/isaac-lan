-- Ordinary native guest pickups must resolve real ItemConfig objects on replay.
local native = assert(_IsaacLan)
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local frame = _IsaacLanFrame
local renders, linked, chosen, finished = 0, false, false, false
local pickups = {
    -- 253 was the replay ID captured in the reported access-violation dump.
    { tick = 80, id = 253 },
    { tick = 200, id = 730 },
    { tick = 320, id = CollectibleType.COLLECTIBLE_MONSTER_MANUAL },
    { tick = 440, id = CollectibleType.COLLECTIBLE_BROTHER_BOBBY },
    { tick = 560, id = TrinketType.TRINKET_PAPER_CLIP, trinket = true },
}
local baseline
local observations = {}
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
    native.test_gamepad(0)
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.prepared then
        local p = native.item_presentation_state()
        if not baseline and s.verified >= 50 then
            baseline = p.items
        end
        for i, pickup in ipairs(pickups) do
            if s.verified >= pickup.tick + 75 and s.verified < pickup.tick + 110 then
                assert(
                    p.items == baseline + (host and 0 or i),
                    "Guest pickup text missing, duplicated or crossed owners: " .. pickup.id
                )
                if not observations[i] then
                    report("PICKUP_PRESENT id=" .. pickup.id .. " items=" .. p.items)
                end
                observations[i] = (observations[i] or 0) + 1
            end
        end
    end
    if s.verified >= 850 and not finished then
        for i in ipairs(pickups) do
            assert((observations[i] or 0) > 3, "Guest pickup was not observed: " .. i)
        end
        assert(
            native.item_presentation_state().items == baseline + (host and 1 or #pickups),
            "Pickup texts did not remain isolated or replayed with later snapshots"
        )
        finished = true
        report("PASS native guest pickup text")
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
local function spawn(slot, id, trinket)
    player(slot, function(p)
        Isaac.Spawn(
            EntityType.ENTITY_PICKUP,
            trinket and PickupVariant.PICKUP_TRINKET or PickupVariant.PICKUP_COLLECTIBLE,
            id,
            p.Position,
            Vector.Zero,
            nil
        )
    end)
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
        for _, pickup in ipairs(pickups) do
            if t == pickup.tick then
                spawn(1, pickup.id, pickup.trinket)
                report("GUEST_PICKUP tick=" .. t .. " id=" .. pickup.id)
            elseif t == pickup.tick + 75 then
                player(1, function(p)
                    assert(
                        pickup.trinket and p:HasTrinket(pickup.id)
                            or not pickup.trinket and p:HasCollectible(pickup.id),
                        "Guest did not pick up item: " .. pickup.id
                    )
                end)
            end
        end
        if t == 700 then
            spawn(0, CollectibleType.COLLECTIBLE_SAD_ONION)
        elseif t == 775 then
            player(0, function(p)
                assert(p:HasCollectible(CollectibleType.COLLECTIBLE_SAD_ONION))
            end)
        end
    end, collect, restore, present, beginFloor)
end
