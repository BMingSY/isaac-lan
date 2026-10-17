-- One connection: shared rewards, holder-only inventories, Genesis, generated
-- definitions/effects, then a native save/continue in the same owned processes.
local native = assert(_IsaacLan)
local Phase, Command = native.net_phases(), native.net_commands()
local fields = assert(_IsaacLanModules["sync/fields"])
local schema = assert(_IsaacLanModules["sync/world_schema"])
local Actor, Entity, Inventory, Item = fields.actor, fields.entity, fields.inventory, fields.item
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local success = _IsaacLanTest.passivesOnly
        and "PASS generated passive effects and native continuation"
    or "PASS shared rewards, Genesis, generated effects and native continuation"
local frame = _IsaacLanFrame
local owner = { Name = "Isolated item issue acceptance" }
local linked, chosen, renders, round = false, false, 0, 1
local step, stepAt, origin, other = "prepare", 0
local completed, savedDefinitions = false, nil
local savedInventories, generatedStage
local genesisSlot, genesisPicks, previousCount = 1, 0, 0
local genesisCase = 1
local genesisCases = { { 1, true }, { 0, false }, { 0, true }, { 1, false } }
local retryObserved = false
local genesisOtherInventory
local pickedGenerated, pickedTargets = {}, {}
local function report(message)
    Isaac.DebugString("LAN_NETWORK ISSUE_ITEMS " .. message)
end
local function player(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
local function collectibleCount(p, id)
    return id < 0 and assert(native.generated_item_count(p:GetSprite(), id))
        or p:GetCollectibleNum(id, true)
end
local function inventory(slot)
    local values = {}
    for id = 1, Isaac.GetItemConfig():GetCollectibles().Size - 1 do
        if Isaac.GetItemConfig():GetCollectible(id) then
            local count = player(slot):GetCollectibleNum(id, true)
            if count > 0 then
                values[#values + 1] = id .. "x" .. count
            end
        end
    end
    for id = -1, -#native.generated_items() / 4, -1 do
        local count = collectibleCount(player(slot), id)
        if count > 0 then
            values[#values + 1] = id .. "x" .. count
        end
    end
    for slotIndex = 0, 3 do
        values[#values + 1] = "active" .. slotIndex .. "=" .. player(slot):GetActiveItem(slotIndex)
    end
    return table.concat(values, ",")
end
local function separateRoom(index)
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= index then
            return d.SafeGridIndex
        end
    end
    error("No separate fixture room")
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(player(slot), Game():GetRoom())
    end))
end
local function mark(name, tick)
    step, stepAt = name, tick
    report("STEP " .. name .. " tick=" .. tick)
end
local function clean(slot)
    actor(slot, function(p, room)
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e.Type ~= EntityType.ENTITY_PLAYER then
                e:Remove()
            end
        end
        room:SetClear(true)
        p.Position, p.Velocity = room:GetCenterPos() + Vector(0, 90), Vector.Zero
        p:SetMinDamageCooldown(90)
    end)
end
local function pedestals(slot)
    local result = {}
    actor(slot, function()
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e.Type == 5 and e.Variant == 100 and e.SubType ~= 0 then
                result[#result + 1] = e
            end
        end
    end)
    table.sort(result, function(a, b)
        return a.InitSeed < b.InitSeed
    end)
    return result
end
local function pickGenerated(passive)
    -- A generated active can remove pedestals or teleport the holder. Rebuild
    -- the passive prerequisite in the resulting room instead of treating the
    -- absence of an unused pedestal as a compatibility failure.
    actor(1, function(p)
        if not p:HasCollectible(CollectibleType.COLLECTIBLE_TMTRAINER) then
            p:AddCollectible(CollectibleType.COLLECTIBLE_TMTRAINER, 0, false)
        end
    end)
    for slot = 0, 1 do
        local target
        local function matches(choice)
            local id = choice.SubType
            if id >= 0x80000000 then
                id = id - 0x100000000
            end
            return id < 0
                and (Isaac.GetItemConfig():GetCollectible(id).Type ~= ItemType.ITEM_ACTIVE)
                    == passive,
                id
        end
        for _, choice in ipairs(pedestals(slot)) do
            local match, id = matches(choice)
            if match then
                target = choice
                pickedTargets[slot] = id
                break
            end
        end
        if not target then
            actor(slot, function(_, room)
                for attempt = 1, 64 do
                    local seed = 400003 + (#native.generated_items() / 4 + attempt) * 7919
                    local id =
                        Game():GetItemPool():GetCollectible(ItemPoolType.POOL_TREASURE, false, seed)
                    local choice = Isaac.Spawn(
                        5,
                        100,
                        id,
                        room:FindFreePickupSpawnPosition(room:GetCenterPos(), 0, true),
                        Vector.Zero,
                        nil
                    )
                    local match, actual = matches(choice)
                    report(
                        "GENERATED_REPLACEMENT slot="
                            .. slot
                            .. " seed="
                            .. seed
                            .. " id="
                            .. actual
                    )
                    if match then
                        target, pickedTargets[slot] = choice, actual
                        break
                    end
                    choice:Remove()
                end
            end)
        end
        assert(target, "No generated sample of requested type in room " .. slot)
        report(
            "GENERATED_TARGET slot="
                .. slot
                .. " id="
                .. pickedTargets[slot]
                .. " passive="
                .. tostring(passive)
        )
        actor(slot, function(p)
            p.Position, p.Velocity = target.Position, Vector.Zero
        end)
    end
end
local function spawn(slot, id)
    actor(slot, function(_, room)
        Isaac.Spawn(5, 100, id, room:GetCenterPos() - Vector(70, 0), Vector.Zero, nil)
    end)
end
local function setupGenesis(slot, tick)
    if not player(slot):AreControlsEnabled() or not player(slot):IsExtraAnimationFinished() then
        return
    end
    genesisSlot, genesisPicks = slot, 0
    actor(slot, function(p)
        for _, id in ipairs({ 1, 25, 33 }) do
            p:AddCollectible(id, 0, false)
        end
        p:AddCollectible(622, 0, false)
    end)
    report(
        "GENESIS before case="
            .. genesisCase
            .. " holder="
            .. slot
            .. " p0="
            .. inventory(0)
            .. " p1="
            .. inventory(1)
    )
    genesisOtherInventory = inventory(1 - slot)
    actor(slot, function(p)
        p:UseActiveItem(622, 0)
    end)
    mark("genesis-enter", tick)
end
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function(_, save)
    if round == 1 and step == "save" then
        assert(not host or save, "Host did not save the generated inventory")
        round, renders, linked, chosen = 2, 0, false, false
        report("CONTINUE requested")
    end
end)
function _IsaacLanFrame()
    Options.FoundHUD, Options.ExtraHUDStyle = true, 1
    renders = renders + 1
    local s = frame()
    assert(s.phase ~= Phase.failed and s.phase ~= Phase.waiting, s.error)
    if host and round == 2 and s.pendingSave == 1 then
        if not retryObserved then
            retryObserved = true
            report("SAVE_RETRY_READY")
        end
        if renders % 30 == 0 and native.net_retry_save() then
            report("SAVE_RETRY_OK")
        end
        return s
    end
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "localhost:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if s.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == Phase.lobby and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand(
            round == 2 and "resume" or "start",
            round == 2 and "" or "YV039KQF:0:0:0:0:0"
        )
    end
    native.test_gamepad(0)
    return s
end
local function advance(t)
    if not native.rooms_ready() then
        stepAt = t
        return
    end
    if round == 2 then
        if t >= 90 and not completed then
            assert(
                native.generated_items() == savedDefinitions,
                "Continue changed generated definitions"
            )
            assert(native.rooms_connected() == 3)
            for slot = 0, 1 do
                assert(
                    inventory(slot) == savedInventories[slot],
                    "Continue changed inventory for slot " .. slot
                )
            end
            report("CONTINUE inventory and definitions match")
            completed = true
            report(success)
        end
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
        assert(other and native.rooms_move(1, other, 0, -1))
        if _IsaacLanTest.passivesOnly then
            mark("tm-prepare", t)
            return
        end
        clean(0)
        clean(1)
        actor(1, function(p)
            p:UseActiveItem(577, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
        end)
        mark("damocles", t)
    elseif step == "damocles" and t - stepAt >= 30 then
        assert(not player(0):HasCollectible(656) and player(1):HasCollectible(656))
        spawn(0, 1)
        spawn(1, 1)
        mark("damocles-rewards", t)
    elseif step == "damocles-rewards" and t - stepAt >= 60 then
        assert(
            #pedestals(0) == 2 and #pedestals(1) == 2,
            "Damocles reward did not reach both rooms"
        )
        actor(0, function(p)
            p:ResetDamageCooldown()
            p:TakeDamage(1, 0, EntityRef(p), 0)
        end)
        assert(not player(0):HasCollectible(656), "Non-holder inherited Damocles risk")
        report("DAMOCLES duplicate=2,2 holder=1 damage_owner=0")
        actor(1, function(p)
            p:RemoveCollectible(656, true)
        end)
        clean(0)
        clean(1)
        spawn(0, 1)
        spawn(1, 1)
        mark("damocles-remove", t)
    elseif step == "damocles-remove" and t - stepAt >= 60 then
        assert(#pedestals(0) == 1 and #pedestals(1) == 1, "Damocles reward survived removal")
        clean(0)
        clean(1)
        actor(1, function(p)
            p:AddCollectible(425, 0, false)
        end)
        mark("night-light", t)
        Isaac.DebugString("LAN_NETWORK VISUAL_READY")
    elseif step == "night-light" and t - stepAt >= 120 then
        assert(not player(0):HasCollectible(425) and player(1):HasCollectible(425))
        assert(native.rooms_move(1, origin, 0, -1))
        mark("night-light-same-room", t)
    elseif step == "night-light-same-room" and t - stepAt >= 90 then
        actor(1, function(p)
            p:RemoveCollectible(425, true)
        end)
        assert(native.rooms_move(1, other, 0, -1))
        clean(0)
        clean(1)
        mark("genesis-prepare", t)
    elseif step == "genesis-prepare" and t - stepAt >= 60 then
        setupGenesis(1, t)
    elseif step == "genesis-enter" and t - stepAt >= 150 then
        local positions = native.rooms_positions()
        assert(
            positions[tostring(genesisSlot)].index == -12,
            "Genesis holder never entered its room"
        )
        assert(#pedestals(genesisSlot) == 3, "Genesis did not offer three choices")
        if genesisCases[genesisCase][2] then
            assert(
                inventory(1 - genesisSlot) == genesisOtherInventory,
                "Split-room Genesis changed the other player's inventory"
            )
        end
        report(
            "GENESIS entered case="
                .. genesisCase
                .. " room0="
                .. positions["0"].index
                .. " room1="
                .. positions["1"].index
                .. " p0="
                .. inventory(0)
                .. " p1="
                .. inventory(1)
        )
        previousCount = player(genesisSlot):GetCollectibleCount()
        mark("genesis-choose", t)
    elseif step == "genesis-choose" and t % 30 == 0 then
        local choices = pedestals(genesisSlot)
        local count = player(genesisSlot):GetCollectibleCount()
        if count > previousCount then
            genesisPicks = genesisPicks + 1
            previousCount = count
            report(
                "GENESIS holder="
                    .. genesisSlot
                    .. " picked="
                    .. genesisPicks
                    .. " choices="
                    .. #choices
            )
        end
        if #choices > 0 then
            actor(genesisSlot, function(p)
                p.Position, p.Velocity = choices[1].Position, Vector.Zero
            end)
        else
            assert(genesisPicks >= 2, "Genesis lost the remaining inventory choices")
            actor(genesisSlot, function(p, room)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if
                        e.Type == EntityType.ENTITY_EFFECT
                        and e.Variant == EffectVariant.HEAVEN_LIGHT_DOOR
                    then
                        p.Position, p.Velocity = e.Position, Vector.Zero
                        mark("genesis-exit", t)
                        return
                    end
                end
                for i = 0, room:GetGridSize() - 1 do
                    local grid = room:GetGridEntity(i)
                    if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then
                        p.Position, p.Velocity = grid.Position, Vector.Zero
                        mark("genesis-exit", t)
                        return
                    end
                end
                error("Genesis offered no native exit")
            end)
        end
    elseif step == "genesis-exit" and t - stepAt >= 120 then
        assert(native.rooms_positions()[tostring(genesisSlot)].index ~= -12, "Genesis exit stalled")
        assert(native.rooms_connected() == 3 and not player(0):IsDead() and not player(1):IsDead())
        report("GENESIS exit holder=" .. genesisSlot .. " stage=" .. Game():GetLevel():GetStage())
        genesisCase = genesisCase + 1
        if genesisCase <= #genesisCases then
            local at = native.rooms_positions()["0"]
            local destination = at.index
            if genesisCases[genesisCase][2] then
                destination = separateRoom(at.index)
            end
            local guest = native.rooms_positions()["1"]
            if guest.index ~= destination or guest.dimension ~= at.dimension then
                assert(native.rooms_move(1, destination, at.dimension, -1))
            end
            clean(0)
            mark("genesis-next-prepare", t)
        else
            local at = native.rooms_positions()["0"]
            assert(native.rooms_move(1, separateRoom(at.index), at.dimension, -1))
            mark("tm-prepare", t)
        end
    elseif step == "tm-prepare" and t - stepAt >= 60 then
        clean(0)
        clean(1)
        actor(1, function(p)
            p:AddCollectible(721, 0, false)
        end)
        mark("tm-generate", t)
    elseif step == "genesis-next-prepare" and t - stepAt >= 60 then
        clean(0)
        clean(1)
        setupGenesis(genesisCases[genesisCase][1], t)
    elseif step == "tm-generate" and t - stepAt >= 60 then
        for slot = 0, 1 do
            actor(slot, function(_, room)
                for i = 1, 8 do
                    local seed = 100003 + (slot * 8 + i) * 7919
                    local id =
                        Game():GetItemPool():GetCollectible(ItemPoolType.POOL_TREASURE, false, seed)
                    assert(id < 0, "Shared TMTRAINER generated a normal item")
                    local pickup = Isaac.Spawn(
                        5,
                        100,
                        id,
                        room:FindFreePickupSpawnPosition(
                            room:GetCenterPos() + Vector((i - 4) * 35, -60),
                            0,
                            true
                        ),
                        Vector.Zero,
                        nil
                    )
                    report(
                        "GENERATED slot="
                            .. slot
                            .. " seed="
                            .. seed
                            .. " pool_id="
                            .. id
                            .. " pedestal_id="
                            .. pickup.SubType
                    )
                end
            end)
        end
        mark("tm-pickup", t)
    elseif step == "tm-pickup" and t - stepAt >= 90 then
        pickGenerated(_IsaacLanTest.passivesOnly == true)
        mark("tm-effects", t)
    elseif step == "tm-effects" or step == "tm-passive-effects" then
        if t % 30 == 0 then
            for slot = 0, 1 do
                actor(slot, function(p, room)
                    local active = p:GetActiveItem(0)
                    local owned = active == pickedTargets[slot]
                        or collectibleCount(p, pickedTargets[slot]) > 0
                    if owned and not pickedGenerated[slot] then
                        pickedGenerated[slot] = true
                        report("GENERATED_PICKUP slot=" .. slot .. " active=" .. active)
                    end
                    if active < 0 and t % 60 == 0 then
                        p:UseActiveItem(active, 0)
                        report("GENERATED_ACTIVE slot=" .. slot .. " id=" .. active)
                    end
                    local target = room:GetCenterPos() - Vector(0, 90)
                    p:FireTear(p.Position, Vector(0, -8), false, true, false, p, 1)
                    local npc = Isaac.Spawn(10, 0, 0, target, Vector.Zero, p):ToNPC()
                    npc:TakeDamage(100, 0, EntityRef(p), 0)
                end)
            end
        end
        if t - stepAt >= 240 then
            assert(native.rooms_connected() == 3)
            for slot = 0, 1 do
                assert(
                    pickedGenerated[slot],
                    "Native pickup did not grant a generated item to slot " .. slot
                )
            end
            if step == "tm-effects" and not _IsaacLanTest.passivesOnly then
                pickedGenerated = {}
                pickGenerated(true)
                mark("tm-passive-effects", t)
            else
                savedDefinitions = native.generated_items()
                report("TMTRAINER effects survived definitions=" .. #savedDefinitions / 4)
                local at = native.rooms_positions()["0"]
                assert(native.rooms_move(1, at.index, at.dimension, -1))
                mark("tm-same-room", t)
            end
        end
    elseif step == "tm-same-room" and t - stepAt >= 90 then
        generatedStage = Game():GetLevel():GetStage()
        actor(0, function(p)
            Game():StartStageTransition(false, 0, p)
        end)
        mark("tm-floor", t)
    elseif step == "tm-floor" and t - stepAt >= 90 then
        assert(
            Game():GetLevel():GetStage() == generatedStage + 1,
            "Generated inventory floor transition stalled"
        )
        assert(
            native.generated_items():sub(1, #savedDefinitions) == savedDefinitions,
            "Floor transition changed existing definitions"
        )
        savedDefinitions = native.generated_items()
        report(
            "TMTRAINER same-room and floor transition survived definitions="
                .. #savedDefinitions / 4
        )
        mark("save", t)
    elseif step == "save" and t - stepAt >= 60 then
        savedInventories = { [0] = inventory(0), [1] = inventory(1) }
        assert(native.net_command(Command.saveExit))
    end
    assert(t - stepAt < 900, "Item acceptance stalled at " .. step)
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        advance(t)
    end, function(slot, t)
        local bytes = collect(slot, t)
        return bytes
            and string.pack(">s4", bytes)
                .. _IsaacLanState.encode({ step, completed, savedDefinitions or false })
    end, function(bytes, t, ack, betweenUpdates)
        local body, cursor = string.unpack(">s4", bytes)
        if restore(body, t, ack, betweenUpdates) == false then
            return false
        end
        local view = schema.unpack(_IsaacLanState.decode(body), t)
        assert(native.generated_items() == view.glitched, "Replica generated definitions differ")
        for _, a in ipairs(view.actors) do
            for _, field in ipairs({
                { "Damage", 1 },
                { "MaxFireDelay", 2 },
                { "ShotSpeed", 4 },
                { "MoveSpeed", 5 },
                { "Luck", 6 },
                { "TearRange", 9 },
            }) do
                local expected = a[Actor.entity][Entity.typed][field[2]]
                assert(
                    math.abs(Isaac.GetPlayer(a[Actor.index])[field[1]] - expected)
                        <= 0.00001 * math.max(1, math.abs(expected)),
                    "Replica attribute differs: " .. field[1]
                )
            end
            for _, item in ipairs(a[Actor.inventory][Inventory.items]) do
                assert(
                    collectibleCount(Isaac.GetPlayer(a[Actor.index]), item[Item.id])
                        == item[Item.count],
                    "Replica inventory differs from authority"
                )
                if item[Item.id] < 0 then
                    assert(
                        Isaac.GetItemConfig():GetCollectible(item[Item.id]),
                        "Replica missed generated config"
                    )
                end
            end
        end
        local meta = _IsaacLanState.decode(bytes:sub(cursor))
        step, savedDefinitions = meta[1], meta[3] or savedDefinitions
        if meta[2] and not completed then
            completed = true
            report(success)
        end
        return true
    end, present, beginFloor)
end
