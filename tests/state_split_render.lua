local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame, gate = _IsaacLanFrame, native.net_gate
local owner = { Name = "Split room familiar and knife rendering" }
local renders, linked, chosen, finished = 0, false, false, false
local origin, other, checks, leaks = nil, nil, 0, 0
local recordedPlayers = {}
local renderedTypes = {}
local spearRenders = 0
local missingOwners, outsideList = 0, 0
local movingRight, splitFrames = true, 0
local function report(message)
    Isaac.DebugString("LAN_NETWORK SPLIT_RENDER " .. message)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end, 1))
end
local function clear()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:IsActiveEnemy(false) then
            e:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function observed(_, e)
    if not native.rooms_ready() then
        return
    end
    renderedTypes[e.Type] = (renderedTypes[e.Type] or 0) + 1
    if e.Type == EntityType.ENTITY_FAMILIAR then
        local p = e:ToFamiliar().Player
        if not p or p.ControllerIndex ~= 1 then
            missingOwners = missingOwners + 1
            if missingOwners <= 6 then
                report(
                    "OWNER type="
                        .. e.Type
                        .. " variant="
                        .. e.Variant
                        .. " controller="
                        .. (p and p.ControllerIndex or -1)
                )
            end
        end
    end
    if e.Type ~= EntityType.ENTITY_PLAYER and e.Visible then
        local found = false
        for _, member in ipairs(Isaac.GetRoomEntities()) do
            if GetPtrHash(member) == GetPtrHash(e) then
                found = true
                break
            end
        end
        if not found then
            outsideList = outsideList + 1
            if outsideList <= 6 then
                report(
                    "OUTSIDE_LIST type="
                        .. e.Type
                        .. " variant="
                        .. e.Variant
                        .. " exists="
                        .. tostring(e:Exists())
                )
            end
        end
    end
    local proxy = e:ToPlayer() and e.Child and e.Child:ToFamiliar()
    local p = proxy and proxy.Player
        or e:ToFamiliar() and e:ToFamiliar().Player
        or e.SpawnerEntity and e.SpawnerEntity:ToPlayer()
        or e.Parent and e.Parent:ToPlayer()
    if not p then
        if e.Type == EntityType.ENTITY_EFFECT then
            missingOwners = missingOwners + 1
            if missingOwners <= 6 then
                report("UNOWNED_EFFECT variant=" .. e.Variant)
            end
        end
        return
    end
    local positions = native.rooms_positions()
    local own = positions[tostring(p.ControllerIndex - 1)]
    local localPosition = positions[host and "0" or "1"]
    if own and localPosition then
        checks = checks + 1
        if own.index ~= localPosition.index or own.dimension ~= localPosition.dimension then
            leaks = leaks + 1
            if leaks <= 10 then
                report(
                    string.format(
                        "LEAK type=%d variant=%d owner=%d room=%d view=%d exists=%s visible=%s",
                        e.Type,
                        e.Variant,
                        p.ControllerIndex,
                        own.index,
                        localPosition.index,
                        tostring(e:Exists()),
                        tostring(e.Visible)
                    )
                )
            end
        end
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_FAMILIAR_RENDER, observed)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_KNIFE_RENDER, observed)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_EFFECT_RENDER, function(_, e)
    if e.Variant == EffectVariant.SPEAR_OF_DESTINY then
        spearRenders = spearRenders + 1
        observed(nil, e)
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_PLAYER_RENDER, function(_, p)
    if not recordedPlayers[p.InitSeed] then
        recordedPlayers[p.InitSeed] = true
        local function identity(e)
            return e and (e.Type .. "." .. e.Variant .. "." .. e.SubType) or "none"
        end
        report(
            "PLAYER_RENDER controller="
                .. p.ControllerIndex
                .. " child="
                .. identity(p.Child)
                .. " parent="
                .. identity(p.Parent)
                .. " spawner="
                .. identity(p.SpawnerEntity)
        )
    end
    observed(nil, p)
end)
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", host and "9:1" or "2:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "MBHM9FSV:0:9:2:0:0")
    end
    if host and status.prepared and native.api_info().ready == 1 then
        actor(0, function(p)
            local center = Game():GetRoom():GetCenterPos().X
            if p.Position.X < center - 90 then
                movingRight = true
            elseif p.Position.X > center + 90 then
                movingRight = false
            end
        end)
    end
    local move = movingRight and 0x0008 or 0x0004
    native.test_gamepad(
        host and status.prepared and native.api_info().ready == 1 and (0x8000 | move) or 0
    )
    if
        status.verified >= 260 and status.verified < 340
        or status.verified >= 540 and status.verified < 580
    then
        local positions = native.rooms_positions()
        assert(positions["0"].index ~= positions["1"].index, "Split trial reunited unexpectedly")
        splitFrames = splitFrames + 1
    end
    if status.verified >= 900 and not finished then
        report(
            "RESULT checks="
                .. checks
                .. " leaks="
                .. leaks
                .. " missingOwners="
                .. missingOwners
                .. " outsideList="
                .. outsideList
                .. " familiars="
                .. (renderedTypes[3] or 0)
                .. " knives="
                .. (renderedTypes[8] or 0)
                .. " spears="
                .. spearRenders
        )
        assert(
            checks > 20 and (renderedTypes[3] or 0) > 20 and (renderedTypes[8] or 0) > 20,
            "Familiar and sword rendering was not observed"
        )
        assert(
            missingOwners == 0 and outsideList == 0,
            "Replica rendered an unowned or unlisted familiar/knife"
        )
        assert(leaks == 0, "Offscreen actor's familiars or sword rendered in another room")
        assert(spearRenders > 20, "Spear of Destiny rendering was not observed")
        assert(splitFrames > 60, "Split rooms were not observed for long enough")
        finished = true
        report("PASS shared, split, return and floor cleanup")
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if t == 30 then
            origin = Game():GetLevel():GetCurrentRoomIndex()
            local list = Game():GetLevel():GetRooms()
            for i = 0, list.Size - 1 do
                local d = list:Get(i)
                if d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= origin then
                    other = d.SafeGridIndex
                    break
                end
            end
            assert(other)
            actor(0, function(p)
                clear()
                p:AddCollectible(CollectibleType.COLLECTIBLE_QUINTS)
                p:AddCollectible(CollectibleType.COLLECTIBLE_SPIRIT_SWORD)
                p:AddCollectible(CollectibleType.COLLECTIBLE_SPEAR_OF_DESTINY)
                p:AddCollectible(CollectibleType.COLLECTIBLE_LIL_BRIMSTONE)
                p.Position = Vector(200, 280)
                p:SetMinDamageCooldown(10000)
                p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
            end)
            actor(1, function(p)
                p.Position = Vector(400, 280)
                p:SetMinDamageCooldown(10000)
                p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
            end)
        elseif t == 60 then
            actor(0, function(p)
                for i = 1, 5 do
                    local e = Isaac.Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        0,
                        Vector(120 + 80 * i, 200),
                        Vector.Zero,
                        nil
                    )
                    e:TakeDamage(10000, 0, EntityRef(p), 0)
                end
            end)
        elseif t == 180 then
            assert(native.rooms_move(1, other, 0, 0))
        elseif t == 220 then
            actor(1, function(p)
                clear()
                p.Position = Game():GetRoom():GetCenterPos()
            end)
        elseif t == 240 then
            actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_LITTLE_STEVEN)
                p:AddCollectible(CollectibleType.COLLECTIBLE_DADDY_LONGLEGS)
                for i = 1, 5 do
                    local e = Isaac.Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        0,
                        Vector(120 + 80 * i, 200),
                        Vector.Zero,
                        nil
                    )
                    e:TakeDamage(10000, 0, EntityRef(p), 0)
                end
            end)
        elseif t == 360 then
            assert(native.rooms_move(0, other, 0, 0))
        elseif t == 480 then
            assert(native.rooms_move(0, origin, 0, 0))
        elseif t == 600 then
            assert(native.rooms_move(1, origin, 0, 0))
        elseif t == 720 then
            Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
        end
        if t == 120 then
            actor(0, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == EntityType.ENTITY_FAMILIAR then
                        report(
                            "FAMILIAR variant="
                                .. e.Variant
                                .. " subtype="
                                .. e.SubType
                                .. " flags="
                                .. e:GetEntityFlags()
                        )
                    end
                end
            end)
        end
    end, collect, restore, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
