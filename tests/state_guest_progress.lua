-- Repeated native Lamb victory: the host already owns its hard mark/unlock,
-- while the guest owns neither. Both peers use the same ordinary Isaac run.
local native = assert(_IsaacLan)
local config = _IsaacLanTest or {}
local difficulty, guestMark = config.difficulty or 0, config.guestMark or 0
local f = assert(io.open("./lan-test-role.txt"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt"))
local port = f:read("*l")
f:close()
local owner = { Name = "Repeated guest completion" }
local frame = _IsaacLanFrame
local renders, linked, chosen, started, won, exited = 0, false, false, false, false, false
local step, stepAt, bossRoom, seenBoss = "init", 0, nil, false
local chestMove = false
local done = false
local LAMB_UNLOCK, LAMB_MARK, PRIVATE_UNLOCK = 149, 97, 640
local function report(text)
    Isaac.DebugString("LAN_NETWORK GUEST_PROGRESS " .. text)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function mark(value, tick)
    step, stepAt = value, tick
    report("STEP " .. value .. " tick=" .. tick)
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_END, function(_, gameOver)
    assert(not gameOver and not won, "Expected one native victory")
    won = true
    report("NATIVE_WIN")
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    exited = true
    report("NATIVE_EXIT")
end)
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 480) then
        local unlock, value = native.progress_values(LAMB_UNLOCK, LAMB_MARK)
        assert(
            unlock == ((host or guestMark > 0) and 1 or 0) and value == (host and 3 or guestMark),
            "Startup profile differs"
        )
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
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
        and not started
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "N024KHNP:" .. difficulty .. ":0:0:0:0")
    end
    local confirm = won or host and step == "chest" and status.scene == 2
    native.test_gamepad(confirm and renders % 30 < 5 and 4096 or 0)
    chestMove = false
    if not host and status.prepared and native.rooms_ready() then
        actor(1, function()
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if
                    e.Type == EntityType.ENTITY_PICKUP
                    and e.Variant == PickupVariant.PICKUP_BIGCHEST
                then
                    chestMove = true
                end
            end
        end)
    end
    if
        not done
        and won
        and exited
        and status.phase == 2
        and not status.prepared
        and status.scene == 1
    then
        local unlock, value = native.progress_values(LAMB_UNLOCK, LAMB_MARK)
        local private = native.progress_values(PRIVATE_UNLOCK, 0)
        report("RESTORED unlock=" .. unlock .. " mark=" .. value .. " private=" .. private)
        assert(
            unlock == 1 and value == ((host or difficulty == 1) and 3 or 1),
            "Repeated native win did not award personal progress"
        )
        assert(private == (host and 1 or 0), "Unrelated host unlock leaked")
        done = true
        report("PASS repeated native completion and cleanup")
    end
    return status
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(function()
        return chestMove and _IsaacLanTestInput.buttons(1) or capture()
    end, function(t, n, bytes)
        before(t, n, bytes)
        if not native.rooms_ready() then
            return
        end
        if step == "init" and t > 30 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:SetMinDamageCooldown(10000)
                end)
            end
            Game():SetStateFlag(GameStateFlag.STATE_HEAVEN_PATH, false)
            Game():GetLevel():SetStage(LevelStage.STAGE6, StageType.STAGETYPE_ORIGINAL)
            Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
            mark("floor", t)
        elseif step == "floor" and t - stepAt > 150 then
            local rooms = Game():GetLevel():GetRooms()
            for i = 0, rooms.Size - 1 do
                local d = rooms:Get(i)
                if d.Data and d.Data.Type == RoomType.ROOM_BOSS and d.SafeGridIndex >= 0 then
                    bossRoom = d.SafeGridIndex
                    break
                end
            end
            assert(bossRoom, "Missing native Lamb room")
            for slot = 0, 1 do
                assert(native.rooms_move(slot, bossRoom, 0, -1))
            end
            mark("fight", t)
        elseif step == "fight" and t - stepAt > 120 then
            local clear
            actor(1, function(p)
                local room = Game():GetRoom()
                p.Position, p.Velocity = Vector(160, 220), Vector.Zero
                p:SetMinDamageCooldown(10000)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == EntityType.ENTITY_THE_LAMB then
                        seenBoss = true
                    end
                    if e:IsActiveEnemy(false) and not e:IsDead() and t % 10 == 0 then
                        e:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(p), 0)
                    end
                end
                clear = room:IsClear()
            end)
            if clear and seenBoss then
                mark("chest", t)
            end
        elseif step == "chest" then
            actor(0, function(p)
                p.Position, p.Velocity = Vector(160, 220), Vector.Zero
            end)
            actor(1, function(p)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if
                        e.Type == EntityType.ENTITY_PICKUP
                        and e.Variant == PickupVariant.PICKUP_BIGCHEST
                    then
                        if p:IsExtraAnimationFinished() and (t - stepAt < 120 or t % 90 < 20) then
                            p.Position, p.Velocity = e.Position + Vector(60, 0), Vector.Zero
                        end
                    end
                end
            end)
        end
        assert(t - stepAt < 1800, "Repeated completion stalled: " .. step)
    end, collect, restore, present, beginFloor)
end

return {
    done = function()
        return done
    end,
}
