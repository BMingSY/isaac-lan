-- One XML-only Mod, four native processes, three consecutive ordinary sessions.
local native, port = assert(_IsaacLan), _IsaacLanTest.port
local roleFile = assert(io.open("./lan-test-role.txt", "r"))
local ordinal = assert(({ host = 0, client = 1, client2 = 2, client3 = 3 })[roleFile:read("*l")])
roleFile:close()
local host = ordinal == 0
local cases = {
    { name = "two-normal", kinds = { "normal", "normal" } },
    { name = "three-mixed", kinds = { "normal", "tainted", "achievement" } },
    { name = "four-tainted", kinds = { "tainted", "tainted", "tainted", "tainted" } },
}
local ids, current, case, renders = nil, 0, nil, 0
local linked, chosen, started, participated, done, reported =
    false, false, false, false, false, false
local startAt, selectedAt, exitedAt, lastHeartbeat = 0, nil, nil, 0
local stage, stageAt, otherRoom, snapshots, starts = "init", 0, nil, 0, 0
local menuOpened, pendingChoice, nextKeyAt, menuSteps = false, nil, 0, 0
local owner = { Name = "Native character catalog acceptance" }
local function read(name)
    local file = io.open(characterCoordination .. "/" .. name, "r")
    if not file then
        return nil
    end
    local value = file:read("*a")
    file:close()
    return value ~= "" and value or nil
end
local function write(name, value)
    local file = assert(io.open(characterCoordination .. "/" .. name, "w"))
    file:write(value)
    file:close()
end
local function report(value)
    Isaac.DebugString(
        "LAN_NETWORK CHARACTER_CATALOG case=" .. (case and case.name or "boot") .. " " .. value
    )
end
local function expected(slot)
    return assert(ids[assert(case.kinds[slot + 1])])
end
local function checkCatalog()
    local choices, catalog = native.net_characters()
    assert(type(catalog) == "table", "Native character catalog metadata is missing")
    local seen = {}
    for _, id in ipairs(choices) do
        assert(type(id) == "number" and not seen[id], "Invalid or duplicate character choice")
        seen[id] = true
        assert(catalog[tostring(id)], "Selectable character has no native metadata")
    end
    assert(seen[0] and not seen[22], "Native Isaac/Tainted Magdalene unlock selection differs")
    assert(catalog["22"], "Locked native starting character is missing from the catalog")
    for _, kind in ipairs({ "normal", "tainted", "achievement" }) do
        assert(seen[ids[kind]], "Registered selectable Mod character is missing: " .. kind)
        local metadata = assert(catalog[tostring(ids[kind])])
        assert(
            metadata.name
                == (kind == "achievement" and "LAN Achievement Probe" or "LAN Catalog Probe"),
            "Mod name was replaced"
        )
        assert(metadata.tainted == (kind == "tainted"), "Mod tainted pairing differs")
    end
    assert(
        not seen[ids.hidden] and not catalog[tostring(ids.hidden)],
        "Hidden Mod character was exposed"
    )
    return choices, catalog
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function checkActors(label)
    local values = {}
    for slot = 0, #case.kinds - 1 do
        actor(slot, function(player)
            assert(player.ControllerIndex == slot + 1, "Native character changed controller slot")
            assert(
                player:GetPlayerType() == expected(slot),
                "Native start substituted the selected Mod character"
            )
            values[#values + 1] = slot .. ":" .. player:GetPlayerType()
        end)
    end
    report(label .. " actors=" .. table.concat(values, ","))
end
local function mark(name, t)
    stage, stageAt = name, t
    report("STEP " .. name .. " tick=" .. t .. " ms=" .. native.api_info().nowMs)
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function()
    starts = starts + 1
    assert(case and linked and starts == 1, "Character test unexpectedly started another game")
    report("NATIVE_STARTED")
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    exitedAt = native.api_info().nowMs
end)
local baseFrame, baseGate, baseMenu = _IsaacLanFrame, native.net_gate, assert(_IsaacLanMenuRender)
function _IsaacLanFrame()
    renders = renders + 1
    local status = baseFrame()
    local info = native.api_info()
    local now = info.nowMs
    native.test_gamepad(0)
    if renders == 60 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if not ids and renders >= 300 and status.scene == 1 then
        ids = {
            normal = Isaac.GetPlayerTypeByName("LAN Catalog Probe", false),
            tainted = Isaac.GetPlayerTypeByName("LAN Catalog Probe", true),
            achievement = Isaac.GetPlayerTypeByName("LAN Achievement Probe", false),
            hidden = Isaac.GetPlayerTypeByName("LAN Hidden Probe", false),
        }
        local seen, values = {}, {}
        for _, kind in ipairs({ "normal", "tainted", "achievement", "hidden" }) do
            local id = ids[kind]
            assert(
                id >= 0 and not seen[id],
                "XML character registration or pairing failed: " .. kind
            )
            seen[id], values[#values + 1] = true, tostring(id)
        end
        checkCatalog()
        write("ids-" .. ordinal .. ".txt", table.concat(values, ","))
        report("REGISTERED ids=" .. table.concat(values, ","))
    end
    if not ids then
        return status
    end
    local registration = read("ids-0.txt")
    for slot = 0, 3 do
        local value = read("ids-" .. slot .. ".txt")
        if not value then
            return status
        end
        assert(value == registration, "Peers registered different native Mod character IDs")
    end
    local requested = tonumber(read("case.txt"))
    if not requested then
        return status
    end
    if requested > #cases then
        if not reported then
            reported = true
            Isaac.DebugString("LAN_NETWORK PASS native character catalog")
        end
        return status
    end
    if requested ~= current then
        if status.phase ~= 0 or status.scene ~= 1 or status.prepared then
            return status
        end
        current, case = requested, assert(cases[requested])
        linked, chosen, started, participated, done = false, false, false, false, false
        selectedAt, exitedAt, startAt = nil, nil, now + 2000
        stage, stageAt, otherRoom, snapshots, starts = "init", 0, nil, 0, 0
        menuOpened, pendingChoice, nextKeyAt, menuSteps = false, nil, 0, 0
        checkCatalog()
        report("BEGIN ordinal=" .. ordinal .. " players=" .. #case.kinds)
    end
    if ordinal >= #case.kinds then
        return status
    end
    if status.phase == 4 or (status.phase == 9 and status.error ~= "") then
        Isaac.DebugString("LAN_NETWORK FAILED " .. status.error)
        return status
    end
    if not linked and now >= startAt + ordinal * 900 and status.scene == 1 then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
    end
    if status.phase == 2 then
        if not menuOpened then
            menuOpened = true
            assert(not native.net_choose(ids.hidden, 0), "Hidden Mod choice was accepted")
            assert(not native.net_choose(22, 0), "Locked vanilla choice was accepted")
            _IsaacLanMenuOpen(true)
        end
        if not chosen and status["choice" .. ordinal] == expected(ordinal) then
            if not selectedAt then
                selectedAt = now
                local _, catalog = checkCatalog()
                local metadata = assert(catalog[tostring(expected(ordinal))])
                report(
                    "MENU_SELECTED id="
                        .. expected(ordinal)
                        .. " name="
                        .. metadata.name
                        .. " tainted="
                        .. tostring(metadata.tainted)
                        .. " steps="
                        .. menuSteps
                )
            elseif now - selectedAt >= 3000 then
                chosen = true
                assert(
                    native.net_choose(expected(ordinal), 1),
                    "Visible native Mod character cannot ready"
                )
            end
        end
        local ready = status.players == #case.kinds
        for slot = 0, #case.kinds - 1 do
            ready = ready and status["ready" .. slot] == 1
            if status["ready" .. slot] == 1 then
                assert(
                    status["choice" .. slot] == expected(slot),
                    "Lobby changed the selected native ID"
                )
            end
        end
        if host and ready and not started then
            started = true
            local values = { "YV039KQF", "0" }
            for slot = 0, 3 do
                values[#values + 1] = tostring(slot < #case.kinds and expected(slot) or 0)
            end
            _IsaacLanCommand("start", table.concat(values, ":"))
        end
    end
    if info.ready == 1 then
        participated = true
        assert(info.players == #case.kinds and info.slot == ordinal and info.challenge == 0)
    end
    if
        participated
        and exitedAt
        and not done
        and status.phase == 0
        and status.scene == 1
        and not status.prepared
        and now - exitedAt > 2000
    then
        assert(
            starts == 1 and (host or snapshots > 100),
            "Native character replica coverage is missing"
        )
        checkCatalog()
        done = true
        write("done-" .. current .. "-" .. ordinal .. ".txt", "done")
        report("PASS menu_cleanup=true snapshots=" .. snapshots)
    end
    if host and done then
        local complete = true
        for slot = 0, #case.kinds - 1 do
            complete = complete and read("done-" .. current .. "-" .. slot .. ".txt") ~= nil
        end
        if complete then
            write("case.txt", tostring(current + 1))
        end
    end
    if now - lastHeartbeat > 10000 then
        lastHeartbeat = now
        report(
            "HEARTBEAT phase=" .. status.phase .. " step=" .. stage .. " tick=" .. status.verified
        )
    end
    assert(done or now - startAt < 180000, "Native character case stalled")
    return status
end
function _IsaacLanMenuRender(
    available,
    visible,
    key,
    typed,
    mx,
    my,
    clicked,
    addresses,
    networkError
)
    local status = _IsaacLanStatus()
    if case and ordinal < #case.kinds and status.phase == 2 and menuOpened then
        visible, key, typed, mx, my, clicked = true, 0, "", -100, -100, false
        local choice, now = status["choice" .. ordinal], native.api_info().nowMs
        if pendingChoice and choice == pendingChoice then
            pendingChoice = nil
        end
        if
            not chosen
            and not pendingChoice
            and choice ~= expected(ordinal)
            and now >= nextKeyAt
        then
            local choices = checkCatalog()
            local index
            for i, id in ipairs(choices) do
                if id == choice then
                    index = i
                    break
                end
            end
            assert(index, "Lobby selected a character outside the native list")
            pendingChoice = choices[index % #choices + 1]
            nextKeyAt, key, menuSteps = now + 250, 39, menuSteps + 1
            assert(menuSteps <= #choices, "Native menu failed to reach the requested Mod character")
        end
    end
    return baseMenu(available, visible, key, typed, mx, my, clicked, addresses, networkError)
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        function()
            return string.rep("\0", 34)
        end,
        function(t, n, bytes)
            before(t, n, bytes)
            if stage == "init" then
                if t < 30 or native.rooms_connected() ~= (1 << #case.kinds) - 1 then
                    return
                end
                checkActors("NATIVE_TYPES")
                local level = Game():GetLevel()
                local first = level:GetCurrentRoomIndex()
                for i = 0, level:GetRooms().Size - 1 do
                    local room = level:GetRooms():Get(i)
                    if
                        room.SafeGridIndex ~= first
                        and room.Data.Type == RoomType.ROOM_DEFAULT
                        and room.Data.Shape == RoomShape.ROOMSHAPE_1x1
                    then
                        otherRoom = room.SafeGridIndex
                        break
                    end
                end
                assert(otherRoom, "No ordinary room for the split-room character check")
                mark("same-room", t)
            elseif stage == "same-room" and t - stageAt > 120 then
                checkActors("SAME_ROOM_TYPES")
                assert(native.rooms_move(#case.kinds - 1, otherRoom, 0, -1))
                mark("split-wait", t)
            elseif stage == "split-wait" then
                local positions = native.rooms_positions()
                if positions[tostring(#case.kinds - 1)].index == otherRoom then
                    actor(#case.kinds - 1, function()
                        for _, entity in ipairs(Isaac.GetRoomEntities()) do
                            if entity:IsActiveEnemy(false) then
                                entity:Remove()
                            end
                        end
                        Game():GetRoom():SetClear(true)
                    end)
                    checkActors("SPLIT_ROOM_TYPES")
                    mark("split-room", t)
                end
            elseif stage == "split-room" and t - stageAt > 150 then
                checkActors("FINAL_TYPES")
                mark("save-exit", t)
                assert(native.net_command(3))
            end
        end,
        collect,
        function(bytes, t, ack, betweenUpdates, stable)
            if restore(bytes, t, ack, betweenUpdates, stable) == false then
                return false
            end
            local value = _IsaacLanState.decode(bytes, stable)
            assert(#value[9] == #case.kinds, "Replica actor count differs from the selected roster")
            for _, entry in ipairs(value[9]) do
                local player = Isaac.GetPlayer(entry[1])
                assert(
                    entry[4][1] == expected(entry[2] - 1),
                    "Authority serialized another character ID"
                )
                assert(
                    player.ControllerIndex == entry[2] and player:GetPlayerType() == entry[4][1],
                    "Replica did not instantiate the selected Mod character"
                )
            end
            snapshots = snapshots + 1
            if snapshots == 100 then
                report("REPLICA_TYPES_VERIFIED tick=" .. t)
            end
            return true
        end,
        present,
        beginFloor
    )
end
