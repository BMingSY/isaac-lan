-- One protected pair; normal room input, host awards and replicated artwork.
local native, input = assert(_IsaacLan), assert(_IsaacLanTestInput)
local file = assert(io.open("./lan-test-role.txt", "r"))
local host = file:read("*l") == "host"
file:close()
file = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = file:read("*l")
file:close()
local rules = _IsaacLanModules["compat/routes/jericho_rules"]
local layout = _IsaacLanModules["compat/routes/jericho_layout"]
local codec = _IsaacLanModules["sync/codec"]
local F = rules.fields
local originalFrame, action, gate = _IsaacLanFrame, _IsaacLanActionStep, native.net_gate
local frames, linked, running, finished = 0, false, false, false
local closedAt, relinked
local step, at, pair, plate, forced, reconnecting, waited, rejoined =
    "find", 0, nil, 1, false, false, false, false
local savedPayload, savedItems, saving, resumeRequested, waterForced, waterKey, configured
local waterAttempts = 0
local function report(text)
    Isaac.DebugString("LAN_NETWORK JERICHO " .. text)
end
local function candidates()
    local level = Game():GetLevel()
    for index = 0, 168 do
        local desc = level:GetRoomByIdx(index, 0)
        if desc and desc.Data and desc.SafeGridIndex == index then
            local _, quest = native.room_connections(index)
            for dimension = 0, 1 do
                local room = level:GetRoomByIdx(index, dimension)
                if room and room.Data then
                    local spawns = {}
                    for i = 0, room.Data.Spawns.Size - 1 do
                        local entries = room.Data.Spawns:Get(i).Entries
                        for j = 0, entries.Size - 1 do
                            local entry = entries:Get(j)
                            spawns[#spawns + 1] =
                                table.concat({ entry.Type, entry.Variant, entry.Subtype }, ".")
                        end
                    end
                    report(table.concat({
                        "candidate",
                        index,
                        dimension,
                        room.SafeGridIndex,
                        room.Data.Type,
                        room.Data.Shape,
                        room.Data.Subtype,
                        room.Flags,
                        room.VisitedCount,
                        tostring(quest),
                        table.concat(spawns, ","),
                    }, " "))
                end
            end
        end
    end
end
local function mark(value)
    step, at = value, native.api_info().tick
    report(value)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(0))
    end, 1))
end
local function park(slot, x, y)
    actor(slot, function(player)
        player.Position = Game():GetRoom():GetCenterPos() + Vector(x, y)
        player.Velocity = Vector.Zero
        player:SetMinDamageCooldown(10000)
    end)
end
local function items(slot)
    local found = {}
    actor(slot, function()
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if
                entity.Type == EntityType.ENTITY_PICKUP
                and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE
            then
                found[#found + 1] = entity.SubType
            end
        end
    end)
    return found
end
local function emptyLayout(slot)
    actor(slot, function()
        local room = Game():GetRoom()
        for index = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(index)
            if grid then
                local kind = grid:GetType()
                assert(
                    kind == GridEntityType.GRID_WALL
                        or kind == GridEntityType.GRID_DOOR
                        or kind == GridEntityType.GRID_DECORATION
                        or kind == GridEntityType.GRID_PILLAR,
                    "Original layout terrain returned: " .. kind .. " at " .. index
                )
            end
        end
    end)
end
local install = native.room_empty_pair
native.room_empty_pair = function(first, second, restore)
    local level = Game():GetLevel()
    local before = {}
    for index = 0, 168 do
        local desc = level:GetRoomByIdx(index, 0)
        if desc and desc.Data and desc.SafeGridIndex == index then
            before[index] = {
                desc.Data.Type,
                desc.Data.Variant,
                desc.Data.Shape,
                desc.Data.SpawnCount,
                table.concat(native.room_connections(index), ":"),
            }
        end
    end
    local ok = install(first, second, restore)
    report(
        "native install "
            .. first
            .. "/"
            .. second
            .. " restore="
            .. restore
            .. " result="
            .. tostring(ok)
    )
    if ok then
        for index, saved in pairs(before) do
            local desc = level:GetRoomByIdx(index, 0)
            assert(
                desc.Data.Type == saved[1]
                    and desc.Data.Variant == saved[2]
                    and desc.Data.Shape == saved[3],
                "Room identity changed"
            )
            assert(
                table.concat(native.room_connections(index), ":") == saved[5],
                "Native map connection changed"
            )
            assert(
                desc.Data.SpawnCount == ((index == first or index == second) and 0 or saved[4]),
                "Unselected room layout changed"
            )
        end
        report("PASS native map preserved " .. first .. "/" .. second)
    end
    return ok
end
native.net_gate = function(capture, ...)
    return gate(function()
        local view = _IsaacLanState.jerichoView()
        local buttons = view
                and view[F.progress] == 6
                and not view[F.complete]
                and (1 << (host and ButtonAction.ACTION_SHOOTDOWN or ButtonAction.ACTION_SHOOTUP))
            or 0
        return input.buttons(buttons)
    end, ...)
end
local function advance()
    action()
    local info = native.api_info()
    if not host or info.ready ~= 1 or info.connected ~= 3 or finished then
        return
    end
    running = true
    local view = _IsaacLanState.jerichoView()
    local elapsed = info.tick - at
    assert(elapsed < 1800, "Jericho fixture stalled: " .. step)
    if step == "find" and info.tick > 50 then
        if not view then
            if forced then
                local level = Game():GetLevel()
                for i = 0, level:GetRooms().Size - 1 do
                    local desc = level:GetRooms():Get(i)
                    if desc.Data then
                        local mirror = level:GetRoomByIdx(desc.SafeGridIndex, 1)
                        report(table.concat({
                            "candidate",
                            desc.SafeGridIndex,
                            desc.Data.Type,
                            desc.Data.Shape,
                            tostring(desc.Data.Subtype),
                            desc.Flags,
                            desc.VisitedCount,
                            mirror and mirror.SafeGridIndex or -99,
                            mirror and mirror.ListIndex or -99,
                        }, " "))
                    end
                end
            end
            assert(not forced, "No eligible pair on fixture floor")
            -- Deterministic fixture setup exercises generation at the normal
            -- 100% cap; probability progression itself is covered offline.
            assert(native.net_run_state(codec.encode({ rules.version, 100, false, 0, {} })))
            forced = true
            report("fixture probability set to cap")
            return
        end
        pair = { view[F.first], view[F.second] }
        for slot = 0, 1 do
            actor(slot, function(player)
                player:AddCollectible(CollectibleType.COLLECTIBLE_D6, 0, false)
                player:SetActiveCharge(0)
            end)
            assert(native.rooms_teleport(slot, pair[slot + 1], 0))
        end
        mark("enter")
    elseif step == "enter" and elapsed > 90 then
        for slot = 0, 1 do
            local position = native.rooms_positions()[tostring(slot)]
            assert(position.index == pair[slot + 1] and position.dimension == 0)
            park(slot, slot == 0 and -100 or 100, 0)
            assert(#items(slot) == 0, "Preview is a real pickup")
            actor(slot, function()
                assert(Game():GetRoom():IsClear(), "Puzzle door sealed")
                local walls = 0
                for index = 0, Game():GetRoom():GetGridSize() - 1 do
                    local grid = Game():GetRoom():GetGridEntity(index)
                    if grid and grid:GetType() == GridEntityType.GRID_PILLAR then
                        walls = walls + 1
                    end
                end
                assert(walls == 8, "Missing native central walls: " .. walls)
            end)
        end
        report("PASS split rooms, open doors and virtual rewards")
        mark("reroll")
    elseif step == "reroll" and elapsed > 30 then
        local first, second = view[F.firstItem], view[F.secondItem]
        actor(0, function(player)
            player:UseActiveItem(CollectibleType.COLLECTIBLE_D6, UseFlag.USE_NOANIM)
        end)
        view = _IsaacLanState.jerichoView()
        assert(view[F.firstItem] == first and view[F.secondItem] == second and #items(0) == 0)
        park(0, -160, 80)
        mark("wrong")
    elseif step == "wrong" and elapsed > 30 then
        assert(view[F.progress] == 0)
        park(0, -100, 0)
        mark("sequence")
    elseif step == "sequence" and elapsed > 25 then
        local offset = layout.plates[plate]
        park((plate - 1) % 2, offset[1], offset[2])
        mark("pressed")
    elseif step == "pressed" and elapsed > 25 then
        assert(
            view[F.progress] == plate,
            "Sequence did not advance: " .. view[F.progress] .. "/" .. plate
        )
        park((plate - 1) % 2, plate % 2 == 1 and -100 or 100, 0)
        plate = plate + 1
        if plate == 4 then
            mark("checkpoint")
        elseif plate <= 6 then
            mark("sequence")
        else
            park(0, 0, -120)
            park(1, 0, 120)
            mark("horns")
        end
    elseif step == "checkpoint" and elapsed > 20 then
        assert(native.rooms_teleport(0, Game():GetLevel():GetStartingRoomIndex(), 0))
        mark("rewind-room")
    elseif step == "rewind-room" and elapsed > 60 then
        actor(0, function(player)
            player:UseActiveItem(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, UseFlag.USE_NOANIM)
        end)
        mark("rewind")
    elseif step == "rewind" and elapsed > 100 then
        assert(
            view and view[F.progress] == 3 and not view[F.complete],
            "Hourglass lost puzzle progress"
        )
        assert(native.rooms_positions()["0"].index == pair[1], "Hourglass lost split location")
        assert(#items(0) == 0 and #items(1) == 0)
        emptyLayout(0)
        emptyLayout(1)
        park(0, -100, 0)
        park(1, 100, 0)
        report("PASS native hourglass restores matching puzzle checkpoint")
        mark("sequence")
    elseif step == "horns" and elapsed > 100 then
        assert(view[F.complete], "Cooperative attack did not complete")
        for slot = 0, 1 do
            local found = items(slot)
            assert(
                #found == 1 and found[1] == view[slot == 0 and F.firstItem or F.secondItem],
                "Reward differs from preview"
            )
            actor(slot, function(player)
                assert(
                    player:GetActiveCharge() == 1,
                    "Room charge differs: " .. player:GetActiveCharge()
                )
            end)
        end
        report("PASS six plates, joint attack, two rewards and one charge per room")
        assert(native.rooms_teleport(0, Game():GetLevel():GetStartingRoomIndex(), 0))
        mark("leave")
    elseif step == "leave" and elapsed > 50 then
        assert(native.rooms_teleport(0, pair[1], 0))
        mark("return")
    elseif step == "return" and elapsed > 60 then
        emptyLayout(0)
        emptyLayout(1)
        assert(#items(0) == 1 and #items(1) == 1)
        for slot = 0, 1 do
            actor(slot, function(player)
                assert(player:GetActiveCharge() == 1, "Reentry repeated charge")
            end)
        end
        _IsaacLanChatSubmit("JERICHO_RECONNECT")
        mark("reconnect")
    elseif step == "reconnect" and elapsed > 50 then
        for _, message in ipairs(_IsaacLanChatMessages()) do
            if message.text:find("JERICHO_REJOINED", 1, true) then
                assert(#items(0) == 1 and #items(1) == 1)
                report("PASS reentry and reconnect preserve awards")
                savedPayload = native.net_run_state()
                savedItems = { view[F.firstItem], view[F.secondItem] }
                saving = true
                _IsaacLanChatSubmit("JERICHO_SAVE")
                assert(native.net_command(3))
                mark("save")
            end
        end
    elseif step == "resume" and elapsed > 100 then
        assert(
            view
                and view[F.complete]
                and view[F.firstItem] == savedItems[1]
                and view[F.secondItem] == savedItems[2],
            "Continue lost fixed rewards"
        )
        assert(native.net_run_state() == savedPayload, "Continue changed bridge payload")
        for slot = 0, 1 do
            emptyLayout(slot)
            assert(#items(slot) == 1, "Continue duplicated or lost pedestal")
            actor(slot, function(player)
                assert(player:GetActiveCharge() == 1, "Continue repeated charge")
            end)
        end
        report("PASS save, native continue and both independent rewards")
        actor(0, function(player)
            Game():GetLevel():SetStage(2, StageType.STAGETYPE_REPENTANCE)
            Game():StartStageTransition(true, 0, player)
        end)
        mark("water")
    elseif step == "water" and elapsed > 150 then
        assert(
            Game():GetLevel():GetStage() == 2
                and Game():GetLevel():GetStageType() == StageType.STAGETYPE_REPENTANCE
        )
        if not view then
            if waterForced then
                candidates()
                waterAttempts = waterAttempts + 1
                assert(waterAttempts <= 10, "No eligible pair across water-two fixtures")
                report("PASS insufficient ordinary rooms skipped; regenerate fixture floor")
                actor(0, function(player)
                    for stage = LevelStage.STAGE1_1, LevelStage.NUM_STAGES - 1 do
                        Game():GetSeeds():ForgetStageSeed(stage)
                    end
                    Game():GetLevel():SetStage(LevelStage.STAGE1_2, StageType.STAGETYPE_REPENTANCE)
                    Game():StartStageTransition(true, 0, player)
                end)
                waterForced = false
                mark("water")
                return
            end
            native.net_run_state(codec.encode({ rules.version, 100, false, 0, {} }))
            waterForced = true
            return
        end
        waterKey = view[F.key]
        pair = { view[F.first], view[F.second] }
        for slot = 0, 1 do
            assert(native.rooms_teleport(slot, pair[slot + 1], 0))
        end
        mark("water-main")
    elseif step == "water-main" and elapsed > 100 then
        assert(view and view[F.key] == waterKey and not view[F.complete])
        for slot = 0, 1 do
            park(slot, slot == 0 and -100 or 100, 0)
            assert(#items(slot) == 0)
            actor(slot, function(player)
                report("water backdrop " .. Game():GetRoom():GetBackdropType())
                player:SetMinDamageCooldown(0)
                Isaac.Spawn(EntityType.ENTITY_FIREPLACE, 4, 0, player.Position, Vector.Zero, nil)
            end)
        end
        mark("white-fire")
    elseif step == "white-fire" and elapsed > 45 then
        for slot = 0, 1 do
            actor(slot, function(player)
                assert(
                    player:GetEffects():HasNullEffect(NullItemID.ID_LOST_CURSE),
                    "Fixture white fire did not transform player"
                )
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity.Type == EntityType.ENTITY_FIREPLACE and entity.Variant == 4 then
                        entity:Remove()
                    end
                end
            end)
            assert(native.rooms_teleport(slot, pair[slot + 1], 1))
        end
        mark("mirror")
    elseif step == "mirror" and elapsed > 100 then
        for slot = 0, 1 do
            emptyLayout(slot)
            assert(native.rooms_positions()[tostring(slot)].dimension == 1)
            actor(slot, function(player)
                assert(Game():GetRoom():IsMirrorWorld(), "Fixture missed native mirror dimension")
                assert(Game():GetRoom():IsClear())
                assert(player:GetActiveCharge() == 1, "Mirror granted charge")
                for index = 0, Game():GetRoom():GetGridSize() - 1 do
                    local grid = Game():GetRoom():GetGridEntity(index)
                    assert(
                        not grid or grid:GetType() ~= GridEntityType.GRID_PILLAR,
                        "Mirror retained active walls"
                    )
                end
            end)
            assert(#items(slot) == 0, "Mirror contained a reward")
        end
        assert(view[F.progress] == 0 and not view[F.complete])
        _IsaacLanChatSubmit("JERICHO_MIRROR_CHECK")
        mark("mirror-check")
    elseif step == "mirror-check" and elapsed > 60 then
        for _, message in ipairs(_IsaacLanChatMessages()) do
            if message.text:find("JERICHO_MIRROR_OK", 1, true) then
                report("PASS water-two native background and empty mirror ruins")
                finished = true
                Isaac.DebugString("LAN_NETWORK PASS jericho rooms")
            end
        end
    end
end
function _IsaacLanActionStep()
    local ok, message = pcall(advance)
    if not ok then
        Isaac.DebugString("LAN_NETWORK FAILED Jericho: " .. tostring(message))
        finished = true
        error(message)
    end
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = originalFrame()
    if running and (status.phase == 0 or status.phase == 5) and not relinked then
        closedAt = closedAt or frames
        if frames - closedAt >= (host and 30 or 90) then
            relinked = true
            configured = false
            _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
            report("reopen lobby for native continue")
        end
    end
    if status.phase == 2 then
        if host and not configured then
            assert(native.net_configure_options(16))
            configured = true
        elseif status["ready" .. status.slot] == 0 then
            _IsaacLanCommand("choose", "0:1")
        end
        if
            host
            and status.roomOptions == 16
            and status.players == 2
            and status.ready0 == 1
            and status.ready1 == 1
        then
            if saving and not resumeRequested then
                resumeRequested = true
                local players, options = native.net_saved_info()
                assert(players == 2 and options == 16, "Saved party/options unavailable")
                assert(native.net_resume(), "Native continue rejected matching party/options")
                mark("resume")
                at = 0
            elseif not running then
                _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
            end
        end
    end
    local info = native.api_info()
    if not host and info.ready == 1 then
        running = true
        local view = _IsaacLanState.jerichoView()
        for _, message in ipairs(_IsaacLanChatMessages()) do
            if message.text:find("JERICHO_RECONNECT", 1, true) and not reconnecting then
                assert(view and view[F.complete] and #items(1) == 1)
                reconnecting = true
                _IsaacLanCommand("reconnect")
            end
        end
        if reconnecting and waited and not rejoined then
            assert(view and view[F.complete] and #items(1) == 1)
            actor(1, function(player)
                assert(player:GetActiveCharge() == 1)
            end)
            rejoined = true
            _IsaacLanChatSubmit("JERICHO_REJOINED")
            report("PASS replica progress, rewards, charge and reconnect")
        end
        for _, message in ipairs(_IsaacLanChatMessages()) do
            if message.text:find("JERICHO_MIRROR_CHECK", 1, true) and not finished then
                assert(view and view[F.progress] == 0 and not view[F.complete])
                assert(native.rooms_positions()["1"].dimension == 1 and #items(1) == 0)
                actor(1, function(player)
                    assert(Game():GetRoom():IsMirrorWorld() and player:GetActiveCharge() == 1)
                end)
                _IsaacLanChatSubmit("JERICHO_MIRROR_OK")
                finished = true
                Isaac.DebugString("LAN_NETWORK PASS jericho rooms")
            end
        end
    elseif reconnecting and not rejoined then
        waited = true
    end
    assert(status.phase ~= 4, status.error)
    return status
end
