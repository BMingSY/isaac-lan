-- Native GUI navigation only; pause_menu_state is a read-only diagnostic copy.
local native, port = assert(_IsaacLan), _IsaacLanTest.port
assert(type(native.pause_menu_state) == "function", "Pause menu diagnostics are unavailable")
local file = assert(io.open("./lan-test-role.txt", "r"))
local ordinal = file:read("*l") == "host" and 0 or 1
file:close()
local host = ordinal == 0
local character = pauseFeedback and 0 or ordinal
local START, UP, DOWN, LEFT, RIGHT, CONFIRM, BACK = 16, 1, 2, 4, 8, 4096, 8192
local renders, starts, exits, snapshots = 0, 0, 0, 0
local current, localFrames, stepAt, matchedAt, acknowledged = 0, 0, 0, nil, false
local acted, nextPulse, pulseCount, pendingButtons = false, 0, 0, 0
local linked, chosen, started = false, false, false
local initialPrepared, resumePrepared, rejoined = false, false, false
local volumeBefore, volumeChanged, exitAt, step
local finished = false
local shortEdges, previousPause = 0, false
local owner = { Name = "Native pause menu acceptance" }
local eidSamples, eidReady, focusAt = 0, false, nil
local focusSetting
local function report(value)
    Isaac.DebugString(
        "LAN_NETWORK PAUSE_MENU step=" .. (step and step.name or "boot") .. " " .. value
    )
end
local function read(name)
    local f = io.open(pauseCoordination .. "/" .. name, "r")
    if not f then
        return nil
    end
    local value = f:read("*a")
    f:close()
    return value ~= "" and value or nil
end
local function write(name, value)
    local f = assert(io.open(pauseCoordination .. "/" .. name, "w"))
    f:write(value)
    f:close()
end
local function checkPlayer(player, slot)
    assert(
        player.ControllerIndex == slot + 1
            and player:GetPlayerType() == (pauseFeedback and 0 or slot),
        "Selected ordinary character changed"
    )
    local own, other = slot == 0 and 1 or 2, slot == 0 and 2 or 1
    assert(
        player:GetCollectibleNum(own, true) == 1 and not player:HasCollectible(other),
        "Per-player passive inventory changed"
    )
    assert(player:GetNumCoins() == 20, "Shared saved coins changed")
end
local function actors()
    for slot = 0, 1 do
        assert(native.rooms_with_player(slot, function()
            checkPlayer(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), slot)
        end))
    end
end
local function running(s)
    return s.phase == 3 and native.api_info().ready == 1
end
local function pausedRoot(hostSelection, guestSelection, pauseOwner)
    return function(s, m)
        return running(s)
            and Game():IsPaused()
            and s.pauseOwner == pauseOwner
            and m.page == 1
            and m.selection == (host and hostSelection or guestSelection)
            and m.controller == ordinal + 1
    end
end
local function hostUnchanged(s, m)
    assert(
        running(s) and Game():IsPaused() and s.pauseOwner == 1,
        "Guest subpage changed shared pause ownership"
    )
    if host then
        assert(
            m.page == 1 and m.selection == 2 and m.controller == 1,
            "Guest navigation moved the host pause menu"
        )
    end
end
local function guestPage(page)
    return function(s, m)
        return host and pausedRoot(2, 2, 1)(s, m)
            or not host
                and running(s)
                and Game():IsPaused()
                and m.page == page
                and m.controller == 2
    end
end
local function rootTarget(target)
    return function(_, m)
        if m.page ~= 1 or m.selection == target then
            return 0
        end
        return m.selection > target and UP or DOWN
    end
end
local function snapshotsReady()
    return host or snapshots >= 30
end
local steps = {
    {
        name = "new-run",
        lobby = true,
        check = function(s)
            return running(s) and read("first-prepared.txt") and snapshotsReady()
        end,
    },
    {
        name = "guest-start",
        -- The shared runner reads keyboard requests from the host log only.
        -- The request still sends Escape to the owned guest's window.
        actor = 0,
        action = function()
            Isaac.DebugString("LAN_NETWORK KEYBOARD_PAUSE_REQUEST 1 client")
            return true
        end,
        check = pausedRoot(2, 2, 1),
    },
    {
        name = "guest-up-items",
        actor = 1,
        button = UP,
        check = pausedRoot(2, 1, 1),
        guard = hostUnchanged,
    },
    {
        name = "guest-items",
        actor = 1,
        button = CONFIRM,
        check = guestPage(3),
        guard = hostUnchanged,
        hold = 1800,
    },
    {
        name = "guest-items-back",
        actor = 1,
        button = BACK,
        check = guestPage(1),
        guard = hostUnchanged,
    },
    {
        name = "guest-up-options",
        actor = 1,
        navigate = rootTarget(0),
        check = pausedRoot(2, 0, 1),
        guard = hostUnchanged,
    },
    {
        name = "guest-options",
        actor = 1,
        button = CONFIRM,
        check = guestPage(2),
        guard = hostUnchanged,
    },
    {
        name = "guest-music-row",
        actor = 1,
        navigate = function(_, m)
            return m.page == 2 and m.optionId ~= 3 and DOWN or 0
        end,
        check = function(s, m)
            return guestPage(2)(s, m) and (host or m.optionId == 3)
        end,
        guard = hostUnchanged,
    },
    {
        name = "guest-music-change",
        actor = 1,
        button = function()
            return volumeBefore < 0.9 and RIGHT or LEFT
        end,
        check = function(s, m)
            if not guestPage(2)(s, m) then
                return false
            end
            if not host then
                if math.abs(Options.MusicVolume - volumeBefore) < 0.01 then
                    return false
                end
                volumeChanged = Options.MusicVolume
            end
            return host or m.optionId == 3
        end,
        guard = hostUnchanged,
        hold = 1800,
    },
    {
        name = "guest-options-back",
        actor = 1,
        button = BACK,
        check = guestPage(1),
        guard = hostUnchanged,
    },
    {
        name = "guest-select-resume",
        actor = 1,
        navigate = rootTarget(2),
        check = pausedRoot(2, 2, 1),
        guard = hostUnchanged,
    },
    {
        name = "guest-root-resume",
        actor = 1,
        button = CONFIRM,
        check = function(s, m)
            return running(s) and not Game():IsPaused() and m.page == 0
        end,
    },
}
if pauseFeedback then
    table.insert(steps, 2, {
        name = "eid-stable",
        check = function(s)
            return running(s) and eidReady
        end,
    })
    table.insert(steps, 3, {
        name = "guest-focus-loss",
        actor = 0,
        action = function(_, now)
            focusAt = now
            Isaac.DebugString("LAN_NETWORK FOCUS_CYCLE_REQUEST 1")
            return true
        end,
        check = function(s, m)
            focusAt = focusAt or native.api_info().nowMs
            return running(s)
                and native.api_info().nowMs - focusAt > 10000
                and m.page == 0
                and not Game():IsPaused()
        end,
    })
    Isaac.AddPriorityCallback(owner, ModCallbacks.MC_POST_RENDER, 10000, function()
        if not step or step.name ~= "eid-stable" or eidReady then
            return
        end
        assert(EID and EID.player, "EID is unavailable in the ready LAN view")
        local entity = EID.lastDescriptionEntity
        if eidSamples == 0 then
            local pickups = Isaac.FindByType(5, 100, -1, false, false)
            for _, pickup in ipairs(pickups) do
                report(
                    string.format(
                        "EID_PROBE subtype=%d age=%d replica=%s first=%s described=%s distance=%.1f radius=%d hidden=%s refresh=%s ready=%s",
                        pickup.SubType,
                        pickup.FrameCount,
                        tostring(pickup:GetData().__isaac_lan_replica),
                        tostring(EID:getEntityData(pickup, "EID_DescribeOnFirstFrame")),
                        tostring(EID:hasDescription(pickup)),
                        pickup.Position:Distance(EID.player.Position),
                        #Isaac.FindInRadius(
                            EID.player.Position,
                            tonumber(EID.Config.MaxDistance) * 40,
                            EntityPartition.PICKUP
                        ),
                        tostring(EID.isHidden),
                        tostring(EID:RefreshThisFrame()),
                        tostring(native.api_info().ready)
                    )
                )
            end
        end
        local diagnostic = " displaying="
            .. tostring(EID.isDisplaying)
            .. " entity="
            .. tostring(entity and entity.SubType)
            .. " player="
            .. tostring(EID.player.ControllerIndex)
            .. " warnings="
            .. tostring(EID.Config.DisableStartOfRunWarnings)
        assert(
            EID.isDisplaying
                and entity
                and entity.Type == 5
                and entity.Variant == 100
                and entity.SubType == 13
                and EID.player.ControllerIndex == ordinal + 1,
            "EID lost the local pedestal description on render " .. eidSamples .. diagnostic
        )
        eidSamples = eidSamples + 1
        if eidSamples == 180 then
            eidReady = true
            report("EID_STABLE samples=180 entity_age=" .. entity.FrameCount)
            if not host then
                focusSetting = Options.PauseOnFocusLost
                Options.PauseOnFocusLost = true
            end
        end
    end)
end
for n = 1, pausePulses do
    steps[#steps + 1] = {
        name = "short-press-" .. n,
        actor = 1,
        button = START,
        short = true,
        check = n % 2 == 1 and pausedRoot(2, 2, 1) or function(s, m)
            return running(s) and not Game():IsPaused() and m.page == 0
        end,
    }
end
local tail = {
    { name = "guest-exit-pause", actor = 1, button = START, check = pausedRoot(2, 2, 1) },
    {
        name = "guest-select-exit",
        actor = 1,
        button = DOWN,
        check = pausedRoot(2, 3, 1),
        guard = hostUnchanged,
    },
    {
        name = "guest-root-exit",
        actor = 1,
        button = CONFIRM,
        check = function(s, m)
            if host then
                return running(s)
                    and native.rooms_connected() == 1
                    and starts == 1
                    and Game():IsPaused()
                    and m.page == 1
                    and s.pauseOwner == 0
            end
            return s.phase == 0 and s.scene == 1 and not s.prepared and exits == 1
        end,
    },
    {
        name = "host-resume-after-leave",
        actor = 0,
        button = CONFIRM,
        check = function(s, m)
            return host and running(s) and not Game():IsPaused() and m.page == 0
                or not host and s.phase == 0 and not s.prepared
        end,
    },
    {
        name = "guest-rejoin",
        actor = 1,
        action = function(s, now)
            if s.phase == 0 and s.scene == 1 and now - exitAt >= 1500 then
                _IsaacLanCommand("join", "127.0.0.1:" .. port)
                return true
            end
        end,
        check = function(s)
            return running(s)
                and native.rooms_connected() == 3
                and read("rejoined.txt")
                and starts == (host and 1 or 2)
        end,
    },
    { name = "host-exit-pause", actor = 0, button = START, check = pausedRoot(2, 2, 0) },
    { name = "host-select-exit", actor = 0, button = DOWN, check = pausedRoot(3, 2, 0) },
    {
        name = "host-root-exit",
        actor = 0,
        button = CONFIRM,
        check = function(s)
            return s.phase == 0 and s.scene == 1 and not s.prepared and exits == (host and 1 or 2)
        end,
    },
    {
        name = "ordinary-resume",
        lobby = true,
        resume = true,
        check = function(s)
            return running(s)
                and read("resume-prepared.txt")
                and snapshotsReady()
                and starts == (host and 2 or 3)
        end,
        hold = 1800,
    },
    {
        name = "final-save-exit",
        actor = 0,
        action = function()
            assert(native.net_command(3))
            return true
        end,
        check = function(s)
            return s.phase == 0 and s.scene == 1 and not s.prepared and exits == (host and 2 or 3)
        end,
    },
}
for _, value in ipairs(tail) do
    steps[#steps + 1] = value
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    starts, snapshots = starts + 1, 0
    assert(continued == (starts > 1), "Unexpected new/continued native run")
    report("NATIVE_STARTED count=" .. starts .. " continued=" .. tostring(continued))
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    exits, exitAt = exits + 1, native.api_info().nowMs
    report("NATIVE_EXIT count=" .. exits)
end)
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
function _IsaacLanFrame()
    renders = renders + 1
    if pauseFeedback and EID and EID.Config then
        EID.Config.DisableStartOfRunWarnings = true
    end
    native.test_gamepad(pendingButtons)
    pendingButtons = 0
    local s = baseFrame()
    local now = native.api_info().nowMs
    if renders == 60 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if renders == 300 then
        volumeBefore = Options.MusicVolume
        assert(type(volumeBefore) == "number", "MusicVolume read oracle is unavailable")
        write("boot-" .. ordinal .. ".txt", "ready")
        report("MUSIC_BASELINE value=" .. volumeBefore)
    end
    if not read("boot-0.txt") or not read("boot-1.txt") then
        return s
    end
    assert(
        not host or math.abs(Options.MusicVolume - volumeBefore) < 0.00001,
        "Guest Options changed host volume"
    )
    if volumeChanged then
        assert(
            math.abs(Options.MusicVolume - volumeChanged) < 0.00001,
            "Guest volume changed after leaving Options"
        )
    end
    local requested = tonumber(read("step.txt"))
    if not requested then
        return s
    end
    if requested > #steps then
        if not finished then
            finished = true
            assert(shortEdges == pausePulses, "Short pause edges were lost")
            report("SHORT_PRESSES edges=" .. shortEdges)
            Isaac.DebugString("LAN_NETWORK PASS native pause menu")
        end
        return s
    end
    if requested ~= current then
        if step and step.name == "guest-focus-loss" and focusSetting ~= nil then
            Options.PauseOnFocusLost = focusSetting
            focusSetting = nil
        end
        current, step = requested, assert(steps[requested])
        localFrames, stepAt, matchedAt, acknowledged = 0, now, nil, false
        acted, nextPulse, pulseCount = false, 0, 0
        linked, chosen, started = false, false, false
        report("BEGIN ms=" .. now)
    end
    localFrames = localFrames + 1
    if s.phase == 4 or (s.phase == 9 and s.error ~= "") then
        error("Native pause session failed: " .. s.error)
    end
    local m = s.prepared and native.pause_menu_state()
        or { page = 0, selection = -1, controller = -1, optionId = -1 }
    if s.prepared then
        local paused = Game():IsPaused()
        if paused ~= previousPause then
            if step.short then
                shortEdges = shortEdges + 1
            end
            previousPause = paused
            report("PAUSE_EDGE paused=" .. tostring(paused) .. " owner=" .. s.pauseOwner)
        end
    end
    if step.guard then
        step.guard(s, m)
    end
    if step.lobby then
        if not linked and now - stepAt > (host and 1000 or 1800) and s.scene == 1 then
            linked = true
            _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        end
        if s.phase == 2 then
            if not chosen then
                chosen = true
                assert(native.net_choose(character, 1), "Required ordinary character is locked")
            end
            if host and not started and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
                started = true
                _IsaacLanCommand(
                    step.resume and "resume" or "start",
                    step.resume and "" or "YV039KQF:0:0:" .. (pauseFeedback and 0 or 1) .. ":0:0"
                )
            end
        end
    elseif step.actor == ordinal and localFrames >= 6 then
        if step.navigate then
            local button = step.navigate(s, m)
            if button == 0 then
                acted = true
            elseif localFrames >= nextPulse then
                pendingButtons, nextPulse, pulseCount = button, localFrames + 20, pulseCount + 1
                assert(pulseCount <= 32, "Native menu navigation did not reach its target")
            end
        elseif not acted then
            if step.action then
                acted = step.action(s, now) == true
            else
                pendingButtons = type(step.button) == "function" and step.button() or step.button
                acted = true
            end
        end
    end
    if (step.actor ~= ordinal or acted) and step.check(s, m) then
        matchedAt = matchedAt or now
        if not acknowledged and now - matchedAt >= (step.hold or 700) then
            acknowledged = true
            local evidence = "page="
                .. m.page
                .. " selection="
                .. m.selection
                .. " controller="
                .. m.controller
                .. " option="
                .. m.optionId
                .. " volume="
                .. Options.MusicVolume
                .. " tick="
                .. s.verified
            report("CHECK " .. evidence)
            write("done-" .. current .. "-" .. ordinal .. ".txt", evidence)
        end
    else
        matchedAt = nil
    end
    if host and acknowledged and read("done-" .. current .. "-1.txt") then
        write("step.txt", tostring(current + 1))
    end
    assert(now - stepAt < 45000, "Native pause step stalled: " .. step.name)
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(
        capture,
        function(t, n, bytes)
            before(t, n, bytes)
            if t < 30 or native.rooms_connected() ~= 3 then
                return
            end
            if starts == 1 and not initialPrepared then
                for slot = 0, 1 do
                    assert(native.rooms_with_player(slot, function()
                        local player = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
                        for _, entity in ipairs(Isaac.GetRoomEntities()) do
                            if entity:IsActiveEnemy(false) then
                                entity:Remove()
                            end
                        end
                        Game():GetRoom():SetClear(true)
                        player:AddCollectible(slot == 0 and 1 or 2)
                        if slot == 0 then
                            player:AddCoins(20 - player:GetNumCoins())
                        end
                        if pauseFeedback then
                            player.Position = Vector(240 + slot * 120, 280)
                            if slot == 1 then
                                Isaac.Spawn(5, 100, 13, Vector(300, 280), Vector.Zero, nil)
                            end
                        end
                    end))
                end
                actors()
                initialPrepared = true
                write("first-prepared.txt", "ready")
                report(
                    "INVENTORY_FIXTURE P1=Isaac,SadOnion P2="
                        .. (pauseFeedback and "Isaac" or "Magdalene")
                        .. ",InnerEye sharedCoins=20"
                )
            elseif starts == 2 and not resumePrepared then
                actors()
                resumePrepared = true
                write("resume-prepared.txt", "ready")
                report("ORDINARY_RESUME_PRESERVED characters=true passives=true coins=20")
            end
        end,
        collect,
        function(bytes, t, ack, betweenUpdates, stable)
            if restore(bytes, t, ack, betweenUpdates, stable) == false then
                return false
            end
            snapshots = snapshots + 1
            if read("first-prepared.txt") then
                local value = _IsaacLanState.decode(bytes, stable)
                for _, entry in ipairs(value[9]) do
                    if t > 35 then
                        checkPlayer(Isaac.GetPlayer(entry[1]), entry[2] - 1)
                    end
                end
                if starts == 2 and not rejoined and t > 35 then
                    rejoined = true
                    assert(native.api_info().slot == 1, "Reconnect lost the guest identity")
                    write("rejoined.txt", "ready")
                    report("REJOIN_PRESERVED slot=1 character=" .. character .. " items=true")
                end
            end
            return true
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
