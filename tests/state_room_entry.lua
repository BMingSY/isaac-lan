-- A separate native API regression, not part of the honest Greed attempt.
-- Establish a real arena return, then re-enter the already loaded wide shop
-- through Game:ChangeRoom. No coordinates or native fields are fabricated.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local playerCount = _IsaacLanTest.players or 2
local baseFrame, baseGate, baseInput = _IsaacLanFrame, native.net_gate, native.input_bot
local controlledMask = 0
local renders, linked, chosen, seenGame, finished = 0, false, false, false, false
local phase, beganAt, arena, shop, rawShop = "setup"
local sawHostShop, peerReturned = false, false
local peer = playerCount - 1
local inward = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
-- The inactive production bot releases automation during baseFrame, before
-- native input capture. Keep this fixture's normal movement at that boundary.
native.input_bot = function()
    return baseInput(finished and 0 or 1, controlledMask)
end
local function report(text)
    Isaac.DebugString("LAN_NETWORK ROOM_ENTRY " .. text)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end, 1))
end
local function canonical(index)
    return Game():GetLevel():GetRoomByIdx(index, 0).SafeGridIndex
end
local function returnDoor(source)
    for slot = 0, 7 do
        local door = Game():GetRoom():GetDoor(slot)
        if door and canonical(door.TargetRoomIndex) == source then
            return door, slot
        end
    end
    error("Native return door is missing")
end
local function walkOut(slot, source)
    local mask = 0
    actor(slot, function(p)
        local door, index = returnDoor(source)
        local direction = inward[index % 4 + 1]
        local x = door.Position.X - direction[1] * 32
        local y = door.Position.Y - direction[2] * 32
        if math.abs(x - p.Position.X) > 6 then
            mask = mask | (x > p.Position.X and 2 or 1)
        end
        if math.abs(y - p.Position.Y) > 6 and (direction[2] == 0 or mask == 0) then
            mask = mask | (y > p.Position.Y and 8 or 4)
        end
        if direction[1] ~= 0 and math.abs(y - p.Position.Y) > 6 then
            mask = y > p.Position.Y and 8 or 4
        end
    end)
    return mask
end
local function advance()
    if not native.rooms_ready() or finished then
        return
    end
    local game = Game()
    assert(game:IsGreedMode() and game:GetLevel():GetStage() == 1)
    local locations = native.rooms_positions()
    beganAt = beganAt or native.api_info().nowMs
    assert(native.api_info().nowMs - beganAt < 60000, "Native entry regression timed out")
    if phase == "setup" then
        actor(0, function()
            arena = Game():GetLevel():GetCurrentRoomIndex()
            for slot = 0, 7 do
                local door = Game():GetRoom():GetDoor(slot)
                if
                    door
                    and Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex, 0).Data.Type
                        == RoomType.ROOM_SHOP
                then
                    rawShop, shop = door.TargetRoomIndex, canonical(door.TargetRoomIndex)
                    break
                end
            end
        end)
        assert(arena and shop)
        for slot = 0, playerCount - 1 do
            actor(slot, function()
                Game():ChangeRoom(rawShop)
            end)
        end
        phase = "wait_shop"
        report("SETUP arena=" .. arena .. " shop=" .. shop .. " players=" .. playerCount)
    elseif phase == "wait_shop" then
        local all = true
        for slot = 0, playerCount - 1 do
            all = all and locations[tostring(slot)].index == shop
        end
        if all then
            phase = "host_return"
            report("ALL_IN_SHOP")
        end
    elseif phase == "host_return" and locations["0"].index == arena then
        phase = "peer_return"
        report("HOST_RETURNED")
    elseif phase == "peer_return" and locations[tostring(peer)].index == arena then
        actor(peer, function()
            Game():ChangeRoom(rawShop)
        end)
        phase = "check_entry"
        report("REENTRY_REQUEST slot=" .. peer)
    elseif phase == "check_entry" and locations[tostring(peer)].index == shop then
        actor(peer, function(p)
            local door, index = returnDoor(arena)
            local direction = inward[index % 4 + 1]
            local x = door.Position.X + direction[1] * 40
            local y = door.Position.Y + direction[2] * 40
            assert(
                (p.Position.X - x) ^ 2 + (p.Position.Y - y) ^ 2 < 25,
                "Re-entry reused a different actor's native EnterDoor"
            )
            local room = Game():GetRoom()
            assert(
                room:GetGridCollision(room:GetGridIndex(p.Position))
                    == GridCollisionClass.COLLISION_NONE,
                "Re-entry landed in blocked terrain"
            )
            report(
                "PASS corrected_reentry slot="
                    .. peer
                    .. " entry="
                    .. index
                    .. " x="
                    .. p.Position.X
                    .. " y="
                    .. p.Position.Y
            )
        end)
        finished = true
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = baseFrame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    local allReady = status.players == playerCount
    for slot = 0, playerCount - 1 do
        allReady = allReady and status["ready" .. slot] == 1
    end
    if host and status.phase == 2 and allReady then
        _IsaacLanCommand("start", "YV039KQF:2:0:0:0:0")
    end
    local mask, info = 0, native.api_info()
    if status.scene == 2 and info.ready == 1 and native.rooms_ready() and not finished then
        seenGame = true
        local locations = native.rooms_positions()
        if host and phase == "host_return" and locations["0"].index == shop then
            mask = walkOut(0, arena)
        elseif not host and info.slot == peer then
            local own, leader = locations[tostring(peer)].index, locations["0"].index
            if own == leader and own ~= Game():GetLevel():GetStartingRoomIndex() then
                shop, arena, sawHostShop = own, Game():GetLevel():GetStartingRoomIndex(), true
            end
            if sawHostShop and own == arena then
                peerReturned = true
            elseif sawHostShop and not peerReturned and own == shop and leader == arena then
                mask = walkOut(peer, arena)
            end
        end
    elseif
        not host
        and seenGame
        and status.phase == 0
        and status.scene == 1
        and not status.prepared
    then
        finished = true
        report("PASS peer_returned")
    end
    controlledMask = mask
    native.input_bot(1, mask)
    native.test_gamepad(0)
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(capture, function(t, n, b)
        before(t, n, b)
        if host then
            advance()
        end
    end, collect, restore, present, beginFloor)
end
