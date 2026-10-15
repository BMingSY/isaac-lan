-- Native deal getters, split-room modifiers, real damage and boss-clear doors.
local native, host, port = assert(_IsaacLan), _IsaacLanTest.host, _IsaacLanTest.port
local linked, chosen, finished, renders, snapshots = false, false, false, 0, 0
local step, stepAt, action = "start", 0, 1
local origin, boss, baseline, previous, angelBaseline
local owner = RegisterMod("Isaac LAN shared deals fixture", 1)
local function report(value)
    Isaac.DebugString("LAN_NETWORK SHARED_DEALS " .. value)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function find(kind)
    local rooms = Game():GetLevel():GetRooms()
    for index = 0, rooms.Size - 1 do
        local room = rooms:Get(index)
        if room.Data and room.Data.Type == kind and room.SafeGridIndex >= 0 then
            return room.SafeGridIndex
        end
    end
end
local function move(slot, index)
    assert(native.rooms_move(slot, index, 0, -1))
end
local function nextFloor(stage)
    Game():GetLevel():SetStage(stage, 0)
    Game():StartStageTransition(true, 0, Isaac.GetPlayer(assert(native.rooms_heads()["1"])))
end
local function item(slot, id, add)
    actor(slot, function(player)
        if add then
            player:AddCollectible(id)
        else
            player:RemoveCollectible(id)
        end
    end)
end
local function equal(a, b)
    return math.abs(a - b) < 0.00001
end
local function check(name)
    local total, angel = native.deal_chances()
    for slot = 0, 1 do
        actor(slot, function()
            local scopedTotal, scopedAngel = native.deal_chances()
            assert(
                equal(total, scopedTotal) and equal(angel, scopedAngel),
                "Split-room deal chances differ: " .. name
            )
            assert(
                equal(Game():GetRoom():GetDevilRoomChance(), total),
                "Public/native total differs"
            )
        end)
    end
    report("CHECK " .. name .. " total=" .. total .. " angel=" .. angel)
    return total, angel
end
local function damage(slot)
    local accepted = false
    actor(slot, function(player)
        local hearts = player:GetHearts()
        -- Act of Contrition leaves its granted eternal heart after removal.
        -- Remove that fixture side effect before measuring red-heart loss.
        if player:GetEternalHearts() > 0 or player:GetSoulHearts() > 0 then
            report(
                "FIXTURE_HEARTS eternal="
                    .. player:GetEternalHearts()
                    .. " soul="
                    .. player:GetSoulHearts()
            )
        end
        player:AddEternalHearts(-player:GetEternalHearts())
        player:AddSoulHearts(-player:GetSoulHearts())
        player:TakeDamage(1, 0, EntityRef(nil), 0)
        accepted = player:GetHearts() < hearts
        if accepted then
            report("DAMAGE slot=" .. slot .. " hearts=" .. hearts .. "->" .. player:GetHearts())
        end
    end)
    -- Room arrival intentionally grants native protection. Wait for it rather
    -- than bypassing invulnerability or aborting a valid room transfer.
    return accepted
end
local function dealHistory(spawned, visited)
    local game = Game()
    game:SetStateFlag(GameStateFlag.STATE_DEVILROOM_SPAWNED, spawned)
    game:SetStateFlag(GameStateFlag.STATE_DEVILROOM_VISITED, visited)
    game:SetStateFlag(GameStateFlag.STATE_FAMINE_SPAWNED, false)
end
local function clearBoss()
    actor(0, function()
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity:IsActiveEnemy(false) then
                entity:Kill()
            end
        end
    end)
end
local function door(kind)
    local found, clear = false, false
    actor(0, function()
        clear = Game():GetRoom():IsClear()
        for slot = 0, 7 do
            local value = Game():GetRoom():GetDoor(slot)
            found = found or value and value.TargetRoomType == kind
        end
    end)
    if clear and found then
        report("DOOR type=" .. kind .. " boss=" .. boss)
        return true
    end
    return false
end
local freezeCallback = function(_, npc)
    if host and not finished and npc.HitPoints > 0 then
        return true
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_NPC_UPDATE, freezeCallback)
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
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
    native.test_gamepad(0)
    return status
end
local c = CollectibleType
local actions = {
    function()
        baseline = check("baseline")
    end,
    function()
        item(1, c.COLLECTIBLE_PENTAGRAM, true)
    end,
    function()
        previous = check("remote Pentagram")
        assert(previous > baseline)
    end,
    function()
        item(0, c.COLLECTIBLE_PENTAGRAM, true)
    end,
    function()
        assert(check("two Pentagrams") > previous)
    end,
    function()
        item(0, c.COLLECTIBLE_PENTAGRAM, false)
        item(1, c.COLLECTIBLE_PENTAGRAM, false)
    end,
    function()
        assert(equal(check("removed modifiers"), baseline))
        return damage(1)
    end,
    function()
        previous = check("remote ordinary-room red-heart damage")
        assert(previous < baseline)
    end,
    function()
        item(1, c.COLLECTIBLE_ACT_OF_CONTRITION, true)
    end,
    function()
        assert(check("remote Act of Contrition") > previous)
    end,
    function()
        item(1, c.COLLECTIBLE_ACT_OF_CONTRITION, false)
        move(1, boss)
        move(0, origin)
    end,
    function()
        return damage(1)
    end,
    function()
        assert(check("remote boss-room red-heart damage") < previous)
    end,
    function()
        dealHistory(true, true)
        _, angelBaseline = check("shared deal history")
    end,
    function()
        item(1, c.COLLECTIBLE_KEY_PIECE_1, true)
    end,
    function()
        local _, angel = check("remote Key Piece")
        assert(angel > angelBaseline)
        previous = angel
    end,
    function()
        item(0, c.COLLECTIBLE_KEY_PIECE_1, true)
    end,
    function()
        local _, angel = check("duplicate Key Piece")
        assert(equal(angel, previous))
    end,
    function()
        item(0, c.COLLECTIBLE_KEY_PIECE_1, false)
        item(1, c.COLLECTIBLE_KEY_PIECE_1, false)
        item(1, c.COLLECTIBLE_BOOK_OF_VIRTUES, true)
    end,
    function()
        _, previous = check("remote Book of Virtues")
        assert(previous > angelBaseline)
    end,
    function()
        Game():GetLevel():AddAngelRoomChance(-0.2)
    end,
    function()
        local _, angel = check("negative Angel modifier")
        assert(angel < previous)
    end,
    function()
        Game():GetLevel():AddAngelRoomChance(0.2)
        item(1, c.COLLECTIBLE_BOOK_OF_VIRTUES, false)
        Game():AddDevilRoomDeal()
    end,
    function()
        local _, angel = check("shared taken Devil deal")
        assert(angel == 0)
    end,
    function()
        Game():GetLevel():AddAngelRoomChance(0.5)
    end,
    function()
        local _, angel = check("positive Angel modifier")
        assert(angel > 0)
    end,
    function()
        Game():GetLevel():AddAngelRoomChance(-0.5)
        dealHistory(false, false)
        item(1, c.COLLECTIBLE_GOAT_HEAD, true)
        move(1, origin)
        move(0, boss)
    end,
    function()
        previous = check("remote Goat Head")
        assert(previous > 1)
    end,
    function()
        item(0, c.COLLECTIBLE_GOAT_HEAD, true)
    end,
    function()
        assert(equal(check("duplicate Goat Head"), previous))
        item(0, c.COLLECTIBLE_GOAT_HEAD, false)
        clearBoss()
    end,
    function()
        if not door(RoomType.ROOM_DEVIL) then
            return false
        end
        item(1, c.COLLECTIBLE_EUCHARIST, true)
        step = "angel-floor"
        nextFloor(3)
    end,
}
local function advance(tick)
    if finished then
        return
    end
    local level = Game():GetLevel()
    if native.rooms_ready() and step ~= "start" and step ~= "floor" and step ~= "angel-floor" then
        for slot = 0, 1 do
            actor(slot, function(player)
                player.Position, player.Velocity =
                    Game():GetRoom():GetTopLeftPos() + Vector(60, 60), Vector.Zero
            end)
        end
    end
    if step == "start" and tick >= 30 then
        step, stepAt = "floor", tick
        nextFloor(2)
    elseif
        (
            step == "floor" and level:GetStage() == 2
            or step == "angel-floor" and level:GetStage() == 3
        ) and native.rooms_ready()
    then
        origin, boss = level:GetCurrentRoomIndex(), assert(find(RoomType.ROOM_BOSS))
        for slot = 0, 1 do
            actor(slot, function(player)
                player:AddMaxHearts(24)
                player:AddHearts(24)
                player:AddSoulHearts(-player:GetSoulHearts())
                player.Position, player.Velocity =
                    Game():GetRoom():GetTopLeftPos() + Vector(60, 60), Vector.Zero
            end)
        end
        move(0, boss)
        step, stepAt = step == "floor" and "modifiers" or "angel-clear", tick
    elseif step == "modifiers" and tick - stepAt >= 40 then
        if actions[action]() ~= false then
            action, stepAt = action + 1, tick
        end
    elseif step == "angel-clear" and tick - stepAt >= 40 then
        local _, angel = check("remote Eucharist after floor change")
        assert(angel == 1)
        clearBoss()
        step, stepAt = "angel-door", tick
    elseif step == "angel-door" and tick - stepAt >= 80 then
        if door(RoomType.ROOM_ANGEL) then
            finished = true
            report("PASS shared probabilities, native damage and generated Devil/Angel doors")
        end
    end
    assert(tick - stepAt < 900, "Shared deals stalled at " .. step)
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        advance(t)
    end, function(slot, t)
        local body = collect(slot, t)
        if not body then
            return body
        end
        return string.pack(">s4", body) .. _IsaacLanState.encode({ step, finished })
    end, function(bytes, tick, ack, betweenUpdates)
        local body, pos = string.unpack(">s4", bytes)
        if restore(body, tick, ack, betweenUpdates) == false then
            return false
        end
        local value = _IsaacLanState.decode(body)
        local total, angel = native.deal_chances()
        assert(
            equal(total, value[19][1]) and equal(angel, value[19][2]),
            "Replica retained local deal chances"
        )
        assert(
            equal(Game():GetRoom():GetDevilRoomChance(), total),
            "Replica public deal getter bypassed authority"
        )
        snapshots = snapshots + 1
        local meta = _IsaacLanState.decode(bytes:sub(pos))
        if meta[1] ~= step then
            step = meta[1]
            report("REPLICA_STEP " .. step)
        end
        if meta[2] and not finished then
            assert(snapshots > 100)
            finished = true
            report("PASS shared probabilities, native damage and generated Devil/Angel doors")
        end
        return true
    end, present, beginFloor)
end
