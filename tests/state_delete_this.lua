-- Drive the public LANBOT with normal movement, shooting and item-button input.
-- Optional route mode accelerates room selection/combat; it is reported as such.
local native = assert(_IsaacLan)
local bridge = assert(_IsaacLanModules["api/public"])
local config = assert(_IsaacLanTest.deleteThis)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local Phase = native.net_phases()
local fields, schema = _IsaacLanModules["sync/fields"], _IsaacLanModules["sync/world_schema"]
local Actor, Entity, Inventory, Item, Location =
    fields.actor, fields.entity, fields.inventory, fields.item, fields.location
local baseFrame, baseGate, baseInput = _IsaacLanFrame, native.net_gate, native.input_bot
local owner = { Name = "Challenge 45 acceptance" }
local renders, linked, chosen, started, botStarted, won, complete =
    0, false, false, false, false, false, false
local baseline, floorKey, floorAt = nil, nil, 0
local snapshots, moveInputs, shootInputs, generatedPickups, negativeUses = 0, 0, 0, 0, 0
local floors, rooms, inventorySeen, bosses = {}, {}, {}, {}
local selectedChecked = {}
local routeEpoch, clearAt, advanced
local lastStage, lastStageType, exited, trophySeen
local itemButton, confirmButton = 0x0100, 0x1000
local function report(text)
    Isaac.DebugString("LAN_NETWORK CHALLENGE45 " .. text)
end
local function bot(command)
    local previous, response = Isaac.ConsoleOutput, ""
    Isaac.ConsoleOutput = function(text)
        response = response .. text
    end
    local ok, message = pcall(_IsaacLanBotCommand, command)
    Isaac.ConsoleOutput = previous
    assert(ok, message)
    if response:find("error=", 1, true) then
        assert(command == "next" and response:find("error=no_known_exit", 1, true), response)
        return false
    end
    if command == "status" then
        report(response:gsub("\n", " "))
    end
    return true
end
native.input_bot = function(active, buttons)
    if active == 1 then
        moveInputs = moveInputs + ((buttons & 15) ~= 0 and 1 or 0)
        shootInputs = shootInputs + ((buttons & 240) ~= 0 and 1 or 0)
    end
    return baseInput(active, buttons)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end))
end
local function observe(t)
    local info = native.api_info()
    if not native.rooms_ready() or info.ready ~= 1 or won then
        return
    end
    assert(info.challenge == 1006 and Game().Challenge == 0)
    local level = Game():GetLevel()
    local key = info.worldEpoch .. ":" .. level:GetStage() .. ":" .. level:GetStageType()
    if key ~= floorKey then
        floorKey, floorAt = key, t
        floors[level:GetStage()] = true
        report("FLOOR key=" .. key .. " rooms=" .. level:GetRooms().Size)
    end
    for slot = 0, info.players - 1 do
        actor(slot, function(p, room)
            if not selectedChecked[slot] then
                assert(
                    p:GetPlayerType() == config.characters[slot + 1],
                    "Challenge replaced a selected character"
                )
                assert(
                    p:HasCollectible(CollectibleType.COLLECTIBLE_TMTRAINER),
                    "Missing starting TMTRAINER"
                )
                selectedChecked[slot] = true
            end
            local roomKey = key .. ":" .. slot .. ":" .. level:GetCurrentRoomIndex()
            if not rooms[roomKey] then
                rooms[roomKey] = true
                report(
                    "ROOM slot="
                        .. slot
                        .. " stage="
                        .. level:GetStage()
                        .. " index="
                        .. level:GetCurrentRoomIndex()
                        .. " backdrop="
                        .. room:GetBackdropType()
                )
            end
            if config.mode == "route" and not p:IsDead() then
                p:AddSoulHearts(math.max(0, 24 - p:GetSoulHearts()))
                if not p:HasCollectible(CollectibleType.COLLECTIBLE_SPOON_BENDER) then
                    p:AddCollectible(CollectibleType.COLLECTIBLE_SPOON_BENDER)
                end
            end
            for id = -1, -#native.generated_items() / 4, -1 do
                local count = assert(native.generated_item_count(p:GetSprite(), id))
                local signature = slot .. ":" .. id
                if count > 0 and not inventorySeen[signature] then
                    inventorySeen[signature] = true
                    generatedPickups = generatedPickups + 1
                    report("GENERATED_PICKUP slot=" .. slot .. " id=" .. id .. " count=" .. count)
                end
            end
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:ToNPC() and e:IsBoss() then
                    bosses[level:GetStage() .. ":" .. e.Type .. ":" .. e.Variant] = true
                end
                if
                    level:GetStage() == LevelStage.STAGE6
                    and e.Type == EntityType.ENTITY_PICKUP
                    and e.Variant == PickupVariant.PICKUP_TROPHY
                then
                    trophySeen = true
                end
            end
        end)
    end
    if config.mode == "route" and t - floorAt > 90 and t % 60 == 0 then
        local target
        local list = level:GetRooms()
        for i = 0, list.Size - 1 do
            local d = list:Get(i)
            if d.Data and d.Data.Type == RoomType.ROOM_BOSS and d.SafeGridIndex >= 0 then
                target = d.SafeGridIndex
            end
        end
        assert(target, "No generated Boss room")
        local positions = native.rooms_positions()
        for slot = 0, info.players - 1 do
            if positions[tostring(slot)].index ~= target then
                assert(native.rooms_move(slot, target, 0, -1))
                report("ASSISTED_BOSS_ENTRY stage=" .. level:GetStage() .. " slot=" .. slot)
            end
        end
    end
end
local function routeBot()
    if config.mode ~= "route" or not bridge.ready() then
        return
    end
    local epoch = native.api_info().worldEpoch
    if routeEpoch ~= epoch then
        routeEpoch, clearAt, advanced = epoch, nil, false
        bot("mode hold")
    end
    bridge.withView(function()
        local room = Game():GetRoom()
        if room:GetType() == RoomType.ROOM_BOSS and room:IsClear() then
            if not clearAt then
                clearAt = renders
                bot("mode run")
            end
            -- Give ordinary pickup collision time to acquire the native reward
            -- before requesting the known exit through the public bot command.
            if not advanced and renders - clearAt > 360 then
                advanced = bot("next")
                if advanced then
                    report("BOT_NATIVE_EXIT_REQUEST stage=" .. Game():GetLevel():GetStage())
                end
            end
        end
    end)
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
    if host and config.mode == "route" and tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer() then
        tear.CollisionDamage = math.max(tear.CollisionDamage, 50)
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_ITEM, function(_, id)
    if id < 0 then
        negativeUses = negativeUses + 1
        report("GENERATED_USE id=" .. id)
    end
end)
local function validateCompletion()
    assert(not won and lastStage == LevelStage.STAGE6)
    assert(lastStageType == StageType.STAGETYPE_WOTL)
    assert(exited, "Native challenge exit callback was not observed")
    assert(moveInputs > 100 and shootInputs > 100)
    if host then
        for _, stage in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 10, 11 }) do
            assert(floors[stage], "Skipped floor " .. stage)
        end
        assert(bosses["11:102:1"], "The native ??? boss was never observed")
        assert(generatedPickups > 0, "No generated item was actually acquired")
        assert(trophySeen, "No native challenge trophy was observed")
    else
        assert(snapshots > 100, "Replica missed challenge snapshots")
    end
    report(
        "WIN mode="
            .. config.mode
            .. " snapshots="
            .. snapshots
            .. " pickups="
            .. generatedPickups
            .. " active_uses="
            .. negativeUses
    )
    won = true
end
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    exited = true
    report("NATIVE_EXIT")
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_END, function(_, gameOver)
    assert(not gameOver, "Challenge 45 ended in a loss")
end)
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        capture,
        function(t, n, bytes)
            before(t, n, bytes)
            observe(t)
        end,
        collect,
        function(bytes, tick, ack, between, stable)
            if restore(bytes, tick, ack, between, stable) == false then
                return false
            end
            local view = schema.unpack(_IsaacLanState.decode(bytes, stable), tick)
            assert(native.generated_items() == view.glitched, "Generated definitions diverged")
            for _, value in ipairs(view.actors) do
                local p = Isaac.GetPlayer(value[Actor.index])
                for _, field in ipairs({
                    { "Damage", 1 },
                    { "MaxFireDelay", 2 },
                    { "ShotSpeed", 4 },
                    { "MoveSpeed", 5 },
                    { "Luck", 6 },
                    { "TearRange", 9 },
                }) do
                    local expected = value[Actor.entity][Entity.typed][field[2]]
                    assert(
                        math.abs(p[field[1]] - expected)
                            <= 0.00001 * math.max(1, math.abs(expected)),
                        "Replica attribute differs: " .. field[1]
                    )
                end
                for _, item in ipairs(value[Actor.inventory][Inventory.items]) do
                    local count = item[Item.id] < 0
                            and native.generated_item_count(p:GetSprite(), item[Item.id])
                        or p:GetCollectibleNum(item[Item.id], true)
                    assert(count == item[Item.count], "Replica inventory differs")
                end
            end
            local positions = native.rooms_positions()
            for _, location in ipairs(view.locations) do
                local actual = assert(positions[tostring(location[Location.slot])])
                assert(
                    actual.index == location[Location.index]
                        and actual.dimension == location[Location.dimension],
                    "Replica room differs"
                )
            end
            snapshots = snapshots + 1
            if snapshots % 300 == 0 then
                report("SYNC snapshots=" .. snapshots .. " definitions=" .. #view.glitched / 4)
            end
            return true
        end,
        present,
        beginFloor
    )
end
function _IsaacLanFrame()
    renders = renders + 1
    local status = baseFrame()
    assert(status.phase ~= Phase.failed and status.phase ~= Phase.waiting, status.error)
    local confirm = won and status.scene == 3
    native.test_gamepad(
        confirm and renders % 30 < 5 and confirmButton
            or started and not won and renders % 300 == 0 and itemButton
            or 0
    )
    if not baseline and status.scene == 1 then
        baseline = native.net_progress()
    end
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "localhost:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if status.phase == Phase.lobby and not started then
        if host and status.challenge ~= 1006 then
            _IsaacLanCommand("challenge", "1006")
        elseif status.challenge == 1006 and not chosen then
            _IsaacLanCommand("choose", config.characters[host and 1 or 2] .. ":1")
            chosen = true
        end
        if
            host
            and status.challenge == 1006
            and status.players == 2
            and status.ready0 == 1
            and status.ready1 == 1
        then
            _IsaacLanCommand(
                "start",
                config.seed .. ":0:" .. table.concat(config.characters, ":") .. ":0:0"
            )
        end
    end
    if status.phase == Phase.running and native.api_info().ready == 1 and not won then
        started = true
        lastStage, lastStageType = Game():GetLevel():GetStage(), Game():GetLevel():GetStageType()
        if not botStarted then
            bot(config.mode == "route" and "mode hold" or "mode run")
            bot("style " .. config.style)
            bot("on")
            botStarted = true
            report("START mode=" .. config.mode)
        end
        routeBot()
        if renders % 300 == 0 then
            bot("status")
        end
    end
    if started and status.scene == 1 and not status.prepared and not complete then
        validateCompletion()
        local progress = native.net_progress()
        for i = 2, 643 do
            assert(
                baseline:byte(i) == 0 or progress:byte(i) == 1,
                "Challenge discarded a personal unlock"
            )
        end
        assert(
            _IsaacLanTestProgress.privateCounter(progress)
                == _IsaacLanTestProgress.privateCounter(baseline),
            "Challenge replaced a private progress counter"
        )
        complete = true
        report(
            "PASS completion, synchronization and personal progress restoration mode="
                .. config.mode
        )
    end
    return status
end
return {
    done = function()
        return complete
    end,
    cleanup = function()
        bot("off")
        native.input_bot = baseInput
        _IsaacLanFrame, native.net_gate = baseFrame, baseGate
    end,
}
