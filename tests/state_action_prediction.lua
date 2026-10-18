-- Normal guest input through delayed transport, including item action locks.
local native, json = assert(_IsaacLan), require("json")
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local Phase = native.net_phases()
local cases = {
    { name = "active", item = CollectibleType.COLLECTIBLE_BOOK_OF_REVELATIONS },
    { name = "card", card = Card.CARD_HANGED_MAN },
    { name = "pill", pill = PillEffect.PILLEFFECT_LUCK_UP, reaction = "Happy" },
    { name = "bad-pill", pill = PillEffect.PILLEFFECT_LUCK_DOWN, reaction = "Sad" },
    {
        name = "collectible",
        pickup = PickupVariant.PICKUP_COLLECTIBLE,
        id = CollectibleType.COLLECTIBLE_BREAKFAST,
    },
    {
        name = "trinket",
        pickup = PickupVariant.PICKUP_TRINKET,
        id = TrinketType.TRINKET_SWALLOWED_PENNY,
    },
    { name = "card-pickup", pickup = PickupVariant.PICKUP_TAROTCARD, id = Card.CARD_STRENGTH },
    { name = "pill-pickup", pickup = PickupVariant.PICKUP_PILL },
    { name = "candle", item = CollectibleType.COLLECTIBLE_CANDLE, held = true },
    { name = "red-candle", item = CollectibleType.COLLECTIBLE_RED_CANDLE, held = true },
    { name = "bobs-head", item = CollectibleType.COLLECTIBLE_BOBS_ROTTEN_HEAD, held = true },
    { name = "crafting-bag", item = CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING, held = true },
}
local firstTick, duration, actionTick = 60, 150, 30
local settleTicks, tailTicks, directionTicks = 20, 10, 20
local minimumActionFrames, maximumFrozenFraction = 15, 0.2
local minimumJumpDistance, maximumWalkStepRatio = 8, 2.5
local owner = { Name = "Isolated guest action prediction" }
local renders, linked, chosen, finished, verified = 0, false, false, false, 0
local frame, gate = _IsaacLanFrame, native.net_gate
Isaac.DebugString(
    "LAN_ACTION_FRAME render,tick,case,phase,x,y,vx,vy,enabled,controls,finished,body,extra,extra_frame,input_x,input_y"
)
local observed, used, prepared, metrics, holding = {}, {}, {}, {}, {}
local previous
local function report(message)
    Isaac.DebugString("LAN_NETWORK ACTION_PREDICTION " .. message)
end
local function phase(tick)
    local offset = tick - firstTick
    if offset < 0 then
        return nil, offset
    end
    return cases[math.floor(offset / duration) + 1], offset % duration
end
local function guest(fn)
    assert(native.rooms_with_player(1, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()["1"])))
    end))
end
local function record(player, index, case, at)
    local extra = assert(native.actor_sprites(index, player:GetSprite()))[1]
    local animation = extra:GetAnimation()
    local body = player:GetSprite():GetAnimation()
    local pose = animation ~= "" and animation or body
    observed[case.name] = observed[case.name] or {}
    observed[case.name][pose] = (observed[case.name][pose] or 0) + 1
    if not host then
        holding[case.name] = animation == "LiftItem"
        local now, position = Isaac.GetTime(), player.Position
        local metric = metrics[case.name]
            or { actionFrames = 0, frozen = 0, maxStep = 0, jumps = 0 }
        metrics[case.name] = metric
        if
            previous
            and previous.case == case.name
            and at > settleTicks
            and at < duration - tailTicks
        then
            local distance = (position - previous.position):Length()
            local dt = math.max(0, math.min((now - previous.at) / 1000, 0.05))
            metric.maxStep = math.max(metric.maxStep, distance)
            if
                distance
                > math.max(
                    minimumJumpDistance,
                    player.MoveSpeed * 4.4117647 * 60 * dt * maximumWalkStepRatio
                )
            then
                metric.jumps = metric.jumps + 1
            end
            if not player:IsExtraAnimationFinished() and previous.pose == pose then
                metric.actionFrames = metric.actionFrames + 1
                if distance < 0.05 then
                    metric.frozen = metric.frozen + 1
                end
            end
        end
        previous = { case = case.name, at = now, position = position, pose = pose }
    end
    local input = player:GetMovementInput()
    Isaac.DebugString(
        string.format(
            "LAN_ACTION_FRAME %d,%d,%s,%d,%.6f,%.6f,%.6f,%.6f,%s,%s,%s,%s,%s,%d,%.4f,%.4f",
            renders,
            verified,
            case.name,
            at,
            player.Position.X,
            player.Position.Y,
            player.Velocity.X,
            player.Velocity.Y,
            tostring(player.ControlsEnabled),
            tostring(player:AreControlsEnabled()),
            tostring(player:IsExtraAnimationFinished()),
            body,
            animation,
            extra:GetFrame(),
            input.X,
            input.Y
        )
    )
end
local function usedItem(kind, id, player)
    assert(host, "Guest executed an authoritative use callback")
    local case = phase(verified)
    if case and player and player.ControllerIndex == 2 then
        assert(id == (case.item or case.card or case.pill), "Unexpected item used in " .. case.name)
        used[case.name] = (used[case.name] or 0) + 1
        report("USE " .. case.name .. " " .. kind)
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_USE_ITEM, function(_, id, _, player)
    usedItem("active", id, player)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_CARD, function(_, id, player)
    usedItem("card", id, player)
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_PILL, function(_, id, player)
    usedItem("pill", id, player)
end)
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    verified = status.verified
    assert(status.phase ~= Phase.failed and status.phase ~= Phase.waiting, status.error)
    if status.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == Phase.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    local case, at = phase(verified)
    local buttons, active = 0, 0
    if not host and status.prepared and case then
        buttons = at % (2 * directionTicks) < directionTicks and 8 or 4
        local press = at >= actionTick and at < actionTick + 6
            or case.held and at >= 90 and at < 96
            or case.held and at >= 120 and at < 126 and holding[case.name]
        if press and case.item then
            active = 255
        elseif press and (case.card or case.pill) then
            buttons = buttons | 0x0200
        end
    end
    native.test_gamepad(buttons, active)
    if verified >= firstTick + #cases * duration and not finished then
        if host then
            for _, case in ipairs(cases) do
                assert(prepared[case.name], "Missing action fixture: " .. case.name)
                assert(case.pickup or used[case.name], "Normal input did not use " .. case.name)
            end
        end
        for _, case in ipairs(cases) do
            local expected = case.held and "LiftItem"
                or case.reaction
                or case.pickup == PickupVariant.PICKUP_COLLECTIBLE and "Pickup"
                or case.pickup == PickupVariant.PICKUP_TRINKET and "Pickup"
                or "UseItem"
            assert(
                observed[case.name] and observed[case.name][expected],
                "Missing action pose: " .. case.name .. "/" .. expected
            )
        end
        report("OBSERVED " .. json.encode(observed))
        report("USES " .. json.encode(used))
        report("METRICS " .. json.encode(metrics))
        if not host then
            for _, case in ipairs(cases) do
                local metric = assert(metrics[case.name])
                assert(
                    metric.actionFrames >= minimumActionFrames,
                    "Insufficient action motion samples: " .. case.name
                )
                assert(
                    metric.frozen <= metric.actionFrames * maximumFrozenFraction,
                    "Prediction stopped between snapshots: " .. case.name
                )
                assert(metric.jumps == 0, "Action caused a position jump: " .. case.name)
            end
        end
        finished = true
        report("PASS guest actions, native results and continuous movement")
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(tick, count, bytes)
        before(tick, count, bytes)
        local case, at = phase(tick)
        if tick == 0 then
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type ~= EntityType.ENTITY_PLAYER then
                    entity:Remove()
                end
            end
            local room = Game():GetRoom()
            for index = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(index)
                if
                    grid
                    and grid:GetType() ~= GridEntityType.GRID_DOOR
                    and room:GetGridCollision(index) ~= GridCollisionClass.COLLISION_WALL
                then
                    room:RemoveGridEntity(index, 0, false)
                end
            end
            room:SetClear(true)
        end
        if case and at == 0 then
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type ~= EntityType.ENTITY_PLAYER then
                    entity:Remove()
                end
            end
            Isaac.GetPlayer(0).Position, Isaac.GetPlayer(0).Velocity = Vector(100, 100), Vector.Zero
            guest(function(player)
                player:StopExtraAnimation()
                player.Position, player.Velocity = Vector(260, 240), Vector.Zero
                player:SetMinDamageCooldown(10000)
                player:SetCard(0, 0)
                player:SetPill(0, 0)
                local activeItem = player:GetActiveItem()
                if activeItem ~= 0 then
                    player:RemoveCollectible(activeItem)
                end
                if case.item then
                    player:AddCollectible(case.item, 12, false)
                    player:SetActiveCharge(12)
                end
                if case.card then
                    player:SetCard(0, case.card)
                    assert(player:GetCard(0) == case.card, "Card prerequisite missing")
                elseif case.pill then
                    local pool = Game():GetItemPool()
                    local color = pool:ForceAddPillEffect(case.pill)
                    assert(
                        pool:GetPillEffect(color, player) == case.pill,
                        "Pill prerequisite missing"
                    )
                    player:SetPill(0, color)
                end
                prepared[case.name] = true
                report("BEGIN " .. case.name)
            end)
        end
        if case and case.pickup and at == actionTick then
            guest(function(player)
                local id = case.id
                    or Game():GetItemPool():ForceAddPillEffect(PillEffect.PILLEFFECT_LUCK_UP)
                local pickup = Isaac.Spawn(
                    EntityType.ENTITY_PICKUP,
                    case.pickup,
                    id,
                    player.Position,
                    Vector.Zero,
                    nil
                ):ToPickup()
                pickup.Wait = 0
                pickup.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
            end)
        end
        if case and case.held and at == 145 then
            guest(function(player)
                assert(
                    player:GetItemState() == 0,
                    "Held item leaked into the next action: " .. case.name
                )
                report("LOWERED " .. case.name)
            end)
        end
        if case and case.pickup and at == 110 then
            guest(function(player)
                local acquired = case.pickup == PickupVariant.PICKUP_COLLECTIBLE
                        and player:HasCollectible(case.id)
                    or case.pickup == PickupVariant.PICKUP_TRINKET and player:HasTrinket(case.id)
                    or case.pickup == PickupVariant.PICKUP_TAROTCARD and player:GetCard(0) == case.id
                    or case.pickup == PickupVariant.PICKUP_PILL and player:GetPill(0) ~= 0
                assert(acquired, "Native pickup did not complete: " .. case.name)
                report("ACQUIRED " .. case.name)
            end)
        end
        if case then
            guest(function(player)
                record(player, native.rooms_heads()["1"], case, at)
            end)
        end
    end, collect, restore, present, beginFloor)
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_RENDER, function()
    if host or finished or not _IsaacLanStatus().prepared or not native.rooms_ready() then
        return
    end
    local case, at = phase(verified)
    if not case then
        return
    end
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player.ControllerIndex == 2 then
            record(player, index, case, at)
            break
        end
    end
end)
return {
    done = function()
        return finished
    end,
    cleanup = function()
        native.test_gamepad(0)
    end,
}
