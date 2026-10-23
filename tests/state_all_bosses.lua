local testInput = assert(_IsaacLanTestInput)
-- bossCases is supplied by build_boss_suite.py. Native room layouts remain
-- game-owned; only the four angel variants require explicit fixture spawns.
local native, host, port = assert(_IsaacLan), _IsaacLanTest.host, _IsaacLanTest.port
local frame = _IsaacLanFrame
local renders, linked, chosen, finished = 0, false, false, false
local caseIndex, phase, at = 1, "floor", 0
local live, visible, views, caseViews, seen, passed = 0, 0, 0, 0, false, {}
local forms = {}
local stomachRooms, stomachSource, heldMask = {}, nil, 0
local protectedDamage = {}
local function report(value)
    Isaac.DebugString("LAN_NETWORK ALL_BOSSES " .. value)
end
-- Actors are held in place to observe native Boss phases. Protect the fixture
-- from accumulated damage: a dead co-op ghost would follow its living teammate
-- out of the next test room instead of participating in that encounter.
Isaac.AddCallback(
    { Name = "Isolated Boss encounter protection" },
    ModCallbacks.MC_ENTITY_TAKE_DMG,
    function(_, _, _, flags, source)
        if host and not finished then
            local key = bossCases[caseIndex].key
            local signature = key .. ":" .. flags .. ":" .. source.Type .. ":" .. source.Variant
            if not protectedDamage[signature] then
                protectedDamage[signature] = true
                report(
                    "DAMAGE_BLOCKED key="
                        .. key
                        .. " flags="
                        .. flags
                        .. " source="
                        .. source.Type
                        .. ":"
                        .. source.Variant
                )
            end
            return false
        end
    end,
    EntityType.ENTITY_PLAYER
)
local function observeRoom(case)
    if not case.stomach then
        return
    end
    local index = Game():GetLevel():GetCurrentRoomIndex()
    stomachSource = stomachSource or index
    if not stomachRooms[index] then
        stomachRooms[index] = true
        report("STOMACH room=" .. index)
    end
    if index == -14 or index == -15 then
        local positions = native.rooms_positions()
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Isaac.GetPlayer(i)
            local location = positions[tostring(p.ControllerIndex - 1)]
            if location and location.index == index then
                assert(
                    p:IsExtraAnimationFinished() or p:GetSprite():GetAnimation() ~= "FallIn",
                    "Rotgut entrant retained the swallowing animation: controller="
                        .. p.ControllerIndex
                )
            end
        end
    end
end
local function actor(slot, fn, actorOnly)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end, actorOnly or 0))
end
local function mark(value, tick)
    phase, at = value, tick
    report("STEP key=" .. bossCases[caseIndex].key .. " phase=" .. phase .. " tick=" .. tick)
end
local function observe(entity, case)
    if entity:ToNPC() and entity:IsBoss() then
        local form = entity.Type .. ":" .. entity.Variant .. ":" .. entity.SubType
        if not forms[form] then
            forms[form] = true
            report("FORM key=" .. case.key .. " entity=" .. form)
        end
    end
    if entity.Type == case.entity and entity.Variant == case.variant then
        if case.held_bombs then
            local bombs = { native.boss_held_bombs(entity:GetSprite()) }
            assert(#bombs == case.held_bombs, "Missing native held bomb slots")
            for slot, index in ipairs(bombs) do
                if index >= 0 then
                    heldMask = heldMask | (1 << (slot - 1))
                end
            end
        end
        seen = true
        if not entity:IsDead() then
            live = live + 1
            if entity.Visible and entity:GetSprite():GetAnimation() ~= "" then
                visible = visible + 1
            end
        end
    end
end
local function complete(case)
    if passed[case.key] then
        return
    end
    assert(seen and live >= 30 and visible >= 10, "Boss was not displayed alive: " .. case.key)
    assert(host or caseViews >= 30, "Boss had insufficient replica views: " .. case.key)
    if case.stomach then
        assert(
            stomachRooms[-14] and stomachRooms[-15] and forms["911:1:0"] and forms["911:2:0"],
            "Missing Rotgut stomach phases"
        )
        for slot = 0, 1 do
            assert(
                native.rooms_positions()[tostring(slot)].index == stomachSource,
                "Rotgut returned a player to the wrong room"
            )
            actor(slot, function(p)
                assert(p:IsExtraAnimationFinished(), "Rotgut return retained an extra animation")
            end)
        end
        report("RETURN source=" .. stomachSource .. " players=2")
    end
    if case.held_bombs then
        assert(heldMask == (1 << case.held_bombs) - 1, "Not all held bomb slots were observed")
        report("HELD key=" .. case.key .. " mask=" .. heldMask)
    end
    passed[case.key] = true
    report(
        "PASS key="
            .. case.key
            .. " live="
            .. live
            .. " visible="
            .. visible
            .. " views="
            .. caseViews
    )
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
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
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    return status
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(function()
        return testInput.neutral
    end, function(tick, count, bytes)
        before(tick, count, bytes)
        if finished or not native.rooms_ready() then
            return
        end
        local case = bossCases[caseIndex]
        for slot = 0, 1 do
            actor(slot, function(player)
                assert(
                    not player:IsDead() and not player:IsCoopGhost(),
                    "Boss fixture actor died: "
                        .. case.key
                        .. " phase="
                        .. phase
                        .. " slot="
                        .. slot
                )
                player:SetMinDamageCooldown(120)
                if case.hold_position ~= false or phase ~= "fight" then
                    player.Position =
                        Game():GetRoom():GetClampedPosition(Vector(160 + slot * 50, 340), 30)
                    player.Velocity = Vector.Zero
                end
            end)
        end
        if phase == "floor" and tick - at >= 45 then
            local level = Game():GetLevel()
            -- Console rooms reuse the same negative room index. A fresh floor
            -- discards its previous room cache before loading the next layout.
            Game():SetStateFlag(GameStateFlag.STATE_SECRET_PATH, case.stage_type >= 4)
            level:SetStage(case.stage, case.stage_type)
            Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
            mark("floor-ready", tick)
        elseif phase == "floor-ready" and tick - at >= 150 then
            assert(
                Game():GetLevel():GetStage() == case.stage
                    and Game():GetLevel():GetStageType() == case.stage_type
            )
            actor(0, function()
                report(
                    "ROOM key="
                        .. case.key
                        .. " result="
                        .. Isaac.ExecuteCommand("goto " .. case.room)
                )
            end, 1)
            mark("enter", tick)
        elseif phase == "enter" and tick - at >= 90 then
            actor(0, function()
                assert(
                    Game():GetRoom():GetType()
                        == (
                            case.room:find("miniboss") and RoomType.ROOM_MINIBOSS
                            or RoomType.ROOM_BOSS
                        ),
                    "Boss room was not entered: " .. case.key
                )
            end)
            local position = native.rooms_positions()["0"]
            assert(native.rooms_move(1, position.index, position.dimension, -1))
            if case.spawn then
                actor(0, function()
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        if entity:IsActiveEnemy(false) then
                            entity:Remove()
                        end
                    end
                    Isaac.Spawn(
                        case.entity,
                        case.variant,
                        0,
                        Game():GetRoom():GetCenterPos(),
                        Vector.Zero,
                        nil
                    )
                    Game():GetRoom():SetClear(false)
                end)
            end
            mark("fight", tick)
        elseif phase == "fight" then
            local clear = false
            actor(0, function(player)
                observeRoom(case)
                if case.stomach and tick % 300 == 0 then
                    report(
                        "ACTOR room="
                            .. Game():GetLevel():GetCurrentRoomIndex()
                            .. " controls="
                            .. tostring(player.ControlsEnabled)
                            .. " visible="
                            .. tostring(player.Visible)
                            .. " position="
                            .. tostring(player.Position)
                            .. " clear="
                            .. tostring(Game():GetRoom():IsClear())
                    )
                end
                local bombs = 0
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    observe(entity, case)
                    if entity.Type == case.entity then
                        if tick % 300 == 0 then
                            report(
                                "LIVE key="
                                    .. case.key
                                    .. " variant="
                                    .. entity.Variant
                                    .. " hp="
                                    .. entity.HitPoints
                                    .. " animation="
                                    .. entity:GetSprite():GetAnimation()
                            )
                        end
                        if
                            case.bombs
                            and tick - at >= (case.warmup or 180)
                            and tick % 60 == 0
                            and bombs < 2
                        then
                            player:FireBomb(entity.Position, Vector.Zero):SetExplosionCountdown(6)
                            bombs = bombs + 1
                        end
                    end
                    if
                        tick - at >= (case.warmup or 180)
                        and tick % 6 == 0
                        and entity:IsActiveEnemy(false)
                        -- Both peers must observe the heart before the fixture kills it.
                        and (
                            not case.stomach
                            or entity.Variant ~= 2
                            or (
                                native.rooms_positions()["0"].index == -15
                                and native.rooms_positions()["1"].index == -15
                            )
                        )
                    then
                        entity:TakeDamage(
                            math.max(10, entity.MaxHitPoints / 30),
                            0,
                            EntityRef(player),
                            0
                        )
                    end
                end
                clear = Game():GetRoom():IsClear()
                if case.stomach and Game():GetLevel():GetCurrentRoomIndex() < -3 then
                    clear = false
                end
                if case.stomach then
                    local positions = native.rooms_positions()
                    clear = clear
                        and positions["0"].index == stomachSource
                        and positions["1"].index == stomachSource
                end
            end)
            if case.stomach then
                -- Each player can leave the first stomach at a different time.
                for slot = 0, 1 do
                    actor(slot, function(p)
                        local room = Game():GetLevel():GetCurrentRoomIndex()
                        if
                            room == -14
                            and #Isaac.FindByType(case.entity, -1, -1, false, false) == 0
                        then
                            p.Velocity = Vector(6, p.Velocity.Y)
                        end
                        if tick % 300 == 0 then
                            report(
                                "FIXTURE_PARTY slot="
                                    .. slot
                                    .. " room="
                                    .. room
                                    .. " position="
                                    .. tostring(p.Position)
                            )
                        end
                    end)
                end
            end
            if clear and seen and tick - at >= 210 then
                complete(case)
                mark("clear", tick)
            end
        elseif phase == "clear" and tick - at >= 120 then
            if caseIndex == #bossCases then
                finished = true
                Isaac.DebugString("LAN_NETWORK PASS all selected Boss encounters")
            else
                caseIndex = caseIndex + 1
                live, visible, seen, forms = 0, 0, false, {}
                heldMask, stomachRooms, stomachSource = 0, {}, nil
                mark("floor", tick)
            end
        end
        assert(tick - at < 6000, "Boss encounter stalled: " .. case.key .. " phase=" .. phase)
    end, function(slot, tick)
        local bytes, stable = collect(slot, tick)
        return string.pack(">s4", bytes) .. _IsaacLanState.encode({ caseIndex, phase, finished }),
            stable
    end, function(bytes, tick, ack, betweenUpdates, stable)
        local body, offset = string.unpack(">s4", bytes)
        local meta = _IsaacLanState.decode(bytes:sub(offset))
        if restore(body, tick, ack, betweenUpdates, stable) == false then
            return false
        end
        views = views + 1
        if meta[1] ~= caseIndex then
            assert(passed[bossCases[caseIndex].key], "Skipped Boss result on replica")
            caseIndex = meta[1]
            live, visible, caseViews, seen, forms = 0, 0, 0, false, {}
            heldMask, stomachRooms, stomachSource = 0, {}, nil
        end
        local case = bossCases[caseIndex]
        if meta[2] == "fight" or meta[2] == "clear" then
            caseViews = caseViews + 1
            assert(native.api_with_local_view(function()
                observeRoom(case)
                local entities = {}
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    observe(entity, case)
                    entities[entity:GetData().__isaac_lan_replica or -1] = entity
                end
                for _, entity in ipairs(_IsaacLanState.decode(body, stable)[11][3]) do
                    if entity[2] == case.entity then
                        local actual = assert(entities[entity[1]], "Boss replica is missing")
                        assert(
                            actual.Type == entity[2]
                                and actual.Variant == entity[3]
                                and actual.SubType == entity[4],
                            "Boss replica identity differs"
                        )
                        assert(
                            actual.Position:Distance(Vector(table.unpack(entity[6]))) < 0.1,
                            "Boss replica position differs"
                        )
                        if case.held_bombs then
                            local actualLinks = { native.boss_held_bombs(actual:GetSprite()) }
                            local links = {
                                string.unpack(">" .. string.rep("I4", case.held_bombs), entity[24]),
                            }
                            for slot = 1, case.held_bombs do
                                local expected = links[slot] == 0 and -1
                                    or assert(entities[links[slot]], "Missing held bomb replica").Index
                                assert(
                                    actualLinks[slot] == expected,
                                    "Native held bomb identity differs"
                                )
                            end
                        end
                    end
                end
            end))
            if meta[2] == "clear" then
                complete(case)
            end
        end
        if meta[3] and not finished then
            for _, value in ipairs(bossCases) do
                assert(passed[value.key], "Missing Boss result")
            end
            finished = true
            Isaac.DebugString("LAN_NETWORK PASS all selected Boss encounters")
        end
        return true
    end, present, beginFloor)
end
