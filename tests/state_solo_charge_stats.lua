-- One pair covers ordinary sandbox Mod loading, solo, LAN and solo continue.
local native, api = assert(_IsaacLan), assert(IsaacLAN)
assert(debug == nil and native.debug.getinfo, "Ordinary sandbox was not exercised")
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local function report(value)
    Isaac.DebugString("LAN_NETWORK " .. value)
end
local owner = { Name = "Solo charge and Stats integration regression" }
local lan = api:RegisterMod(owner, { id = "test.solo-charge-stats", integrationVersion = 1 })
local phase, renders, soloSeed = "start", 0, nil
local linked, chosen, ended = false, false, false
local originalWarning
local soloDraws, localDraws, chargeSamples, shots = 0, 0, 0, 0
local registry = _IsaacLanModules["compat/registry"]
local observe = registry.observeRequire
function registry.observeRequire(source, name, value)
    observe(source, name, value)
    if name == "services.renderer.Renderer" and value.Renderer then
        local prototype = value.Renderer.prototype
        local original = prototype.render
        function prototype.render(self, players)
            if native.api_info().active == 1 and lan:IsReady() then
                assert(#players == 1, "Stats rendered multiple participants")
                assert(players[1].index == 0, "Stats used the remote player's HUD layout")
                assert(
                    lan:GetOwnerId(players[1].entityPlayer) == (host and 1 or 2),
                    "Stats rendered a teammate's multiplier"
                )
                localDraws = localDraws + 1
            elseif (phase == "save" or phase == "restored") and Game():GetFrameCount() > 30 then
                assert(#players == 1, "Solo Stats player count=" .. #players)
                soloDraws = soloDraws + 1
            end
            return original(self, players)
        end
    end
end
local function modsReady()
    local active = 0
    for _, status in ipairs(api:GetCompatibilityStatus()) do
        assert(
            status.state == "active",
            "Mod adaptation failed: " .. status.id .. " " .. status.state
        )
        active = active + 1
    end
    assert(active == 3 and EID and gt, "Requested Mods did not load in the ordinary sandbox")
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    if phase == "start" then
        modsReady()
        assert(Game():GetNumPlayers() == 1 and not continued)
        soloSeed = Game():GetSeeds():GetStartSeedString()
        phase, renders = "save", 0
        report("GAME_STARTED solo sandbox fixture")
    elseif phase == "continue" then
        assert(continued and Game():GetNumPlayers() == 1)
        assert(Game():GetSeeds():GetStartSeedString() == soloSeed)
        modsReady()
        phase, renders, soloDraws = "restored", 0, 0
        report("SOLO_RESTORED seed=" .. soloSeed)
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    if phase == "saving" then
        phase, renders = "file", 0
    elseif phase == "network-exit" then
        phase, renders = "close", 0
    end
end)
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    if EID and EID.Config and phase ~= "passed" then
        if originalWarning == nil then
            originalWarning = EID.Config.DisableStartOfRunWarnings
        end
        EID.Config.DisableStartOfRunWarnings = true
    end
    renders = renders + 1
    local status = frame()
    if phase ~= "network" then
        if phase == "save" and renders >= 120 and soloDraws > 5 then
            phase = "saving"
            report("SOLO_READY")
        elseif phase == "file" and renders == 60 then
            phase, renders = "network", 0
            report("SOLO_FILE_READY")
        elseif phase == "close" and renders >= 60 then
            _IsaacLanCommand("close", "")
            phase = "continue"
            report("SOLO_NETWORK_EXIT")
        elseif phase == "restored" and renders >= 120 and soloDraws > 10 then
            phase = "passed"
            EID.Config.DisableStartOfRunWarnings = originalWarning
            report("PASS solo sandbox charged transfers and Stats owner")
        end
        return status
    end
    if not linked and renders >= (host and 120 or 180) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
    end
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", (host and "7" or "0") .. ":1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "LBCD0G4M:0:7:0:7:7")
    end
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    native.test_gamepad(not host and status.verified >= 100 and status.verified < 800 and 8192 or 0)
    if status.verified >= 920 and not ended then
        modsReady()
        assert(localDraws > 20, "Stats local provider rendering was not checked")
        if host then
            assert(chargeSamples > 400 and shots > 0, "Charge hold/release did not run")
            report("CHARGE_TRANSFER samples=" .. chargeSamples .. " shots=" .. shots)
        end
        report("STATS_LOCAL_DRAWS " .. localDraws)
        phase, renders, ended = "network-exit", 0, true
        if host then
            assert(native.net_command(3))
        end
    end
    return status
end
local function charge(bytes)
    local cursor = 11
    for i = 1, 5 do
        local present
        present, cursor = string.unpack(">B", bytes, cursor)
        if present == 1 then
            local kind, delay, maximum, current
            kind, delay, maximum, current, cursor = string.unpack(">I4fff", bytes, cursor)
            if i == 2 then
                assert(kind == 2, "Brimstone weapon missing")
                return current
            end
        end
    end
    error("Brimstone charge not captured")
end
local origin, other, baseline
local captureInput = native.input_capture
native.input_capture = function(controller)
    local bytes = captureInput(controller)
    local t = native.api_info().tick
    if not host and t >= 230 and t <= 260 then
        local held = { string.unpack(">I2I2I2I2", bytes, 9) }
        report("CHARGE_CAPTURE tick=" .. t .. " fire=" .. table.concat(held, ",", 1, 4))
    end
    return bytes
end
local function clear()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) then
            entity:Remove()
        end
    end
    Game():GetRoom():SetClear(true)
end
local function move(slot, index)
    assert(native.rooms_move(slot, index, 0, -1))
    assert(native.rooms_with_player(slot, clear))
    report("CHARGED_ROOM_TRANSFER slot=" .. slot .. " room=" .. index)
end
local gate = native.net_gate
native.net_gate = function(capture, apply, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        apply(t, n, bytes)
        if host and t >= 230 and t <= 260 then
            local held = { string.unpack(">I2I2I2I2", bytes, 43) }
            report("CHARGE_APPLY tick=" .. t .. " fire=" .. table.concat(held, ",", 1, 4))
        end
        if t == 30 then
            origin = Game():GetLevel():GetCurrentRoomIndex()
            for i = 0, Game():GetLevel():GetRooms().Size - 1 do
                local room = Game():GetLevel():GetRooms():Get(i)
                if room.Data.Type == RoomType.ROOM_DEFAULT and room.SafeGridIndex ~= origin then
                    other = room.SafeGridIndex
                    break
                end
            end
            assert(other)
            local p = Isaac.GetPlayer(1)
            p:AddCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
            p:SetMinDamageCooldown(10000)
            Isaac.GetPlayer(0):SetMinDamageCooldown(10000)
            assert(native.rooms_with_player(1, clear))
        elseif t == 240 then
            move(1, other)
        elseif t == 400 then
            move(1, origin)
        elseif t == 520 then
            move(0, other)
        elseif t == 640 then
            move(1, other)
        elseif t == 720 then
            move(1, origin)
        end
    end, function(slot, t)
        if host and slot == 1 and t >= 225 then
            local current = charge(assert(native.actor_pose(Isaac.GetPlayer(1):GetSprite())))
            if t == 225 then
                assert(current > 0)
                baseline = current
                report("CHARGE_BASELINE " .. current)
            elseif t >= 240 and t < 790 then
                assert(
                    baseline and current >= baseline - 0.0001,
                    "Held Brimstone discharged on room transfer: tick="
                        .. t
                        .. " charge="
                        .. current
                )
                chargeSamples = chargeSamples + 1
            end
            if t >= 810 and t <= 850 then
                assert(native.rooms_with_player(1, function()
                    shots = shots + #Isaac.FindByType(7, -1, -1, false, false)
                end))
            end
        end
        return collect(slot, t)
    end, restore, present, beginFloor)
end
