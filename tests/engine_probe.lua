-- Internal automation harness, never packaged as the user's co-op Mod.
local mod = RegisterMod("Isaac LAN native engine audit", 1)
local load, err = package.loadlib("./isaac_lan_probe.dll", "luaopen_isaac_lan_probe")
assert(load, err)
local native = assert(load(), "Native lab bootstrap is missing; stop this test")
local game = Game()
local checks = 0
local experiment = 0
local ticks = 0
local firstRoom
local backgroundIndex
local foregroundMarker
local backgroundMarker
local p1, p2
local frame1, frame2
local baselineHearts1, baselineHearts2
local playerUpdates = { 0, 0 }
local collisions = { 0, 0 }
local callbackFailure
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
    if experiment ~= 2 or not p1 or not p2 then
        return
    end
    local who = GetPtrHash(player) == GetPtrHash(p1) and 1 or 2
    local expected = who == 1 and firstRoom or backgroundIndex
    if game:GetLevel():GetCurrentRoomIndex() ~= expected then
        callbackFailure = "Player update callback ran in another player's room"
    end
    playerUpdates[who] = playerUpdates[who] + 1
    native.trace_callback(who)
end)
mod:AddCallback(ModCallbacks.MC_PRE_PLAYER_COLLISION, function(_, player, other)
    if experiment ~= 2 or not p1 or not p2 or not other:ToNPC() then
        return
    end
    local who = GetPtrHash(player) == GetPtrHash(p1) and 1 or 2
    collisions[who] = collisions[who] + 1
end)
local function report(tag)
    local players, entities = 0, Isaac.GetRoomEntities()
    for _, entity in ipairs(entities) do
        if entity.Type == EntityType.ENTITY_PLAYER then
            players = players + 1
        end
    end
    Isaac.DebugString(
        string.format(
            "LAN_ROOM_%s index=%d players=%d entities=%d",
            tag,
            game:GetLevel():GetCurrentRoomIndex(),
            players,
            #entities
        )
    )
    return players
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    Isaac.DebugString("LAN_NATIVE_TEST_STARTED")
end)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    local level, room = game:GetLevel(), game:GetRoom()
    if room:GetFrameCount() < 2 then
        return
    end
    if checks < 10 then
        assert(
            native.audit(
                level:GetStage(),
                level:GetCurrentRoomIndex(),
                room:GetFrameCount(),
                game:GetNumPlayers()
            ),
            "Engine layout audit failed"
        )
        checks = checks + 1
        if checks == 10 then
            Isaac.DebugString("LAN_NATIVE_AUDIT_PASS")
        end
        return
    end
    if experiment == 0 then
        experiment = 1
        firstRoom = level:GetCurrentRoomIndex()
        -- Controller zero exists in a keyboard-only test environment. Asking the
        -- game's debug command for a nonexistent controller dereferences null.
        if game:GetNumPlayers() == 1 then
            Isaac.ExecuteCommand("addplayer 0 0")
        end
        return
    end
    if experiment == 1 then
        if game:GetNumPlayers() ~= 2 then
            return
        end
        p1, p2 = Isaac.GetPlayer(0), Isaac.GetPlayer(1)
        p1.ControlsEnabled, p2.ControlsEnabled = false, false
        p1.Position, p2.Position = Vector(320, 200), Vector(320, 200)
        p1.Velocity, p2.Velocity = Vector.Zero, Vector.Zero
        p2:AddMaxHearts(18)
        p2:AddHearts(24)
        baselineHearts1, baselineHearts2 = p1:GetHearts(), p2:GetHearts()
        local rooms = level:GetRooms()
        for i = 0, rooms.Size - 1 do
            local desc = rooms:Get(i)
            if
                desc.SafeGridIndex ~= firstRoom
                and desc.Data.Type == RoomType.ROOM_DEFAULT
                and desc.Data.Shape == RoomShape.ROOMSHAPE_1x1
            then
                backgroundIndex = desc.SafeGridIndex
                break
            end
        end
        assert(backgroundIndex, "No test room on generated floor")
        -- Change state first: native initialization can invoke Lua callbacks.
        experiment = 2
        assert(native.create_room(backgroundIndex), "Native room creation failed")
        assert(report("FOREGROUND_CREATED") == 1, "Foreground contains wrong players")
        assert(
            native.with_room(function()
                assert(report("BACKGROUND_CREATED") == 1, "Background contains wrong players")
                assert(game:GetLevel():GetCurrentRoomIndex() == backgroundIndex)
                backgroundMarker = Isaac.Spawn(
                    EntityType.ENTITY_EFFECT,
                    EffectVariant.CREEP_RED,
                    0,
                    Vector(280, 200),
                    Vector.Zero,
                    nil
                )
                backgroundMarker:ToEffect().Timeout = 1000
                local enemy =
                    Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, p2.Position, Vector.Zero, nil)
                enemy:AddFreeze(EntityRef(p2), 400)
            end),
            "Background callback failed"
        )
        assert(level:GetCurrentRoomIndex() == firstRoom, "Room context not restored")
        foregroundMarker = Isaac.Spawn(
            EntityType.ENTITY_EFFECT,
            EffectVariant.CREEP_RED,
            0,
            Vector(320, 200),
            Vector.Zero,
            nil
        )
        foregroundMarker:ToEffect().Timeout = 1000
        frame1, frame2 = p1.FrameCount, p2.FrameCount
        playerUpdates = { 0, 0 }
        return
    end
    if experiment == 2 and ticks < 300 then
        assert(native.step_room(), "Background update failed")
        ticks = ticks + 1
        assert(level:GetCurrentRoomIndex() == firstRoom, "Unexpected foreground transition")
        if ticks % 60 == 0 then
            Isaac.DebugString(
                string.format(
                    "LAN_ROOM_TICK tick=%d foreground_frame=%d background_frame=%d p1_delta=%d p2_delta=%d",
                    ticks,
                    foregroundMarker.FrameCount,
                    backgroundMarker.FrameCount,
                    p1.FrameCount - frame1,
                    p2.FrameCount - frame2
                )
            )
            assert(
                p1.FrameCount - frame1 == ticks and p2.FrameCount - frame2 == ticks,
                "A player updated twice or stopped updating"
            )
            assert(not callbackFailure, callbackFailure)
            assert(report("FOREGROUND_TICK") == 1)
            assert(native.with_room(function()
                assert(report("BACKGROUND_TICK") == 1)
            end))
        end
        if ticks == 300 then
            experiment = 3
            local pass = playerUpdates[1] == playerUpdates[2]
                and playerUpdates[1] >= 300
                and collisions[1] == 0
                and collisions[2] > 0
                and p1:GetHearts() == baselineHearts1
                and p2:GetHearts() < baselineHearts2
            Isaac.DebugString(
                string.format(
                    "LAN_ROOM_ISOLATION pass=%s updates=%d,%d collisions=%d,%d hearts=%d,%d initial=%d,%d",
                    tostring(pass),
                    playerUpdates[1],
                    playerUpdates[2],
                    collisions[1],
                    collisions[2],
                    p1:GetHearts(),
                    p2:GetHearts(),
                    baselineHearts1,
                    baselineHearts2
                )
            )
            assert(native.finish_rooms(), "Room cleanup failed")
            assert(report("RESTORED") == 2)
            assert(pass, "Room/player/collision isolation failed")
            Isaac.DebugString("LAN_ROOM_EXPERIMENT_FINISHED")
        end
    end
end)
