-- Feedback 261024-B7FS: Terra contacts must retain the native flash decision.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, json = config.host, require("json")
local frame, gate, capture = _IsaacLanFrame, native.net_gate, native.combat_events
local tick, renders, linked, chosen, finished = 0, 0, false, false, false
local cases = {
    { name = "ordinary-horf", type = EntityType.ENTITY_HORF, flash = true },
    { name = "terra-horf", type = EntityType.ENTITY_HORF, terra = true, flash = true },
    { name = "terra-closed-host", type = EntityType.ENTITY_HOST, terra = true },
    { name = "terra-stonehead", type = EntityType.ENTITY_STONEHEAD, terra = true },
    { name = "terra-poky", type = EntityType.ENTITY_POKY, terra = true },
    { name = "terra-veto", type = EntityType.ENTITY_HORF, terra = true, veto = true },
    { name = "terra-no-flash", type = EntityType.ENTITY_HORF, terra = true, noFlash = true },
}
local start, length = 60, 150
local samples, serial = {}, 0
local function current()
    local index = math.floor((tick - start) / length) + 1
    return cases[index], index, (tick - start) % length
end
local function log(kind, data)
    data.kind, data.role, data.tick = kind, host and "host" or "client", tick
    Isaac.DebugString("LAN_B7FS " .. json.encode(data))
end
local function sample(index)
    samples[index] = samples[index]
        or {
            name = cases[index].name,
            red = 0,
            renders = 0,
            events = 0,
            flashEvents = 0,
            tears = {},
        }
    return samples[index]
end
local owner = { Name = "Isaac LAN B7FS native feedback regression" }
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_NPC_UPDATE, function(_, npc)
    if
        host
        and npc:GetData().b7fs
        and npc.Type == EntityType.ENTITY_HOST
        and npc.State == NpcState.STATE_IDLE
        and not npc:GetSprite():IsPlaying("Appear")
    then
        return true
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity)
    local case = current()
    if case and entity:ToNPC() and case.veto then
        return false
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_NPC_RENDER, function(_, npc)
    local case, index, elapsed = current()
    if case and elapsed >= 30 and elapsed < length - 10 and npc.Type == case.type then
        local value = sample(index)
        value.renders = value.renders + 1
        value.red = value.red + (npc:GetSprite().Color.RO > 0.5 and 1 or 0)
        value.hp, value.animation, value.state =
            npc.HitPoints, npc:GetSprite():GetAnimation(), npc.State
    end
end)
function native.combat_events(slot)
    local bytes = capture(slot)
    if slot == 1 then
        local count, offset = string.unpack(">I4", bytes)
        for _ = 1, count do
            local id, at, epoch, dimension, room, source, target, accepted, duration
            id, at, epoch, dimension, room, source, target, accepted, duration, offset =
                string.unpack(">I4I4I4i4i4I4I4BB", bytes, offset)
            if id > serial then
                serial = id
                local case, index = current()
                if case then
                    local value = sample(index)
                    value.events = value.events + 1
                    value.flashEvents = value.flashEvents + (duration > 0 and 1 or 0)
                    log("event", {
                        case = case.name,
                        accepted = accepted,
                        duration = duration,
                        target = target,
                    })
                end
            end
        end
    end
    return bytes
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
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
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    tick = status.verified
    local case, index, elapsed = current()
    native.test_gamepad(
        not host and case and elapsed >= 30 and elapsed < length - 10 and 0x2000 or 0
    )
    if case and status.prepared then
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity:ToTear() then
                sample(index).tears[tostring(entity.Variant)] = true
            end
        end
    end
    if not finished and tick >= start + length * #cases then
        finished = true
        for i, entry in ipairs(cases) do
            local value = sample(i)
            log("summary", value)
        end
        for i, entry in ipairs(cases) do
            local value = sample(i)
            assert(
                value.renders > 0 and next(value.tears),
                "Missing target render or actual shots: " .. entry.name
            )
            if host then
                assert(value.events > 0, "Missing actual native contact: " .. entry.name)
            end
            assert(
                (value.hp < 1000) == (entry.flash == true or entry.noFlash == true),
                "Unexpected authoritative damage: " .. entry.name
            )
            if not config.observeOnly then
                assert(
                    (value.red > 0) == (entry.flash == true),
                    "Wrong native flash: " .. entry.name
                )
                if host then
                    assert(
                        (value.flashEvents > 0) == (entry.flash == true),
                        "Wrong event duration: " .. entry.name
                    )
                end
            end
        end
        Isaac.DebugString("LAN_NETWORK PASS B7FS feedback")
    end
    return status
end
function native.net_gate(inputCapture, player, collect, restore, present, beginFloor)
    return gate(inputCapture, function(t, inputs, connected)
        player(t, inputs, connected)
        tick = t
        local phase = t - start
        if phase >= 0 and phase % length == 0 and cases[phase // length + 1] then
            local case = cases[phase // length + 1]
            assert(native.rooms_with_player(1, function()
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity.Type ~= EntityType.ENTITY_PLAYER then
                        entity:Remove()
                    end
                end
                for i = 0, Game():GetRoom():GetGridSize() - 1 do
                    Game():GetRoom():RemoveGridEntity(i, 0, false)
                end
                Game():GetRoom():SetClear(true)
                local p
                for i = 0, Game():GetNumPlayers() - 1 do
                    local actor = Isaac.GetPlayer(i)
                    if actor.ControllerIndex == 2 then
                        p = actor
                    else
                        actor.Position, actor.Velocity = Vector(200, 400), Vector.Zero
                    end
                end
                assert(p, "Missing guest actor")
                p.Position, p.Velocity = Vector(250, 280), Vector.Zero
                if case.terra and not p:HasCollectible(CollectibleType.COLLECTIBLE_TERRA) then
                    p:AddCollectible(CollectibleType.COLLECTIBLE_TERRA)
                end
                p:SetMinDamageCooldown(10000)
                p.MaxFireDelay = 5
                local npc = Isaac.Spawn(case.type, 0, 0, Vector(340, 280), Vector.Zero, nil):ToNPC()
                npc:GetData().b7fs = true
                npc:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
                npc.HitPoints, npc.MaxHitPoints = 1000, 1000
                if case.noFlash then
                    npc:AddEntityFlags(EntityFlag.FLAG_NO_FLASH_ON_DAMAGE)
                end
                log("setup", {
                    case = case.name,
                    terra = p:HasCollectible(CollectibleType.COLLECTIBLE_TERRA),
                    controller = p.ControllerIndex,
                })
            end, 1))
        end
    end, collect, restore, present, beginFloor)
end
