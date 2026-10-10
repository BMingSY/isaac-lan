-- Six terminal routes, one owned pair. Native bosses, loot, doors, exits and
-- win callbacks are required; debug stage changes only prepare source floors.
-- Knife/key pieces are declared prerequisites, not knife-chase/angel tests.
local assert = assert
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local frame = _IsaacLanFrame
local owner = { Name = "Six native ending routes" }
local cases = { "lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent" }
local caseIndex, wins, renders, lastExit = 1, 0, 0, 0
local lastExitMs, relinkAt = 0, 0
local localProgress
local linked, chosen, started, finished = false, false, false, false
local step, stepAt, floorAt, seenBoss, photo, contact, shoot = "init", 0, 0, false, nil, nil, -1
local previousStage, previousType, lastFloor, bedroom, living
local exitContact
local observed, snapshots, floorEvents = {}, 0, 0
local bosses = {}
local appeared = {}
local scratchReported = {}
local homeOnly = _IsaacLanTest.homeOnly
local homeVisuals = { sleep = 0, television = 0 }
local homeWalking, homeMovement, homeOrigin = false, false, nil
local homeWakeMovement = false
local homeDistance = 0
local homeWalkReadyAt, homeWalkPrevious, homeWalkMotion = nil, nil, 0
local replicaWakeOrigin, replicaWakePrevious, replicaWakeDistance, replicaWakeMotion =
    nil, nil, 0, 0
local dreamFrames = {}
local function checkHomeVisual(value)
    assert(native.home_scene_pose() == value[5], "Home scene state differs from authority")
    if value[6] then
        local sprite = assert(native.home_scene_sprite(Isaac.GetPlayer(0):GetSprite()))
        assert(sprite:GetFilename() == value[6][1] and sprite:GetFrame() == value[6][3])
        assert(native.sprite_state(sprite) == value[6][12], "Home scene layers differ")
        local id = value[5]:byte(2)
        if id == 2 or id == 3 then
            homeVisuals.television = homeVisuals.television + 1
        end
    end
end
local terminal = {
    lamb = 273,
    ["blue-baby"] = 102,
    delirium = 412,
    ["mega-satan"] = 275,
    mother = 912,
    ascent = 951,
}
local function report(s)
    Isaac.DebugString("LAN_NETWORK ENDINGS " .. cases[caseIndex] .. " " .. s)
end
local function mark(s, t)
    step, stepAt = s, t
    report("STEP " .. s .. " tick=" .. t)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function protect(p)
    p:SetMinDamageCooldown(10000)
    p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
end
local function move(index, t, dimension)
    assert(native.rooms_move(1, index, dimension or 0, -1))
    actor(1, function(p)
        protect(p)
        p.Position, p.Velocity = Vector(160, 220), Vector.Zero
        report("ROOM index=" .. index .. " type=" .. Game():GetRoom():GetType())
    end)
    contact, seenBoss, exitContact = nil, false, nil
    floorAt = t
end
local function findRoom(predicate)
    local list = Game():GetLevel():GetRooms()
    for i = 0, list.Size - 1 do
        local d = list:Get(i)
        if d.Data and predicate(d) then
            return d.SafeGridIndex
        end
    end
end
local function hasSpawn(data, entityType)
    if not data then
        return false
    end
    for i = 0, data.SpawnCount - 1 do
        local spawn = data.Spawns:Get(i)
        for j = 0, spawn.EntryCount - 1 do
            if spawn.Entries:Get(j).Type == entityType then
                return true
            end
        end
    end
    return false
end
local function boss(t, target)
    local index = target
        or findRoom(function(d)
            return d.Data.Type == RoomType.ROOM_BOSS and d.SafeGridIndex >= 0
        end)
    assert(index, "Missing native Boss room")
    move(index, t)
    mark("boss-enter", t)
end
local function pick(variant, subtype)
    local found
    actor(1, function(p)
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e.Type == 5 and e.Variant == variant and (not subtype or e.SubType == subtype) then
                found = true
                local pickup = e:ToPickup()
                pickup.Wait = 0
                contact = EntityPtr(pickup)
                p.Position, p.Velocity = pickup.Position, Vector.Zero
                report("NATIVE_PICKUP variant=" .. variant .. " subtype=" .. e.SubType)
                break
            end
        end
    end)
    return found
end
local function exitPosition(kind)
    local result
    actor(1, function()
        local room = Game():GetRoom()
        for i = 0, room:GetGridSize() - 1 do
            local g = room:GetGridEntity(i)
            if g and g:GetType() == kind then
                result = g.Position
                break
            end
        end
    end)
    return result
end
local function useExit(kind, t)
    local pos = exitPosition(kind)
    if not pos then
        return false
    end
    actor(1, function(p)
        p.Position, p.Velocity = pos, Vector.Zero
    end)
    exitContact = pos
    previousStage, previousType = Game():GetLevel():GetStage(), Game():GetLevel():GetStageType()
    mark("floor-wait", t)
    report("NATIVE_EXIT kind=" .. kind .. " from=" .. previousStage .. ":" .. previousType)
    return true
end
local function useEffect(variant, t)
    local found
    actor(1, function(p)
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e.Type == EntityType.ENTITY_EFFECT and e.Variant == variant then
                p.Position, p.Velocity = e.Position, Vector(1, 0)
                found = true
                break
            end
        end
    end)
    if not found then
        return false
    end
    previousStage, previousType = Game():GetLevel():GetStage(), Game():GetLevel():GetStageType()
    mark("floor-wait", t)
    report("NATIVE_EXIT effect=" .. variant .. " from=" .. previousStage .. ":" .. previousType)
    return true
end
local function specialEntrance(index, t)
    local d = Game():GetLevel():GetRoomByIdx(index, 0)
    assert(d and d.Data, "Native route entrance was not generated: " .. index)
    move(index, t)
    mark("entrance", t)
end
local function observeBoss(e)
    local name = cases[caseIndex]
    if
        name == "blue-baby" and e.Type == 102 and e.Variant ~= 1
        or name == "ascent" and e.Type == 951 and e.Variant ~= 0
    then
        return
    end
    if e.Type == terminal[name] and not bosses[e.Type] then
        report("TERMINAL_BOSS type=" .. e.Type .. " variant=" .. e.Variant)
    end
    bosses[e.Type] = true
end
local function fight(t)
    local clear = false
    actor(1, function(p)
        protect(p)
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if
                e:ToNPC()
                and (e:IsBoss() or e:IsActiveEnemy(false) or e.Type == 950 or e.Type == 951)
            then
                seenBoss = true
                observeBoss(e)
                local key = e.Type .. ":" .. e.Variant .. ":" .. e.InitSeed
                if not appeared[key] then
                    report(
                        "BOSS_FIRST type="
                            .. e.Type
                            .. " variant="
                            .. e.Variant
                            .. " hp="
                            .. e.HitPoints
                            .. " max="
                            .. e.MaxHitPoints
                            .. " state="
                            .. e:ToNPC().State
                            .. " animation="
                            .. e:GetSprite():GetAnimation()
                            .. " frame="
                            .. e.FrameCount
                            .. " boss="
                            .. tostring(e:IsBoss())
                    )
                end
                appeared[key] = appeared[key] or t
                if t % 300 == 0 then
                    report(
                        "BOSS_LIVE type="
                            .. e.Type
                            .. " variant="
                            .. e.Variant
                            .. " hp="
                            .. e.HitPoints
                            .. " dead="
                            .. tostring(e:IsDead())
                            .. " state="
                            .. e:ToNPC().State
                            .. " state_frame="
                            .. e:ToNPC().StateFrame
                            .. " animation="
                            .. e:GetSprite():GetAnimation()
                            .. " frame="
                            .. e:GetSprite():GetFrame()
                    )
                end
                local warmup = e.Type == 950 and 200 or 30
                if t % 10 == 0 and t - appeared[key] >= warmup and not e:IsDead() then
                    if e.Type == 950 or e.Type == 951 then
                        -- These bosses have non-damageable companion/intro
                        -- entities. Native tear collision must choose targets;
                        -- direct TakeDamage can bypass their phase protection.
                        local tear = p:FireTear(
                            e.Position + Vector(-40, 0),
                            Vector(8, 0),
                            false,
                            true,
                            false
                        )
                        tear.CollisionDamage = 1000000
                    else
                        e:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(p), 0)
                    end
                end
            end
        end
        clear = Game():GetRoom():IsClear()
    end)
    return clear and seenBoss
end
local function prepare(stage, kind, t)
    if stage ~= 1 then
        Game():GetLevel():SetStage(stage, kind)
        Game():StartStageTransition(true, 0, Isaac.GetPlayer(assert(native.rooms_heads()["1"])))
    end
    mark("source-wait", t)
    report("SOURCE_FIXTURE stage=" .. stage .. " type=" .. kind)
end
local chestContacts = 0
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
    if host and collider:ToPlayer() and chestContacts < 12 then
        chestContacts = chestContacts + 1
        local p = collider:ToPlayer()
        report(
            "CHEST_CONTACT state="
                .. pickup.State
                .. " wait="
                .. pickup.Wait
                .. " controller="
                .. p.ControllerIndex
                .. " animation="
                .. p:GetSprite():GetAnimation()
                .. " extra_done="
                .. tostring(p:IsExtraAnimationFinished())
        )
    end
end, PickupVariant.PICKUP_BIGCHEST)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_END, function(_, gameOver)
    assert(not gameOver, "Ending route ended in a defeat")
    assert(wins == caseIndex - 1, "Duplicate native win callback")
    assert(bosses[terminal[cases[caseIndex]]], "Win callback without the expected terminal Boss")
    if homeOnly then
        assert(homeVisuals.sleep > 10, "Native Home sleep animation was not displayed")
        local frames = 0
        for _ in pairs(dreamFrames) do
            frames = frames + 1
        end
        assert(frames > 10, "Native Home dream sprite did not animate")
        assert(homeVisuals.television > 10, "Native TV animation was not displayed")
        assert(homeMovement, "Guest did not move after entering the Dogma arena")
        assert(homeWakeMovement, "Guest did not move after waking at Home")
        report(
            "HOME_VISUALS sleep=" .. homeVisuals.sleep .. " television=" .. homeVisuals.television
        )
    end
    wins, lastExit = wins + 1, renders
    lastExitMs = native.api_info().nowMs
    report("NATIVE_WIN callback=MC_POST_GAME_END game_over=false")
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    lastExit = renders
    lastExitMs = native.api_info().nowMs
    report("NATIVE_EXIT_CALLBACK wins=" .. wins)
end)
function _IsaacLanFrame()
    renders = renders + 1
    if EID and EID.Config then
        EID.Config.DisableStartOfRunWarnings = true
    end
    local s = frame()
    if homeOnly and s.prepared then
        local visual = native.item_presentation_state()
        if host and visual.sceneState == 1 and (visual.sceneID == 2 or visual.sceneID == 3) then
            local sprite = native.home_scene_sprite(Isaac.GetPlayer(0):GetSprite())
            if sprite and sprite:GetFilename() ~= "" then
                homeVisuals.television = homeVisuals.television + 1
            end
        end
        if visual.dreamActive == 1 and visual.dreamHome == 1 then
            local sample = Isaac.GetPlayer(0):GetSprite()
            local background = assert(native.home_dream_sprite(sample, 0))
            local dream = assert(native.home_dream_sprite(sample, 1))
            -- Native scene cleanup clears its sprites before switching the
            -- manager back to gameplay. Do not count that final empty frame.
            if background:GetFilename() ~= "" and dream:GetFilename() ~= "" then
                homeVisuals.sleep = homeVisuals.sleep + 1
                dreamFrames[dream:GetFrame()] = true
                if homeVisuals.sleep == 1 then
                    report(
                        "NATIVE_HOME_DREAM background="
                            .. background:GetFilename()
                            .. " dream="
                            .. dream:GetFilename()
                    )
                end
            end
        end
    end
    local now = native.api_info().nowMs
    if finished then
        native.test_gamepad(0)
        return s
    end
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    assert(
        lastExit == 0 or wins == caseIndex or now - lastExitMs < 10000,
        "Session exited without the native win callback on this peer"
    )
    -- The native Lamb reward asks whether to start a Victory Lap. Its default
    -- selection is No; confirm that prompt rather than leaving the run paused.
    local confirm = (wins == caseIndex and s.scene == 3)
        or (s.scene == 3 and cases[caseIndex] == "ascent")
        or (
            s.scene == 2
            and wins < caseIndex
            and host
            and cases[caseIndex] == "lamb"
            and step == "ending-chest"
        )
    native.test_gamepad(confirm and renders % 30 < 5 and 4096 or 0)
    if wins == caseIndex then
        if now - lastExitMs > 3000 and s.phase == 0 and not s.prepared and s.scene == 1 then
            local progress = native.net_progress()
            local diffs = {}
            for i = 2, 643 do
                if progress:byte(i) ~= localProgress:byte(i) then
                    diffs[#diffs + 1] = (i - 2)
                        .. ":"
                        .. localProgress:byte(i)
                        .. ">"
                        .. progress:byte(i)
                end
            end
            report(
                "PROGRESS_DIFF flags="
                    .. table.concat(diffs, ",")
                    .. " private="
                    .. string.unpack(">I4", localProgress:sub(-4))
                    .. ">"
                    .. string.unpack(">I4", progress:sub(-4))
            )
            -- Native menu loading derives unlocks from earned Boss counters
            -- (for example Eden and the Void gate). Retain every prior flag;
            -- do not mistake new earned flags for a replaced save.
            for i = 2, 643 do
                assert(
                    localProgress:byte(i) == 0 or progress:byte(i) == 1,
                    "Ending discarded a prior local achievement: " .. (i - 2)
                )
            end
            -- These host-only prerequisites cannot be earned by a seeded
            -- normal Isaac route: Death Certificate, Dead God, online daily.
            for _, id in ipairs({ 636, 637, 640 }) do
                assert(
                    progress:byte(id + 2) == localProgress:byte(id + 2),
                    "Ending inherited host-only prior achievement: " .. id
                )
            end
            assert(
                progress:sub(-4) == localProgress:sub(-4),
                "Ending replaced this peer's private counter"
            )
            report("LOCAL_PROGRESS_RESTORED")
            report("PASS native ending and session cleanup snapshots=" .. snapshots)
            if caseIndex == #cases then
                if not finished then
                    finished = true
                    Isaac.DebugString("LAN_NETWORK PASS all selected native ending routes")
                end
            else
                caseIndex = caseIndex + 1
                linked, chosen, started = false, false, false
                step, stepAt, lastFloor, contact, shoot = "init", 0, nil, nil, -1
                lastExit = 0
                snapshots, floorEvents, observed, bosses = 0, 0, {}, {}
                appeared = {}
                scratchReported = {}
                -- Menu rendering is throttled differently in each window.
                -- Schedule lobbies in wall time rather than render counts.
                relinkAt = now + (host and 250 or 1000)
            end
        end
        return s
    end
    if
        not linked
        and s.scene == 1
        and (relinkAt > 0 and now >= relinkAt or relinkAt == 0 and renders >= (host and 300 or 360))
    then
        linked = true
        localProgress = native.net_progress()
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
        report("LOCAL_UNLOCK_BASELINE achievement640=" .. native.net_progress():byte(642))
    end
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", homeOnly and not host and "7:1" or "0:1")
    end
    if
        host
        and not started
        and s.phase == 2
        and s.players == 2
        and s.ready0 == 1
        and s.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "YV039KQF:0:0:" .. (homeOnly and "7" or "0") .. ":0:0")
    end
    return s
end
local function advance(t)
    if not native.rooms_ready() then
        return
    end
    local level, name = Game():GetLevel(), cases[caseIndex]
    local stage, kind = level:GetStage(), level:GetStageType()
    if step == "init" and t > 30 then
        for slot = 0, 1 do
            actor(slot, protect)
        end
        if name == "mega-satan" then
            actor(1, function(p)
                p:AddCollectible(238)
                p:AddCollectible(239)
            end)
            report("PREREQUISITE_FIXTURE key_pieces=238,239")
        elseif name == "mother" then
            actor(1, function(p)
                p:AddCollectible(626)
                p:AddCollectible(627)
            end)
            report("PREREQUISITE_FIXTURE knife_pieces=626,627")
        end
        prepare(
            name == "ascent" and (homeOnly and 13 or 1)
                or name == "mother" and 2
                or name == "delirium" and 8
                or 6,
            0,
            t
        )
    elseif step == "source-wait" and t - stepAt > 140 then
        if homeOnly then
            mark("floor-arrived", t)
        else
            boss(t)
        end
    elseif step == "floor-wait" then
        if stage ~= previousStage or kind ~= previousType then
            exitContact = nil
            mark("floor-arrived", t)
            report("ARRIVED stage=" .. stage .. " type=" .. kind)
            lastFloor = stage .. ":" .. kind
        elseif exitContact then
            actor(1, function(p)
                -- Walk into the native exit after its opening animation.
                -- A stationary overlap can miss its first collision.
                local away = (t - stepAt) % 90 < 20
                p.Position = exitContact + (away and Vector(60, 0) or Vector(4, 0))
                p.Velocity = Vector(away and -1 or 1, 0)
                if (t - stepAt) % 120 == 0 then
                    local room = Game():GetRoom()
                    local grid = room:GetGridEntity(room:GetGridIndex(exitContact))
                    report(
                        "EXIT_CONTACT kind="
                            .. (grid and grid:GetType() or -1)
                            .. " state="
                            .. (grid and grid.State or -1)
                            .. " animation="
                            .. (grid and grid:GetSprite():GetAnimation() or "none")
                            .. " frame="
                            .. (grid and grid:GetSprite():GetFrame() or -1)
                            .. " x="
                            .. p.Position.X
                            .. " y="
                            .. p.Position.Y
                    )
                end
            end)
        end
    elseif step == "floor-arrived" and t - stepAt > 130 then
        if name == "mega-satan" and stage == 11 then
            move(level:GetStartingRoomIndex(), t)
            mark("mega-door", t)
        elseif name == "ascent" and stage == 13 then
            bedroom = findRoom(function(d)
                return d.Data.Type == 1 and d.Data.Variant == 3
            end)
            living = findRoom(function(d)
                return d.Data.Type == 1 and d.Data.Variant == 4
            end)
            assert(bedroom and living, "Missing native Home rooms")
            move(bedroom, t)
            mark("home-bed", t)
        elseif name == "ascent" and Game():GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH) then
            local first = findRoom(function(d)
                return d.Data.Type == 1
                    and d.Data.Variant ~= 10000
                    and d.SafeGridIndex ~= level:GetCurrentRoomIndex()
            end)
            assert(first, "Missing Ascent first room")
            move(first, t)
            mark("ascent-first", t)
        elseif stage == 12 then
            local delirium = findRoom(function(d)
                if d.Data.Type == RoomType.ROOM_BOSS then
                    report(
                        "VOID_BOSS index="
                            .. d.SafeGridIndex
                            .. " variant="
                            .. d.Data.Variant
                            .. " shape="
                            .. d.Data.Shape
                            .. " distance="
                            .. d.DeliriumDistance
                            .. " name="
                            .. d.Data.Name
                    )
                end
                return hasSpawn(d.Data, EntityType.ENTITY_DELIRIUM)
                    or hasSpawn(d.OverrideData, EntityType.ENTITY_DELIRIUM)
            end)
            assert(delirium, "Missing native Delirium room")
            boss(t, delirium)
        else
            boss(t)
        end
    elseif step == "boss-enter" and t - stepAt > 130 then
        mark("boss-fight", t)
    elseif step == "boss-enter" and name == "mega-satan" and stage == 11 and t - stepAt > 40 then
        actor(1, function(p)
            if t - stepAt == 41 then
                report(
                    "NATIVE_MEGA_ENTRY variant="
                        .. p.Variant
                        .. " x="
                        .. p.Position.X
                        .. " y="
                        .. p.Position.Y
                )
            end
            -- Native room entry places the player below y=540. Walking north
            -- of that line starts the background's Mega Satan introduction.
            p.Position, p.Velocity = Vector(320, 440), Vector(0, -1)
        end)
    elseif
        step == "boss-enter"
        and name == "mother"
        and stage == 8
        and kind >= 4
        and t - stepAt > 40
    then
        actor(1, function(p)
            -- Corpse II's Boss room contains the native hole into the arena.
            -- Contact it after Room::Init has placed the entering player.
            p.Position, p.Velocity = Game():GetRoom():GetCenterPos(), Vector(1, 0)
        end)
    elseif step == "boss-fight" then
        if fight(t) and t - stepAt > 120 then
            mark("boss-loot", t)
            report("NATIVE_BOSS_CLEAR stage=" .. stage .. " type=" .. kind)
        end
    elseif step == "boss-loot" and t - stepAt > 100 then
        if stage == 6 and kind < 4 then
            photo = (name == "blue-baby" or name == "ascent") and 327 or 328
            if pick(PickupVariant.PICKUP_COLLECTIBLE, photo) then
                mark("photo", t)
            end
        elseif name == "mother" and stage == 6 and kind >= 4 then
            if Game():GetStateFlag(GameStateFlag.STATE_MAUSOLEUM_HEART_KILLED) then
                -- The heart room has no trapdoor. Return through the flesh
                -- door to Mom's room, whose native exit now leads to Corpse.
                local mom = findRoom(function(d)
                    return d.Data.Type == RoomType.ROOM_BOSS and d.SafeGridIndex >= 0
                end)
                assert(mom, "Missing native Mausoleum Mom room")
                move(mom, t)
                mark("entrance", t)
                report("NATIVE_MAUSOLEUM_HEART_RETURN")
            else
                mark("mother-door", t)
            end
        elseif stage == 11 or stage == 12 or name == "mother" and stage == 8 and kind >= 4 then
            if pick(PickupVariant.PICKUP_BIGCHEST) then
                mark("ending-chest", t)
            end
        elseif name == "delirium" and stage == 8 then
            specialEntrance(GridRooms.ROOM_BLUE_WOOM_IDX, t)
        elseif name == "delirium" and stage == 9 then
            specialEntrance(-9, t)
        elseif stage == 10 then
            if pick(PickupVariant.PICKUP_BIGCHEST) then
                mark("chest-floor", t)
            end
        elseif name == "mother" and (stage == 2 or stage == 4) then
            specialEntrance(GridRooms.ROOM_SECRET_EXIT_IDX, t)
        elseif stage == 8 and name == "blue-baby" then
            useEffect(EffectVariant.HEAVEN_LIGHT_DOOR, t)
        else
            useExit(GridEntityType.GRID_TRAPDOOR, t)
        end
    elseif step == "photo" then
        local has
        actor(1, function(p)
            has = p:HasCollectible(photo)
        end)
        if has and t - stepAt > 100 then
            report("NATIVE_PHOTO owned=" .. photo)
            if name == "ascent" then
                actor(1, function(p)
                    p:UseCard(Card.CARD_FOOL)
                end)
                mark("strange-door", t)
            else
                useExit(GridEntityType.GRID_TRAPDOOR, t)
            end
        end
    elseif step == "entrance" and t - stepAt > 100 then
        useExit(GridEntityType.GRID_TRAPDOOR, t)
    elseif step == "chest-floor" then
        if stage == 11 then
            mark("floor-arrived", t)
            contact = nil
            report("NATIVE_PHOTO_CHEST destination=" .. stage .. ":" .. kind)
        end
    elseif step == "mega-door" or step == "strange-door" or step == "mother-door" then
        local destination
        actor(1, function(p)
            protect(p)
            local room = Game():GetRoom()
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door then
                    local wanted = step == "mega-door" and door.TargetRoomIndex == -7
                        or step == "strange-door" and door.TargetRoomIndex == -10
                        or step == "mother-door" and door.TargetRoomType == RoomType.ROOM_BOSS
                    if wanted then
                        door:TryUnlock(p, false)
                        if step == "mother-door" then
                            shoot = ({ [0] = 4, [1] = 6, [2] = 5, [3] = 7 })[slot % 4]
                            p.Position = door.Position
                                + ({
                                        [0] = Vector(1, 0),
                                        [1] = Vector(0, 1),
                                        [2] = Vector(-1, 0),
                                        [3] = Vector(0, -1),
                                    })[slot % 4]
                                    * 60
                        else
                            p.Position = door.Position
                        end
                        if door:IsOpen() then
                            destination = door.TargetRoomIndex
                        end
                    end
                end
            end
        end)
        if destination then
            local old = step
            shoot = -1
            move(destination, t)
            mark(old == "strange-door" and "entrance" or "boss-enter", t)
            report("NATIVE_ROUTE_DOOR opened=" .. destination)
        end
    elseif step == "ascent-first" and t - stepAt > 110 then
        local exit = findRoom(function(d)
            return d.Data.Type == 1 and d.Data.Variant == 10000
        end)
        assert(exit, "Missing native upward exit")
        move(exit, t)
        mark("ascent-exit", t)
    elseif step == "ascent-exit" and t - stepAt > 110 then
        if not useEffect(EffectVariant.HEAVEN_LIGHT_DOOR, t) then
            if not useExit(GridEntityType.GRID_TRAPDOOR, t) then
                useExit(GridEntityType.GRID_STAIRS, t)
            end
        end
    elseif step == "home-bed" and t - stepAt > 110 then
        if pick(PickupVariant.PICKUP_BED) then
            mark("home-sleep", t)
        end
    elseif step == "home-sleep" and kind == 1 then
        contact = nil
        mark("home-night", t)
        report("NATIVE_HOME_NIGHT")
    elseif step == "home-night" and t - stepAt > 180 then
        if homeOnly then
            homeWalking, homeWalkReadyAt = true, nil
            mark("home-walk", t)
        else
            move(living, t)
            mark("dogma-tv", t)
        end
    elseif step == "dogma-tv" then
        actor(0, protect)
        local found
        actor(1, function(p)
            protect(p)
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == 950 then
                    found = true
                elseif e.Type == 960 and e.Variant == 4 then
                    p.Position = e.Position + Vector(0, 36)
                    p.Velocity = Vector.Zero
                end
            end
        end)
        if found and t - stepAt > 20 then
            actor(0, function()
                local arena = Game():GetLevel():GetRoomByIdx(living, 0)
                assert(
                    arena.Data and Game():GetRoom():GetRoomShape() == arena.Data.Shape,
                    "Host did not arrive in the native Dogma arena"
                )
                assert(
                    Game():GetLevel():GetCurrentRoomIndex() == living,
                    "Host remained outside the Dogma arena"
                )
            end)
            report("NATIVE_DOGMA_ARENA both_peers=" .. living)
            if homeOnly then
                actor(1, function(p)
                    homeOrigin, homeDistance = p.Position, 0
                end)
                homeWalking = true
                mark("dogma-walk", t)
            else
                mark("beast-fight", t)
            end
        end
    elseif step == "dogma-walk" or step == "home-walk" then
        actor(0, protect)
        actor(1, function(p)
            protect(p)
            local ready = p.ControlsEnabled
                and p:AreControlsEnabled()
                and p:IsExtraAnimationFinished()
            if not ready then
                homeWalkReadyAt = nil
                if (t - stepAt) % 150 == 1 then
                    report(
                        "DOGMA_CONTROLS enabled="
                            .. tostring(p.ControlsEnabled)
                            .. " allowed="
                            .. tostring(p:AreControlsEnabled())
                            .. " extra_finished="
                            .. tostring(p:IsExtraAnimationFinished())
                            .. " cooldown="
                            .. p.ControlsCooldown
                            .. " animation="
                            .. p:GetSprite():GetAnimation()
                    )
                end
                assert(t - stepAt < 900, "Native Home controls remain locked at " .. step)
                return
            end
            if not homeWalkReadyAt then
                homeWalkReadyAt, homeOrigin, homeDistance = t, p.Position, 0
                homeWalkPrevious, homeWalkMotion = p.Position, 0
            end
            homeDistance = math.max(homeDistance, (p.Position - homeOrigin):Length())
            local delta = (p.Position - homeWalkPrevious):Length()
            if delta > 0.01 and delta < 20 then
                homeWalkMotion = homeWalkMotion + 1
            end
            homeWalkPrevious = p.Position
            if t - homeWalkReadyAt > 100 then
                assert(
                    homeDistance > 10 and homeWalkMotion > 20,
                    "Guest input cannot move in the Dogma arena"
                )
                report(
                    (
                        step == "home-walk" and "NATIVE_HOME_WAKE_MOVEMENT distance="
                        or "NATIVE_DOGMA_MOVEMENT distance="
                    )
                        .. homeDistance
                        .. " walking_ticks="
                        .. homeWalkMotion
                )
                homeWalking, homeWalkReadyAt = false, nil
                if step == "home-walk" then
                    homeWakeMovement = true
                else
                    homeMovement = true
                    mark("beast-fight", t)
                end
            end
        end)
        if homeWakeMovement and step == "home-walk" then
            move(living, t)
            mark("dogma-tv", t)
        end
        if homeMovement then
            actor(0, function(p)
                assert(
                    p.ControlsEnabled and p:AreControlsEnabled(),
                    "Host Dogma controls remain disabled"
                )
            end)
        end
    elseif step == "beast-fight" then
        fight(t)
    end
    -- Dad's Note replaces the Mausoleum boss when the Strange Door selected
    -- the route. Use the generated pickup, never manufacture the route flags.
    if
        name == "ascent"
        and stage == 6
        and kind >= 4
        and step == "boss-enter"
        and t - stepAt > 110
    then
        if pick(PickupVariant.PICKUP_COLLECTIBLE, 668) then
            mark("note", t)
        end
    elseif
        step == "note"
        and Game():GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH)
        and t - stepAt > 150
    then
        previousStage, previousType = -1, -1
        contact = nil
        mark("floor-arrived", t)
        report("NATIVE_DADS_NOTE_ASCENT")
    end
    if contact then
        local e = contact.Ref
        if not e or not e:Exists() or e:IsDead() then
            contact = nil
        else
            actor(1, function(p)
                if step == "ending-chest" and t % 120 == 0 then
                    local pickup, sprite = e:ToPickup(), e:GetSprite()
                    report(
                        "CHEST_STATE state="
                            .. pickup.State
                            .. " touched="
                            .. tostring(pickup.Touched)
                            .. " animation="
                            .. sprite:GetAnimation()
                            .. " frame="
                            .. sprite:GetFrame()
                            .. " playing="
                            .. tostring(sprite:IsPlaying(sprite:GetAnimation()))
                            .. " wait="
                            .. pickup.Wait
                            .. " collision="
                            .. pickup.EntityCollisionClass
                            .. " seed="
                            .. pickup.InitSeed
                            .. " player_collision="
                            .. p.EntityCollisionClass
                            .. " cooldown="
                            .. p.ControlsCooldown
                    )
                    for _, other in ipairs(Isaac.GetRoomEntities()) do
                        if other.Type == 5 and other.Variant == 340 then
                            report(
                                "CHEST_ENTITY seed="
                                    .. other.InitSeed
                                    .. " state="
                                    .. other:ToPickup().State
                                    .. " wait="
                                    .. other:ToPickup().Wait
                                    .. " collision="
                                    .. other.EntityCollisionClass
                                    .. " x="
                                    .. other.Position.X
                                    .. " y="
                                    .. other.Position.Y
                            )
                        end
                    end
                end
                -- Re-enter a terminal chest after its native Victory Lap
                -- prompt, approaching from the side to avoid a Void portal. A stationary overlap before Appear finishes is not
                -- a new contact with the unlocked chest.
                local away = step == "ending-chest" and t % 90 < 20
                p.Position = e.Position + (away and Vector(60, 0) or Vector(4, 0))
                p.Velocity = Vector(away and -1 or 1, 0)
            end)
        end
    end
    actor(1, function()
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            local npc = e:ToNPC()
            if npc and npc.V2.X ~= npc.V2.X and not scratchReported[e.Type] then
                scratchReported[e.Type] = true
                report(
                    "NPC_SCRATCH type="
                        .. e.Type
                        .. " variant="
                        .. e.Variant
                        .. " v2x_bits="
                        .. string.format("%08x", string.unpack(">I4", string.pack(">f", npc.V2.X)))
                )
            end
        end
    end)
    assert(
        t - stepAt < (step == "beast-fight" and 3500 or 1500),
        "Route stalled at " .. step .. " stage=" .. stage .. ":" .. kind
    )
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        function()
            if not host and (shoot >= 0 or homeWalking) then
                local values = {}
                local direction = ({ 0, 2, 1, 3 })[math.floor(native.api_info().tick / 12) % 4 + 1]
                for action = 0, 15 do
                    values[#values + 1] = string.pack(
                        ">I2",
                        (homeWalking and action == direction or not homeWalking and action == shoot)
                                and 65535
                            or 0
                    )
                end
                return table.concat(values) .. string.pack(">I2", 0)
            end
            return capture()
        end,
        function(t, n, bytes)
            before(t, n, bytes)
            advance(t)
        end,
        function(slot, t)
            local bytes = collect(slot, t)
            if not bytes then
                return bytes
            end
            if homeOnly and slot == 0 then
                checkHomeVisual(_IsaacLanState.decode(bytes)[16])
            end
            return string.pack(">s4", bytes)
                .. _IsaacLanState.encode({ caseIndex, step, shoot, homeWalking })
        end,
        function(bytes, t, ack)
            local body, pos = string.unpack(">s4", bytes)
            local meta = _IsaacLanState.decode(bytes:sub(pos))
            local ok = restore(body, t, ack)
            if ok == false then
                return false
            end
            assert(meta[1] == caseIndex, "Ending case changed without a native win")
            snapshots = snapshots + 1
            if homeOnly then
                checkHomeVisual(_IsaacLanState.decode(body)[16])
            end
            observed[meta[2]] = (observed[meta[2]] or 0) + 1
            shoot = meta[3]
            homeWalking = meta[4]
            if homeOnly and meta[2] == "home-walk" then
                local p = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
                replicaWakeOrigin = replicaWakeOrigin or p.Position
                replicaWakeDistance =
                    math.max(replicaWakeDistance, (p.Position - replicaWakeOrigin):Length())
                if replicaWakePrevious then
                    local delta = (p.Position - replicaWakePrevious):Length()
                    if p:IsExtraAnimationFinished() and delta > 0.01 and delta < 40 then
                        replicaWakeMotion = replicaWakeMotion + 1
                    end
                end
                replicaWakePrevious = p.Position
            elseif homeOnly and meta[2] == "dogma-tv" and not homeWakeMovement then
                local p = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
                assert(
                    p.ControlsEnabled and p:AreControlsEnabled(),
                    "Replica remains locked after waking"
                )
                assert(
                    replicaWakeDistance > 10 and replicaWakeMotion > 5,
                    "Replica did not display walking after waking"
                )
                homeWakeMovement = true
                report(
                    "NATIVE_HOME_WAKE_MOVEMENT replica_distance="
                        .. replicaWakeDistance
                        .. " walking_snapshots="
                        .. replicaWakeMotion
                )
            end
            if homeOnly and (meta[2] == "dogma-walk" or meta[2] == "beast-fight") then
                local p = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
                homeOrigin = homeOrigin or p.Position
                homeDistance = math.max(homeDistance, (p.Position - homeOrigin):Length())
                if meta[2] == "beast-fight" and not homeMovement then
                    assert(
                        p.ControlsEnabled and p:AreControlsEnabled(),
                        "Replica Dogma controls remain disabled"
                    )
                    assert(homeDistance > 10, "Replica did not display Dogma arena movement")
                    homeMovement = true
                end
            end
            assert(native.api_with_local_view(function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:ToNPC() then
                        observeBoss(e)
                    end
                end
            end))
            return ok
        end,
        present,
        function(...)
            floorEvents = floorEvents + 1
            return beginFloor(...)
        end
    )
end
