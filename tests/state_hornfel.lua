local testInput = assert(_IsaacLanTestInput)
-- One protected pair: native Hornfel AI/rendering, room recreation, rejoin,
-- next floor and death. Mines I uses its generated Hornfel encounter;
-- Mines II fixture-spawns the on-foot variant for allocation/cleanup coverage.
local native, host, port = assert(_IsaacLan), _IsaacLanTest.host, _IsaacLanTest.port
local linked, chosen, finished, renders = false, false, false, 0
local phase, at, origin, arena = "start", 0, nil, nil
local departed, rejoined, leaveRequested, joinRequested = false, false, false, false
local exitAt, snapshots, held, seenFloors, clearTicks = nil, 0, 0, {}, 0
local visible, railViews, cartViews = 0, 0, 0
local owner = { Name = "Hornfel replica regression" }
local function report(message)
    Isaac.DebugString("LAN_NETWORK SIDE hornfel " .. message)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local exitCallback = function()
    if not host and leaveRequested and not rejoined then
        exitAt = native.api_info().nowMs
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, exitCallback)
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    local failed = s.phase == 4 or (s.phase == 9 and s.error ~= "")
    if failed then
        Isaac.DebugString("LAN_NETWORK FAILED " .. s.error)
    end
    assert(not failed, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "0N1B0EE9:0:0:0:0:0")
    end
    if not host and not leaveRequested and s.phase == 3 and s.verified >= 850 then
        leaveRequested = true
        assert(native.net_command(4))
        report("LEAVE")
    end
    if
        exitAt
        and not joinRequested
        and s.phase == 0
        and s.scene == 1
        and native.api_info().nowMs - exitAt > 2000
    then
        joinRequested = true
        _IsaacLanCommand("join", "127.0.0.1:" .. port)
        report("REJOIN_REQUEST")
    end
    if joinRequested and s.prepared and s.phase == 3 and not rejoined then
        rejoined = true
        report("REJOIN_READY")
    end
    return s
end
local function floor(stage)
    Game():SetStateFlag(GameStateFlag.STATE_SECRET_PATH, true)
    Game():GetLevel():SetStage(stage, StageType.STAGETYPE_REPENTANCE)
    Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
end
local function enterArena()
    local level = Game():GetLevel()
    origin, arena = level:GetCurrentRoomIndex(), nil
    local rooms = level:GetRooms()
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc.Data and desc.Data.Type == RoomType.ROOM_BOSS then
            arena = desc.SafeGridIndex
            if desc.Data.Shape == RoomShape.ROOMSHAPE_1x1 then
                break
            end
        end
    end
    assert(arena, "Mines boss room missing")
    assert(native.rooms_move(0, arena, 0, -1))
end
local function setup(variant)
    actor(0, function()
        assert(Game():GetLevel():GetCurrentRoomIndex() == arena)
        local npc
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if variant == 0 and e.Type == EntityType.ENTITY_HORNFEL and e.Variant == 0 then
                npc = e:ToNPC()
            elseif variant == 1 and e:IsBoss() then
                e:Remove()
            end
        end
        if variant == 1 then
            npc = Game():Spawn(
                EntityType.ENTITY_HORNFEL,
                variant,
                Game():GetRoom():GetCenterPos(),
                Vector.Zero,
                nil,
                0,
                123457
            ):ToNPC()
        end
        assert(npc, "Seed no longer generates the native Hornfel encounter")
        npc.MaxHitPoints, npc.HitPoints = 2000, 2000
        Game():GetRoom():SetClear(false)
        report("HOST_BACKDROP " .. Game():GetRoom():GetBackdropType())
    end)
    report(
        "SETUP stage="
            .. Game():GetLevel():GetStage()
            .. " variant="
            .. variant
            .. " room="
            .. arena
    )
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        function()
            return testInput.neutral
        end,
        function(t, n, b)
            before(t, n, b)
            for slot = 0, 1 do
                if native.rooms_heads()[tostring(slot)] then
                    actor(slot, function(p)
                        p:SetMinDamageCooldown(120)
                    end)
                end
            end
            if phase == "start" and t >= 30 then
                floor(3)
                phase, at = "floor1", t
            elseif
                phase == "floor1"
                and t > at + 180
                and native.rooms_ready()
                and Game():GetLevel():GetStage() == 3
            then
                enterArena()
                phase = "enter1"
            elseif phase == "enter1" and native.rooms_positions()["0"].index == arena then
                setup(0)
                phase, at = "combat", t
            elseif phase == "combat" then
                if t == at + 60 then
                    assert(native.rooms_move(1, arena, 0, -1))
                    report("ENTER_OCCUPIED")
                elseif t == at + 350 then
                    assert(native.rooms_move(1, origin, 0, -1))
                    report("LEAVE_ROOM")
                elseif t == at + 400 then
                    assert(native.rooms_move(1, arena, 0, -1))
                    report("REENTER_ROOM")
                end
                if native.rooms_connected() == 1 then
                    departed = true
                end
                if departed and native.rooms_connected() == 3 then
                    rejoined = true
                    phase, at = "returned", t
                    report("HOST_REJOINED")
                end
            elseif phase == "returned" and t > at + 180 then
                floor(4)
                phase, at = "floor2", t
            elseif
                phase == "floor2"
                and t > at + 180
                and native.rooms_ready()
                and Game():GetLevel():GetStage() == 4
            then
                enterArena()
                phase = "enter2"
            elseif phase == "enter2" and native.rooms_positions()["0"].index == arena then
                setup(1)
                phase, at = "combat2", t
            elseif phase == "combat2" then
                if t == at + 60 then
                    assert(native.rooms_move(1, arena, 0, -1))
                    report("ENTER_NEXT_FLOOR")
                elseif t >= at + 500 then
                    actor(0, function(p)
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e.Type == EntityType.ENTITY_HORNFEL then
                                e:TakeDamage(
                                    100000,
                                    DamageFlag.DAMAGE_IGNORE_ARMOR,
                                    EntityRef(p),
                                    0
                                )
                                e:Kill()
                            end
                        end
                    end)
                    phase, at = "death", t
                    report("NATIVE_DEATH")
                end
            elseif phase == "death" then
                local alive = false
                actor(0, function()
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e.Type == EntityType.ENTITY_HORNFEL and e:Exists() then
                            alive = true
                        end
                    end
                end)
                clearTicks = alive and 0 or clearTicks + 1
                if clearTicks >= 90 and not finished then
                    assert(rejoined)
                    finished = true
                    report("PASS host room, rejoin, floor and death")
                end
            end
            if t % 300 == 0 then
                report("HOST tick=" .. t .. " phase=" .. phase)
            end
        end,
        collect,
        function(bytes, t, ack, betweenUpdates, stable)
            if restore(bytes, t, ack, betweenUpdates, stable) == false then
                return false
            end
            local view = _IsaacLanState.decode(bytes, stable)
            local found = false
            assert(native.rooms_with_player(1, function()
                assert(native.room_rails() == view[11][9], "Room rails differ")
                if snapshots == 1 then
                    report("CLIENT_BACKDROP " .. Game():GetRoom():GetBackdropType())
                end
                local entities = {}
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:Exists() then
                        entities[e:GetData().__isaac_lan_replica or -1] = e
                    end
                end
                for _, v in ipairs(view[11][3]) do
                    if v[25] ~= 0 then
                        local rider, cart = assert(entities[v[1]]), assert(entities[v[25]])
                        assert(
                            native.entity_minecart(rider:GetSprite()) == cart.Index,
                            "Minecart reference differs"
                        )
                        cartViews = cartViews + 1
                    end
                    if v[2] == EntityType.ENTITY_HORNFEL then
                        found = true
                        local boss = assert(entities[v[1]])
                        if boss.Visible then
                            visible = visible + 1
                        end
                        if view[11][9]:find("[^\255]") then
                            railViews = railViews + 1
                        end
                        local first, second = string.unpack(">I4I4", v[24])
                        local actualFirst, actualSecond = native.boss_held_bombs(boss:GetSprite())
                        assert(
                            actualFirst == (first == 0 and -1 or assert(entities[first]).Index),
                            "First bomb differs"
                        )
                        assert(
                            actualSecond == (second == 0 and -1 or assert(entities[second]).Index),
                            "Second bomb differs"
                        )
                        if first ~= 0 or second ~= 0 then
                            held = held + 1
                        end
                        snapshots = snapshots + 1
                        seenFloors[view[4]] = true
                    end
                end
            end))
            clearTicks = not found and seenFloors[4] and clearTicks + 1 or 0
            if clearTicks >= 60 and rejoined and not finished then
                assert(
                    snapshots > 300
                        and held > 0
                        and visible > 100
                        and railViews > 300
                        and cartViews > 300
                        and seenFloors[3]
                        and seenFloors[4],
                    "Missing Hornfel coverage"
                )
                finished = true
                report(
                    "PASS client snapshots="
                        .. snapshots
                        .. " held="
                        .. held
                        .. " visible="
                        .. visible
                        .. " rails="
                        .. railViews
                        .. " carts="
                        .. cartViews
                )
            end
        end,
        present,
        beginFloor
    )
end

-- Explicit test-only lifecycle consumed by both suite coordinators.
return {
    done = function()
        return finished
    end,
}
