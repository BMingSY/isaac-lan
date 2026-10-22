-- Cross the old native EntityList capacity without saturating any single pool.
local native, host, port = _IsaacLan, _IsaacLanTest.host, _IsaacLanTest.port
local Phase = native.net_phases()
local originalFrame = _IsaacLanFrame
local OLD_CAPACITY, BATCH_SIZE, LIFETIME = 2048, 32, 1000
local FIRST_SAMPLE, SECOND_SAMPLE, REMOVE_AT, CLEAR_SAMPLE, FINISH_AT = 260, 320, 380, 440, 460
-- J460 native array RTTI: NPC/Tear/Projectile each 512; Effect 1024.
-- Spawn NPCs first so appearance effects expire before the effect load begins.
local loads = {
    { name = "npc", kind = EntityType.ENTITY_ATTACKFLY, count = 400, capacity = 512, at = 80 },
    { name = "tear", kind = EntityType.ENTITY_TEAR, count = 400, capacity = 512, at = 100 },
    {
        name = "projectile",
        kind = EntityType.ENTITY_PROJECTILE,
        count = 400,
        capacity = 512,
        at = 120,
    },
    {
        name = "effect",
        kind = EntityType.ENTITY_EFFECT,
        variant = EffectVariant.CREEP_RED,
        count = 900,
        capacity = 1024,
        at = 160,
    },
}
local renders, linked, chosen, started = 0, false, false, false
local selectionConfirmed, prepared, removed, cleared, finished, cleaned =
    false, false, false, false, false, false
local owned, samples = {}, {}
local roomIndex

local function report(message)
    Isaac.DebugString(
        "LAN_NETWORK ENTITY_CAPACITY role=" .. (host and "host" or "client") .. " " .. message
    )
end

local function matches(entity, load)
    return entity.Type == load.kind and entity.Variant == (load.variant or 0)
end

local function removeOwned()
    for _, value in ipairs(owned) do
        local entity = value.pointer.Ref
        if entity and entity:Exists() and entity.InitSeed == value.seed then
            entity:Remove()
        end
    end
    owned = {}
end

local function snapshot(label, tick, empty)
    local entities, counts, identities, pointers = Isaac.GetRoomEntities(), {}, {}, {}
    local minimumFrame, total = math.huge, 0
    for _, load in ipairs(loads) do
        counts[load.name] = 0
    end
    for _, entity in ipairs(entities) do
        for _, load in ipairs(loads) do
            if matches(entity, load) then
                local pointer = GetPtrHash(entity)
                assert(not pointers[pointer], "Capacity query repeated an entity")
                pointers[pointer] = true
                counts[load.name], total = counts[load.name] + 1, total + 1
                identities[#identities + 1] = load.name .. ":" .. entity.InitSeed
                minimumFrame = math.min(minimumFrame, entity.FrameCount)
                break
            end
        end
    end
    table.sort(identities)
    local identity = table.concat(identities, ",")
    local signature = 0
    for i = 1, #identity do
        signature = (signature * 65599 + identity:byte(i)) & 0xffffffff
    end
    report(
        string.format(
            "SAMPLE label=%s tick=%d total=%d room_total=%d npc=%d tear=%d projectile=%d effect=%d min_frame=%d signature=%u",
            label,
            tick,
            total,
            #entities,
            counts.npc,
            counts.tear,
            counts.projectile,
            counts.effect,
            total > 0 and minimumFrame or 0,
            signature
        )
    )
    for _, load in ipairs(loads) do
        assert(
            counts[load.name] == (empty and 0 or load.count),
            "Capacity fixture count differs: " .. load.name
        )
    end
    if not empty then
        assert(
            total > OLD_CAPACITY and #entities > OLD_CAPACITY,
            "Capacity fixture did not cross the native limit"
        )
        assert(minimumFrame >= 30, "Capacity fixture entities did not survive native frames")
    end
    return identity
end

local function spawn(load, count)
    local existing, entities = 0, Isaac.GetRoomEntities()
    for _, entity in ipairs(entities) do
        if (load.name == "npc" and entity:ToNPC()) or entity.Type == load.kind then
            existing = existing + 1
        end
    end
    assert(
        existing + count <= load.capacity,
        "Capacity fixture would saturate the " .. load.name .. " pool"
    )
    if #entities <= OLD_CAPACITY and #entities + count > OLD_CAPACITY then
        report("CROSSING room_total=" .. #entities .. " batch=" .. count .. " kind=" .. load.name)
    end
    local player, center = Isaac.GetPlayer(0), Game():GetRoom():GetCenterPos()
    for offset = 1, count do
        local index = load.spawned + offset
        local position = center
            + Vector((index % 17 - 8) * 12, (math.floor(index / 17) % 11 - 5) * 12)
        local entity
        if load.name == "tear" then
            entity = player:FireTear(position, Vector.Zero, false, true, false, player, 1)
            entity.FallingAcceleration, entity.FallingSpeed, entity.Height = -0.1, 0, -30
        else
            entity = Isaac.Spawn(load.kind, load.variant or 0, 0, position, Vector.Zero, nil)
            if load.name == "npc" then
                entity:ToNPC():AddFreeze(EntityRef(player), LIFETIME)
            elseif load.name == "projectile" then
                entity = entity:ToProjectile()
                entity.FallingAccel, entity.FallingSpeed, entity.Height = -0.1, 0, -30
            else
                entity = entity:ToEffect()
                entity.Timeout = LIFETIME
            end
        end
        owned[#owned + 1] = { pointer = EntityPtr(entity), seed = entity.InitSeed }
        entity:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        entity.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        entity.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        entity.CollisionDamage = 0
    end
    load.spawned = load.spawned + count
    if load.spawned == load.count then
        report("SPAWN kind=" .. load.name .. " count=" .. load.spawned)
    end
end

function _IsaacLanFrame()
    if cleaned then
        return originalFrame()
    end
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = originalFrame()
    if cleaned then
        return status
    end
    assert(status.phase ~= Phase.failed and status.phase ~= Phase.waiting, status.error)
    native.test_gamepad(0)
    if status.phase == Phase.lobby and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if chosen and status["choice" .. status.slot] == 0 and status["ready" .. status.slot] == 1 then
        selectionConfirmed = true
    end
    if
        host
        and not started
        and status.phase == Phase.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if not status.prepared then
        return status
    end
    assert(selectionConfirmed, "Capacity fixture character selection was not confirmed")
    local tick = status.verified
    if tick < 60 or not native.rooms_ready() then
        return status
    end
    if not prepared then
        roomIndex = Game():GetLevel():GetCurrentRoomIndex()
        for slot = 0, 1 do
            assert(native.rooms_with_player(slot, function()
                Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
                    :SetMinDamageCooldown(LIFETIME)
            end))
        end
        for _, load in ipairs(loads) do
            load.spawned = 0
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                assert(not matches(entity, load), "Capacity fixture started with matching entities")
            end
        end
        prepared = true
    end
    assert(Game():GetLevel():GetCurrentRoomIndex() == roomIndex, "Capacity fixture left its arena")
    if host and tick < REMOVE_AT then
        for _, load in ipairs(loads) do
            local due = math.min(load.count, math.max(0, tick - load.at + 1) * BATCH_SIZE)
            if load.spawned < due then
                spawn(load, due - load.spawned)
            end
        end
    end
    for _, sampleAt in ipairs({ FIRST_SAMPLE, SECOND_SAMPLE }) do
        if tick >= sampleAt and not samples[sampleAt] then
            samples[sampleAt] = snapshot(tostring(sampleAt), tick, false)
            if sampleAt == SECOND_SAMPLE then
                assert(
                    samples[FIRST_SAMPLE] == samples[SECOND_SAMPLE],
                    "Capacity fixture replaced entities during the stable hold"
                )
            end
        end
    end
    if host and tick >= REMOVE_AT and not removed then
        removed = true
        removeOwned()
        report("REMOVE requested=2100 tick=" .. tick)
    end
    if tick >= CLEAR_SAMPLE and not cleared then
        snapshot("cleared", tick, true)
        cleared = true
    end
    if tick >= FINISH_AT and not finished then
        assert(
            samples[FIRST_SAMPLE] and samples[SECOND_SAMPLE] and cleared,
            "Capacity fixture missed its checks"
        )
        finished = true
        Isaac.DebugString("LAN_NETWORK PASS native mixed entity capacity and cleanup")
    end
    return status
end

return {
    done = function()
        return finished
    end,
    cleanup = function()
        cleaned = true
        removeOwned()
    end,
}
