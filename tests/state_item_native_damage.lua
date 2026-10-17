-- `controlCases` is injected from item_damage_effects.py. This control starts
-- a native single-player run through normal menu keys, without a LAN session.
local native, json = assert(_IsaacLan), require("json")
local host = _IsaacLanTest.host
local role = host and "host" or "client"
local case = controlCases[host and 1 or 2]
local baseFrame, baseMenu = _IsaacLanFrame, _IsaacLanMenuRender
local owner = { Name = "Native damage control" }
local phase, renders, tick, nextStep = "menu", 0, 0, 1
local pending, floorPending
local function report(event, values)
    values = values or {}
    values.event, values.key, values.role = event, case.key, role
    Isaac.DebugString("LAN_NATIVE_DAMAGE " .. json.encode(values))
end
local traceDamage = createDamageTrace(report, function()
    return phase == "running"
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, p)
    traceDamage("player_effects", p)
end)
local function health(p)
    return {
        hearts = p:GetHearts(),
        soul = p:GetSoulHearts(),
        cooldown = p:GetDamageCooldown(),
        mantle = p:GetEffects():GetCollectibleEffectNum(CollectibleType.COLLECTIBLE_HOLY_MANTLE),
        multiplier = p:GetTrinketMultiplier(TrinketType.TRINKET_WOODEN_CROSS),
        stage = Game():GetLevel():GetStage(),
        room_frame = Game():GetRoom():GetFrameCount(),
    }
end
local function clear()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type ~= EntityType.ENTITY_PLAYER then
            e:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
_IsaacLanMenuRender = function(...)
    local visible = baseMenu(...)
    if phase == "start" then
        Isaac.DebugString(
            "LAN_NETWORK SOLO_UI_STATE action=new-run visible="
                .. tostring(visible)
                .. " ms="
                .. native.api_info().nowMs
                .. " role="
                .. role
        )
    end
    return visible
end
function _IsaacLanFrame()
    traceDamage("before_frame")
    local status = baseFrame()
    traceDamage("after_frame")
    if floorPending then
        floorPending = false
        Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
    end
    renders = renders + 1
    native.test_gamepad(0)
    Options.FoundHUD, Options.ExtraHUDStyle = true, 1
    if phase == "menu" and status.scene == 1 and renders >= 30 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
        _IsaacLanCommand("close", "")
        phase = "start"
        Isaac.DebugString("LAN_NETWORK SOLO_GUI_REQUEST action=new-run sequence=0 role=" .. role)
    elseif phase == "saved" and status.scene == 1 then
        phase = "done"
        Isaac.DebugString("LAN_NETWORK NATIVE_DAMAGE_CONTROL_COMPLETE")
    end
    return status
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    assert(phase == "start" and not continued)
    assert(native.api_info().active == 0 and Game():GetNumPlayers() == 1)
    phase, tick = "running", 0
    report("native_start", { active = native.api_info().active, players = Game():GetNumPlayers() })
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_NEW_ROOM, function()
    if phase == "running" then
        traceDamage("new_room")
        clear()
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_NEW_LEVEL, function()
    if phase == "running" then
        report("native_floor", health(Isaac.GetPlayer(0)))
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_UPDATE, function()
    if phase ~= "running" then
        return
    end
    tick = tick + 1
    local p = Isaac.GetPlayer(0)
    assert(native.api_info().active == 0)
    if tick == 20 and controlPlayers == 2 then
        Isaac.ExecuteCommand("addplayer 0 1")
        assert(Game():GetNumPlayers() == 2 and not Isaac.GetPlayer(1):IsCoopGhost())
        report(
            "native_coop",
            { active = native.api_info().active, players = Game():GetNumPlayers() }
        )
    end
    assert(Game():GetNumPlayers() == (tick < 20 and 1 or controlPlayers))
    if tick == 30 then
        clear()
        p:AddMaxHearts(24 - p:GetMaxHearts(), false)
        p:AddHearts(24 - p:GetHearts())
        p:ResetDamageCooldown()
        if case.kind == "trinket" then
            p:AddTrinket(case.id, true)
        else
            p:AddCollectible(case.id, 0, true)
        end
        report("acquired", health(p))
    end
    if pending then
        pending.after, pending.after_tick = health(p), tick
        report("damage_trial", pending)
        pending = nil
    end
    local step = case.damage_effects.steps[nextStep]
    if step and tick >= step.tick then
        nextStep = nextStep + 1
        if step.action == "hit" then
            pending = {
                tick = tick,
                probe = step.name,
                amount = step.amount,
                before = health(p),
                stage = Game():GetLevel():GetStage(),
            }
            p:TakeDamage(step.amount, 0, EntityRef(p), 0)
        elseif step.action == "floor" then
            report("floor", health(p))
            if controlFloorInFrame then
                floorPending = true
            else
                Game():StartStageTransition(false, 0, p)
            end
        else
            local level = Game():GetLevel()
            local rooms, origin = level:GetRooms(), level:GetCurrentRoomIndex()
            for i = 0, rooms.Size - 1 do
                local d = rooms:Get(i)
                if
                    d.Data
                    and d.Data.Type == RoomType.ROOM_DEFAULT
                    and d.SafeGridIndex ~= origin
                then
                    p:SetMinDamageCooldown(20)
                    Game():ChangeRoom(d.SafeGridIndex)
                    break
                end
            end
        end
    end
    if tick >= case.end_tick then
        phase = "exit"
        Isaac.DebugString("LAN_NETWORK SOLO_GUI_REQUEST action=save-exit sequence=1 role=" .. role)
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
    assert(phase == "exit" and shouldSave)
    phase = "saved"
    report("native_exit", { active = native.api_info().active, saved = shouldSave })
end)
