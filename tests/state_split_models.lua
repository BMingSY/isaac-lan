-- Native split-body rendering requires the actor's temporary effect set.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local json = require("json")
local host, frame, gate = config.host, _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished, tick = 0, false, false, false, 0
local home, away
local cases = {
    { name = "scissors", item = CollectibleType.COLLECTIBLE_SCISSORS },
    { name = "pinking-shears", item = CollectibleType.COLLECTIBLE_PINKING_SHEARS },
    { name = "guillotine", item = CollectibleType.COLLECTIBLE_GUILLOTINE, passive = true },
    { name = "decap-attack", item = CollectibleType.COLLECTIBLE_DECAP_ATTACK },
}
local gamepad = { left = 4, right = 8, shootRight = 0x2000 }
local first, duration, seen, cleaned = 60, 240, {}, {}
local function actor(slot, fn)
    return native.rooms_with_player(slot, function()
        local index = assert(native.rooms_heads()[tostring(slot)])
        return fn(Isaac.GetPlayer(index), Game():GetRoom(), index)
    end, 1)
end
local function phase(t)
    local at = t - first
    if at < 0 then
        return nil, at
    end
    return cases[at // duration + 1], at % duration
end
local function clear(room)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:ToNPC() then
            e:Remove()
        end
    end
    room:SetClear(true)
end
local function remove(p)
    for _, case in ipairs(cases) do
        if p:HasCollectible(case.item) then
            p:RemoveCollectible(case.item)
        end
        local effects = p:GetEffects()
        local count = effects:GetCollectibleEffectNum(case.item)
        if count > 0 then
            effects:RemoveCollectibleEffect(case.item, count)
        end
    end
end
local function log(event, value)
    value = value or {}
    value.event, value.tick, value.time, value.role =
        event, tick, Isaac.GetTime(), host and "host" or "client"
    Isaac.DebugString("LAN_SPLIT_MODELS " .. json.encode(value))
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
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    tick = s.verified
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    local case, at = phase(tick)
    local decap = case and case.item == CollectibleType.COLLECTIBLE_DECAP_ATTACK
    local input = 0
    if not host and case then
        if decap then
            input = (at >= 10 and at < 35 and gamepad.shootRight)
                or (at >= 35 and at < 80 and gamepad.left)
                or 0
        else
            input = (at >= 65 and at < 90 and gamepad.right)
                or (at >= 100 and at < 125 and gamepad.shootRight)
                or 0
        end
    end
    native.test_gamepad(input)
    local observing = decap and at >= 40 and at <= 60 or not decap and at >= 70 and at <= 120
    if s.prepared and case and observing then
        local data = { case = case.name, actors = {} }
        for slot = 0, 1 do
            actor(slot, function(p, room)
                local count = p:GetEffects():GetCollectibleEffectNum(case.item)
                if slot == 1 then
                    assert(p:HasCollectible(case.item), "Split collectible missing on its owner")
                    if not case.passive then
                        assert(count > 0, "Split temporary effect missing: " .. case.name)
                    end
                    seen[case.name] = (seen[case.name] or 0) + 1
                else
                    assert(
                        count == 0 and not p:HasCollectible(case.item),
                        "Split state crossed actors"
                    )
                end
                if slot == 1 and case.item == CollectibleType.COLLECTIBLE_PINKING_SHEARS then
                    local found = false
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        if
                            entity.Type == EntityType.ENTITY_FAMILIAR
                            and entity.Variant == FamiliarVariant.ISAACS_BODY
                        then
                            local layers, sprites = native.familiar_body(entity:GetSprite())
                            assert(layers and #sprites == 5, "Missing detached body sprites")
                            local visible = false
                            for i = 1, 4 do
                                local layer = string.unpack(">i4", layers, (i - 1) * 4 + 1)
                                if layer >= 0 then
                                    assert(sprites[i + 1]:GetFilename() ~= "", "Empty body costume")
                                    visible = true
                                end
                            end
                            assert(visible, "Invisible detached body")
                            found = true
                        end
                    end
                    assert(found, "Detached body familiar missing")
                end
                local sprite = p:GetSprite()
                data.actors[#data.actors + 1] = {
                    controller = p.ControllerIndex,
                    effect = count,
                    body = sprite:GetAnimation(),
                    overlay = sprite:GetOverlayAnimation(),
                    x = p.Position.X,
                    y = p.Position.Y,
                    room = Game():GetLevel():GetCurrentRoomIndex(),
                }
            end)
        end
        if tick % 10 == 0 then
            log("active", data)
        end
    elseif s.prepared and case and at >= 220 and at <= 230 then
        actor(1, function(p)
            for _, item in ipairs(cases) do
                assert(
                    not p:HasCollectible(item.item)
                        and p:GetEffects():GetCollectibleEffectNum(item.item) == 0,
                    "Split state survived cleanup/room change"
                )
            end
            cleaned[case.name] = true
        end)
    end
    if tick >= first + #cases * duration and not finished then
        for _, item in ipairs(cases) do
            assert(
                (seen[item.name] or 0) >= 10 and cleaned[item.name],
                "Missing split model/cleanup coverage"
            )
        end
        finished = true
        log("complete", { seen = seen, cleaned = cleaned })
        Isaac.DebugString("LAN_NETWORK PASS split models and temporary effects")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, b)
        before(t, n, b)
        tick = t
        if t == 30 then
            home = Game():GetLevel():GetCurrentRoomIndex()
            for i = 0, Game():GetLevel():GetRooms().Size - 1 do
                local d = Game():GetLevel():GetRooms():Get(i)
                if d.SafeGridIndex ~= home and d.Data.Type == RoomType.ROOM_DEFAULT then
                    away = d.SafeGridIndex
                    break
                end
            end
            assert(away)
        end
        local case, at = phase(t)
        if case and at == 0 then
            actor(1, remove)
            for slot = 0, 1 do
                assert(native.rooms_move(slot, home, 0, -1))
            end
        elseif case and at == 10 then
            for slot = 0, 1 do
                actor(slot, function(p, room)
                    clear(room)
                    p.Position, p.Velocity = Vector(160 + slot * 180, 280), Vector.Zero
                end)
            end
            actor(1, function(p)
                p:AddCollectible(case.item)
                p:ResetDamageCooldown()
            end)
        elseif case and at == 30 and not case.passive then
            actor(1, function(p)
                p:UseActiveItem(case.item, 0)
            end)
        elseif case and at == 180 then
            actor(1, remove)
            for slot = 0, 1 do
                assert(native.rooms_move(slot, away, 0, -1))
            end
        elseif case and at == 190 then
            for slot = 0, 1 do
                actor(slot, function(_, room)
                    clear(room)
                end)
            end
        end
    end, collect, restore, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        _IsaacLanFrame, native.net_gate = frame, gate
        native.test_gamepad(0)
    end,
}
