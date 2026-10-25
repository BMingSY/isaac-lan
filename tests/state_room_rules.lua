-- Native 80 ms RTT acceptance, with distinct protected personal-save marks.
local native, host, port = _IsaacLan, _IsaacLanTest.host, _IsaacLanTest.port
local route = _IsaacLanTest.route
local enabled = route ~= "room-rules-off" and route ~= "room-rules-items-off"
local resume = route == "room-rules-resume"
local base, gate, menu = _IsaacLanFrame, native.net_gate, _IsaacLanMenuRender
local owner = RegisterMod("Isaac LAN room rules fixture", 1)
local json = require("json")
local renders, linked, configured, finished, snapshots = 0, false, false, false, 0
local tick, lobbyAt, chooseAt, index, began, initialized = 0, nil, 0, 1, nil, false
local marksChecked, readOnlyChecked, lastHealth = false, false, {}
local events, nativeExplosions, results = {}, {}, {}
local buttons, currentCase, knivesSeen = 0, nil, 0
local lastCaseAt = -100
local targetFlag = enabled and 1 or 0
local function report(event, value)
    Isaac.DebugString(
        "LAN_NETWORK SIDE " .. route .. " " .. event .. " " .. json.encode(value or {})
    )
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        for i = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if player.ControllerIndex == slot + 1 then
                return fn(player)
            end
        end
        error("Missing fixture actor " .. slot)
    end))
end
local function health(slot)
    local result
    actor(slot, function(p)
        result = p:GetHearts()
    end)
    return result
end
local function ghost(slot)
    local result
    actor(slot, function(p)
        result = p:IsCoopGhost()
    end)
    return result
end
local function clear(slot)
    actor(slot or 0, function()
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:ToNPC() or e:ToTear() or e:ToLaser() or e:ToKnife() or e:ToBomb() then
                e:Remove()
            end
        end
        Game():GetRoom():SetClear(true)
    end)
end
local function restoreHealth()
    for slot = 0, 1 do
        actor(slot, function(p)
            assert(not p:IsDead() and not p:IsCoopGhost())
            p:AddSoulHearts(-p:GetSoulHearts())
            p:AddEternalHearts(-p:GetEternalHearts())
            p:AddMaxHearts(24 - p:GetMaxHearts())
            p:AddHearts(24)
            p:AddCacheFlags(CacheFlag.CACHE_ALL)
            p:EvaluateItems()
            p.Position, p.Velocity = Vector(slot == 0 and 160 or 340, 200), Vector.Zero
        end)
    end
end
local function ready()
    local ok = true
    for slot = 0, 1 do
        actor(slot, function(p)
            ok = ok and p:GetDamageCooldown() == 0 and not p:HasInvincibility()
        end)
    end
    return ok
end
local function tear(damage, attacker, victim)
    attacker, victim = attacker or 0, victim or 1
    local position
    actor(victim, function(p)
        position = p.Position
    end)
    actor(attacker, function(p)
        local value = p:FireTear(position - Vector(12, 0), Vector(6, 0), false, true, false)
        value.CollisionDamage = damage
    end)
end
local function explosion(kind, victim)
    local position
    actor(victim, function(p)
        position = p.Position
    end)
    actor(0, function(p)
        local item = kind == "doctor" and CollectibleType.COLLECTIBLE_DR_FETUS
            or CollectibleType.COLLECTIBLE_IPECAC
        p:AddCollectible(item)
        p:AddCacheFlags(CacheFlag.CACHE_ALL)
        p:EvaluateItems()
        if kind == "doctor" then
            p:FireBomb(position, Vector.Zero):SetExplosionCountdown(1)
        else
            local shot = p:FireTear(position, Vector.Zero, false, true, false)
            assert(
                shot:HasTearFlags(TearFlags.TEAR_EXPLOSIVE),
                "Ipecac fixture did not fire Ipecac"
            )
            -- Self control uses exactly the native tear's explosion. For the
            -- ally case the production contact detector triggers that explosion.
            if victim == 0 or not enabled then
                shot:Die()
            end
        end
        p:RemoveCollectible(item)
        p:AddCacheFlags(CacheFlag.CACHE_ALL)
        p:EvaluateItems()
    end)
end
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
    local p = entity:ToPlayer()
    if p and host then
        report("damage", {
            tick = tick,
            slot = p.ControllerIndex - 1,
            amount = amount,
            flags = flags,
            source = source.Type,
            cooldown = p:GetDamageCooldown(),
        })
    end
end)
_IsaacLanMenuRender = function(available, visible, ...)
    return menu(available, _IsaacLanStatus().phase == 2 or visible, ...)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        _IsaacLanMenuOpen(true)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = base()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    local now = native.api_info().nowMs
    if s.phase == 2 and s.players == 2 then
        if not marksChecked and s.marks0 and s.marks1 then
            for seat = 0, 1 do
                for layer = 1, 12 do
                    assert(
                        s["marks" .. seat][layer] == (layer - 1 + seat) % 3,
                        "Personal completion card differs at seat/layer " .. seat .. "/" .. layer
                    )
                end
            end
            marksChecked = true
            report("personal_marks", { host = s.marks0, guest = s.marks1 })
        end
        if not host and not readOnlyChecked then
            assert(not native.net_configure_options(1), "Guest changed room rules")
            readOnlyChecked = true
        end
        if s["ready" .. s.slot] == 0 and now - chooseAt > 250 then
            chooseAt = now
            _IsaacLanCommand("choose", "0:1")
        end
        if host and s.ready0 == 1 and s.ready1 == 1 and marksChecked then
            if not configured then
                assert(native.net_configure_options(1))
                if not enabled then
                    assert(native.net_configure_options(0))
                end
                local changed = native.net_poll()
                assert(changed.ready0 == 0 and changed.ready1 == 0, "Rule change kept readiness")
                configured, lobbyAt = true, now
                report("rules", { options = changed.roomOptions })
            elseif now - lobbyAt > 6000 then
                assert(s.roomOptions == targetFlag)
                if resume then
                    local count, options = native.net_saved_info()
                    assert(count == 2 and options == 1, "Saved room rules were lost")
                    assert(native.net_resume(), "Native resume failed")
                else
                    _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
                end
            end
        end
    end
    native.test_gamepad(host and buttons or 0)
    return s
end
local cases = {}
local nativeLaserHits = {}
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_NPC_UPDATE, function(_, npc)
    if host and not npc:GetData().RoomRulesLaserTarget then
        return true
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, _, _, source)
    if host and entity:ToNPC() then
        nativeLaserHits[#nativeLaserHits + 1] = Game():GetFrameCount()
    end
end)
local function add(name, action, check, duration)
    cases[#cases + 1] = { name = name, action = action, check = check, duration = duration or 40 }
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, knife)
    if host and currentCase == "knife" then
        knivesSeen = knivesSeen + 1
        if knivesSeen % 6 == 1 then
            report("knife_pose", {
                x = knife.Position.X,
                y = knife.Position.Y,
                damage = knife.CollisionDamage,
                rotation = knife.Rotation,
                flying = knife:IsFlying(),
            })
        end
    end
end)
add("starting_tear", function(at)
    if at <= 44 and at % 11 == 0 then
        tear(3.5)
    end
end, function()
    assert(health(1) == (enabled and 22 or 24), "Starting tear accumulation differs")
end, 65)
if enabled and not resume then
    add("guest_attack", function(at)
        if at <= 44 and at % 11 == 0 then
            tear(3.5, 1, 0)
        end
    end, function()
        assert(health(0) == 22, "Guest attack did not hurt host")
    end, 65)
    add("weak_hits", function(at)
        if at <= 60 and at % 6 == 0 then
            tear(0.7)
        end
        if at == 59 then
            assert(health(1) == 24, "Weak damage applied before threshold")
        end
    end, function()
        assert(health(1) == 23, "Weak hits did not accumulate")
    end, 80)
    local duelTimes = {}
    local function duel(name, interval, damage, count, minimum, maximum)
        local reached
        add(name, function(at)
            if at == 0 then
                actor(0, function(p)
                    p.MaxFireDelay, p.Damage = interval - 1, damage
                end)
            end
            if not reached and health(1) <= 18 then
                reached = at / 30
            end
            if not reached and at % interval == 0 then
                for _ = 1, count do
                    tear(damage)
                end
            end
        end, function()
            assert(
                reached and reached >= minimum and reached <= maximum,
                name .. " native time differs: " .. tostring(reached)
            )
            duelTimes[name] = reached
            report("pvp_time", { name = name, seconds = reached, health = health(1) })
            if name == "heavy_equal_dps" then
                assert(
                    math.abs(reached - duelTimes.rapid_equal_dps) <= 0.7,
                    "Equal-DPS native attacks diverged"
                )
            end
        end, 180)
    end
    duel("ordinary_duel", 11, 3.5, 1, 4, 5)
    duel("five_rate_ten_damage", 6, 10, 1, 2.5, 3.5)
    duel("strong_duel", 3, 10, 1, 2, 3.3)
    duel("rapid_equal_dps", 3, 1, 1, 3.8, 5)
    duel("heavy_equal_dps", 30, 10, 1, 3.8, 5)
    duel("scatter_duel", 11, 3.5, 6, 2, 3.5)
    add("native_hurt_protection", function(at)
        if at == 0 then
            actor(1, function(p)
                p:TakeDamage(1, 0, EntityRef(nil), 0)
            end)
        elseif at == 5 or at == 10 then
            tear(1000)
        end
    end, function()
        assert(health(1) == 23, "PvP bypassed native environmental protection")
    end)
    add("extended_protection", function(at)
        if at == 0 then
            tear(8)
        elseif at == 5 then
            assert(health(1) == 23)
            actor(1, function(p)
                p:SetMinDamageCooldown(180)
            end)
        elseif at == 10 or at == 15 then
            tear(1000)
        end
    end, function()
        assert(health(1) == 23, "PvP shortened extended native protection")
    end)
    add("item_invincibility", function(at)
        if at == 0 then
            actor(1, function(p)
                p:UseActiveItem(
                    CollectibleType.COLLECTIBLE_BOOK_OF_SHADOWS,
                    UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER
                )
            end)
        elseif at == 5 or at == 15 then
            tear(1000)
        end
    end, function()
        assert(health(1) == 24, "PvP bypassed Book of Shadows")
    end)
    add("holy_mantle", function(at)
        if at == 0 then
            actor(1, function(p)
                p:GetEffects():AddCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE, false)
            end)
            tear(84)
        end
    end, function()
        assert(health(1) == 24, "Friendly fire bypassed Holy Mantle")
        actor(1, function(p)
            p:GetEffects():RemoveCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE, -1)
        end)
    end)
    add("wafer", function(at)
        if at == 0 then
            actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_WAFER)
                p:TakeDamage(2, 0, EntityRef(nil), 0)
            end)
            actor(1, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_WAFER)
            end)
            tear(15)
        end
    end, function()
        assert(
            health(1) == health(0) and health(1) < 24,
            "Friendly fire differs from native Wafer damage"
        )
        actor(0, function(p)
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_WAFER)
        end)
        actor(1, function(p)
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_WAFER)
        end)
    end)
    add("wafer_explosion", function(at)
        if at == 0 then
            actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_WAFER)
                p:TakeDamage(4, DamageFlag.DAMAGE_EXPLOSION, EntityRef(p), 0)
            end)
            local source
            actor(0, function(p)
                source = p
            end)
            actor(1, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_WAFER)
                p:TakeDamage(4, DamageFlag.DAMAGE_EXPLOSION, EntityRef(source), 0)
            end)
        end
    end, function()
        assert(health(0) == 22 and health(1) == health(0), "Explosion applied Wafer twice")
        for slot = 0, 1 do
            actor(slot, function(p)
                p:RemoveCollectible(CollectibleType.COLLECTIBLE_WAFER)
            end)
        end
    end)
    add("continuous_laser", function(at)
        if at == 0 then
            actor(0, function(p)
                local npc =
                    Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, Vector(480, 200), Vector.Zero, nil)
                npc.HitPoints, npc.MaxHitPoints = 10000, 10000
                npc:GetData().RoomRulesLaserTarget = true
                npc:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
                npc:ToNPC().State = 3
                npc:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                local laser = EntityLaser.ShootAngle(2, p.Position, 0, 25, Vector.Zero, p)
                laser.CollisionDamage = 0.7
            end)
        end
    end, function()
        assert(health(1) == 23, "Continuous laser did not accumulate raw damage")
        report("native_laser_cadence", nativeLaserHits)
    end)
    add("laser_ring_edge", function(at)
        if at == 0 then
            actor(0, function(p)
                local ring = p:FireTechXLaser(Vector(300, 200), Vector.Zero, 40)
                ring.CollisionDamage = 3.5
                ring:SetTimeout(20)
            end)
        end
    end, function()
        assert(health(1) == 23, "Native Tech X ring edge missed")
    end)
    add("laser_ring_center", function(at)
        if at == 0 then
            actor(0, function(p)
                local ring = p:FireTechXLaser(Vector(340, 200), Vector.Zero, 100)
                ring.CollisionDamage = 3.5
                ring:SetTimeout(20)
            end)
        end
    end, function()
        assert(health(1) == 24, "Native ring's empty center hurt its target")
    end)
    add("knife", function(at)
        if at == 0 then
            actor(1, function(p)
                p.Position = Vector(290, 200)
            end)
            actor(0, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
            end)
        end
        buttons = at < 30 and 0x2000 or 0
    end, function()
        assert(knivesSeen > 0, "Native knife input did not create a knife")
        assert(health(1) < 24, "Native thrown knife missed friendly contact")
        actor(0, function(p)
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
        end)
    end, 80)
    local sourceRoom, otherRoom
    add("separate_rooms", function(at)
        if at == 0 then
            sourceRoom = native.rooms_positions()["0"].index
            actor(0, function()
                local rooms = Game():GetLevel():GetRooms()
                for i = 0, rooms.Size - 1 do
                    local room = rooms:Get(i)
                    if
                        room.SafeGridIndex ~= sourceRoom
                        and room.SafeGridIndex >= 0
                        and room.Data
                        and room.Data.Type == RoomType.ROOM_DEFAULT
                    then
                        otherRoom = room.SafeGridIndex
                        break
                    end
                end
            end)
            assert(otherRoom and native.rooms_move(1, otherRoom, 0, -1))
        elseif at == 25 then
            assert(native.rooms_positions()["1"].index == otherRoom)
            clear(1)
            tear(84)
        elseif at == 45 then
            assert(health(1) == 24, "Friendly fire crossed native rooms")
            assert(native.rooms_move(1, sourceRoom, 0, -1))
        end
    end, function()
        assert(native.rooms_positions()["1"].index == sourceRoom and health(1) == 24)
    end, 80)
end
for _, kind in ipairs({ "doctor", "ipecac" }) do
    add(kind .. "_self", function(at)
        if at == 0 then
            explosion(kind, 0)
        end
    end, function()
        nativeExplosions[kind] = 24 - health(0)
        assert(
            nativeExplosions[kind] > 0 and nativeExplosions[kind] <= 2,
            "Native self explosion control failed"
        )
    end)
    add(kind .. "_ally", function(at)
        if at == 0 then
            explosion(kind, 1)
        end
    end, function()
        assert(
            24 - health(1) == (enabled and nativeExplosions[kind] or 0),
            "Explosion differs from original player damage: " .. kind
        )
    end)
end
if enabled and not resume then
    add("burst_and_lethal", function(at)
        if at == 0 then
            actor(1, function(p)
                p:AddMaxHearts(6 - p:GetMaxHearts())
                p:AddHearts(6)
            end)
            for _ = 1, 8 do
                tear(1000)
            end
        elseif at == 5 then
            assert(health(1) == 3, "Scatter burst exceeded half maximum health")
            tear(1000)
        elseif at == 9 then
            assert(health(1) == 3, "Burst protection did not block a follow-up")
        elseif at == 15 then
            tear(1000)
        end
    end, function()
        actor(1, function(p)
            assert(
                p:IsCoopGhost() or p:IsDead(),
                "Later PvP attack could not finish a wounded player"
            )
        end)
    end, 120)
end
if route == "room-rules-items" or route == "room-rules-items-off" then
    cases = {}
    addPvpItemCases({
        add = add,
        actor = actor,
        health = health,
        report = report,
        host = host,
        enabled = enabled,
        clear = clear,
    })
end
local function advance(t)
    tick = t
    if not native.rooms_ready() or finished or t < 30 then
        return
    end
    assert(native.api_info().roomOptions == targetFlag, "Gameplay room rules changed")
    if resume then
        if t > 100 then
            finished = true
            report("resume", { options = targetFlag })
        end
        return
    end
    if not initialized then
        clear()
        restoreHealth()
        initialized = true
    end
    local case = cases[index]
    if not began then
        if not ready() or t - lastCaseAt <= 31 then
            return
        end
        clear()
        restoreHealth()
        began, events, lastHealth = t, {}, { 24, 24 }
        currentCase = case.name
        report("begin", { name = case.name, tick = tick })
    end
    for slot = 0, 1 do
        local value = health(slot)
        if value ~= lastHealth[slot + 1] then
            local event = { tick = tick, slot = slot, before = lastHealth[slot + 1], after = value }
            events[#events + 1] = event
            report("health", event)
            lastHealth[slot + 1] = value
        end
    end
    local elapsed = t - began
    case.action(elapsed)
    if elapsed >= case.duration then
        case.check()
        results[#results + 1] = { case.name, health(0), health(1) }
        report("pass", results[#results])
        index, began, lastCaseAt = index + 1, nil, t
        if index > #cases then
            finished = true
        end
    end
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        advance(t)
    end, function(slot, t)
        local body, stable = collect(slot, t)
        if not body then
            return body, stable
        end
        return string.pack(">s4", body) .. _IsaacLanState.encode({
            finished,
            health(0),
            health(1),
            index,
            ghost(0),
            ghost(1),
        }),
            stable
    end, function(bytes, t, ack, between, stable)
        local body, at = string.unpack(">s4", bytes)
        if restore(body, t, ack, between, stable) == false then
            return false
        end
        if finished then
            -- The suite has released this fixture. Exit can replace player
            -- bodies before the final world publications drain; keep unwrapping
            -- its wire envelope without inspecting released fixture actors.
            return true
        end
        local meta = _IsaacLanState.decode(bytes:sub(at))
        for slot = 0, 1 do
            local isGhost = ghost(slot)
            assert(isGhost == meta[slot + 5], "Replica ghost state differs")
            -- Native ghost bodies keep non-combat heart storage. Death and
            -- revival use the synchronized ghost state, not that storage.
            assert(
                isGhost or health(slot) == meta[slot + 2],
                "Guest health differs from authority: tick="
                    .. t
                    .. " slot="
                    .. slot
                    .. " actual="
                    .. health(slot)
                    .. " expected="
                    .. meta[slot + 2]
            )
        end
        assert(native.api_info().roomOptions == targetFlag, "Replica lost room options")
        snapshots = snapshots + 1
        if meta[1] and not finished then
            assert(snapshots > 30 and marksChecked and readOnlyChecked)
            finished = true
            report("replica_pass", { snapshots = snapshots })
        end
        return true
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        _IsaacLanMenuRender = menu
    end,
}
