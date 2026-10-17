-- Focused observation of held crafting bags and native Dross I/II currents.
local native = assert(_IsaacLan)
local previousSprite, previousPrediction = native.sprite_state, _IsaacLanPrediction.new
local previousEidMethods, previousBagMode = {}, nil
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local waterOnly = _IsaacLanTest.waterOnly
local timelineOffset = waterOnly and 1200 or 0
local renders, linked, chosen, finished, verified = 0, false, false, false, 0
local phase, profiled = "startup", false
local eid
local flowFloors = {}
local currentChecked = false
local spraySeen, sprayExpired, oldestSpray, sprayReferences = false, false, 0, {}
local eidCalls = 0
local entityReports = {}
local previousButtons, lastRender = 0, nil
local changedLayers, seenPaths = 0, {}
local output = assert(io.open("./lan-test-digest-scenes.csv", "w"))
output:write(
    "time_ms,tick,phase,interval_ms,entities,changed_layers,current_x,current_y,x,y,extra_finished,animation,local_spray,other_entities,replicated_spray\n"
)
local function report(message)
    Isaac.DebugString("LAN_NETWORK SCENES " .. message)
end
local function checkCurrent(current)
    if currentChecked or current:Length() == 0 then
        return
    end
    assert(not native.room_water_current(0 / 0, 0))
    assert(not native.room_water_current(0, math.huge))
    assert(not native.room_water_current(1, 1))
    if host then
        assert(not native.room_water_current(0, 0), "Authority accepted replica write")
    else
        assert(native.room_water_current(0, 0))
        assert(Game():GetRoom():GetWaterCurrent():Length() == 0)
        assert(native.room_water_current(current.X, current.Y))
    end
    assert((Game():GetRoom():GetWaterCurrent() - current):Length() == 0)
    currentChecked = true
end
local function measure(name, fn)
    return function(...)
        if name:match("^eid%.") then
            eidCalls = eidCalls + 1
        end
        local start = Isaac.GetTime()
        local result = table.pack(fn(...))
        native.diagnostics_sample(name, Isaac.GetTime() - start)
        return table.unpack(result, 1, result.n)
    end
end
local spriteState = native.sprite_state
native.sprite_state = function(...)
    local sprite, value = ...
    local result = spriteState(...)
    if value and result then
        changedLayers = changedLayers + #result
        for _, layer in ipairs(result) do
            local key = sprite:GetFilename() .. "|" .. layer[1] .. "|" .. layer[2]
            if not seenPaths[key] then
                seenPaths[key] = true
                report("LAYER " .. key)
            end
        end
    end
    return result
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function clearEnemies()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function changePhase(name)
    if phase ~= name then
        phase = name
        report("PHASE " .. name .. " tick=" .. verified .. " ms=" .. Isaac.GetTime())
    end
end
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if finished then
        native.test_gamepad(0)
        return frame()
    end
    if not eid then
        for mod, handle in pairs(_IsaacLanModules["api/public"].modHandles) do
            if handle.id == "isaac-lan.compat.eid" then
                eid = mod
                previousBagMode = eid.Config.DisplayBagOfCrafting
            end
        end
    end
    if not profiled and eid then
        profiled = true
        report(
            "EID found global="
                .. tostring(EID == eid)
                .. " bag="
                .. type(eid.handleBagOfCraftingRendering)
                .. " rep="
                .. tostring(eid.isRepentance)
        )
        for _, name in ipairs({
            "setPlayer",
            "resumeCoroutines",
            "handleBagOfCraftingUpdating",
            "handleBagOfCraftingRendering",
            "BoCGetRoomPickupList",
            "calculateBagOfCrafting",
            "printDescription",
        }) do
            if type(eid[name]) == "function" then
                previousEidMethods[name] = eid[name]
                eid[name] = measure("eid." .. name:lower(), eid[name])
            end
        end
    end
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    verified = s.verified + timelineOffset
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "23:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:23:23:0:0")
    end
    local moving = verified % 72
    native.test_gamepad(
        s.prepared and not host and (moving < 18 and 8 or moving >= 36 and moving < 54 and 4) or 0
    )
    if s.prepared and native.rooms_ready() and verified > 0 then
        local name = verified < 390 and "bag_idle"
            or verified < 750 and "bag_held"
            or verified < 1050 and "bag_no_eid_render"
            or verified < 1260 and "bag_released"
            or verified < 1530 and "water1_load"
            or verified < 2100 and "water1"
            or verified < 2400 and "water2_load"
            or "water2"
        changePhase(name)
        if eid then
            eid.Config.DisplayBagOfCrafting = name == "bag_no_eid_render" and "never" or "hold"
        end
        local now = Isaac.GetTime()
        local current, entities, sprayCount, replicatedSpray = Vector.Zero, {}, 0, 0
        local scoped = native.rooms_with_player(host and 0 or 1, function()
            current = Game():GetRoom():GetWaterCurrent()
            checkCurrent(current)
            entities = Isaac.GetRoomEntities()
            for _, e in ipairs(entities) do
                if
                    e.Type == EntityType.ENTITY_EFFECT
                    and e.Variant == EffectVariant.WATER_SPLASH
                    and e.SubType == 1
                then
                    if e:GetData().__isaac_lan_replica then
                        replicatedSpray = replicatedSpray + 1
                    end
                    assert(
                        host or not e:GetData().__isaac_lan_replica,
                        "Current spray was replicated"
                    )
                    spraySeen, sprayCount = true, sprayCount + 1
                    oldestSpray = math.max(oldestSpray, e.FrameCount)
                    local key = GetPtrHash(e)
                    if not sprayReferences[key] then
                        sprayReferences[key] = EntityPtr(e)
                    end
                end
            end
        end)
        -- The frontend can poll during a native room transfer, while the
        -- enclosing room scope is still active. Observe only committed frames.
        if not scoped then
            lastRender = nil
            return s
        end
        if current:Length() > 0 and verified % 300 == 0 and not entityReports[verified] then
            entityReports[verified] = true
            local counts, summary = {}, {}
            for _, e in ipairs(entities) do
                local key = e.Type
                    .. ":"
                    .. e.Variant
                    .. ":"
                    .. e.SubType
                    .. (e:GetData().__isaac_lan_replica and ":replica" or ":local")
                counts[key] = (counts[key] or 0) + 1
            end
            for key, count in pairs(counts) do
                summary[#summary + 1] = key .. "=" .. count
            end
            table.sort(summary)
            report(
                "ENTITIES phase="
                    .. phase
                    .. " tick="
                    .. verified
                    .. " "
                    .. table.concat(summary, " ")
            )
        end
        for key, pointer in pairs(sprayReferences) do
            if not pointer.Ref then
                sprayExpired, sprayReferences[key] = true, nil
            end
        end
        local p = Isaac.GetPlayer(assert(native.rooms_heads()[host and "0" or "1"]))
        output:write(
            string.format(
                "%.3f,%d,%s,%.3f,%d,%d,%.4f,%.4f,%.3f,%.3f,%s,%s,%d,%d,%d\n",
                now,
                verified,
                phase,
                lastRender and now - lastRender or 0,
                #entities,
                changedLayers,
                current.X,
                current.Y,
                p.Position.X,
                p.Position.Y,
                tostring(p:IsExtraAnimationFinished()),
                p:GetSprite():GetAnimation(),
                sprayCount,
                #entities - sprayCount,
                replicatedSpray
            )
        )
        lastRender, changedLayers = now, 0
        if renders % 60 == 0 then
            output:flush()
        end
    end
    if verified >= 3060 and not finished then
        finished = true
        output:flush()
        assert(eid and profiled and eidCalls > 100, "EID not profiled")
        assert(currentChecked, "Room current write boundary not checked")
        if not host then
            assert(
                spraySeen and sprayExpired and oldestSpray > 2,
                "Local spray did not animate/expire"
            )
        end
        if host then
            assert(flowFloors[1530] and flowFloors[2400], "Both current floors must be observed")
        end
        report("PASS scene observation")
    end
    return s
end
local gate = native.net_gate
local function seekFlow(t, start)
    if t == start then
        assert(native.rooms_with_player(1, function()
            report("CURRENT Dross command " .. Isaac.ExecuteCommand("goto d.3"))
        end, 1))
    elseif t == start + 30 then
        actor(1, function(p)
            p.Position = Game():GetRoom():GetCenterPos()
            local room = Game():GetRoom()
            local flow = room:GetWaterCurrent()
            checkCurrent(flow)
            report(
                "CURRENT stage="
                    .. Game():GetLevel():GetStage()
                    .. " current="
                    .. flow.X
                    .. ","
                    .. flow.Y
            )
            assert(flow:Length() > 0, "Current room was not loaded")
            flowFloors[start] = true
            clearEnemies()
        end)
    end
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(function()
        local physical = capture()
        local input, buttons = {}, 0
        for action = 0, 15 do
            local value = string.unpack(">I2", physical, action * 2 + 1)
            if action == ButtonAction.ACTION_PILLCARD then
                value = (
                    (verified >= 390 and verified < 393) or (verified >= 1050 and verified < 1053)
                )
                        and 65535
                    or 0
            end
            input[#input + 1] = string.pack(">I2", value)
            if value > 0 then
                buttons = buttons | (1 << action)
            end
        end
        input[#input + 1] = string.pack(">I2", buttons & ~previousButtons)
        previousButtons = buttons
        return table.concat(input)
    end, function(t, n, bytes)
        before(t, n, bytes)
        if t == 30 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:SetMinDamageCooldown(100000)
                    p.Position = Game():GetRoom():GetCenterPos()
                        + Vector(slot == 0 and -90 or 90, 0)
                    clearEnemies()
                end)
            end
            for i, variant in ipairs({ 10, 20, 30, 40, 90, 300, 70, 10, 20, 30, 40, 90 }) do
                Isaac.Spawn(
                    EntityType.ENTITY_PICKUP,
                    variant,
                    1,
                    Vector(100 + (i % 6) * 70, 200 + math.floor(i / 6) * 60),
                    Vector.Zero,
                    nil
                )
            end
        end
        local sceneTick = t + timelineOffset
        if sceneTick == 1260 or sceneTick == 2100 then
            Game()
                :GetLevel()
                :SetStage(sceneTick == 1260 and 1 or 2, StageType.STAGETYPE_REPENTANCE_B)
            Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
        end
        if sceneTick >= 1530 and sceneTick < 2100 then
            seekFlow(sceneTick, 1530)
        end
        if sceneTick >= 2400 then
            seekFlow(sceneTick, 2400)
        end
    end, collect, measure("scene.restore", restore), measure("scene.present", present), beginFloor)
end

return {
    done = function()
        return finished
    end,
    cleanup = function()
        output:close()
        native.sprite_state, _IsaacLanPrediction.new = previousSprite, previousPrediction
        if eid then
            for name, fn in pairs(previousEidMethods) do
                eid[name] = fn
            end
            eid.Config.DisplayBagOfCrafting = previousBagMode
        end
    end,
}
