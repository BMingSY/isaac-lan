-- A delayed follower must discard source-room history on resident-room entry.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished, checks = 0, false, false, false, 0
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end, 1))
end
local function inspect(t)
    if not (t >= 181 and t <= 230 or t >= 451 and t <= 500) then
        return
    end
    actor(host and 0 or 1, function()
        local count = 0
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e.Type == EntityType.ENTITY_FAMILIAR and e.Variant == FamiliarVariant.SHADE then
                count = count + 1
                assert(
                    e.Position:Distance(Vector(320, 400)) < 64,
                    "Shade followed its previous room's path"
                )
            end
        end
        assert(count == 1, "Resident-room entry lost the arriving Shade")
        checks = checks + 1
    end)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "1XJTX49A:0:0:0:0:0")
    end
    native.test_gamepad(0)
    if s.prepared and s.verified >= 540 and not finished then
        assert(checks >= 50, "Both follower arrival checks were not exercised")
        finished = true
        Isaac.DebugString("LAN_NETWORK ROOM_FOLLOWERS PASS repeated occupied-room Shade entry")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if t == 30 then
            actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_SHADE, 0, false)
                p.Position, p.Velocity = Vector(80, 200), Vector.Zero
                p:SetMinDamageCooldown(10000)
            end)
            assert(native.rooms_move(1, 71, 0, -1))
        elseif t == 60 then
            actor(1, function(p, room)
                p.Position, p.Velocity = Vector(300, 280), Vector.Zero
                p:SetMinDamageCooldown(10000)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Remove()
                    end
                end
                room:SetClear(true)
            end)
        elseif t == 180 or t == 450 then
            assert(native.rooms_positions()["1"].index == 71, "Destination lost its resident")
            assert(native.rooms_move(0, 71, 0, 3))
        elseif t == 300 then
            assert(native.rooms_move(0, 84, 0, -1))
        elseif t == 330 then
            actor(0, function(p)
                p.Position, p.Velocity = Vector(80, 200), Vector.Zero
            end)
        end
    end, function(slot, t)
        if slot == 1 then
            inspect(t)
        end
        return collect(slot, t)
    end, function(bytes, t, ...)
        local applied = restore(bytes, t, ...)
        if applied ~= false then
            inspect(t)
        end
        return applied
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
