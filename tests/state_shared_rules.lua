-- One native pair: room-clear charging, ordinary dice allocation and the luck
-- challenge using the same allocator. Assertions on each peer precede progress.
local native, host, port = _IsaacLan, _IsaacLanTest.host, _IsaacLanTest.port
local json = require("json")
local Phase, Command = native.net_phases(), native.net_commands()
local frame, action = _IsaacLanFrame, _IsaacLanActionStep
local renders, linked, configured, started, finished = 0, false, false, false, false
local phase, at, case, waiting, checked = "setup", 0, 0, nil, {}
local mode, nextMode, began = 1, 1, nil
local greedPress
local choiceSent, relinking = false, false
local target, origin, large, nativeClears, pickup, beforeWins, beforeItems, beforeEpoch
local boosts = false
local owner = RegisterMod("Shared room rules acceptance", 1)
local function report(text)
    Isaac.DebugString("LAN_SHARED_RULES " .. text)
end
local function messages()
    return _IsaacLanChatMessages()
end
local function has(text)
    for _, m in ipairs(messages()) do
        if m.text == text then
            return true
        end
    end
end
local function wins()
    local result = {}
    for _, m in ipairs(messages()) do
        if m.text:find("获得了道具", 1, true) then
            result[#result + 1] = m.text
        end
    end
    return result
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        local p = Isaac.GetPlayer(0)
        assert(p.ControllerIndex == slot + 1)
        return fn(p)
    end, 1))
end
local function clear(slot)
    actor(slot, function()
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:ToNPC() or e:ToPickup() or e:ToTear() then
                e:Remove()
            end
        end
        Game():GetRoom():SetClear(true)
    end)
end
local function setupActives(slot)
    actor(slot, function(p)
        p:AddCollectible(CollectibleType.COLLECTIBLE_SCHOOLBAG)
        p:AddCollectible(CollectibleType.COLLECTIBLE_BATTERY)
        p:AddCollectible(CollectibleType.COLLECTIBLE_D6, 0, false, 0)
        p:AddCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL, 0, false, 1)
        p:SetPocketActiveItem(CollectibleType.COLLECTIBLE_YUM_HEART, 2, false)
        for i = 0, 2 do
            p:SetActiveCharge(0, i)
        end
    end)
end
local function zero(slot, value)
    actor(slot, function(p)
        for i = 0, 2 do
            p:SetActiveCharge(value or 0, i)
        end
    end)
end
local function charge(slot, active)
    local value
    actor(slot, function(p)
        value = p:GetActiveCharge(active or 0) + p:GetBatteryCharge(active or 0)
    end)
    return value
end
local function snapshot()
    local result = {}
    for slot = 0, 1 do
        actor(slot, function(p)
            local row = {}
            for i = 0, 2 do
                row[#row + 1] = p:GetActiveItem(i)
                row[#row + 1] = p:GetActiveCharge(i) + p:GetBatteryCharge(i)
            end
            row[#row + 1] = p:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION, true)
            row[#row + 1] = p:GetCollectibleNum(CollectibleType.COLLECTIBLE_SPOON_BENDER, true)
            result[#result + 1] = row
        end)
    end
    return result
end
local function verify(name)
    case = case + 1
    waiting = case
    local payload = { id = case, name = name, state = snapshot() }
    _IsaacLanChatOutput("RULES_CHECK:" .. json.encode(payload), { audience = "party" })
    report("HOST " .. name .. " " .. json.encode(payload.state))
end
local function mark(nextPhase)
    phase, at = nextPhase, native.api_info().tick
    report("PHASE " .. phase)
end
local clearCallback = _IsaacLanPlayerRoomCleared
function _IsaacLanPlayerRoomCleared(...)
    nativeClears = (nativeClears or 0) + 1
    clearCallback(...)
end
local function combat(slot)
    nativeClears = 0
    actor(slot, function()
        local room = Game():GetRoom()
        room:SetClear(false)
        local e =
            Isaac.Spawn(EntityType.ENTITY_ATTACKFLY, 0, 0, room:GetCenterPos(), Vector.Zero, nil)
        e:Die()
    end)
end
local function spawn(slot, id)
    actor(slot, function(p)
        p:FlushQueueItem()
        pickup = Isaac.Spawn(
            EntityType.ENTITY_PICKUP,
            PickupVariant.PICKUP_COLLECTIBLE,
            id,
            p.Position,
            Vector.Zero,
            nil
        ):ToPickup()
        pickup:Morph(
            EntityType.ENTITY_PICKUP,
            PickupVariant.PICKUP_COLLECTIBLE,
            id,
            false,
            true,
            true
        )
        pickup.Wait, pickup.Price, pickup.AutoUpdatePrice = 0, 0, false
    end)
end
Isaac.AddCallback(owner, ModCallbacks.MC_EVALUATE_CACHE, function(_, p, flag)
    if boosts and flag == CacheFlag.CACHE_LUCK then
        p.Luck = p.ControllerIndex == 2 and 500 or -500
    end
end)
local function advance()
    action()
    local info = native.api_info()
    if not host or info.ready ~= 1 or info.connected ~= 3 or finished then
        return
    end
    if greedPress and info.tick - greedPress > 5 then
        actor(0, function(p)
            p.Position = Vector(120, 280)
        end)
        greedPress = nil
    end
    if phase == "greed-waves" then
        actor(0, function()
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:ToNPC() and e:IsActiveEnemy(false) then
                    e:TakeDamage(100000, 0, EntityRef(Isaac.GetPlayer(0)), 0)
                end
            end
        end)
    end
    if waiting then
        if not has("RULES_ACK:" .. waiting) then
            return
        end
        waiting = nil
        at = info.tick
    end
    for slot = 0, 1 do
        actor(slot, function(p)
            p:SetMinDamageCooldown(10000)
            p.Velocity = Vector.Zero
        end)
    end
    local elapsed = info.tick - at
    if elapsed < 45 then
        return
    end
    if phase == "setup" then
        for slot = 0, 1 do
            clear(slot)
            setupActives(slot)
        end
        local rooms = Game():GetLevel():GetRooms()
        origin = native.rooms_positions()["0"].index
        for i = 0, rooms.Size - 1 do
            local d = rooms:Get(i)
            if
                d.SafeGridIndex ~= origin
                and d.SafeGridIndex >= 0
                and d.Data
                and d.Data.Type == RoomType.ROOM_DEFAULT
            then
                target = target or d.SafeGridIndex
                if d.Data.Shape >= 8 then
                    large = d.SafeGridIndex
                end
            end
        end
        assert(target, "No split room")
        report("ROOMS origin=" .. origin .. " target=" .. target .. " large=" .. tostring(large))
        mark("same-start")
    elseif phase == "same-start" then
        zero(0)
        zero(1)
        combat(0)
        mark("same-check")
    elseif phase == "same-check" then
        assert(nativeClears >= 2, "Native clear callback absent")
        for slot = 0, 1 do
            for a = 0, 2 do
                assert(charge(slot, a) == 1, "Same-room double/missing charge")
            end
        end
        verify("same room once, all slots")
        mark("split")
    elseif phase == "split" then
        assert(native.rooms_move(1, target, 0, -1))
        mark("split-ready")
    elseif phase == "split-ready" then
        assert(native.rooms_positions()["1"].index == target)
        clear(1)
        zero(1)
        zero(0, 12)
        mark("remote-start")
    elseif phase == "remote-start" then
        zero(1)
        combat(0)
        mark("remote-check")
    elseif phase == "remote-check" then
        assert(charge(0) == 12 and charge(1) == 1, "Full clearer did not share one charge")
        verify("split room with full clearer")
        mark("overflow-start")
    elseif phase == "overflow-start" then
        zero(1, 6)
        combat(0)
        mark("overflow-check")
    elseif phase == "overflow-check" then
        assert(charge(1) == 7, "Native battery overflow missing")
        verify("battery overflow")
        mark("aaa-start")
    elseif phase == "aaa-start" then
        actor(1, function(p)
            p:AddTrinket(TrinketType.TRINKET_AAA_BATTERY, false)
        end)
        zero(1, 4)
        combat(0)
        mark("aaa-check")
    elseif phase == "aaa-check" then
        assert(charge(1) == 6, "Recipient AAA Battery not applied")
        verify("recipient AAA Battery")
        mark("volt-start")
    elseif phase == "volt-start" then
        actor(1, function(p)
            p:TryRemoveTrinket(TrinketType.TRINKET_AAA_BATTERY)
            p:AddCollectible(CollectibleType.COLLECTIBLE_4_5_VOLT)
        end)
        zero(1)
        combat(0)
        mark("volt-check")
    elseif phase == "volt-check" then
        assert(charge(1) == 0, "Damage-charging item received room charge")
        verify("4.5 Volt exclusion")
        mark("timed-start")
    elseif phase == "timed-start" then
        actor(1, function(p)
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_4_5_VOLT)
            p:SetPocketActiveItem(CollectibleType.COLLECTIBLE_SPIN_TO_WIN, 2, false)
            p:SetActiveCharge(0, 2)
        end)
        combat(0)
        mark("timed-check")
    elseif phase == "timed-check" then
        local maximum
        actor(1, function(p)
            local kind
            kind, maximum = native.items_active_charge(p:GetSprite(), 2)
            assert(kind == ItemConfig.CHARGE_TIMED)
        end)
        report("TIMED charge=" .. charge(1, 2) .. " max=" .. maximum)
        assert(charge(1, 2) >= maximum, "Timed active did not fill")
        actor(1, function(p)
            p:SetPocketActiveItem(CollectibleType.COLLECTIBLE_YUM_HEART, 2, false)
            p:SetActiveCharge(0, 2)
        end)
        verify("timed active")
        mark("large-move")
    elseif phase == "large-move" then
        if not large then
            actor(0, function(p)
                Game():GetLevel():SetStage(2, 0)
                Game():StartStageTransition(true, 0, p)
            end)
            mark("large-find")
        else
            assert(native.rooms_move(0, large, 0, -1))
            mark("large-ready")
        end
    elseif phase == "large-find" then
        local rooms = Game():GetLevel():GetRooms()
        for i = 0, rooms.Size - 1 do
            local d = rooms:Get(i)
            if d.Data and d.Data.Shape >= 8 and d.Data.Type == 1 then
                large = d.SafeGridIndex
                break
            end
        end
        if not large then
            local nextStage = Game():GetLevel():GetStage() + 1
            assert(nextStage <= 6, "No large room on validation route")
            actor(0, function(p)
                Game():GetLevel():SetStage(nextStage, 0)
                Game():StartStageTransition(true, 0, p)
            end)
            mark("large-find")
            return
        end
        assert(native.rooms_move(0, large, 0, -1))
        mark("large-ready")
    elseif phase == "large-ready" then
        clear(0)
        zero(1)
        mark("large-start")
    elseif phase == "large-start" then
        zero(1)
        combat(0)
        mark("large-check")
    elseif phase == "large-check" then
        assert(charge(1) == 2, "Large-room progress was not shared")
        verify("large room two charges")
        mark("rewind-prepare")
    elseif phase == "rewind-prepare" then
        for slot = 0, 1 do
            zero(slot)
        end
        beforeItems = snapshot()
        local rooms = Game():GetLevel():GetRooms()
        local positions = native.rooms_positions()
        local destination
        for i = 0, rooms.Size - 1 do
            local d = rooms:Get(i)
            if
                d.Data
                and d.Data.Type == 1
                and d.SafeGridIndex >= 0
                and d.SafeGridIndex ~= positions["0"].index
                and d.SafeGridIndex ~= positions["1"].index
            then
                destination = d.SafeGridIndex
                break
            end
        end
        assert(destination and native.rooms_move(0, destination, 0, -1))
        mark("rewind-clear")
    elseif phase == "rewind-clear" then
        clear(0)
        for slot = 0, 1 do
            zero(slot)
        end
        combat(0)
        mark("rewind-use")
    elseif phase == "rewind-use" then
        assert(charge(1) > 0, "Pre-rewind shared charge absent")
        beforeEpoch = info.worldEpoch
        actor(0, function(p)
            p:UseActiveItem(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, 0, -1)
        end)
        mark("rewind-check")
    elseif phase == "rewind-check" then
        assert(info.worldEpoch == beforeEpoch + 1, "Hourglass did not change epoch once")
        assert(
            json.encode(snapshot()) == json.encode(beforeItems),
            "Hourglass retained shared charge or replayed pending clear"
        )
        verify("hourglass restores charge without replay")
        mark("loot-start")
    elseif phase == "loot-start" then
        boosts = true
        for slot = 0, 1 do
            actor(slot, function(p)
                p:AddCacheFlags(CacheFlag.CACHE_LUCK)
                p:EvaluateItems()
            end)
        end
        beforeWins = #wins()
        beforeItems = snapshot()
        spawn(0, CollectibleType.COLLECTIBLE_SAD_ONION)
        mark("loot-check")
    elseif phase == "loot-check" then
        assert(#wins() == beforeWins + 1, "Normal pickup did not roll once")
        assert(not wins()[#wins()]:find("=", 1, true), "Normal rule applied luck modifier")
        local current = snapshot()
        assert(
            current[1][7] + current[2][7] == beforeItems[1][7] + beforeItems[2][7] + 1,
            "Pickup duplicated/lost"
        )
        verify("ordinary dice without luck")
        mark("active-start")
    elseif phase == "active-start" then
        beforeWins = #wins()
        spawn(0, CollectibleType.COLLECTIBLE_SATANIC_BIBLE)
        pickup.Charge = 3
        mark("active-check")
    elseif phase == "active-check" then
        assert(#wins() == beforeWins, "Active pickup incorrectly rolled")
        local found = 0
        for slot = 0, 1 do
            actor(slot, function(p)
                if p:GetActiveItem() == CollectibleType.COLLECTIBLE_SATANIC_BIBLE then
                    found = found + 1
                    assert(p:GetActiveCharge() == 3, "Native active charge changed")
                    assert(
                        slot == 0
                            and p:GetActiveItem(1) == CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL,
                        "Native active swap lost secondary item"
                    )
                end
            end)
        end
        assert(found == 1, "Active duplicated/lost")
        verify("native active pickup and Schoolbag preservation")
        mark("challenge-exit")
    elseif phase == "challenge-exit" then
        nextMode = 2
        _IsaacLanChatOutput("RULES_SWITCH", { audience = "party" })
        assert(native.net_command(Command.saveExit))
        mark("lobby")
    elseif phase == "challenge-setup" then
        assert(info.challenge == 1002 and info.roomOptions == 6)
        for slot = 0, 1 do
            clear(slot)
            actor(slot, function(p)
                assert(p:HasTrinket(TrinketType.TRINKET_NO))
                p:AddCacheFlags(CacheFlag.CACHE_LUCK)
                p:EvaluateItems()
            end)
        end
        beforeWins = #wins()
        spawn(0, CollectibleType.COLLECTIBLE_SPOON_BENDER)
        mark("challenge-check")
    elseif phase == "challenge-check" then
        assert(
            #wins() == beforeWins + 1 and wins()[#wins()]:find("+500=", 1, true),
            "Challenge lost luck correction or double-rolled"
        )
        actor(0, function(p)
            assert(p:GetCollectibleNum(CollectibleType.COLLECTIBLE_SPOON_BENDER) == 0)
        end)
        actor(1, function(p)
            assert(p:GetCollectibleNum(CollectibleType.COLLECTIBLE_SPOON_BENDER) == 1)
        end)
        verify("challenge reuses allocator with luck")
        mark("challenge-active")
    elseif phase == "challenge-active" then
        beforeWins = #wins()
        spawn(0, CollectibleType.COLLECTIBLE_D6)
        mark("challenge-active-check")
    elseif phase == "challenge-active-check" then
        assert(#wins() == beforeWins, "Challenge active fell through to optional rule")
        actor(0, function(p)
            p:FlushQueueItem()
            assert(p:GetActiveItem() == CollectibleType.COLLECTIBLE_D6)
        end)
        verify("challenge policy takes precedence")
        mark("greed-exit")
    elseif phase == "greed-exit" then
        nextMode = 3
        _IsaacLanChatOutput("RULES_GREED", { audience = "party" })
        assert(native.net_command(Command.saveExit))
        mark("lobby")
    elseif phase == "greed-setup" then
        assert(Game():IsGreedMode())
        for slot = 0, 1 do
            setupActives(slot)
        end
        local rooms = Game():GetLevel():GetRooms()
        local shop
        for i = 0, rooms.Size - 1 do
            local d = rooms:Get(i)
            if d.Data and d.Data.Type == RoomType.ROOM_SHOP then
                shop = d.SafeGridIndex
                break
            end
        end
        assert(shop and native.rooms_move(1, shop, 0, -1))
        mark("greed-ready")
    elseif phase == "greed-ready" then
        clear(1)
        zero(0)
        zero(1)
        nativeClears = 0
        actor(0, function(p)
            local room = Game():GetRoom()
            local button
            for i = 0, room:GetGridSize() - 1 do
                local g = room:GetGridEntity(i)
                if g and g:GetType() == GridEntityType.GRID_PRESSURE_PLATE then
                    button = g
                    break
                end
            end
            assert(button)
            p.Position = button.Position
        end)
        greedPress = info.tick
        mark("greed-waves")
    elseif phase == "greed-waves" then
        local wave = Game():GetLevel().GreedModeWave
        local clearArena
        actor(0, function()
            clearArena = Game():GetRoom():IsClear()
        end)
        if wave >= 8 and clearArena then
            report(
                "GREED wave="
                    .. wave
                    .. " host="
                    .. charge(0)
                    .. " guest="
                    .. charge(1)
                    .. " clears="
                    .. nativeClears
            )
            assert(
                charge(0) > 0 and charge(0) == charge(1),
                "Greed wave clear progress was not shared"
            )
            verify("native Greed waves across rooms")
            mark("finish")
        end
    elseif phase == "finish" then
        finished = true
        _IsaacLanChatOutput("RULES_FINISHED", { audience = "party" })
        report("PASS shared rules")
    end
end
function _IsaacLanActionStep()
    local ok, reason = pcall(advance)
    if not ok then
        finished = true
        Isaac.DebugString("LAN_NETWORK FAILED " .. tostring(reason))
        report("FAILED " .. tostring(reason))
        error(reason)
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 420) then
        linked = true
        if not host then
            assert(native.menu_room_options_save(1))
        end
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= Phase.failed, s.error)
    local info = native.api_info()
    began = began or info.nowMs
    assert(finished or info.nowMs - began < 480000, "Shared rules fixture stalled: " .. phase)
    if not host and has("RULES_SWITCH") then
        nextMode = 2
    end
    if not host and has("RULES_GREED") then
        nextMode = 3
    end
    if info.active ~= 1 and nextMode > mode and not relinking and s.phase ~= Phase.lobby then
        linked, renders, relinking = false, 0, true
    end
    if s.phase == Phase.lobby then
        if nextMode > mode then
            mode, started, choiceSent, relinking = nextMode, false, false, false
            if host then
                _IsaacLanCommand("challenge", mode == 2 and "1002" or "0")
                mark(mode == 2 and "challenge-setup" or "greed-setup")
            end
        end
        if host and not configured then
            _IsaacLanCommand("room_options", "6")
            configured = true
            assert(native.menu_room_options() == 6)
            native.menu_connection_save("127.0.0.1", tonumber(port))
            assert(native.menu_room_options() == 6, "Saving IP overwrote rules")
        end
        if
            s.players == 2
            and s.roomOptions == 6
            and (mode == 1 or mode == 2 and s.challenge == 1002 or mode == 3 and s.challenge == 0)
        then
            if not choiceSent and s["ready" .. s.slot] == 0 then
                choiceSent = true
                _IsaacLanCommand("choose", "0:1")
            end
            if host and not started and s.ready0 == 1 and s.ready1 == 1 then
                started = true
                at = 0
                _IsaacLanCommand("start", "YV039KQF:" .. (mode == 3 and "2" or "0") .. ":0:0:0:0")
            end
        end
    end
    if not host and info.ready == 1 then
        assert(native.menu_room_options() == 1, "Guest lobby overwrote hosting preferences")
        for _, m in ipairs(messages()) do
            if m.text:sub(1, 12) == "RULES_CHECK:" then
                local data = json.decode(m.text:sub(13))
                if not checked[data.id] then
                    checked[data.id] = { at = info.tick, data = data }
                end
            end
        end
        for _, entry in pairs(checked) do
            if not entry.done and info.tick - entry.at > 30 then
                assert(
                    json.encode(snapshot()) == json.encode(entry.data.state),
                    "Replica inventory differs: " .. entry.data.name
                )
                entry.done = true
                if entry.data.name == "native active pickup and Schoolbag preservation" then
                    nextMode = 2
                end
                if entry.data.name == "challenge policy takes precedence" then
                    nextMode = 3
                end
                _IsaacLanChatSubmit("RULES_ACK:" .. entry.data.id)
                report("CLIENT " .. entry.data.name)
            end
        end
        if has("RULES_FINISHED") and not finished then
            finished = true
            report("PASS shared rules")
        end
    end
    return s
end
return {
    done = function()
        return finished
    end,
}
