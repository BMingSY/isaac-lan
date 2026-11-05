-- Real input and authoritative state under an externally configured transport relay.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local Phase = native.net_phases()
local A, E, I, R = fields.actor, fields.entity, fields.inventory, fields.resources
local frame, gate = _IsaacLanFrame, native.net_gate
local owner = { Name = "Isolated weak-network regression" }
local item = CollectibleType.COLLECTIBLE_BOOK_OF_REVELATIONS
local actionCount, finishTick, stopTick = 8, 1500, 1200
local combatStart, combatEnd = 300, 900
local renders, activeFrames, used, sent, confirmed, samples = 0, 0, 0, 0, 0, 0
local linked, chosen, finished = false, false, false
local nextAction, releaseAt, previousTick, verified = 120, 0, -1, -1
local lastAuthority, settled = nil, 0
local sourceRoom
local enemies, combatSamples = {}, 0
local function report(message)
    Isaac.DebugString("LAN_NETWORK WEAK_NET " .. message)
end
local function guest(fn)
    assert(native.rooms_with_player(1, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()["1"])))
    end))
end
Isaac.AddCallback(owner, ModCallbacks.MC_USE_ITEM, function(_, id, _, player)
    assert(host, "Replica executed an authoritative item callback")
    if player.ControllerIndex == 2 then
        assert(id == item, "Unexpected item callback")
        used = used + 1
        assert(used <= actionCount, "A queued active-item press repeated")
        player:AddCoins(used - player:GetNumCoins())
        report("USE count=" .. used)
    end
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
    local buttons, active = 0, 0
    if not host and status.prepared and verified >= 30 then
        activeFrames = activeFrames + 1
        if verified < stopTick then
            buttons = activeFrames % 80 < 40 and 8 or 4
        end
        if sent < actionCount and confirmed == sent and activeFrames >= nextAction then
            sent = sent + 1
            releaseAt = activeFrames + 2
            nextAction = activeFrames + 120
            report("PRESS count=" .. sent)
        end
        active = activeFrames < releaseAt and 255 or 0
    end
    native.test_gamepad(buttons, active)
    if verified >= finishTick and not finished then
        if host then
            assert(used == actionCount, "An active-item press was lost")
        else
            assert(
                sent == actionCount and confirmed == actionCount,
                "Action results did not converge"
            )
            assert(samples > 100 and settled > 20, "Insufficient state and stopped-motion coverage")
            assert(combatSamples > 50, "Insufficient weak-network combat delivery coverage")
        end
        finished = true
        report("PASS actions exactly once, state consistency and recovery")
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(tick, count, bytes)
        before(tick, count, bytes)
        if tick == 0 then
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
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type ~= EntityType.ENTITY_PLAYER then
                    entity:Remove()
                end
            end
            room:SetClear(true)
            -- Delayed direction changes can drift into an open door. Keep the
            -- measurement workload in this room instead of spawning enemies
            -- partway through a bandwidth comparison.
            for _, x in ipairs({ 80, 560 }) do
                for y = 240, 320, 40 do
                    room:SpawnGridEntity(
                        room:GetGridIndex(Vector(x, y)),
                        GridEntityType.GRID_ROCK,
                        0,
                        1,
                        0
                    )
                end
            end
            guest(function(player)
                sourceRoom = Game():GetLevel():GetCurrentRoomIndex()
                player:AddCollectible(item, 6, false)
                player:AddCoins(-player:GetNumCoins())
                player.Position, player.Velocity = Vector(300, 280), Vector.Zero
                player:SetMinDamageCooldown(10000)
                player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
            end)
            Isaac.GetPlayer(0).Position, Isaac.GetPlayer(0).Velocity = Vector(100, 100), Vector.Zero
            Isaac.GetPlayer(0):SetMinDamageCooldown(10000)
        end
        if tick == combatStart then
            -- Fixed native workload across candidate builds; actual AI and
            -- projectiles keep the transport comparison representative.
            for index, position in ipairs({
                Vector(220, 160),
                Vector(420, 160),
                Vector(220, 380),
                Vector(420, 380),
            }) do
                local kind = index <= 2 and EntityType.ENTITY_HORF or EntityType.ENTITY_ATTACKFLY
                local enemy = Isaac.Spawn(kind, 0, 0, position, Vector.Zero, nil):ToNPC()
                enemy.MaxHitPoints, enemy.HitPoints = 10000, 10000
                enemies[#enemies + 1] = enemy
            end
            report("LOAD combat")
        elseif tick == combatEnd then
            for _, enemy in ipairs(enemies) do
                if enemy:Exists() then
                    enemy:Remove()
                end
            end
            enemies = {}
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_PROJECTILE then
                    entity:Remove()
                end
            end
            Game():GetRoom():SetClear(true)
            report("LOAD movement")
        end
        guest(function(player)
            assert(
                Game():GetLevel():GetCurrentRoomIndex() == sourceRoom,
                "Weak-network measurement left its fixed workload room"
            )
            player:SetActiveCharge(6)
        end)
    end, function(slot, tick)
        local bytes, stable = collect(slot, tick)
        if slot == 1 then
            report("VIEW tick=" .. tick .. " ms=" .. Isaac.GetTime())
        end
        return bytes, stable
    end, function(bytes, tick, ack, betweenUpdates, stable)
        if restore(bytes, tick, ack, betweenUpdates, stable) == false then
            return false
        end
        local value = worldSchema.unpack(_IsaacLanState.decode(bytes, stable), tick)
        if tick >= combatStart + 30 and tick < combatEnd and tick ~= previousTick then
            local count = 0
            for _, entity in ipairs(value.room[fields.room.entities]) do
                if
                    entity[E.type] == EntityType.ENTITY_HORF
                    or entity[E.type] == EntityType.ENTITY_ATTACKFLY
                then
                    count = count + 1
                end
            end
            assert(count == 4, "Weak-network combat workload changed")
            combatSamples = combatSamples + 1
        end
        for _, actor in ipairs(value.actors) do
            if actor[A.controller] == 2 then
                local player = Isaac.GetPlayer(actor[A.index])
                local position = actor[A.entity][E.position]
                lastAuthority = Vector(position[1], position[2])
                assert(
                    player.Position:Distance(lastAuthority) < 0.05,
                    "Replica position differs after recovery"
                )
                confirmed = actor[A.inventory][I.resources][R.coins]
                assert(confirmed <= sent, "Authoritative use was duplicated")
                assert(player:GetNumCoins() == confirmed, "Inventory differs after recovery")
            end
        end
        if tick ~= previousTick then
            samples = samples + 1
            previousTick = tick
            report("APPLY tick=" .. tick .. " ms=" .. Isaac.GetTime() .. " ack=" .. ack)
        end
    end, present, beginFloor)
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_RENDER, function()
    if host or finished or not lastAuthority or verified < stopTick + 150 then
        return
    end
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player.ControllerIndex == 2 then
            assert(
                player.Position:Distance(lastAuthority) < 0.5,
                "Stopped motion failed to converge"
            )
            settled = settled + 1
        end
    end
end)
return {
    done = function()
        return finished
    end,
    cleanup = function()
        native.test_gamepad(0)
        if host then
            for _, enemy in ipairs(enemies) do
                if enemy:Exists() then
                    enemy:Remove()
                end
            end
        end
    end,
}
