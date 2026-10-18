local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local owner = { Name = "Special movement regression" }
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished, tick = 0, false, false, false, 0
local stationaryChecks, dungeonChecks, heldChecks = 0, 0, 0
local ghostChecks, ghostDoor = 0, nil
local function report(s)
    Isaac.DebugString("LAN_NETWORK SPECIAL " .. s)
end
local function guest(fn)
    assert(native.rooms_with_player(1, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()["1"])), Game():GetRoom())
    end))
end
-- Door cases use real directional input after placing the actor just inside
-- the source aperture. Both unoccupied and resident destinations are checked.
local doorPhase, doorAt, doorCases, doorIndex, doorChecked = "floor", 0, {}, 0, 0
local doorMask, selectedRoom, selectedStage, doorway = 0, nil, 11, nil
local doorTargets, targetIndex = {}, 0
local inward = { Vector(1, 0), Vector(0, 1), Vector(-1, 0), Vector(0, -1) }
local function clearRoom()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:ToNPC() then
            e:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function doors(t)
    if not native.rooms_ready() then
        doorAt = t
        return
    end
    local level = Game():GetLevel()
    if doorPhase == "floor" then
        if selectedRoom then
            -- Maze may redirect the setup move to a different neighbor. This
            -- fixture checks the selected aperture and ghost landing only.
            level:RemoveCurses(level:GetCurses())
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                if d.Data.Shape == RoomShape.ROOMSHAPE_LTL then
                    doorTargets[#doorTargets + 1] = d.SafeGridIndex
                    break
                end
            end
            if #doorTargets > 0 then
                doorPhase = "inspect-next"
                return
            end
            error("Missing deterministic LTL room")
        end
        level:SetStage(selectedStage, StageType.STAGETYPE_ORIGINAL)
        Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
        selectedRoom = true
        doorPhase = "floor-wait"
        doorAt = t
    elseif doorPhase == "floor-wait" and t - doorAt > 90 then
        doorPhase = "floor"
    elseif doorPhase == "inspect-next" then
        targetIndex = targetIndex + 1
        if not doorTargets[targetIndex] then
            doorPhase = "next"
            return
        end
        assert(native.rooms_move(1, doorTargets[targetIndex], 0, -1))
        doorPhase = "inspect"
        doorAt = t
    elseif doorPhase == "inspect" and t - doorAt > 30 then
        guest(function(_, room)
            clearRoom()
            do
                local slot = DoorSlot.RIGHT0
                local door = room:GetDoor(slot)
                if door and door.TargetRoomIndex >= 0 then
                    local source = level:GetRoomByIdx(door.TargetRoomIndex, 0).SafeGridIndex
                    ghostDoor = { target = doorTargets[targetIndex], source = source }
                    for _, resident in ipairs({ false, true }) do
                        doorCases[#doorCases + 1] = {
                            target = doorTargets[targetIndex],
                            source = source,
                            entry = slot,
                            resident = resident,
                        }
                    end
                end
            end
        end)
        doorPhase = "inspect-next"
    elseif doorPhase == "next" then
        doorIndex = doorIndex + 1
        doorway = doorCases[doorIndex]
        if not doorway then
            assert(doorChecked == 2, "Missing repeated outer door case")
            doorPhase = "ghost-setup"
            return
        end
        local target = doorway.resident and doorway.target or level:GetStartingRoomIndex()
        assert(native.rooms_move(0, target, 0, -1))
        assert(native.rooms_move(1, doorway.source, 0, -1))
        doorPhase = "approach"
        doorAt = t
    elseif doorPhase == "approach" and t - doorAt > 30 then
        guest(function(p, room)
            clearRoom()
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if
                    door
                    and door.TargetRoomIndex >= 0
                    and slot % 4 == (doorway.entry % 4 + 2) % 4
                    and level:GetRoomByIdx(door.TargetRoomIndex, 0).SafeGridIndex
                        == doorway.target
                then
                    door:Open()
                    p.Position = door.Position + inward[slot % 4 + 1] * 32
                    p.Velocity = Vector.Zero
                    doorMask = ({ 1, 4, 2, 8 })[slot % 4 + 1]
                    report(
                        "DOOR_WALK source="
                            .. doorway.source
                            .. " target="
                            .. doorway.target
                            .. " expected="
                            .. doorway.entry
                            .. " resident="
                            .. tostring(doorway.resident)
                    )
                    doorPhase = "walk"
                    doorAt = t
                    return
                end
            end
            error("Missing door from source")
        end)
    elseif doorPhase == "walk" then
        if native.rooms_positions()["1"].index == doorway.target then
            doorMask = 0
            guest(function(p, room)
                local expected = assert(room:GetDoor(doorway.entry)).Position
                    + inward[doorway.entry % 4 + 1] * 40
                report(
                    "DOOR_ARRIVAL shape="
                        .. room:GetRoomShape()
                        .. " pos="
                        .. tostring(p.Position)
                        .. " expected="
                        .. tostring(expected)
                )
                assert(room:IsPositionInRoom(p.Position, 5), "Door arrival landed outside L room")
                assert(
                    (p.Position - expected):Length() < 5,
                    "Door arrival used a different aperture"
                )
            end)
            doorChecked = doorChecked + 1
            doorPhase = "check"
            doorAt = t
        else
            assert(t - doorAt < 180, "Door input did not transition")
        end
    elseif doorPhase == "check" and t - doorAt > 30 then
        doorPhase = "next"
    elseif doorPhase == "ghost-setup" then
        assert(ghostDoor, "Missing outer door for ghost follow")
        assert(native.rooms_move(0, ghostDoor.source, 0, -1))
        assert(native.rooms_move(1, ghostDoor.source, 0, -1))
        doorPhase, doorAt = "ghost-kill", t
    elseif doorPhase == "ghost-kill" and t - doorAt > 30 then
        guest(function(p)
            clearRoom()
            p:ChangePlayerType(PlayerType.PLAYER_BLUEBABY_B)
            p:Kill()
        end)
        doorPhase, doorAt = "ghost-ready", t
    elseif doorPhase == "ghost-ready" and t - doorAt > 120 then
        guest(function(p, room)
            assert(p:IsCoopGhost(), "Guest did not become a co-op ghost")
            p.Position, p.Velocity = room:GetCenterPos(), Vector.Zero
        end)
        assert(native.rooms_with_player(0, function()
            local p, room = Isaac.GetPlayer(assert(native.rooms_heads()["0"])), Game():GetRoom()
            clearRoom()
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if
                    door
                    and door.TargetRoomIndex >= 0
                    and level:GetRoomByIdx(door.TargetRoomIndex, 0).SafeGridIndex
                        == ghostDoor.target
                then
                    door:Open()
                    p.Position, p.Velocity = door.Position + inward[slot % 4 + 1] * 32, Vector.Zero
                    doorMask = ({ 1, 4, 2, 8 })[slot % 4 + 1]
                    doorPhase, doorAt = "ghost-walk", t
                    return
                end
            end
            error("Missing survivor return door")
        end))
    elseif doorPhase == "ghost-walk" then
        if native.rooms_positions()["0"].index == ghostDoor.target then
            doorMask = 0
            doorPhase, doorAt = "ghost-follow", t
        else
            assert(t - doorAt < 180, "Survivor did not walk through door")
        end
    elseif doorPhase == "ghost-follow" and t - doorAt > 30 then
        guest(function(p, room)
            assert(
                native.rooms_positions()["1"].index == ghostDoor.target,
                "Ghost did not follow survivor"
            )
            assert(
                room:IsPositionInRoom(p.Position, 5),
                "Ghost kept departure coordinates in missing L quadrant"
            )
            local survivor = Isaac.GetPlayer(assert(native.rooms_heads()["0"]))
            assert(
                (p.Position - survivor.Position):Length() < 30,
                "Ghost did not arrive beside survivor"
            )
            report("GHOST_ARRIVAL pos=" .. tostring(p.Position) .. " inside=true")
        end)
        ghostChecks = ghostChecks + 1
        doorPhase, doorAt = "ghost-check", t
    elseif doorPhase == "ghost-check" and t - doorAt > 30 then
        if ghostChecks < 2 then
            assert(native.rooms_move(0, ghostDoor.source, 0, -1))
            doorPhase, doorAt = "ghost-ready", t
        else
            level:SetStage(1, StageType.STAGETYPE_ORIGINAL)
            Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
            doorPhase, doorAt = "floor-cleanup", t
        end
    elseif doorPhase == "floor-cleanup" and t - doorAt > 120 then
        for slot = 0, 1 do
            assert(native.rooms_with_player(slot, function()
                local p = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
                assert(
                    Game():GetRoom():IsPositionInRoom(p.Position, 5),
                    "Floor retained an old arrival"
                )
                assert(native.actor_held_entity(p:GetSprite()) == -1, "Floor retained a held body")
            end))
        end
        doorPhase = "done"
    end
end

local function move(t)
    if t >= 900 then
        return doorMask
    end
    if t >= 410 and t < 445 then
        return 2
    end
    if t < 60 or t >= 360 and t < 450 or t > 840 then
        return 0
    end
    if t >= 450 and t < 510 then
        return 1
    end
    return 1 << (math.floor(t / 30) % 4)
end
local function botEnabled()
    return host == (doorPhase:match("^ghost") ~= nil)
end
function _IsaacLanBotFrame()
    native.input_bot(botEnabled() and 1 or 0, move(tick))
end
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function()
    return false
end, EntityType.ENTITY_PLAYER)
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    tick = s.verified
    if s.phase == 2 and not chosen then
        chosen = true
        assert(native.net_choose(0, 1))
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    native.input_bot(botEnabled() and s.phase == 3 and 1 or 0, move(tick))
    if s.phase == 4 or s.phase == 9 then
        Isaac.DebugString("LAN_NETWORK FAILED " .. s.error)
    end
    if doorPhase == "done" and not finished then
        if not host then
            assert(
                stationaryChecks >= 10 and dungeonChecks >= 5 and heldChecks >= 5,
                "Missing special motion coverage"
            )
        end
        native.input_bot(0, 0)
        finished = true
        report("PASS movement and ghost arrival")
    end
    return s
end
local function soulBody()
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        if p.ControllerIndex == 2 and p:GetPlayerType() == PlayerType.PLAYER_THESOUL_B then
            return p
        end
    end
    error("Missing tainted soul")
end
local function sample(label)
    guest(function(p, room)
        for i = 0, Game():GetNumPlayers() - 1 do
            local e = Isaac.GetPlayer(i)
            if e.ControllerIndex == 2 then
                local a = not host and _IsaacLanState.actorPose(e)
                local d = e:GetMovementInput()
                if
                    not host
                    and e:GetPlayerType() == PlayerType.PLAYER_THESOUL_B
                    and tick >= 200
                    and tick < 260
                then
                    assert(
                        native.actor_held_entity(e:GetSprite()) == p.Index,
                        "Carried skeleton reference missing"
                    )
                    heldChecks = heldChecks + 1
                end
                if not host and tick >= 290 and tick < 310 then
                    assert(
                        native.actor_held_entity(e:GetSprite()) == -1,
                        "Thrown skeleton reference retained"
                    )
                end
                if
                    not host
                    and e:GetPlayerType() == PlayerType.PLAYER_THEFORGOTTEN_B
                    and tick >= 90
                    and tick < 170
                then
                    assert(
                        a and (e.Position - Vector(a.x, a.y)):Length() < 0.01,
                        "Stationary skeleton followed movement input"
                    )
                    stationaryChecks = stationaryChecks + 1
                end
                if not host and room:GetType() == RoomType.ROOM_DUNGEON then
                    assert(
                        a and (e.Position - Vector(a.x, a.y)):Length() < 30,
                        "Dungeon used ordinary walking prediction"
                    )
                    dungeonChecks = dungeonChecks + 1
                end
                if renders % 60 == 0 then
                    local function actorKind(link)
                        return link and link:ToPlayer() and link:ToPlayer():GetPlayerType() or -1
                    end
                    report(
                        "LINK t="
                            .. tick
                            .. " kind="
                            .. e:GetPlayerType()
                            .. " parent="
                            .. actorKind(e.Parent)
                            .. " child="
                            .. actorKind(e.Child)
                            .. " holding="
                            .. tostring(e:IsHoldingItem())
                            .. " offset="
                            .. tostring(e.SpriteOffset)
                    )
                    report(
                        string.format(
                            "%s t=%d i=%d kind=%d room=%d pos=%.2f,%.2f vel=%.2f,%.2f input=%.2f,%.2f host=%s anim=%s fly=%s collide=%d",
                            label,
                            tick,
                            i,
                            e:GetPlayerType(),
                            room:GetType(),
                            e.Position.X,
                            e.Position.Y,
                            e.Velocity.X,
                            e.Velocity.Y,
                            d.X,
                            d.Y,
                            a and string.format("%.2f,%.2f", a.x, a.y) or "-",
                            e:GetSprite():GetAnimation(),
                            tostring(e.CanFly),
                            room:GetGridCollisionAtPos(e.Position)
                        )
                    )
                end
            end
        end
    end)
end
native.net_gate = function(capture, apply, collect, restore, present, stage)
    return gate(capture, function(t, n, b)
        apply(t, n, b)
        if not host then
            return
        end
        if t >= 900 then
            doors(t)
            return
        end
        if t == 30 then
            guest(function(p, room)
                p:ChangePlayerType(PlayerType.PLAYER_THEFORGOTTEN_B)
                p.Position = room:GetCenterPos() + Vector(100, 0)
                if p:GetSubPlayer() then
                    p:GetSubPlayer().Position = room:GetCenterPos() - Vector(100, 0)
                end
            end)
        end
        if t == 180 then
            guest(function(p)
                local soul = soulBody()
                soul.Position = p.Position + Vector(16, 0)
                assert(soul:TryHoldEntity(p), "Could not carry skeleton")
                report("CARRIED")
            end)
        end
        if t == 270 then
            guest(function(p)
                local soul = soulBody()
                assert(soul:ThrowHeldEntity(Vector(-12, 0)), "Could not throw skeleton")
                report("THROWN")
            end)
        end
        if t == 315 then
            guest(function(p)
                local teammate = Isaac.GetPlayer(0)
                teammate.Position = p.Position + Vector(16, 0)
                assert(teammate:TryHoldEntity(p), "Teammate could not carry skeleton")
                report("TEAMMATE_CARRIED")
            end)
        end
        if t == 345 then
            assert(
                Isaac.GetPlayer(0):ThrowHeldEntity(Vector(12, 0)),
                "Teammate could not throw skeleton"
            )
            report("TEAMMATE_THROWN")
        end
        if t == 390 then
            guest(function(p)
                p:ChangePlayerType(PlayerType.PLAYER_THELOST)
            end)
        end
        if t == 410 then
            guest(function(p, room)
                local index = room:GetGridIndex(Vector(320, 280))
                room:RemoveGridEntity(index, 0, false)
                room:Update()
                assert(room:SpawnGridEntity(index, GridEntityType.GRID_ROCK, 0, 123, 0))
                room:GetGridEntity(index).CollisionClass = GridCollisionClass.COLLISION_SOLID
                p.Position, p.Velocity = Vector(240, 280), Vector.Zero
            end)
        end
        if t == 445 then
            guest(function(p, room)
                assert(p.Position.X > 340, "Native flying stopped at a ground obstacle")
                room:RemoveGridEntity(room:GetGridIndex(Vector(320, 280)), 0, false)
                p.Velocity = Vector.Zero
                report("FLYING_GROUND_OBSTACLE passed")
            end)
        end
        if t == 450 then
            guest(function(p, room)
                local pos = room:FindFreePickupSpawnPosition(Vector(160, 220), 0, true)
                local index = room:GetGridIndex(pos)
                room:RemoveGridEntity(index, 0, false)
                room:Update()
                room:SpawnGridEntity(index, GridEntityType.GRID_STAIRS, 0, 123, 0)
                p.Position = room:GetGridPosition(index) + Vector(60, 0)
                p.Velocity = Vector.Zero
                report(
                    "STAIRS type="
                        .. room:GetGridEntity(index):GetType()
                        .. " state="
                        .. room:GetGridEntity(index).State
                )
            end)
        end
        if t % 30 == 0 then
            guest(function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToNPC() and e:IsActiveEnemy(false) then
                        e:Remove()
                    end
                end
            end)
            if t >= 60 then
                sample("authority")
            end
        end
    end, function(...)
        return string.pack(
            ">s4s2i4i4i4i4",
            collect(...),
            doorPhase,
            doorMask,
            doorChecked,
            doorway and doorway.target or ghostDoor and ghostDoor.target or -1,
            ghostChecks
        )
    end, function(bytes, ...)
        local data, target
        data, doorPhase, doorMask, doorChecked, target, ghostChecks =
            string.unpack(">s4s2i4i4i4i4", bytes)
        local accepted = restore(data, ...)
        if accepted ~= false and (doorPhase == "check" or doorPhase == "ghost-check") then
            guest(function(p, room)
                assert(
                    Game():GetLevel():GetCurrentRoomIndex() == target,
                    "Replica arrival room differs"
                )
                assert(room:IsPositionInRoom(p.Position, 5), "Replica arrival outside L room")
                if doorPhase == "ghost-check" then
                    assert(p:IsCoopGhost(), "Replica lost ghost state")
                end
            end)
        end
        return accepted
    end, function(input, sequence)
        present(input, sequence)
        if not host and tick >= 60 and tick < 900 and renders % 6 == 0 then
            sample("display")
        end
    end, stage)
end
