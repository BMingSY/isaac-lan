-- One native pair: split-room item use by each controller, including Jacob
-- and Esau, annex exploration/cards, pickup returns and a subsequent floor.
-- Isolated profiles must unlock Jacob and Esau before native menus load.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local step, stepAt, round = "prepare", 0, 0
local origin, large, returnRoom, explore, selected, stage
local searched
local function report(text)
    Isaac.DebugString("LAN_NETWORK DEATH_CERTIFICATE " .. text)
end
local function mark(nextStep, tick)
    step, stepAt = nextStep, tick
    report("STEP " .. step .. " round=" .. round .. " tick=" .. tick)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end, 1))
end
local function location(slot)
    return assert(native.rooms_positions()[tostring(slot)])
end
local function move(slot, index, dimension)
    assert(native.rooms_move(slot, index, dimension or 0, -1))
end
local function checkPosition(slot, label)
    actor(slot, function(_, room)
        local bodies = 0
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            assert(
                room:IsPositionInRoom(p.Position, 0),
                label .. " body outside room: " .. p.Position.X .. "," .. p.Position.Y
            )
            bodies = bodies + 1
        end
        assert(
            bodies == (slot == 1 and 2 or 1),
            label .. " controlled body count: slot=" .. slot .. " count=" .. bodies
        )
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local familiar = entity:ToFamiliar()
            if familiar and familiar.Player and familiar.Player.ControllerIndex == slot + 1 then
                assert(
                    room:IsPositionInRoom(familiar.Position, 0),
                    label .. " familiar outside room"
                )
            end
        end
    end)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "localhost:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", host and "0:1" or "19:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:19:0:0")
    end
    native.test_gamepad(0)
    return status
end
local function advance(t)
    if finished or not native.rooms_ready() then
        return
    end
    local level = Game():GetLevel()
    if step == "prepare" and t >= 30 then
        origin, stage = location(0).index, level:GetStage()
        level:RemoveCurses(level:GetCurses())
        for i = 0, level:GetRooms().Size - 1 do
            local desc = level:GetRooms():Get(i)
            if
                desc.Data
                and desc.Data.Type == RoomType.ROOM_DEFAULT
                and desc.Data.Shape >= RoomShape.ROOMSHAPE_1x2
            then
                large = desc.SafeGridIndex
                break
            end
        end
        assert(large, "Fixture seed has no large source room")
        actor(1, function(p)
            p:AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, 0, false)
        end)
        move(1, large)
        mark("source", t)
    elseif step == "source" and t - stepAt >= 60 then
        for slot = 0, 1 do
            actor(slot, function(_, room)
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity:IsActiveEnemy(false) then
                        entity:Remove()
                    end
                end
                for index = 0, room:GetGridSize() - 1 do
                    if room:GetGridCollision(index) ~= GridCollisionClass.COLLISION_WALL then
                        room:RemoveGridEntity(index, 0, false)
                    end
                end
                room:SetClear(true)
                local position = slot == 1
                        and room:GetClampedPosition(room:GetBottomRightPos() - Vector(80, 80), 20)
                    or room:GetCenterPos()
                assert(
                    slot == 0 or position.X > 640 or position.Y > 560,
                    "Source does not exercise out-of-annex pixels"
                )
                for i = 0, Game():GetNumPlayers() - 1 do
                    local p = Isaac.GetPlayer(i)
                    p:SetMinDamageCooldown(10000)
                    p.Position, p.Velocity = position, Vector.Zero
                end
                report("SOURCE slot=" .. slot .. " x=" .. position.X .. " y=" .. position.Y)
            end)
        end
        returnRoom = location(round).index
        searched = {}
        actor(round, function(p)
            p:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM)
        end)
        mark("enter", t)
    elseif step == "enter" and location(0).dimension == 2 and location(1).dimension == 2 then
        assert(location(0).index == location(1).index, "Entry split the party")
        for slot = 0, 1 do
            checkPosition(slot, "entry")
        end
        report("PASS entry round=" .. round)
        mark("explore", t)
    elseif step == "explore" and t - stepAt >= 60 then
        actor(0, function(_, room)
            explore = nil
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door.TargetRoomIndex >= 0 then
                    explore = door.TargetRoomIndex
                    break
                end
            end
        end)
        move(1, assert(explore), 2)
        mark("split", t)
    elseif step == "split" and t - stepAt >= 60 then
        assert(
            location(0).dimension == 2
                and location(1).dimension == 2
                and location(0).index ~= location(1).index,
            "Annex exploration gathered the party"
        )
        actor(1, function(p)
            p:UseCard(Card.CARD_FOOL, UseFlag.USE_NOANIM)
        end)
        mark("card", t)
    elseif step == "card" and t - stepAt >= 90 then
        assert(location(0).dimension == 2 and location(1).dimension == 2, "Card escaped annex")
        move(1, explore, 2)
        mark("select", t)
    elseif step == "select" and t - stepAt >= 60 then
        local nextRoom
        actor(1, function(_, room)
            selected = nil
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                local pickup = entity:ToPickup()
                if
                    pickup
                    and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
                    and pickup.SubType > 0
                then
                    selected = EntityPtr(pickup)
                    break
                end
            end
            if not selected then
                -- Native pickup removes this chamber's pedestals. A second
                -- use on the same floor must continue into an unvisited one.
                searched[location(1).index] = true
                for slot = 0, 7 do
                    local door = room:GetDoor(slot)
                    if
                        door
                        and door.TargetRoomIndex >= 0
                        and door.TargetRoomIndex ~= 80
                        and not searched[door.TargetRoomIndex]
                    then
                        nextRoom = door.TargetRoomIndex
                        break
                    end
                end
            end
        end)
        if selected then
            mark("pickup", t)
        else
            move(1, assert(nextRoom, "Annex has no unvisited pedestal chamber"), 2)
            mark("select", t)
        end
    elseif step == "pickup" then
        if location(1).dimension == 2 then
            actor(1, function(p)
                if selected.Ref and selected.Ref:Exists() then
                    p.Position, p.Velocity = selected.Ref.Position - Vector(10, 0), Vector(1, 0)
                end
            end)
        else
            for slot = 0, 1 do
                assert(
                    location(slot).dimension == 0 and location(slot).index == returnRoom,
                    "Pickup lost the party's source room"
                )
                checkPosition(slot, "return")
            end
            report("PASS return round=" .. round)
            mark("returned", t)
        end
    elseif step == "returned" and t - stepAt >= 90 then
        if round == 0 then
            round = 1
            move(0, origin)
            move(1, large)
            mark("source", t)
        else
            actor(0, function(p)
                level:SetStage(stage + 1, StageType.STAGETYPE_ORIGINAL)
                Game():StartStageTransition(true, 0, p)
            end)
            mark("floor", t)
        end
    elseif step == "floor" and level:GetStage() == stage + 1 and t - stepAt >= 60 then
        for slot = 0, 1 do
            assert(location(slot).dimension == 0, "New floor retained annex dimension")
            checkPosition(slot, "floor")
        end
        finished = true
        report("PASS entry return split card bodies familiars repeated use and floor cleanup")
    end
    assert(t - stepAt < 900, "Death Certificate stalled at " .. step)
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        advance(t)
    end, function(slot, t)
        local bytes = collect(slot, t)
        if bytes then
            return string.pack(">s4", bytes) .. _IsaacLanState.encode({ step, round, finished })
        end
    end, function(bytes, t, ack)
        local body, cursor = string.unpack(">s4", bytes)
        if restore(body, t, ack) == false then
            return false
        end
        local meta = _IsaacLanState.decode(bytes:sub(cursor))
        if meta[1] == "explore" or meta[1] == "returned" or meta[3] then
            checkPosition(1, "replica " .. meta[1])
            if step ~= meta[1] or round ~= meta[2] then
                report("PASS replica " .. meta[1] .. " round=" .. meta[2])
            end
        end
        step, round = meta[1], meta[2]
        if meta[3] and not finished then
            finished = true
            report("PASS authoritative arrivals and floor cleanup")
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
