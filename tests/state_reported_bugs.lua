-- One host/client connection for reported regressions, followed by save/continue.
local native = assert(_IsaacLan)
local owner = { Name = "Reported LAN synchronization regressions" }
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
f = io.open("./lan-test-solo-fixture.txt", "r")
local soloFixture = f and f:read("*l") == "1"
if f then
    f:close()
end
local soloPhase = soloFixture and "start" or nil
local soloSeed, soloRoom, soloCharacter, soloFrames = nil, nil, nil, 0
local function report(s)
    Isaac.DebugString("LAN_NETWORK " .. s)
end
local failures, observations = {}, {}
local function check(name, condition, detail)
    observations[name] = true
    if not condition and not failures[name] then
        failures[name] = true
        report("ISSUE_FAIL " .. name .. " " .. (detail or ""))
    end
end
local function player(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
local function scoped(slot, fn)
    assert(native.rooms_with_player(slot, fn))
end
local function clear(preserveEffects)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type ~= 1 and e.Type ~= 866 and (not preserveEffects or e.Type ~= 1000) then
            e:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local round, renders, linked, chosen, done = 1, 0, false, false, false
local origin, other, boss, red, gridIndex, esau, introUpdates
local esauSeeds = {}
local deliriumRoom
local introFrames, pinSamples, pauseFrames, pauseEdges = 0, 0, nil, 0
local segmentSamples = {}
local lastPause = false
local originalFrame = _IsaacLanFrame
Isaac.AddPriorityCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, -100, function(_, continued)
    if soloPhase == "start" then
        assert(not continued and Game():GetNumPlayers() == 1)
        local p = Isaac.GetPlayer(0)
        p:AddCoins((host and 13 or 27) - p:GetNumCoins())
        p:AddBombs((host and 7 or 11) - p:GetNumBombs())
        p:AddKeys((host and 5 or 9) - p:GetNumKeys())
        soloSeed = Game():GetSeeds():GetStartSeedString()
        soloRoom = Game():GetLevel():GetCurrentRoomIndex()
        soloCharacter = p:GetPlayerType()
        soloPhase, soloFrames = "save", 0
        report("GAME_STARTED solo save fixture " .. soloSeed)
        return
    elseif soloPhase == "continue" then
        assert(continued, "Original solo save was not continued")
        assert(Game():GetNumPlayers() == 1, "LAN roster leaked into the original solo run")
        local p = Isaac.GetPlayer(0)
        assert(Game():GetSeeds():GetStartSeedString() == soloSeed, "Original solo seed changed")
        assert(Game():GetLevel():GetCurrentRoomIndex() == soloRoom, "Original solo room changed")
        assert(p:GetPlayerType() == soloCharacter, "Original solo character changed")
        assert(p:GetNumCoins() == (host and 13 or 27), "Original solo coins changed")
        assert(p:GetNumBombs() == (host and 7 or 11), "Original solo bombs changed")
        assert(p:GetNumKeys() == (host and 5 or 9), "Original solo keys changed")
        soloPhase, soloFrames = "restored", 0
        report("SOLO_RESTORED seed=" .. soloSeed)
        return
    end
    report("START continued=" .. tostring(continued) .. " count=" .. Game():GetNumPlayers())
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        report(
            "ROSTER index="
                .. i
                .. " controller="
                .. p.ControllerIndex
                .. " type="
                .. p:GetPlayerType()
        )
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    if soloPhase == "save" then
        soloPhase, soloFrames = "file", 0
        return
    elseif soloPhase == "network_exit" then
        soloPhase, soloFrames = "close", 0
        return
    end
    round = round + 1
    renders, linked, chosen = 0, false, false
    report("SAVE_EXIT round=" .. round)
end)
function _IsaacLanFrame()
    local hold = io.open("./lan-test-hold-lobby", "r")
    if hold then
        hold:close()
        return originalFrame()
    end
    if soloPhase and soloPhase ~= "network" then
        local s = originalFrame()
        soloFrames = soloFrames + 1
        if soloPhase == "save" and soloFrames == 100 then
            report("SOLO_READY")
        elseif soloPhase == "file" and soloFrames == 60 then
            report("SOLO_FILE_READY")
            soloPhase, renders = "network", 0
        elseif soloPhase == "close" and soloFrames >= 60 then
            _IsaacLanCommand("close", "")
            soloPhase = "continue"
            report("SOLO_NETWORK_EXIT")
        elseif soloPhase == "restored" and soloFrames == 60 then
            report("PASS reported issue synchronization and saved progress")
        end
        return s
    end
    renders = renders + 1
    if pauseFrames then
        pauseFrames = pauseFrames + 1
    end
    local tick = _IsaacLanStatus().verified or 0
    local mapHeld = round == 1 and tick >= 520 and tick < 620
    native.test_gamepad(
        mapHeld and 32
            or not host and pauseFrames and (pauseFrames == 1 or pauseFrames == 61) and 16
            or 0
    )
    local function checkReloadedProgress()
        local p = native.net_progress()
        check(
            "22 local unlock disk reload",
            p:byte(642) == (host and 1 or 0),
            tostring(p:byte(642))
        )
        check(
            "22 local counter disk reload",
            string.unpack(">I4", p, 644 + 522 * 4) == (host and 98765 or 321),
            tostring(string.unpack(">I4", p, 644 + 522 * 4))
        )
        report("PROGRESS_RELOADED " .. (host and "host" or "client"))
    end
    if round == 2 and renders == 60 then
        local p = native.net_progress()
        check("22 local unlock restoration", p:byte(642) == (host and 1 or 0))
        check(
            "22 local counter restoration",
            string.unpack(">I4", p, 644 + 522 * 4) == (host and 98765 or 321)
        )
        report("PROGRESS_RESTORED " .. (host and "host" or "client"))
    end
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = originalFrame()
    if round == 1 and s.prepared and s.verified >= 70 and s.verified < 360 then
        if not pauseFrames then
            pauseFrames = 0
        end
        local paused = Game():IsPaused()
        if paused ~= lastPause then
            pauseEdges = pauseEdges + 1
            lastPause = paused
            report("CHECK 17 guest pause edge=" .. pauseEdges)
        end
    end
    if s.phase == 2 and not chosen then
        if round == 1 then
            checkReloadedProgress()
        end
        _IsaacLanCommand("choose", host and "37:1" or "0:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand(
            round == 2 and "resume" or "start",
            round == 2 and "" or "LBCD0G4M:0:37:0:0:0"
        )
    end
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if
        round == 1
        and s.prepared
        and s.verified >= 100
        and s.verified < 360
        and native.presentation_active()
    then
        check("8 intro viewport isolation", not host)
        introFrames = introFrames + 1
    end
    if round == 2 and s.prepared and s.verified >= 160 and not done then
        check("9 needle sample", pinSamples > 0 or host)
        for _, kind in ipairs({ 62, 881, 19, 237 }) do
            check("9 synchronized monster " .. kind, host or (segmentSamples[kind] or 0) > 0)
        end
        check("8 guest intro playback", introFrames > 5 or host)
        check("17 guest pause opens and closes", pauseEdges == 2)
        done = true
        local names = {}
        for name in pairs(failures) do
            names[#names + 1] = name
        end
        table.sort(names)
        for name in pairs(observations) do
            if not failures[name] then
                report("ISSUE_PASS " .. name)
            end
        end
        assert(#names == 0, "Reported regressions: " .. table.concat(names, "; "))
        if soloFixture then
            soloPhase, soloFrames = "network_exit", 0
            if host then
                assert(native.net_command(3))
            end
        else
            report("PASS reported issue synchronization and saved progress")
        end
    end
    return s
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    if round == 1 then
        local level = Game():GetLevel()
        origin = level:GetStartingRoomIndex()
        for i = 0, level:GetRooms().Size - 1 do
            local d = level:GetRooms():Get(i)
            if d.Data.Type == RoomType.ROOM_BOSS then
                boss = d.SafeGridIndex
            elseif
                d.SafeGridIndex ~= origin
                and d.Data.Type == RoomType.ROOM_DEFAULT
                and d.Data.Shape == RoomShape.ROOMSHAPE_1x1
            then
                other = other or d.SafeGridIndex
            end
        end
        assert(other and boss)
    end
    return gate(capture, function(t, n, b)
        before(t, n, b)
        for slot = 0, 1 do
            player(slot):SetMinDamageCooldown(10000)
        end
        if round == 2 then
            return
        end
        if t == 20 then
            scoped(0, function()
                clear(true)
            end)
            player(1):AddCoins(37 - player(1):GetNumCoins())
            player(1):AddBombs(8 - player(1):GetNumBombs())
            player(1):AddKeys(6 - player(1):GetNumKeys())
            scoped(0, function()
                local room = Game():GetRoom()
                gridIndex = room:GetGridIndex(room:GetCenterPos() + Vector(80, 40))
                room:SpawnGridEntity(gridIndex, GridEntityType.GRID_ROCK, 0, 123, 0)
                for i, variant in ipairs({ 20, 30, 40 }) do
                    Isaac.Spawn(5, variant, 1, Vector(100 + 40 * i, 100), Vector.Zero, nil)
                end
            end)
        elseif t == 40 then
            scoped(0, function()
                local room = Game():GetRoom()
                room:RemoveGridEntity(gridIndex, 0, false)
            end)
        elseif t == 42 then
            scoped(0, function()
                Game():GetRoom():SpawnGridEntity(gridIndex, GridEntityType.GRID_POOP, 0, 124, 0)
            end)
        elseif t == 60 then
            assert(native.rooms_move(1, other, 0, -1))
        elseif t == 80 then
            scoped(1, clear)
        elseif t == 100 then
            assert(native.rooms_move(1, boss, 0, -1))
            report("CHECK 8 remote boss intro")
        elseif t >= 105 and t < 120 then
            introUpdates = introUpdates or native.rooms_positions()["1"].updates
            check("8 boss held during intro", native.rooms_positions()["1"].updates == introUpdates)
            if t == 110 then
                scoped(1, function()
                    local r = Game():GetRoom()
                    local index = r:GetGridIndex(r:GetCenterPos() + Vector(80, 0))
                    r:SpawnGridEntity(index, GridEntityType.GRID_TRAPDOOR, 0, 187, 0)
                    local trap = assert(r:GetGridEntity(index))
                    trap.State = 0
                    trap:GetSprite():Play("Closed", true)
                end)
            end
        elseif t == 360 then
            assert(native.rooms_move(0, boss, 0, -1))
        elseif t == 370 then
            scoped(0, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == 866 then
                        esau = e
                    end
                end
                if not esau then
                    esau = Isaac.Spawn(866, 0, 0, Vector(480, 180), Vector.Zero, player(0))
                    report("ESAU explicit owned follower fixture")
                end
            end)
        elseif t == 380 then
            scoped(1, function()
                for slot = 0, 7 do
                    local door = Game():GetRoom():GetDoor(slot)
                    if door then
                        check("21 boss doors closed", not door:IsOpen())
                    end
                end
                for index = 0, Game():GetRoom():GetGridSize() - 1 do
                    local grid = Game():GetRoom():GetGridEntity(index)
                    if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then
                        report(
                            "TRAPDOOR state="
                                .. grid.State
                                .. " animation="
                                .. grid:GetSprite():GetAnimation()
                        )
                        check(
                            "18 boss trapdoor closed",
                            grid:GetSprite():GetAnimation() ~= "Opened"
                        )
                    end
                end
                clear()
                player(1):AddCollectible(698)
            end)
        elseif t == 390 then
            scoped(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == EntityType.ENTITY_DARK_ESAU then
                        esau = e
                        esauSeeds[e.InitSeed] = true
                        report(
                            "ESAU parent="
                                .. tostring(e.Parent and e.Parent.Type)
                                .. " spawner="
                                .. tostring(e.SpawnerEntity and e.SpawnerEntity.Type)
                                .. " target="
                                .. tostring(e.Target and e.Target.Type)
                        )
                    end
                end
            end)
            check("14 Dark Esau fixture", esau ~= nil)
            assert(native.rooms_move(0, other, 0, -1))
            assert(native.rooms_move(1, other, 0, -1))
        elseif t == 395 then
            scoped(1, function()
                local count = 0
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == EntityType.ENTITY_DARK_ESAU then
                        count = count + 1
                        esauSeeds[e.InitSeed] = nil
                        report("ESAU arrived seed=" .. e.InitSeed)
                        e:Remove()
                    end
                end
                check(
                    "14 Dark Esau survives simultaneous departure",
                    count > 0 and next(esauSeeds) == nil
                )
                report("ESAU arrived count=" .. count)
                for seed in pairs(esauSeeds) do
                    report("ESAU missing seed=" .. seed)
                end
                player(0):ChangePlayerType(PlayerType.PLAYER_ISAAC)
            end)
            assert(native.rooms_move(1, boss, 0, -1))
        elseif t == 400 then
            assert(native.rooms_move(0, origin, 0, -1))
        elseif t == 415 then
            scoped(1, function()
                local r = Game():GetRoom()
                for index = 0, r:GetGridSize() - 1 do
                    local g = r:GetGridEntity(index)
                    if g and g:GetType() == GridEntityType.GRID_TRAPDOOR then
                        check(
                            "18 boss trapdoor opens after clear",
                            g:GetSprite():GetAnimation() == "Opened"
                        )
                    end
                end
            end)
        elseif t == 420 then
            scoped(1, function()
                player(1):Kill()
            end)
        elseif t == 550 then
            check(
                "16 ghost follows living teammate",
                player(1):IsCoopGhost() and native.rooms_positions()["1"].index == origin
            )
            scoped(0, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    check(
                        "7 no remote death familiars",
                        e.Type ~= 3 or e.Variant ~= FamiliarVariant.TWISTED_PAIR
                    )
                end
            end)
            assert(native.rooms_move(0, other, 0, -1))
        elseif t == 570 then
            check("16 ghost room transition", native.rooms_positions()["1"].index == other)
            assert(native.actor_ghost(native.rooms_heads()["1"], 0))
            scoped(1, function()
                player(1):Revive()
                player(1):AddHearts(6)
                player(1):StopExtraAnimation()
                player(1).ControlsEnabled = true
                player(1).ControlsCooldown = 0
                check("fixture ghost revival", not player(1):IsCoopGhost())
                report("GHOST revived controls=" .. tostring(player(1):AreControlsEnabled()))
            end)
        elseif t == 620 then
            assert(native.rooms_move(1, origin, 0, -1))
        elseif t == 660 then
            scoped(1, function()
                clear()
                player(1).Position = Vector(160, 200)
                Isaac.Spawn(EntityType.ENTITY_PIN, 0, 0, Vector(400, 360), Vector.Zero, nil)
                Isaac.Spawn(EntityType.ENTITY_NEEDLE, 0, 0, Vector(480, 200), Vector.Zero, nil)
                report("CHECK 9 small Pin/Needle segments")
            end)
        elseif t == 850 then
            scoped(1, clear)
            assert(native.rooms_move(0, origin, 0, -1))
            scoped(1, function()
                Isaac.Spawn(EntityType.ENTITY_LARRYJR, 0, 0, Vector(400, 320), Vector.Zero, nil)
                Isaac.Spawn(EntityType.ENTITY_GURGLING, 0, 0, Vector(480, 200), Vector.Zero, nil)
                report("CHECK 9 Larry/Gurgling segments")
            end)
        elseif t == 1050 then
            assert(native.rooms_move(0, other, 0, -1))
            assert(native.rooms_move(1, other, 0, -1))
        elseif t == 1100 then
            scoped(1, function()
                local level = Game():GetLevel()
                for slot = 0, 7 do
                    if level:MakeRedRoomDoor(other, slot) then
                        red = Game():GetRoom():GetDoor(slot).TargetRoomIndex
                        break
                    end
                end
                check("5 red room fixture", red ~= nil)
            end)
            if red then
                assert(native.rooms_move(1, red, 0, -1))
            end
        elseif t == 1180 then
            check("5 red room entry", not red or native.rooms_positions()["1"].index == red)
            assert(native.rooms_move(1, other, 0, -1))
        elseif t == 1230 then
            scoped(1, function()
                clear()
                report(
                    "VENTRICLE before controls="
                        .. tostring(player(1):AreControlsEnabled())
                        .. " animation="
                        .. player(1):GetSprite():GetAnimation()
                        .. " extra="
                        .. tostring(player(1):IsExtraAnimationFinished())
                )
                player(1):UseActiveItem(396, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
            end)
            assert(native.rooms_move(0, red, 0, -1))
            assert(native.rooms_move(1, origin, 0, -1))
        elseif t == 1280 then
            scoped(1, function()
                player(1):UseActiveItem(396, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
                player(1).Position = Vector(160, 180)
                report("CHECK 5 ventricle portals")
            end)
        elseif t == 1340 then
            scoped(1, function()
                local found = false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == 1000 and e.Variant == EffectVariant.WOMB_TELEPORT then
                        player(1).Position = e.Position
                        found = true
                        report("VENTRICLE entry subtype=" .. e.SubType)
                    end
                end
                check("5 ventricle portal fixture", found)
            end)
        elseif t == 1380 then
            report("VENTRICLE destination=" .. native.rooms_positions()["1"].index)
            check("5 ventricle per-actor teleport", native.rooms_positions()["1"].index == other)
            check("5 ventricle host isolation", native.rooms_positions()["0"].index == red)
            scoped(1, function()
                report(
                    "VENTRICLE arrival enabled="
                        .. tostring(player(1).ControlsEnabled)
                        .. " cooldown="
                        .. player(1).ControlsCooldown
                        .. " extra="
                        .. tostring(player(1):IsExtraAnimationFinished())
                        .. " animation="
                        .. player(1):GetSprite():GetAnimation()
                )
                check("5 ventricle controls restored", player(1):AreControlsEnabled())
            end)
            assert(native.rooms_move(1, origin, 0, -1))
        elseif t == 1390 then
            scoped(1, function()
                clear()
                player(1):AddCollectible(681)
            end)
        elseif t == 1430 then
            scoped(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == 3 and e.Variant == FamiliarVariant.LIL_PORTAL then
                        -- Charge through the game's familiar API; its native
                        -- AI still generates the room and creates the portal.
                        for i = 1, 3 do
                            e:ToFamiliar():AddCoins(1)
                        end
                        report(
                            "LIL_PORTAL charged state="
                                .. e:ToFamiliar().State
                                .. " animation="
                                .. e:GetSprite():GetAnimation()
                                .. " controls="
                                .. tostring(player(1):AreControlsEnabled())
                        )
                    end
                end
            end)
        elseif t == 1600 then
            scoped(1, function()
                local portalFound = false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == 1000 and e.Variant == EffectVariant.PORTAL_TELEPORT then
                        report("LIL_PORTAL effect subtype=" .. e.SubType)
                        if e.SubType >= 900 then
                            player(1).Position = e.Position
                            portalFound = true
                        end
                    end
                end
                check("5 Lil Portal native portal", portalFound)
                local d = Game():GetLevel():GetRoomByIdx(-20)
                check("5 Lil Portal room generated", d and d.Data ~= nil)
            end)
        elseif t == 1660 then
            check("5 Lil Portal native entry", native.rooms_positions()["1"].index == -20)
            scoped(1, function()
                local found = false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == 1000 and e.Variant == EffectVariant.PORTAL_TELEPORT then
                        player(1).Position = e.Position
                        found = true
                        report("LIL_PORTAL return subtype=" .. e.SubType)
                    end
                end
                check("5 Lil Portal return portal", found)
            end)
        elseif t == 1720 then
            check("5 Lil Portal native return", native.rooms_positions()["1"].index == origin)
            check("5 Lil Portal host isolation", native.rooms_positions()["0"].index == red)
            report("CHECK 5 Lil Portal current=" .. native.rooms_positions()["1"].index)
            scoped(0, function()
                Game():GetLevel():SetStage(1, StageType.STAGETYPE_REPENTANCE)
                Game():StartStageTransition(true, 0, player(0))
            end)
        elseif t == 2000 then
            check(
                "5 alt path checkpoint",
                Game():GetLevel():GetStageType() == StageType.STAGETYPE_REPENTANCE
            )
            report("CHECK 5 alternate floor loaded")
            scoped(0, function()
                Game():GetLevel():SetStage(12, StageType.STAGETYPE_ORIGINAL)
                Game():StartStageTransition(true, 0, player(0))
            end)
        elseif t == 2300 then
            local level = Game():GetLevel()
            local target, fallback
            report("VOID stage=" .. level:GetStage() .. " type=" .. level:GetStageType())
            for i = 0, level:GetRooms().Size - 1 do
                local d = level:GetRooms():Get(i)
                if d.Data.Type == RoomType.ROOM_BOSS then
                    report(
                        "VOID boss="
                            .. d.SafeGridIndex
                            .. " variant="
                            .. d.Data.Variant
                            .. " shape="
                            .. d.Data.Shape
                            .. " distance="
                            .. d.DeliriumDistance
                    )
                end
                if d.Data.Type == RoomType.ROOM_BOSS and d.DeliriumDistance == 0 then
                    target = d.SafeGridIndex
                    report("VOID distance-zero type=" .. d.Data.Type .. " index=" .. target)
                elseif not fallback and d.Data.Type == RoomType.ROOM_BOSS then
                    fallback = d.SafeGridIndex
                end
            end
            target = target or fallback
            check("13 Delirium room fixture", target ~= nil)
            if target then
                deliriumRoom = target
                assert(native.rooms_move(1, target, 0, -1))
            end
        elseif t == 2400 then
            scoped(1, function()
                report("DELIRIUM native room bossID=" .. Game():GetRoom():GetBossID())
                if Game():GetRoom():GetBossID() ~= 70 then
                    clear()
                    Isaac.Spawn(
                        EntityType.ENTITY_DELIRIUM,
                        0,
                        0,
                        Game():GetRoom():GetCenterPos(),
                        Vector.Zero,
                        nil
                    )
                    report("DELIRIUM explicit fixture fallback")
                end
                Game():GetRoom():SetClear(false)
                report("CHECK 13 native Delirium fixture bossID=" .. Game():GetRoom():GetBossID())
            end)
        elseif t == 2650 then
            scoped(1, function()
                local found = false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == 412 or (e:ToNPC() and e:ToNPC():IsBoss()) then
                        e.HitPoints = 1
                        local damaged = e:TakeDamage(
                            1000000,
                            DamageFlag.DAMAGE_IGNORE_ARMOR,
                            EntityRef(player(1)),
                            0
                        )
                        report(
                            "DELIRIUM damage="
                                .. tostring(damaged)
                                .. " hp="
                                .. e.HitPoints
                                .. " maxHP="
                                .. e.MaxHitPoints
                                .. " flags="
                                .. e:GetEntityFlags()
                        )
                        found = true
                    end
                end
                check("13 Delirium boss fixture", found)
                report("CHECK 13 remote Delirium killed")
            end)
        elseif t == 3100 then
            scoped(1, function()
                local found = false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == 5 and e.Variant == 340 then
                        found = true
                    end
                end
                check("13 completion chest", found)
                report("CHECK 13 completion clear=" .. tostring(Game():GetRoom():IsClear()))
            end)
        elseif t == 3200 then
            assert(native.rooms_move(0, deliriumRoom, 0, -1))
        elseif t == 3250 then
            scoped(1, function()
                clear()
                Isaac.Spawn(
                    EntityType.ENTITY_DELIRIUM,
                    0,
                    0,
                    Game():GetRoom():GetCenterPos(),
                    Vector.Zero,
                    nil
                )
                Game():GetRoom():SetClear(false)
                report("CHECK 13 same room Delirium fixture")
            end)
        elseif t == 3600 then
            scoped(0, function()
                local found = false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToNPC() and e:ToNPC():IsBoss() then
                        e.HitPoints = 1
                        e:TakeDamage(
                            1000000,
                            DamageFlag.DAMAGE_IGNORE_ARMOR,
                            EntityRef(player(0)),
                            0
                        )
                        found = true
                    end
                end
                check("13 same room boss fixture", found)
            end)
        elseif t == 4100 then
            scoped(0, function()
                local found = false
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type == 5 and e.Variant == 340 then
                        found = true
                    end
                end
                check("13 same room completion chest", found)
                report(
                    "CHECK 13 same room completion clear=" .. tostring(Game():GetRoom():IsClear())
                )
            end)
        elseif t == 4200 then
            assert(native.net_command(3))
        end
        if (t >= 2650 and t <= 3100 or t >= 3600 and t <= 4100) and t % 100 == 0 then
            scoped(1, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    local npc = e:ToNPC()
                    if npc and npc:IsBoss() then
                        report(
                            "DELIRIUM tick="
                                .. t
                                .. " type="
                                .. e.Type
                                .. " state="
                                .. npc.State
                                .. " frame="
                                .. npc.StateFrame
                                .. " hp="
                                .. e.HitPoints
                                .. " dead="
                                .. tostring(e:IsDead())
                                .. " animation="
                                .. e:GetSprite():GetAnimation()
                                .. " spriteFrame="
                                .. e:GetSprite():GetFrame()
                        )
                    end
                end
            end)
        end
    end, function(slot, t)
        local bytes = collect(slot, t)
        if round == 1 and t == 600 then
            check("20 offscreen pickup fixture", #native.map_pickups(origin, 0) >= 8 + 3 * 24)
            report("CHECK 20 offscreen pickup icons")
        end
        return bytes
    end, function(bytes, t, ack)
        if restore(bytes, t, ack) == false then
            return false
        end
        local value = _IsaacLanState.decode(bytes)
        if round == 1 and t >= 670 and t < 1050 then
            for _, e in ipairs(value[11][3]) do
                segmentSamples[e[2]] = (segmentSamples[e[2]] or 0) + 1
            end
        end
        for _, actor in ipairs(value[9]) do
            local p = Isaac.GetPlayer(actor[1])
            check(
                "6 resources after death",
                p:GetNumCoins() == actor[4][5][1]
                    and p:GetNumBombs() == actor[4][5][2]
                    and p:GetNumKeys() == actor[4][5][3],
                "tick="
                    .. t
                    .. " index="
                    .. actor[1]
                    .. " ghost="
                    .. tostring(p:IsCoopGhost())
                    .. " coins="
                    .. p:GetNumCoins()
                    .. "/"
                    .. actor[4][5][1]
                    .. " bombs="
                    .. p:GetNumBombs()
                    .. "/"
                    .. actor[4][5][2]
                    .. " keys="
                    .. p:GetNumKeys()
                    .. "/"
                    .. actor[4][5][3]
            )
        end
        for _, d in ipairs(value[8]) do
            check("20 saved pickup metadata", native.map_pickups(d[1], d[7]) == d[8])
        end
        local room = Game():GetRoom()
        for _, grid in ipairs(value[11][4]) do
            local current = room:GetGridEntity(grid[1])
            check("19 authoritative terrain", current and current:GetType() == grid[2])
        end
        if round == 1 and t >= 670 and t < 850 then
            for _, e in ipairs(value[11][3]) do
                if e[2] == EntityType.ENTITY_PIN or e[2] == EntityType.ENTITY_NEEDLE then
                    pinSamples = pinSamples + 1
                    if t % 30 == 0 then
                        report(
                            "PIN type="
                                .. e[2]
                                .. " parent="
                                .. e[11]
                                .. " child="
                                .. e[13]
                                .. " state="
                                .. e[9][1]
                        )
                    end
                    break
                end
            end
        end
    end, present, beginFloor)
end
