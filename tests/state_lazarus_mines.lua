-- One pair, one connection: native room-clear Flip, active Flip, and Mines.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local function report(value)
    Isaac.DebugString("LAN_NETWORK " .. value)
end
local linked, chosen, finished, renders = false, false, false, 0
local snapshots, changes, lastTypes, motion, poses = 0, {}, {}, {}, {}
local checkpoint = {}
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if EID and EID.Config then
        EID.Config.DisableStartOfRunWarnings = true
    end
    local status = frame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    native.test_gamepad(0)
    local fixture = status.scene == 1 and select(2, native.progress_values(640, 522))
    if not linked and fixture == (host and 98765 or 321) and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", (host and "0" or "29") .. ":1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YPVLAR60:0:0:29:0:0")
    end
    if status.verified >= 1400 and not finished then
        if host then
            assert(
                checkpoint.clear
                    and checkpoint.active
                    and checkpoint.host
                    and checkpoint.boss
                    and checkpoint.mines2
                    and checkpoint.birthright
                    and checkpoint.arrival
            )
        else
            assert(snapshots > 300, "Too few authoritative snapshots")
            assert((changes[1] or 0) >= 4, "Native form changes were not replicated")
            for _, kind in ipairs({ 29, 38 }) do
                local positions, animations = 0, 0
                for _ in pairs(motion[kind] or {}) do
                    positions = positions + 1
                end
                for _ in pairs(poses[kind] or {}) do
                    animations = animations + 1
                end
                assert(
                    positions > 8 and animations > 3,
                    "Replacement body stopped moving or animating: " .. kind
                )
                report(
                    "ANIMATED type="
                        .. kind
                        .. " positions="
                        .. positions
                        .. " poses="
                        .. animations
                )
            end
        end
        finished = true
        report("PASS native Lazarus forms and Mines combat")
    end
    return status
end
local function actor(slot, call)
    assert(native.rooms_with_player(slot, function()
        local index = native.rooms_heads()[tostring(slot)]
        if not index then
            local values = {}
            for i = 0, Game():GetNumPlayers() - 1 do
                local p = Isaac.GetPlayer(i)
                values[#values + 1] = i .. ":" .. p.ControllerIndex .. ":" .. p:GetPlayerType()
            end
            error("Missing scoped head slot=" .. slot .. " actors=" .. table.concat(values, ","))
        end
        call(Isaac.GetPlayer(index))
    end))
end
local attackCount = 0
local function kill(slot)
    attackCount = attackCount + 1
    actor(slot, function(p)
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if
                entity:ToNPC()
                and not entity:IsDead()
                and entity.HitPoints > 0
                and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            then
                entity:ClearEntityFlags(EntityFlag.FLAG_FREEZE)
                entity:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(p), 0)
                if not entity:IsDead() and attackCount % 5 == 0 then
                    local tear = p:FireTear(
                        entity.Position + Vector(-40, 0),
                        Vector(8, 0),
                        false,
                        true,
                        false
                    )
                    tear.CollisionDamage = 1000000
                end
            end
        end
    end)
end
local function flip(slot)
    actor(slot, function(p)
        p:UseActiveItem(CollectibleType.COLLECTIBLE_FLIP, 0, -1)
    end)
    report("NATIVE_ACTIVE_FLIP slot=" .. slot)
end
local function verify(name, types)
    for slot = 0, 1 do
        actor(slot, function(p)
            assert(p:GetPlayerType() == types[slot + 1], name .. " unexpected form slot=" .. slot)
            assert(p.ControllerIndex == slot + 1, name .. " reordered native actor slots")
        end)
    end
    checkpoint[name] = true
    report("CHECKED " .. name)
end
local origin, combat, boss, floorAt, arrivalFlip, arrivalKind
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local inputTick = 0
    local function input()
        local values = {}
        local direction = ({ 0, 2, 1, 3 })[math.floor(inputTick / 12) % 4 + 1]
        for action = 0, 15 do
            values[#values + 1] =
                string.pack(">I2", not host and action == direction and 65535 or 0)
        end
        values[#values + 1] = string.pack(">I2", 0)
        inputTick = inputTick + 1
        return table.concat(values)
    end
    return gate(input, function(t, n, bytes)
        before(t, n, bytes)
        if t == 30 then
            Game():SetStateFlag(GameStateFlag.STATE_SECRET_PATH, true)
            Game():GetLevel():SetStage(3, StageType.STAGETYPE_REPENTANCE)
            Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
        elseif t == 220 then
            assert(native.rooms_ready())
            local level = Game():GetLevel()
            assert(level:GetStage() == 3 and level:GetStageType() == StageType.STAGETYPE_REPENTANCE)
            origin = level:GetCurrentRoomIndex()
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                if d.Data.Type == RoomType.ROOM_BOSS then
                    boss = d.SafeGridIndex
                end
                if
                    d.Data.Type == RoomType.ROOM_DEFAULT
                    and d.SafeGridIndex ~= origin
                    and not d.Clear
                    and not combat
                then
                    combat = d.SafeGridIndex
                end
            end
            assert(combat and boss)
            assert(native.rooms_move(1, combat, 0, -1))
            report("MINES_1 separate-room combat")
        elseif t == 380 then
            actor(1, function()
                assert(Game():GetRoom():IsClear(), "Combat did not clear natively")
            end)
            verify("clear", { 0, 38 })
        elseif t == 430 then
            flip(1)
        elseif t == 500 then
            verify("active", { 0, 29 })
        elseif t == 520 then
            assert(native.rooms_move(1, origin, 0, -1))
        elseif t == 560 then
            flip(1)
        elseif t == 620 then
            verify("host", { 0, 38 })
        elseif t == 660 then
            assert(native.rooms_move(1, boss, 0, -1))
        elseif t == 720 then
            assert(native.rooms_move(0, boss, 0, -1))
        elseif t == 850 then
            verify("boss", { 0, 38 })
        elseif t == 860 then
            actor(1, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
            end)
            report("BIRTHRIGHT_FIXTURE native two listed bodies")
        elseif t == 900 then
            assert(native.rooms_move(1, origin, 0, -1))
            assert(native.rooms_move(0, origin, 0, -1))
        elseif t == 1000 then
            -- This character regression prepares Mines II directly. Native
            -- reward and route exits are covered by the side-route fixtures.
            Game():GetLevel():SetStage(4, StageType.STAGETYPE_REPENTANCE)
            Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
        end
        if t > 1000 and not checkpoint.mines2 and native.rooms_ready() then
            local level = Game():GetLevel()
            if level:GetStage() == 4 and level:GetStageType() == StageType.STAGETYPE_REPENTANCE then
                checkpoint.mines2, floorAt = true, t
                report("CHECKED mines2")
            end
        end
        if floorAt and t > floorAt + 40 and not checkpoint.birthright then
            local level = Game():GetLevel()
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                local mapped = level:GetRoomByIdx(d.SafeGridIndex, 0)
                if
                    d.SafeGridIndex >= 0
                    and d.SafeGridIndex < 169
                    and d.SafeGridIndex ~= level:GetCurrentRoomIndex()
                    and d.Data.Type == RoomType.ROOM_DEFAULT
                    and mapped
                    and mapped.ListIndex == d.ListIndex
                then
                    assert(native.rooms_move(1, d.SafeGridIndex, 0, -1))
                    checkpoint.birthright = true
                    report("BIRTHRIGHT separate-room transfer index=" .. d.SafeGridIndex)
                    break
                end
            end
            assert(checkpoint.birthright, "Missing a main-floor Birthright test room")
        end
        if floorAt and t > floorAt + 80 and not arrivalFlip then
            arrivalFlip = true
            actor(1, function(p)
                arrivalKind = p:GetPlayerType() == 29 and 38 or 29
            end)
            flip(1)
        end
        if floorAt and t > floorAt + 120 and not checkpoint.arrival then
            verify("arrival", { 0, arrivalKind })
        end
        if t >= 225 and native.rooms_ready() then
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:SetMinDamageCooldown(10000)
                    p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                end)
            end
        end
        if t >= 320 and t < 350 then
            kill(1)
        end
    end, function(slot, t)
        local bytes = collect(slot, t)
        if t < 3 then
            for _, a in ipairs(_IsaacLanState.decode(bytes)[9]) do
                report(
                    "AUTH_ROSTER index=" .. a[1] .. " controller=" .. a[2] .. " type=" .. a[4][1]
                )
            end
        end
        return bytes
    end, function(bytes, t, ack)
        if t < 3 then
            for i = 0, Game():GetNumPlayers() - 1 do
                local p = Isaac.GetPlayer(i)
                report(
                    "REPLICA_ROSTER index="
                        .. i
                        .. " controller="
                        .. p.ControllerIndex
                        .. " type="
                        .. p:GetPlayerType()
                )
            end
        end
        if restore(bytes, t, ack) == false then
            return false
        end
        snapshots = snapshots + 1
        local value = _IsaacLanState.decode(bytes)
        for _, a in ipairs(value[9]) do
            local p, slot = Isaac.GetPlayer(a[1]), a[2] - 1
            assert(
                p.ControllerIndex == a[2] and p:GetPlayerType() == a[4][1],
                "Replica body differs from authoritative form"
            )
            local kind = p:GetPlayerType()
            if lastTypes[slot] and lastTypes[slot] ~= kind then
                changes[slot] = (changes[slot] or 0) + 1
                report("REPLACED slot=" .. slot .. " type=" .. kind .. " tick=" .. t)
            end
            lastTypes[slot] = kind
        end
    end, function(...)
        present(...)
        local index = native.rooms_heads()["1"]
        if index then
            local p = Isaac.GetPlayer(index)
            local kind = p:GetPlayerType()
            motion[kind], poses[kind] = motion[kind] or {}, poses[kind] or {}
            motion[kind][math.floor(p.Position.X) .. ":" .. math.floor(p.Position.Y)] = true
            local head = p:GetSprite()
            local body = assert(native.actor_sprites(index, head)[1])
            poses[kind][head:GetAnimation() .. ":" .. head:GetFrame() .. "," .. body:GetAnimation() .. ":" .. body:GetFrame()] =
                true
        end
    end, beginFloor)
end
