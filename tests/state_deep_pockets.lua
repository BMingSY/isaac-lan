-- Shared native coin cap with either holder, together/apart, and removal.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local step, stepAt, round, expected, holder = "prepare", 0, 0, nil, 0
local origin, other
local item = CollectibleType.COLLECTIBLE_DEEP_POCKETS
local function player(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(player(slot))
    end))
end
local function mark(name, t, coins)
    step, stepAt, expected = name, t, coins
    Isaac.DebugString("LAN_NETWORK DEEP_POCKETS round=" .. round .. " step=" .. name)
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
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    native.test_gamepad(0)
    return s
end
local function check(coins)
    for slot = 0, 1 do
        assert(player(slot):GetNumCoins() == coins, "Shared coin cap/balance differs")
    end
end
local function advance(t)
    if finished or not native.rooms_ready() then
        return
    end
    if step == "prepare" and t >= 30 then
        origin = native.rooms_positions()["0"].index
        local rooms = Game():GetLevel():GetRooms()
        for i = 0, rooms.Size - 1 do
            local d = rooms:Get(i)
            if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= origin then
                other = d.SafeGridIndex
                break
            end
        end
        assert(other)
        mark("begin", t)
    elseif step == "begin" and t - stepAt >= 30 then
        holder = round % 2
        assert(native.rooms_move(1, round >= 2 and other or origin, 0, -1))
        mark("baseline", t)
    elseif step == "baseline" and t - stepAt >= 30 then
        for slot = 0, 1 do
            actor(slot, function(p)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type ~= EntityType.ENTITY_PLAYER then
                        e:Remove()
                    end
                end
                Game():GetRoom():SetClear(true)
                p.Position, p.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
                assert(not p:HasCollectible(item))
            end)
        end
        actor(1 - holder, function(p)
            p:AddCoins(-p:GetNumCoins())
            p:AddCoins(1100)
        end)
        check(99)
        mark("grant", t, 99)
    elseif step == "grant" and t - stepAt >= 45 then
        actor(holder, function(p)
            p:AddCollectible(item, 0, false)
        end)
        actor(1 - holder, function(p)
            p:AddCoins(1100)
        end)
        check(999)
        mark("spend", t, 999)
    elseif step == "spend" and t - stepAt >= 45 then
        actor(1 - holder, function(p)
            p:AddCoins(-1)
        end)
        check(998)
        for slot = 0, 1 do
            assert(player(slot):GetCollectibleNum(item, true) == (slot == holder and 1 or 0))
        end
        mark("remove", t, 998)
    elseif step == "remove" and t - stepAt >= 45 then
        actor(holder, function(p)
            p:RemoveCollectible(item)
        end)
        actor(1 - holder, function(p)
            p:AddCoins(-p:GetNumCoins())
            p:AddCoins(1100)
        end)
        check(99)
        mark("removed", t, 99)
    elseif step == "removed" and t - stepAt >= 45 then
        round = round + 1
        if round == 4 then
            finished = true
            Isaac.DebugString("LAN_NETWORK DEEP_POCKETS PASS four contexts and removal")
        else
            mark("begin", t)
        end
    end
    assert(t - stepAt < 300, "Deep Pockets acceptance stalled")
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        advance(t)
    end, function(slot, t)
        local bytes, stable = collect(slot, t)
        return bytes and string.pack(">s4", bytes) .. _IsaacLanState.encode({
            expected or false,
            finished,
        }),
            stable
    end, function(bytes, t, ack, betweenUpdates, stable)
        local body, cursor = string.unpack(">s4", bytes)
        if restore(body, t, ack, betweenUpdates, stable) == false then
            return false
        end
        local meta = _IsaacLanState.decode(bytes:sub(cursor))
        if meta[1] then
            check(meta[1])
        end
        if meta[2] and not finished then
            finished = true
            Isaac.DebugString("LAN_NETWORK DEEP_POCKETS PASS replicated balances")
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
