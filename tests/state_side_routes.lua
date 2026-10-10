-- Source floors are prepared once; route entrances, drops and exits are native.
local native = assert(_IsaacLan)
local host, port, route = _IsaacLanTest.host, _IsaacLanTest.port, _IsaacLanTest.route
local linked, chosen, finished, renders = false, false, false, 0
local snapshots, checkpoint, observed = 0, {}, {}
local endTick = route == "poop" and 1000 or route == "hush" and 2200 or 7000
local frame = _IsaacLanFrame
local function report(s)
    Isaac.DebugString("LAN_NETWORK SIDE " .. route .. " " .. s)
end
local function actor(slot, call)
    assert(native.rooms_with_player(slot, function()
        call(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
function _IsaacLanFrame()
    renders = renders + 1
    if EID and EID.Config then
        EID.Config.DisableStartOfRunWarnings = true
    end
    native.test_gamepad(0)
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    local fixture = s.scene == 1 and select(2, native.progress_values(640, 522))
    if not linked and fixture == (host and 98765 or 321) and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", (not host and route == "poop" and "25" or "0") .. ":1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        local seed = route == "knife" and Seeds.Seed2String(1477942995):gsub("%s", "") or "YPVLAR60"
        _IsaacLanCommand("start", seed .. ":0:0:" .. (route == "poop" and "25" or "0") .. ":0:0")
    end
    if
        not finished
        and (
            s.verified >= endTick
            or host and checkpoint.complete
            or not host and observed.complete and snapshots > 200
        )
    then
        if host then
            assert(checkpoint.complete, "Native route did not complete: " .. route)
        else
            assert(snapshots > 200, "Insufficient route snapshots")
            assert(observed.complete, "Replica missed route completion: " .. route)
        end
        finished = true
        report("PASS native route snapshots=" .. snapshots)
    end
    return s
end
local step, stepAt, origin, other, boss = "init", 0
local firstMana, seenHush, exitPosition, cartRoom, cartPosition = nil, false
local rooms, roomNumber, buttons, visited = {}, 0, 0, {}
local knife, shadow = false, false
local function mark(name, t)
    step, stepAt = name, t
    report("STEP " .. name .. " tick=" .. t)
end
local function move(index, t)
    assert(native.rooms_move(1, index, 0, -1))
    mark("room-wait", t)
end
local function source(stage, kind, t)
    Game():SetStateFlag(GameStateFlag.STATE_SECRET_PATH, route == "knife")
    Game():GetLevel():SetStage(stage, kind)
    Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
    mark("source-wait", t)
end
local function trap()
    local result
    actor(1, function(p)
        local room = Game():GetRoom()
        for i = 0, room:GetGridSize() - 1 do
            local g = room:GetGridEntity(i)
            if
                g
                and (
                    g:GetType() == GridEntityType.GRID_TRAPDOOR
                    or g:GetType() == GridEntityType.GRID_STAIRS
                )
            then
                result = g.Position
                p.Position, p.Velocity = result, Vector.Zero
                report("NATIVE_EXIT grid=" .. g:GetType())
                break
            end
        end
    end)
    return result
end
local function protect()
    for slot = 0, 1 do
        actor(slot, function(p)
            p:SetMinDamageCooldown(10000)
            p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
        end)
    end
end
local function poop(t)
    if t == 40 then
        origin = Game():GetLevel():GetCurrentRoomIndex()
        local list = Game():GetLevel():GetRooms()
        for i = 0, list.Size - 1 do
            local d = list:Get(i)
            if d.SafeGridIndex ~= origin and d.Data.Type == RoomType.ROOM_DEFAULT then
                other = d.SafeGridIndex
                break
            end
        end
        assert(other)
        actor(1, function(p)
            p:AddPoopMana(10)
            firstMana = p:GetPoopMana()
            assert(firstMana > 0)
        end)
    elseif t == 220 then
        actor(1, function(p)
            assert(p:GetPoopMana() < firstMana, "Poop input did not consume mana")
        end)
        assert(native.rooms_move(1, other, 0, -1))
        report("SEPARATE_ROOMS")
    elseif t == 340 then
        actor(1, function(p)
            p:UsePoopSpell(PoopSpellType.SPELL_BURNING)
        end)
        report("NATIVE_SPELL fire")
    elseif t == 440 then
        assert(native.rooms_move(0, other, 0, -1))
        report("SHARED_ROOM")
    elseif t == 540 then
        actor(1, function(p)
            p:UsePoopSpell(PoopSpellType.SPELL_HOLY)
        end)
        report("NATIVE_SPELL holy")
    elseif t == 660 then
        source(3, StageType.STAGETYPE_REPENTANCE, t)
    elseif t == 880 then
        assert(Game():GetLevel():GetStage() == 3 and native.rooms_ready())
        checkpoint.complete = true
        report("CHECKED mana queue spells room and floor transfer")
    end
end
local function hush(t)
    if step == "init" and t >= 30 then
        local void, count = native.progress_values(320, 158)
        assert(void and count >= 3, "Hush continuation requires the host's previous completion")
        report("PREREQUISITE_FIXTURE host_hush_kills=" .. count .. " void_unlocked=true")
        source(9, 0, t)
    elseif step == "source-wait" and t - stepAt > 160 then
        origin = Game():GetLevel():GetCurrentRoomIndex()
        local list = Game():GetLevel():GetRooms()
        for i = 0, list.Size - 1 do
            local d = list:Get(i)
            if d.Data.Type == RoomType.ROOM_BOSS then
                boss = d.SafeGridIndex
                break
            end
        end
        assert(boss, "Blue Womb lacks a Boss room")
        assert(native.rooms_move(1, boss, 0, -1))
        mark("fight", t)
    elseif step == "fight" then
        local clear
        actor(1, function(p)
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e:IsBoss() then
                    if e.Type == 407 then
                        seenHush = true
                    end
                    if e.FrameCount > 45 then
                        e:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(p), 0)
                    end
                end
            end
            clear = Game():GetRoom():IsClear()
        end)
        if seenHush and clear then
            assert(native.rooms_move(0, boss, 0, -1))
            visited = {}
            mark("reward", t)
            report("CHECKED native Hush defeat and clear")
        end
    elseif (step == "reward" or step == "exit-room") and t - stepAt > 100 then
        if step == "reward" then
            actor(1, function()
                local light, void = false, false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    assert(
                        e.Type ~= 5 or e.Variant ~= 340,
                        "Hush incorrectly spawned an ending chest"
                    )
                    if e.Type == 1000 and e.Variant == EffectVariant.HEAVEN_LIGHT_DOOR then
                        light = true
                    end
                end
                for slot = 0, 7 do
                    local door = Game():GetRoom():GetDoor(slot)
                    if door and door:IsOpen() and door.TargetRoomIndex ~= origin then
                        void = true
                        report("NATIVE_VOID_DOOR index=" .. door.TargetRoomIndex)
                    end
                end
                assert(light and void, "Hush lacks Cathedral light or Void doorway")
            end)
        end
        exitPosition = trap()
        if step == "reward" then
            assert(exitPosition, "Hush lacks its native Sheol trapdoor")
            report("CHECKED all three native Hush exits and no ending chest")
        end
        if exitPosition then
            mark("exit-wait", t)
        else
            actor(1, function(p)
                local room = Game():GetRoom()
                visited[Game():GetLevel():GetCurrentRoomIndex()] = true
                for slot = 0, 7 do
                    local door = room:GetDoor(slot)
                    if door and door:IsOpen() and not visited[door.TargetRoomIndex] then
                        report("NATIVE_EXIT_ROOM index=" .. door.TargetRoomIndex)
                        Game():StartRoomTransition(door.TargetRoomIndex, door.Direction, 0, p, 0)
                        mark("exit-room", t)
                        break
                    end
                end
            end)
        end
    elseif step == "exit-wait" then
        if Game():GetLevel():GetStage() ~= 9 and native.rooms_ready() then
            local pos = native.rooms_positions()
            assert(pos["0"].index == pos["1"].index, "Hush exit stranded one player")
            checkpoint.complete = true
            mark("done", t)
            report("CHECKED Hush continuation stage=" .. Game():GetLevel():GetStage())
        elseif exitPosition then
            actor(1, function(p)
                p.Position, p.Velocity = exitPosition, Vector.Zero
            end)
        end
    end
end
local function mines(t)
    if step == "init" and t >= 30 then
        actor(1, function(p)
            p:AddCollectible(CollectibleType.COLLECTIBLE_KNIFE_PIECE_1)
        end)
        report("PREREQUISITE_FIXTURE knife_piece_1=626")
        source(4, StageType.STAGETYPE_REPENTANCE, t)
    elseif step == "source-wait" and t - stepAt > 160 then
        assert(Game():GetLevel():GetStage() == 4)
        origin = Game():GetLevel():GetCurrentRoomIndex()
        local list = Game():GetLevel():GetRooms()
        for i = 0, list.Size - 1 do
            local d = list:Get(i)
            report(
                "FLOOR_ROOM index="
                    .. d.SafeGridIndex
                    .. " type="
                    .. d.Data.Type
                    .. " name="
                    .. d.Data.Name
            )
            if
                d.SafeGridIndex >= 0
                and d.SafeGridIndex < 169
                and d.Data.Type ~= RoomType.ROOM_BOSS
            then
                local mapped = Game():GetLevel():GetRoomByIdx(d.SafeGridIndex, 0)
                if mapped and mapped.Data and mapped.ListIndex == d.ListIndex then
                    rooms[#rooms + 1] = d.SafeGridIndex
                end
            end
        end
        roomNumber = 1
        move(rooms[roomNumber], t)
    elseif step == "room-wait" and t - stepAt > 40 then
        local button
        actor(1, function(p)
            local room = Game():GetRoom()
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == 965 and e.Variant == 10 then
                    cartRoom = Game():GetLevel():GetCurrentRoomIndex()
                    report("NATIVE_CART type=" .. e.Type .. " variant=" .. e.Variant)
                elseif e:IsActiveEnemy(false) then
                    e:Kill()
                end
            end
            for i = 0, room:GetGridSize() - 1 do
                local g = room:GetGridEntity(i)
                if
                    g
                    and g:GetType() == GridEntityType.GRID_PRESSURE_PLATE
                    and not visited[room:GetDecorationSeed() .. ":" .. i]
                then
                    visited[room:GetDecorationSeed() .. ":" .. i] = true
                    button = g.Position
                    report("NATIVE_BUTTON variant=" .. g:GetVariant() .. " index=" .. i)
                    break
                end
            end
            if button then
                p.Position, p.Velocity = button, Vector.Zero
            end
        end)
        if button then
            exitPosition = button
            buttons = buttons + 1
            mark("button", t)
        else
            roomNumber = roomNumber + 1
            if roomNumber <= #rooms then
                move(rooms[roomNumber], t)
            else
                assert(
                    cartRoom and buttons >= 3,
                    "Mines II did not expose three switches and a cart"
                )
                assert(native.rooms_move(1, cartRoom, 0, -1))
                mark("cart", t)
            end
        end
    elseif step == "button" then
        actor(1, function(p)
            p.Position, p.Velocity = exitPosition, Vector.Zero
        end)
        if t - stepAt > 40 then
            mark("room-wait", t)
        end
    elseif step == "cart" and t - stepAt > 60 then
        actor(1, function(p)
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == 965 and e.Variant == 10 then
                    cartPosition = e.Position
                    break
                end
            end
            assert(cartPosition, "Native empty cart disappeared")
            p.Position, p.Velocity = cartPosition, Vector.Zero
        end)
        mark("cart-wait", t)
    elseif step == "cart-wait" then
        local pos = native.rooms_positions()["1"]
        if pos.dimension ~= 0 or pos.index ~= cartRoom then
            report("CHECKED native minecart entrance index=" .. pos.index)
            visited = {}
            mark("tunnel", t)
        else
            actor(1, function(p)
                p.Position, p.Velocity = cartPosition, Vector.Zero
            end)
        end
    elseif step == "tunnel" and t - stepAt > 60 then
        actor(1, function(p)
            local room = Game():GetRoom()
            local position = native.rooms_positions()["1"]
            if knife and shadow and position.dimension == 0 and position.index == cartRoom then
                assert(p:HasCollectible(627), "Native shaft return lost knife piece 2")
                checkpoint.complete = true
                mark("done", t)
                report("CHECKED knife piece chase and original floor return")
                return
            end
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == 5 and e.Variant == 100 and e.SubType == 627 then
                    e:ToPickup().Wait = 0
                    p.Position, p.Velocity = e.Position, Vector.Zero
                    mark("knife-wait", t)
                    report("NATIVE_KNIFE_PICKUP")
                    return
                end
                if e:GetSprite():GetFilename():lower():find("shadow", 1, true) then
                    shadow = true
                    report("NATIVE_SHADOW type=" .. e.Type)
                end
            end
            visited[room:GetDecorationSeed()] = true
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door:IsOpen() then
                    local desc = Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex, -1)
                    if desc and desc.Data and not visited[desc.DecorationSeed] then
                        Game():StartRoomTransition(door.TargetRoomIndex, door.Direction, 0, p, -1)
                        stepAt = t
                        report("NATIVE_TUNNEL_DOOR index=" .. door.TargetRoomIndex)
                        return
                    end
                end
            end
        end)
    elseif step == "knife-wait" then
        local acquired = false
        actor(1, function(p)
            acquired = p:HasCollectible(627)
            if t - stepAt > 180 then
                assert(acquired, "Native knife collision did not grant piece 2")
            end
        end)
        -- Native collectible pickup grants the item after its lift animation.
        if acquired then
            knife = true
            visited = {}
            mark("tunnel", t)
            report("CHECKED native knife piece 2 acquired")
        end
    end
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local inputTick = 0
    return gate(
        function()
            local values = {}
            local use = not host
                and route == "poop"
                and (inputTick == 120 or inputTick == 320 or inputTick == 520)
            for action = 0, 15 do
                values[#values + 1] = string.pack(
                    ">I2",
                    (
                        use and action == ButtonAction.ACTION_PILLCARD
                        or not host
                            and route == "poop"
                            and action == 5
                            and inputTick % 200 > 140
                    )
                            and 65535
                        or 0
                )
            end
            values[#values + 1] = string.pack(">I2", use and 1 << ButtonAction.ACTION_PILLCARD or 0)
            inputTick = inputTick + 1
            return table.concat(values)
        end,
        function(t, n, bytes)
            before(t, n, bytes)
            if not native.rooms_ready() then
                return
            end
            protect()
            if route == "poop" then
                poop(t)
            elseif route == "hush" then
                hush(t)
            else
                mines(t)
            end
        end,
        collect,
        function(bytes, t, ack)
            if restore(bytes, t, ack) == false then
                return false
            end
            snapshots = snapshots + 1
            local value = _IsaacLanState.decode(bytes)
            if route == "poop" then
                for _, a in ipairs(value[9]) do
                    if a[4][1] == 25 then
                        local p = Isaac.GetPlayer(a[1])
                        local mana = string.unpack(">I4", a[7])
                        assert(p:GetPoopMana() == mana, "Replica poop mana differs")
                        for i = 0, 5 do
                            assert(p:GetPoopSpell(i) == a[7]:byte(5 + i), "Replica queue differs")
                        end
                    end
                end
                if value[4] == 3 and t > 800 then
                    observed.complete = true
                end
            elseif route == "hush" then
                if value[4] ~= 9 and t > 300 then
                    observed.complete = true
                end
            else
                local p = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
                local position = native.rooms_positions()["1"]
                if p:HasCollectible(627) and position.dimension == 0 and position.index >= 0 then
                    observed.complete = true
                end
            end
        end,
        present,
        beginFloor
    )
end
