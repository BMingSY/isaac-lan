-- One ordinary-sandbox session: actual guest pills / Confessional payments,
-- and split-room Black Candle. The Ascent checks use state_endings.lua.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local linked, chosen, finished, renders = false, false, false, 0
local step, stepAt, paid, snapshots = "curses", 0, false, 0
local origin, boss, machine, initialHearts, attempted = nil, nil, nil, 0, 0
local function report(s)
    Isaac.DebugString("LAN_NETWORK SHARED_CURSES " .. s)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function mark(s, t)
    step, stepAt = s, t
    report("STEP " .. s .. " tick=" .. t)
end
local function find(kind)
    local list = Game():GetLevel():GetRooms()
    for i = 0, list.Size - 1 do
        local d = list:Get(i)
        if d.Data and d.Data.Type == kind and d.SafeGridIndex >= 0 then
            return d.SafeGridIndex
        end
    end
end
local function move(slot, index)
    assert(native.rooms_move(slot, index, 0, -1))
    actor(slot, function(p)
        p.Position, p.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:IsActiveEnemy(false) then
                e:Remove()
            end
        end
        p:SetMinDamageCooldown(10000)
    end)
end
local function pill(effect)
    actor(1, function(p)
        local color = Game():GetItemPool():ForceAddPillEffect(effect)
        assert(Game():GetItemPool():GetPillEffect(color, p) == effect)
        p:SetCard(0, 0)
        p:SetPill(0, color)
    end)
end
local function curse(mask, name)
    assert(Game():GetLevel():GetCurses() == mask, name .. " authority curse mask differs")
    report("CURSES " .. name .. " mask=" .. mask)
end
local frame = _IsaacLanFrame
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
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    local t = s.verified
    native.test_gamepad(not host and (t >= 100 and t < 106 or t >= 230 and t < 236) and 512 or 0)
    return s
end
local function advance(t)
    local level = Game():GetLevel()
    if step == "curses" then
        if t == 30 then
            origin, boss = level:GetCurrentRoomIndex(), assert(find(RoomType.ROOM_BOSS))
            level:RemoveCurses(level:GetCurses())
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:AddMaxHearts(24)
                    p:AddHearts(24)
                    p:SetMinDamageCooldown(10000)
                end)
            end
        elseif t == 60 then
            pill(PillEffect.PILLEFFECT_AMNESIA)
        elseif t == 170 then
            curse(LevelCurse.CURSE_OF_THE_LOST, "guest Amnesia")
        elseif t == 190 then
            pill(PillEffect.PILLEFFECT_QUESTIONMARK)
        elseif t == 300 then
            curse(LevelCurse.CURSE_OF_THE_LOST | LevelCurse.CURSE_OF_MAZE, "guest ???")
            move(0, boss)
        elseif t == 330 then
            actor(1, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_BLACK_CANDLE)
            end)
        elseif t == 390 then
            curse(0, "remote Black Candle")
            level:AddCurse(LevelCurse.CURSE_OF_THE_LOST | LevelCurse.CURSE_OF_MAZE, false)
        elseif t == 450 then
            curse(0, "Black Candle protects later curses")
            actor(1, function(p)
                p:RemoveCollectible(CollectibleType.COLLECTIBLE_BLACK_CANDLE)
            end)
        elseif t == 500 then
            level:AddCurse(LevelCurse.CURSE_OF_THE_LOST | LevelCurse.CURSE_OF_MAZE, false)
            mark("confessional", t)
            actor(1, function(p)
                initialHearts = p:GetHearts()
            end)
        end
    elseif step == "confessional" then
        actor(1, function(p)
            p:ResetDamageCooldown()
            local e = machine and machine.Ref
            if not e or not e:Exists() or (t - stepAt) % 160 == 1 then
                if e and e:Exists() then
                    e:Remove()
                end
                attempted = attempted + 1
                e = Game():Spawn(
                    6,
                    17,
                    Game():GetRoom():GetCenterPos(),
                    Vector.Zero,
                    nil,
                    0,
                    attempted
                )
                machine = EntityPtr(e)
            end
            local away = (t - stepAt) % 60 < 20
            p.Position = e.Position + Vector(away and 60 or 0, 0)
            p.Velocity = Vector(away and -1 or 1, 0)
            paid = paid or p:GetHearts() < initialHearts
            if p:GetHearts() < 12 then
                p:AddHearts(24)
            end
        end)
        if level:GetCurses() == 0 then
            assert(paid, "Confessional cleared curses without an actual guest payment")
            curse(0, "native guest Confessional")
            actor(1, function()
                if machine and machine.Ref then
                    machine.Ref:Remove()
                end
            end)
            mark("done", t)
        end
    elseif step == "done" and not finished and t - stepAt > 100 then
        finished = true
        report("PASS shared curses and native Confessional")
    end
    assert(t - stepAt < 1600, "Shared route stalled at " .. step)
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        advance(t)
    end, function(slot, t)
        local bytes = collect(slot, t)
        if not bytes then
            return bytes
        end
        return string.pack(">s4", bytes) .. _IsaacLanState.encode({ step, finished })
    end, function(bytes, t, ack)
        local body, pos = string.unpack(">s4", bytes)
        if restore(body, t, ack) == false then
            return false
        end
        local value = _IsaacLanState.decode(body)
        assert(Game():GetLevel():GetCurses() == value[17], "Replica shared curse mask differs")
        snapshots = snapshots + 1
        local meta = _IsaacLanState.decode(bytes:sub(pos))
        if meta[1] ~= step then
            step = meta[1]
            report("REPLICA_STEP " .. step .. " mask=" .. value[17])
        end
        if meta[2] and not finished then
            assert(snapshots > 100)
            finished = true
            report("PASS shared curses and native Confessional")
        end
        return true
    end, present, beginFloor)
end
