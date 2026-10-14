-- Last factory in special_suite_driver.lua; append `return function() return finished end`.
-- The runner handles these requests using real native-menu keys only:
--   LAN_NETWORK SOLO_GUI_REQUEST action=new-run|save-exit|continue role=host|client sequence=N
-- On SOLO_FILE_READY it hashes the native gamestate and writes
--   <releaseCoordination>/solo-file-<role>.ack
-- On SOLO_NETWORK_EXIT it verifies that hash is unchanged and writes
--   <releaseCoordination>/solo-network-<role>.ack
-- No menu/Manager fields, console starts, Stats/EID dependencies or save-file writes.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local role = host and "host" or "client"
local coordination =
    assert(_IsaacLanTest.releaseCoordination, "Solo fixture needs runner ACK directory")
assert(io and io.open, "Solo ACKs require the suite's LuaDebug sandbox")
local frame, gate = _IsaacLanFrame, native.net_gate
local menuRender = assert(_IsaacLanMenuRender)
local owner = { Name = "Release native solo Continue observers" }
local finished, renders, phaseAt = false, 0, 0
local phase = "initial-menu"
local uiAction, uiVisible, lobbyRequested
local solo, restored, linked, chosen, started, lanPrepared, lanChecked =
    nil, false, false, false, false, false, false
local expectedItems =
    { CollectibleType.COLLECTIBLE_SAD_ONION, CollectibleType.COLLECTIBLE_PENTAGRAM }
local function report(value)
    Isaac.DebugString("LAN_NETWORK " .. value .. " role=" .. role)
end
local function mark(value)
    phase, renders, phaseAt = value, 0, native.api_info().nowMs
    report("RELEASE_SOLO STEP " .. value)
end
local function request(action, sequence)
    report("SOLO_GUI_REQUEST action=" .. action .. " sequence=" .. sequence)
end
local function ack(kind, peer)
    local file = io.open(coordination .. "/solo-" .. kind .. "-" .. (peer or role) .. ".ack", "r")
    if not file then
        return false
    end
    file:close()
    return true
end
local function actor(slot, call)
    assert(native.rooms_with_player(slot, function()
        call(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
_IsaacLanMenuRender = function(...)
    local visible = menuRender(...)
    local action = phase == "await-new-run" and "new-run"
        or phase == "await-continue" and "continue"
        or phase == "lan" and "show-lobby"
    if action and (action ~= uiAction or visible ~= uiVisible) then
        uiAction, uiVisible = action, visible
        report(
            "SOLO_UI_STATE action="
                .. action
                .. " visible="
                .. tostring(visible)
                .. " ms="
                .. native.api_info().nowMs
        )
    end
    return visible
end
local function clear()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) or entity.Type == EntityType.ENTITY_PICKUP then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function inventory(player)
    local items = {}
    for i, item in ipairs(expectedItems) do
        items[i] = player:GetCollectibleNum(item, true)
    end
    return {
        seed = Game():GetSeeds():GetStartSeedString(),
        character = player:GetPlayerType(),
        coins = player:GetNumCoins(),
        keys = player:GetNumKeys(),
        bombs = player:GetNumBombs(),
        maxHearts = player:GetMaxHearts(),
        hearts = player:GetHearts(),
        items = items,
    }
end
local function checkSolo()
    assert(
        Game():GetNumPlayers() == 1 and native.api_info().active == 0,
        "Continue retained a LAN actor/session"
    )
    local player = Isaac.GetPlayer(0)
    local actual = inventory(player)
    for _, key in ipairs({ "seed", "character", "coins", "keys", "bombs", "maxHearts", "hearts" }) do
        assert(
            actual[key] == solo[key],
            "Native Continue changed solo " .. key .. ": " .. tostring(actual[key])
        )
    end
    for i, item in ipairs(expectedItems) do
        assert(
            actual.items[i] == solo.items[i],
            "Native Continue changed solo collectible " .. item
        )
    end
    assert(
        player.Visible and not player:IsDead() and not player:IsCoopGhost(),
        "Continued solo actor is not visible/alive"
    )
    assert(player:AreControlsEnabled(), "Native solo controls remain disabled")
end
local function soloUsable()
    if Game():GetNumPlayers() ~= 1 or native.api_info().active ~= 0 then
        return false
    end
    local player = Isaac.GetPlayer(0)
    return player:AreControlsEnabled()
        and player:IsExtraAnimationFinished()
        and not Game():IsPaused()
end
local startedCallback = function(_, continued)
    if phase == "await-new-run" then
        assert(
            not continued and Game():GetNumPlayers() == 1,
            "Native New Run did not create a fresh single-player run"
        )
        assert(native.api_info().active == 0, "Native New Run entered a LAN session")
        mark("prepare-solo")
        report("RELEASE_SOLO NEW_RUN_STARTED continued=false")
    elseif phase == "await-continue" then
        assert(
            continued and Game():GetNumPlayers() == 1,
            "Native GUI Continue did not load a single-player save"
        )
        assert(
            Game():GetSeeds():GetStartSeedString() == solo.seed,
            "Continue loaded the intervening LAN seed"
        )
        restored = true
        mark("continued")
        report("RELEASE_SOLO CONTINUED continued=true seed=" .. solo.seed)
    elseif phase == "lan" then
        assert(not continued, "Intervening LAN unexpectedly resumed a run")
        report("RELEASE_SOLO LAN_STARTED")
    elseif not finished then
        error("Unexpected game-start callback in solo phase " .. phase)
    end
end
local exitCallback = function(_, shouldSave)
    if phase == "await-save-1" then
        assert(shouldSave, "First native Exit Game did not request a save")
        mark("first-saved-menu")
        report("RELEASE_SOLO SAVE_EXIT_CALLBACK sequence=1 should_save=true")
    elseif phase == "await-save-2" then
        assert(shouldSave, "Final native Exit Game did not request a save")
        mark("final-saved-menu")
        report("RELEASE_SOLO SAVE_EXIT_CALLBACK sequence=2 should_save=true")
    elseif phase == "lan" or phase == "lan-exit" then
        assert(lanChecked, "Intervening LAN exited before its independent inventory check")
        mark("network-saved-menu")
        report("RELEASE_SOLO LAN_EXIT_CALLBACK")
    elseif not finished then
        error("Unexpected game-exit callback in solo phase " .. phase)
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, startedCallback)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, exitCallback)
local function checkLan()
    assert(
        Game():GetSeeds():GetStartSeedString() ~= solo.seed,
        "Intervening LAN reused the solo seed"
    )
    assert(native.rooms_connected() == 3, "Intervening LAN lost a participant")
    for slot = 0, 1 do
        actor(slot, function(player)
            assert(
                player:GetPlayerType() == PlayerType.PLAYER_ISAAC
                    and player.ControllerIndex == slot + 1
            )
            assert(
                player:GetNumCoins() == 6 and player:GetNumKeys() == 1 and player:GetNumBombs() == 2,
                "Intervening LAN inventory was not independent"
            )
            assert(
                player:GetCollectibleNum(slot + 1, true) == 1
                    and not player:HasCollectible(CollectibleType.COLLECTIBLE_PENTAGRAM),
                "LAN inherited solo collectibles"
            )
            assert(player.Visible and player:HasEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK))
        end)
    end
    lanChecked = true
end
function _IsaacLanFrame()
    renders = renders + 1
    local status = frame()
    assert(status.phase ~= 4 and not (status.phase == 9 and status.error ~= ""), status.error)
    -- The runner injects native keyboard/menu input; the test gamepad is idle.
    native.test_gamepad(0)
    if finished then
        return status
    end
    if phaseAt == 0 then
        phaseAt = native.api_info().nowMs
    end
    if not finished then
        assert(native.api_info().nowMs - phaseAt < 180000, "Solo fixture stalled in " .. phase)
    end
    local menu = status.phase == 0 and status.scene == 1 and not status.prepared
    if phase == "initial-menu" and menu and renders >= 30 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
        _IsaacLanCommand("close", "")
        mark("await-new-run")
        request("new-run", 0)
    elseif phase == "prepare-solo" and renders >= 90 and soloUsable() then
        assert(Game():GetNumPlayers() == 1)
        local player = Isaac.GetPlayer(0)
        clear()
        for _, item in ipairs(expectedItems) do
            player:AddCollectible(item)
        end
        player:AddCoins(37 - player:GetNumCoins())
        player:AddKeys(4 - player:GetNumKeys())
        player:AddBombs(3 - player:GetNumBombs())
        player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
        player:SetMinDamageCooldown(10000)
        player.Position, player.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
        solo = inventory(player)
        mark("solo-ready")
        report(
            "RELEASE_SOLO INVENTORY seed="
                .. solo.seed
                .. " character="
                .. solo.character
                .. " coins=37 keys=4 bombs=3"
        )
    elseif phase == "solo-ready" and renders >= 90 and soloUsable() then
        checkSolo()
        mark("await-save-1")
        request("save-exit", 1)
    elseif phase == "first-saved-menu" and menu and renders >= 60 then
        mark("await-file-ack")
        report("SOLO_FILE_READY seed=" .. solo.seed)
    elseif phase == "await-file-ack" and ack("file") then
        mark("lan")
        report("RELEASE_SOLO FILE_ACK")
    elseif phase == "lan" then
        if not linked and renders >= (host and 120 or 180) then
            linked = true
            _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        end
        if status.phase == 2 then
            if not chosen then
                chosen = true
                assert(native.net_choose(0, 1))
            end
            if status.players == 2 and not lobbyRequested then
                lobbyRequested = true
                request("show-lobby", 0)
            end
            if
                host
                and not started
                and status.players == 2
                and status.ready0 == 1
                and status.ready1 == 1
                and ack("lobby")
                and ack("lobby", host and "client" or "host")
            then
                started = true
                -- Guaranteed distinct from even a coincidentally matching random New Run.
                local lanSeed = (solo.seed == "YV03 9KQF" or solo.seed == "YV039KQF") and "LBCD0G4M"
                    or "YV039KQF"
                _IsaacLanCommand("start", lanSeed .. ":0:0:0:0:0")
            end
        end
        if host and status.phase == 3 and status.verified >= 300 then
            assert(lanChecked)
            mark("lan-exit")
            assert(native.net_command(3))
        end
    elseif phase == "network-saved-menu" and menu and renders >= 60 then
        _IsaacLanCommand("close", "")
        mark("await-network-ack")
        report("SOLO_NETWORK_EXIT seed=" .. solo.seed)
    elseif phase == "await-network-ack" and ack("network") then
        mark("await-continue")
        request("continue", 0)
    elseif phase == "continued" and renders >= 120 and soloUsable() then
        assert(restored)
        checkSolo()
        report(
            "RELEASE_SOLO CONTINUE_PASS continued=true seed="
                .. solo.seed
                .. " coins=37 keys=4 bombs=3 independent_inventory=true"
        )
        mark("await-save-2")
        request("save-exit", 2)
    elseif phase == "final-saved-menu" and menu and renders >= 60 then
        Isaac.RemoveCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, startedCallback)
        Isaac.RemoveCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, exitCallback)
        _IsaacLanMenuRender = menuRender
        finished = true
        report(
            "RELEASE_SOLO PASS native_new_run=true native_save_exit=true native_continue=true lan_between=true"
        )
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, bytes)
            before(t, n, bytes)
            if phase ~= "lan" then
                return
            end
            if not lanPrepared and t >= 30 and native.rooms_ready() then
                for slot = 0, 1 do
                    actor(slot, function(player)
                        clear()
                        player:AddCollectible(slot + 1)
                        player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                        player:SetMinDamageCooldown(10000)
                        if slot == 0 then
                            player:AddCoins(6 - player:GetNumCoins())
                            player:AddKeys(1 - player:GetNumKeys())
                            player:AddBombs(2 - player:GetNumBombs())
                        end
                    end)
                end
                lanPrepared = true
            end
            if not lanChecked and t >= 150 and native.rooms_ready() then
                checkLan()
                report("RELEASE_SOLO LAN_INVENTORY_PASS coins=6 keys=1 bombs=2")
            end
        end,
        collect,
        function(bytes, t, ackSequence)
            if restore(bytes, t, ackSequence) == false then
                return false
            end
            if phase == "lan" and not lanChecked and t >= 150 and native.rooms_ready() then
                checkLan()
                report("RELEASE_SOLO LAN_INVENTORY_PASS coins=6 keys=1 bombs=2")
            end
            return true
        end,
        present,
        beginFloor
    )
end
