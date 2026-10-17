-- Exercise the actual J460 pools with two players in separate room contexts.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame = _IsaacLanFrame
local linked, chosen, finished, renders = false, false, false, 0
local step, stepAt, baseline, ordinaryCards, restrictedCards = "prepare", 0
local function report(message)
    Isaac.DebugString("LAN_NETWORK ITEM_GENERATION " .. message)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end, 1))
end
local function mark(nextStep, tick)
    step, stepAt = nextStep, tick
    report("STEP " .. step .. " tick=" .. tick)
end
local function sample(slot, cards, special)
    local result = {}
    actor(slot, function()
        local pool = Game():GetItemPool()
        for i = 1, cards and 1024 or 512 do
            local seed = 100003 + i * 7919
            -- GetCard booleans are playing cards, runes and only-runes.
            -- Only-runes is the public path that disables special cards.
            result[i] = cards and pool:GetCard(seed, true, true, not special)
                or pool:GetCollectible(ItemPoolType.POOL_TREASURE, false, seed)
        end
    end)
    return result
end
local function same(a, b, message)
    assert(#a == #b)
    for i, id in ipairs(a) do
        assert(id == b[i], message .. " seed=" .. i)
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "localhost:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", host and "0:1" or "31:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:31:0:0")
    end
    native.test_gamepad(0)
    return s
end
local function advance(t)
    if step == "prepare" and t >= 30 then
        local target
        local rooms = Game():GetLevel():GetRooms()
        local origin = native.rooms_positions()["0"].index
        for i = 0, rooms.Size - 1 do
            local d = rooms:Get(i)
            if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= origin then
                target = d.SafeGridIndex
                break
            end
        end
        assert(target and native.rooms_move(1, target, 0, -1))
        actor(1, function(p)
            p:ChangePlayerType(PlayerType.PLAYER_ISAAC)
            p:SetMinDamageCooldown(10000)
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:IsActiveEnemy(false) then
                    e:Remove()
                end
            end
        end)
        mark("baseline", t)
    elseif step == "baseline" and t - stepAt >= 60 then
        baseline = sample(0, false)
        ordinaryCards, restrictedCards = sample(0, true, true), sample(0, true, false)
        same(baseline, sample(1, false), "Baseline pools differ across rooms")
        local low = 0
        for _, id in ipairs(baseline) do
            if Isaac.GetItemConfig():GetCollectible(id).Quality < 2 then
                low = low + 1
            end
        end
        assert(low > 0, "Fixture has no low-quality baseline candidates")
        actor(1, function(p)
            p:AddCollectible(CollectibleType.COLLECTIBLE_SACRED_ORB, 0, false)
        end)
        mark("orb", t)
    elseif step == "orb" and t - stepAt >= 60 then
        local orb = sample(0, false)
        same(orb, sample(1, false), "Sacred Orb depends on the generating player's room")
        for _, id in ipairs(orb) do
            assert(
                Isaac.GetItemConfig():GetCollectible(id).Quality >= 2,
                "Remote Sacred Orb allowed quality 0/1"
            )
        end
        report("ORB seeds=512 remote owner's native rerolls apply to both rooms")
        actor(1, function(p)
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_SACRED_ORB)
            p:ChangePlayerType(PlayerType.PLAYER_THELOST_B)
        end)
        mark("lost", t)
    elseif step == "lost" and t - stepAt >= 60 then
        local lost, cards = sample(0, false), sample(0, true, true)
        same(lost, sample(1, false), "Tainted Lost item generation depends on room")
        same(cards, sample(1, true, true), "Tainted Lost Holy Cards depend on room")
        same(
            restrictedCards,
            sample(0, true, false),
            "Holy Card replaced a special-card-disabled result"
        )
        local low, qualityTwo, replaced = 0, 0, 0
        for _, id in ipairs(lost) do
            local config = Isaac.GetItemConfig():GetCollectible(id)
            assert(
                config.Tags & ItemConfig.TAG_OFFENSIVE ~= 0,
                "Tainted Lost allowed a non-offensive random item"
            )
            if config.Quality < 2 then
                low = low + 1
            end
            if config.Quality == 2 then
                qualityTwo = qualityTwo + 1
            end
        end
        assert(
            low > 0 and qualityTwo > 0,
            "Native reroll unexpectedly blacklisted an entire quality"
        )
        for i, id in ipairs(cards) do
            if id ~= ordinaryCards[i] then
                assert(
                    id == Card.CARD_HOLY,
                    "Tainted Lost altered a card into something other than Holy Card"
                )
                replaced = replaced + 1
            end
        end
        assert(
            replaced > 20 and replaced < 170,
            "Native Holy Card replacement count is implausible"
        )
        actor(1, function()
            Isaac.Spawn(
                EntityType.ENTITY_PICKUP,
                PickupVariant.PICKUP_TAROTCARD,
                Card.CARD_HOLY,
                Game():GetRoom():GetCenterPos() + Vector(0, 100),
                Vector.Zero,
                nil
            )
        end)
        report(
            "LOST seeds=512 offensive-only low="
                .. low
                .. " quality2="
                .. qualityTwo
                .. " cards=1024 replacements="
                .. replaced
        )
        mark("replication", t)
    elseif step == "replication" and not finished and t - stepAt >= 90 then
        assert(native.rooms_connected() == 3)
        finished = true
        report("PASS split-room native item/card generation and result replication")
    end
    assert(t - stepAt < 600, "Item generation stalled at " .. step)
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        advance(t)
    end, function(slot, t)
        local bytes = collect(slot, t)
        return bytes and string.pack(">s4", bytes) .. _IsaacLanState.encode({ step, finished })
    end, function(bytes, t, ack, betweenUpdates)
        local body, cursor = string.unpack(">s4", bytes)
        if restore(body, t, ack, betweenUpdates) == false then
            return false
        end
        local meta = _IsaacLanState.decode(bytes:sub(cursor))
        if meta[1] == "replication" then
            local holy = false
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if
                    e.Type == EntityType.ENTITY_PICKUP
                    and e.Variant == PickupVariant.PICKUP_TAROTCARD
                    and e.SubType == Card.CARD_HOLY
                then
                    holy = true
                end
            end
            assert(holy, "Replica lost the generated Holy Card")
        end
        if meta[2] then
            finished = true
            report("PASS split-room native item/card generation and result replication")
        end
        return true
    end, present, beginFloor)
end

-- Explicit test-only lifecycle consumed by both suite coordinators.
return {
    done = function()
        return finished
    end,
}
