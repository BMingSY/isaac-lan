-- Native white fire, mirror doorway, ordered Death's List kills and return.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local setup, rooms, scan, searched, mirrorIndex, mirrorSlot, flameAt
local enteredAt, exitedAt, prepared, initial, reward, kills = nil, nil, false, nil, false, 0
local observedLost, observedMirror, observedReturn = false, false, false
local combatRoom, combatAt, nativeTargets, returnedToPortal
local suppressAwards = false
local spawnedRewards = {}
local movement, starts = {}, {}
local sentBubble = false
local exits = { Vector(-1, 0), Vector(0, -1), Vector(1, 0), Vector(0, 1) }
Isaac.AddCallback(
    { Name = "Isolated mirror reward provenance" },
    ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD,
    function()
        if suppressAwards and Game():GetRoom():IsMirrorWorld() then
            Isaac.DebugString("LAN_NETWORK MIRROR_ROUTE SUPPRESSED_CLEAN_AWARD")
            return true
        end
    end
)
local function report(s)
    Isaac.DebugString("LAN_NETWORK MIRROR_ROUTE " .. s)
end
Isaac.AddCallback(
    { Name = "Mirror Death's List reward" },
    ModCallbacks.MC_POST_PICKUP_INIT,
    function(_, pickup)
        if host and suppressAwards and Game():GetRoom():IsMirrorWorld() then
            spawnedRewards[pickup.InitSeed] = kills
            report(
                "REWARD_SPAWN tick="
                    .. Game():GetFrameCount()
                    .. " kills="
                    .. kills
                    .. " variant="
                    .. pickup.Variant
                    .. " subtype="
                    .. pickup.SubType
            )
        end
    end
)
local function guest(fn)
    assert(native.rooms_with_player(1, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()["1"])))
    end, 1))
end
local function mirrorDoor()
    for slot = 0, 7 do
        local door = Game():GetRoom():GetDoor(slot)
        if door and door.TargetRoomIndex == GridRooms.ROOM_MIRROR_IDX then
            return door, slot
        end
    end
end
local function checkPortal(p)
    local door = assert(mirrorDoor(), "Native mirror portal is missing after transfer")
    local distance = p.Position:Distance(door.Position)
    report("PORTAL_DISTANCE " .. distance)
    assert(distance <= 65, "Mirror transfer landed at the opposite wall")
end
local function stats(p)
    return { p.Damage, -p.MaxFireDelay, p.MoveSpeed, p.TearRange, p.Luck, p.ShotSpeed }
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", host and "0:1" or "2:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "MBHM9FSV:0:0:2:0:0")
    end
    local buttons = 0
    if s.prepared and native.api_info().ready == 1 then
        local location = native.rooms_positions()["1"]
        if location.dimension == 1 then
            if not enteredAt then
                guest(function(p)
                    report(
                        "ENTER tick="
                            .. s.verified
                            .. " x="
                            .. p.Position.X
                            .. " y="
                            .. p.Position.Y
                    )
                    checkPortal(p)
                end)
            end
            enteredAt = enteredAt or s.verified
            observedMirror = true
        elseif observedMirror then
            if not exitedAt then
                guest(function(p)
                    report(
                        "EXIT tick=" .. s.verified .. " x=" .. p.Position.X .. " y=" .. p.Position.Y
                    )
                    checkPortal(p)
                end)
            end
            exitedAt = exitedAt or s.verified
            observedReturn = true
        end
        if not host then
            native.api_with_local_view(function()
                local p = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
                local lost = p:GetEffects():HasNullEffect(NullItemID.ID_LOST_CURSE)
                observedLost = observedLost or lost
                if
                    lost
                    and not observedReturn
                    and (not enteredAt or s.verified >= enteredAt + 900)
                then
                    local door, slot = mirrorDoor()
                    if door then
                        local direction = exits[slot % 4 + 1]
                        local mirrored = Game():GetRoom():IsMirrorWorld()
                        local x = direction.X * (mirrored and -1 or 1)
                        buttons = x < 0 and 4 or x > 0 and 8 or direction.Y < 0 and 1 or 2
                    end
                end
            end)
        end
        if exitedAt and s.verified >= exitedAt + 90 and not finished then
            assert(observedMirror and observedReturn, "Mirror return was not exercised")
            if host then
                assert(
                    kills > 0 and nativeTargets > 0 and reward,
                    "Death's List did not reward its ordered kills"
                )
            else
                assert(observedLost, "Guest missed native white-fire form")
            end
            for _, direction in ipairs({ "right", "left" }) do
                assert(
                    (movement[direction] or 0) > 25,
                    "Mirrored input moved the wrong way: " .. direction
                )
            end
            finished = true
            report("PASS native mirror entry, Death's List reward and return")
        end
        if enteredAt and not exitedAt then
            local age = s.verified - enteredAt
            local direction = age >= 690 and age < 720 and "right"
                or age >= 750 and age < 780 and "left"
            if direction then
                guest(function(p)
                    starts[direction] = starts[direction] or p.Position.X
                    local sign = direction == "right" and -1 or 1
                    movement[direction] = math.max(
                        movement[direction] or 0,
                        (p.Position.X - starts[direction]) * sign
                    )
                    if age % 10 == 0 then
                        report(
                            "MOVE "
                                .. direction
                                .. " x="
                                .. p.Position.X
                                .. " body="
                                .. p:GetSprite():GetAnimation()
                        )
                    end
                end)
                if not host then
                    buttons = direction == "right" and 8 or 4
                end
            end
            if not host and age >= 680 and not sentBubble then
                sentBubble = true
                assert(_IsaacLanChatSubmit("镜子中的气泡"))
            end
        end
        assert(s.verified < 2100 or finished, "Mirror route timed out")
    end
    native.test_gamepad(buttons)
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if not native.rooms_ready() then
            return
        end
        if t >= 30 and not setup then
            setup = true
            Game():GetLevel():SetStage(2, StageType.STAGETYPE_REPENTANCE)
            Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
            return
        end
        if not setup or t < 180 then
            return
        end
        if not rooms then
            rooms, scan = {}, 0
            local level = Game():GetLevel()
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                if d.Data.Type == RoomType.ROOM_DEFAULT then
                    rooms[#rooms + 1] = d.SafeGridIndex
                end
            end
        end
        if not mirrorIndex then
            guest(function()
                local _, slot = mirrorDoor()
                if slot then
                    mirrorIndex, mirrorSlot = Game():GetLevel():GetCurrentRoomIndex(), slot
                    report("FOUND index=" .. mirrorIndex .. " slot=" .. slot)
                end
            end)
            if not mirrorIndex and (not searched or t >= searched + 10) then
                scan = scan + 1
                assert(rooms[scan], "Generated mirror doorway was not found")
                assert(native.rooms_move(1, rooms[scan], 0, -1))
                searched = t
            end
            return
        end
        if not flameAt then
            flameAt = t
            guest(function(p)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Remove()
                    end
                end
                Game():GetRoom():SetClear(true)
                p:AddCollectible(CollectibleType.COLLECTIBLE_DEATHS_LIST)
                p.Position = Game():GetRoom():GetCenterPos()
                Isaac.Spawn(EntityType.ENTITY_FIREPLACE, 4, 0, p.Position, Vector.Zero, nil)
            end)
        end
        if not enteredAt and t >= flameAt + 30 then
            guest(function(p)
                assert(
                    p:GetEffects():HasNullEffect(NullItemID.ID_LOST_CURSE),
                    "White fire did not transform guest"
                )
                local door = assert(Game():GetRoom():GetDoor(mirrorSlot))
                if t == flameAt + 30 then
                    p.Position = door.Position - exits[mirrorSlot % 4 + 1] * 32
                    p.Velocity = Vector.Zero
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e.Type == EntityType.ENTITY_FIREPLACE and e.Variant == 4 then
                            e:Remove()
                        end
                    end
                end
            end)
        end
        if enteredAt and not exitedAt then
            local age = t - enteredAt
            if age >= 60 and not prepared then
                prepared = true
                guest(function(p)
                    assert(Game():GetRoom():IsMirrorWorld())
                    assert(p:GetEffects():HasNullEffect(NullItemID.ID_LOST_CURSE))
                    assert(p:HasCollectible(CollectibleType.COLLECTIBLE_DEATHS_LIST))
                    p:SetMinDamageCooldown(10000)
                    p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                    initial = stats(p)
                    local descriptors = Game():GetLevel():GetRooms()
                    for i = 0, descriptors.Size - 1 do
                        local d = descriptors:Get(i)
                        if
                            d.Data
                            and d.Data.Type == RoomType.ROOM_DEFAULT
                            and d.SafeGridIndex ~= mirrorIndex
                        then
                            for j = 0, d.Data.SpawnCount - 1 do
                                local spawn = d.Data.Spawns:Get(j)
                                for k = 0, spawn.EntryCount - 1 do
                                    local kind = spawn.Entries:Get(k).Type
                                    if
                                        kind >= 10
                                        and kind < 1000
                                        and kind ~= EntityType.ENTITY_FIREPLACE
                                        and kind ~= EntityType.ENTITY_MOVABLE_TNT
                                        and kind ~= EntityType.ENTITY_SHOPKEEPER
                                    then
                                        combatRoom = combatRoom or d.SafeGridIndex
                                    end
                                end
                            end
                        end
                    end
                end)
                assert(combatRoom, "No native mirror combat room")
                assert(native.rooms_move(1, combatRoom, 1, -1))
                combatAt = t
            end
            if combatAt and t == combatAt + 30 then
                guest(function(p)
                    nativeTargets = Game():GetRoom():GetAliveEnemiesCount()
                    report(
                        "COMBAT room="
                            .. combatRoom
                            .. " targets="
                            .. nativeTargets
                            .. " item="
                            .. p:GetCollectibleNum(CollectibleType.COLLECTIBLE_DEATHS_LIST)
                    )
                    suppressAwards = true
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e.Type == EntityType.ENTITY_PICKUP then
                            e:Remove()
                        elseif e:IsActiveEnemy(false) then
                            e:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                        end
                    end
                end)
            end
            if combatAt and age >= 120 and age <= 570 and age % 30 == 0 then
                guest(function(p)
                    local mark
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if
                            e.Type == EntityType.ENTITY_EFFECT
                            and e.Variant == EffectVariant.DEATH_SKULL
                        then
                            mark = e
                            break
                        end
                    end
                    if mark then
                        local target, distance
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e:IsActiveEnemy(false)
                                and e:IsVulnerableEnemy()
                                and not e:IsDead()
                            then
                                local d = e.Position:DistanceSquared(mark.Position)
                                if not distance or d < distance then
                                    target, distance = e, d
                                end
                            end
                        end
                        if target then
                            kills = kills + 1
                            report("MARKED_KILL count=" .. kills .. " seed=" .. target.InitSeed)
                            target:TakeDamage(10000, 0, EntityRef(p), 0)
                        end
                    end
                    local after = stats(p)
                    for i, value in ipairs(after) do
                        if value > initial[i] + 0.001 then
                            reward = true
                            report(
                                "STAT_REWARD field="
                                    .. i
                                    .. " before="
                                    .. initial[i]
                                    .. " after="
                                    .. value
                            )
                        end
                    end
                    if
                        not reward
                        and kills > 0
                        and Game():GetRoom():GetAliveEnemiesCount() == 0
                    then
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if
                                e.Type == EntityType.ENTITY_PICKUP
                                and (spawnedRewards[e.InitSeed] or 0) >= nativeTargets
                            then
                                reward = true
                                report(
                                    "PICKUP_REWARD variant="
                                        .. e.Variant
                                        .. " subtype="
                                        .. e.SubType
                                )
                            end
                        end
                    end
                end)
            end
            if age >= 630 and not returnedToPortal then
                returnedToPortal = true
                assert(native.rooms_move(1, mirrorIndex, 1, -1))
            end
            if age == 660 then
                guest(function(p)
                    p.Position, p.Velocity =
                        Game():GetRoom():GetCenterPos() + Vector(0, -80), Vector.Zero
                end)
            end
            if age == 900 then
                guest(function(p)
                    local door, slot = mirrorDoor()
                    assert(door, "Mirror exit disappeared")
                    p.Position, p.Velocity = door.Position - exits[slot % 4 + 1] * 32, Vector.Zero
                end)
            end
        end
    end, collect, restore, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
