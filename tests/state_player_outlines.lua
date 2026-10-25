-- Visual acceptance uses the native player renderer on both protected peers.
local native, test = _IsaacLan, _IsaacLanTest
local host, port = test.host, test.port
local frame, gate = _IsaacLanFrame, native.net_gate
local owner = { Name = "LAN player outline presentation" }
local renders, linked, chosen, finished = 0, false, false, false
local tick, origin, other = 0, nil, nil
local observed, renderChecks, tintChecks, plainChecks = {}, 0, 0, 0
local function report(message)
    Isaac.DebugString("LAN_NETWORK OUTLINES " .. message)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function clear()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function arrange(overlap)
    for slot = 0, 1 do
        actor(slot, function(p)
            clear()
            local distance = overlap and 4 or 65
            p.Position = Game():GetRoom():GetCenterPos()
                + Vector(slot == 0 and -distance or distance, 0)
            p.Velocity = Vector.Zero
        end)
    end
end
local function colors(p)
    local color = p:GetSprite().Color
    return { color.R, color.G, color.B, color.A, color.RO, color.GO, color.BO }
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    tick = status.verified
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
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if status.verified >= 1110 and not finished then
        assert(
            observed[1]
                and observed[2]
                and renderChecks > 100
                and tintChecks > 10
                and plainChecks > 10,
            "Missing native player rendering"
        )
        assert(Game():GetLevel():GetStage() == 2, "Floor transition did not finish")
        report(
            "PASS colors preserved across native render, room and floor; checks=" .. renderChecks
        )
        finished = true
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(function()
        return _IsaacLanTestInput.neutral
    end, function(t, n, bytes)
        before(t, n, bytes)
        if t == 60 then
            origin = native.rooms_positions()["0"].index
            local rooms = Game():GetLevel():GetRooms()
            for i = 0, rooms.Size - 1 do
                local room = rooms:Get(i)
                if
                    room.SafeGridIndex ~= origin
                    and room.Data.Type == RoomType.ROOM_DEFAULT
                    and room.Data.Shape == RoomShape.ROOMSHAPE_1x1
                then
                    other = room.SafeGridIndex
                    break
                end
            end
            assert(other)
            arrange()
            report("SCENE plain tick=" .. t)
        elseif t == 180 then
            actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
            end)
            actor(1, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM)
            end)
            arrange()
            report("SCENE costumes-size tick=" .. t)
        elseif t == 300 then
            arrange(true)
            report("SCENE overlap tick=" .. t)
        elseif t == 390 then
            arrange()
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:TakeDamage(1, 0, EntityRef(p), 30)
                end)
            end
            report("SCENE hurt-blink tick=" .. t)
        elseif t == 480 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:SetColor(Color(0.3, 0.8, 0.4, 1), 80, 1, false, false)
                end)
            end
            report("SCENE tint tick=" .. t)
        elseif t == 600 then
            assert(native.rooms_move(1, other, 0, -1))
            report("SCENE split tick=" .. t)
        elseif t == 630 then
            arrange()
        elseif t == 720 then
            assert(native.rooms_move(1, origin, 0, -1))
            report("SCENE reunited tick=" .. t)
        elseif t == 750 then
            arrange()
        elseif t == 810 then
            actor(1, function(p)
                p:ChangePlayerType(PlayerType.PLAYER_JACOB)
            end)
            arrange()
            report("SCENE twins tick=" .. t)
        elseif t == 930 then
            actor(0, function(p)
                Game():StartStageTransition(false, 0, p)
            end)
            report("SCENE next-floor tick=" .. t)
        elseif t == 1050 then
            arrange()
        end
    end, collect, restore, present, beginFloor)
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_PLAYER_RENDER, function(_, p)
    if native.rooms_ready() and tick >= 60 then
        observed[p.ControllerIndex] = true
        -- A frame callback precedes native updates/presentation. Compare the
        -- actual draw against stable fixture colors, not the previous update.
        local tinted = tick >= 500 and tick <= 535
        local plain = tick >= 100 and tick <= 150 or tick >= 570 and tick <= 590
        local expected = tinted and { 0.3, 0.8, 0.4, 1, 0, 0, 0 }
            or plain and { 1, 1, 1, 1, 0, 0, 0 }
        if expected then
            for i, value in ipairs(colors(p)) do
                assert(
                    math.abs(value - expected[i]) < 0.0001,
                    string.format(
                        "Sprite color changed tick=%d controller=%d channel=%d expected=%f actual=%f",
                        tick,
                        p.ControllerIndex,
                        i,
                        expected[i],
                        value
                    )
                )
            end
            tintChecks = tintChecks + (tinted and 1 or 0)
            plainChecks = plainChecks + (plain and 1 or 0)
        end
        renderChecks = renderChecks + 1
    end
end)
return {
    done = function()
        return finished
    end,
}
