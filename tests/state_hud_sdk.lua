-- One local settings change in each real lobby, then independent HUD overrides
-- on both machines during a single run. Native frame capture records every phase.
local host, port = _IsaacLanTest.host, tostring(_IsaacLanTest.port)
local frame, menu, gate = _IsaacLanFrame, _IsaacLanMenuRender, _IsaacLan.net_gate
local mod = { Name = "HUD fixture" }
local handle = IsaacLAN:Attach(mod, "fixture.hud")
local phase, hits, joined, chosen, finished = -1, {}, false, false, false
local lobbyStep, lobbyChanged, frames = 0, false, 0
local function report(message)
    Isaac.DebugString("LAN_NETWORK " .. message)
end
handle:RegisterMenuSetting({
    id = "display",
    name = "HUD fixture",
    choices = { "Native", "Custom" },
    onChange = function(index)
        assert(index == 2)
        lobbyChanged = true
        report("HUD_SDK lobby change")
    end,
})
local keys = { 38, 38, 13, 39, 27 }
function _IsaacLanMenuRender(available, visible, key, ...)
    if _IsaacLanStatus().phase == _IsaacLan.net_phases().lobby and lobbyStep < #keys then
        if lobbyStep == 0 then
            _IsaacLanMenuOpen(true)
        end
        lobbyStep = lobbyStep + 1
        return menu(true, true, keys[lobbyStep], ...)
    end
    return menu(available, visible, key, ...)
end
local localId = host and 1 or 2
local remoteId = host and 2 or 1
local changes, twins = {}, {}
handle:OnHUDHearts("all", function(panel)
    if phase < 0 then
        return
    end
    assert(panel.isLocal == (panel.ownerId == localId))
    if phase < 4 then
        assert(panel.playerId == "p" .. panel.ownerId .. ":1")
    elseif
        panel.playerType == PlayerType.PLAYER_JACOB
        or panel.playerType == PlayerType.PLAYER_ESAU
    then
        assert(panel.ownerId == 2)
        if not twins[panel.playerId] then
            report(string.format("HUD_SDK twin=%s x=%.1f y=%.1f", panel.playerId, panel.x, panel.y))
        end
        twins[panel.playerId] = { x = panel.x, y = panel.y }
    end
    assert(panel.health and panel.health.red > 0 and panel.x > 0 and panel.y > 0)
    local bodies = Game():GetNumPlayers()
    assert(
        (bodies == 1 or (not host and phase >= 4 and bodies == 2))
            and Isaac.GetPlayer(0).ControllerIndex == localId
    )
    hits[phase][panel.ownerId] = true
    if (phase == 2 and (host or not panel.isLocal)) or (phase == 4 and panel.ownerId == 2) then
        Isaac.RenderText("HP " .. panel.health.red, panel.x, panel.y, 0, 1, 1, 1)
        return true
    end
end)
local function setPhase(nextPhase)
    for _, release in ipairs(changes) do
        release()
    end
    changes, phase = {}, nextPhase
    hits[phase] = {}
    if phase == 1 then
        if host then
            changes[1] = handle:HideHUD("hearts", "teammates")
        else
            changes[1] = handle:HideHUD("activeItem", "local")
            changes[2] = handle:HideHUD("pocketItems", "local")
        end
    end
    report("HUD_SDK phase=" .. phase)
end
function _IsaacLanFrame()
    frames = frames + 1
    if not joined and frames >= (host and 300 or 480) then
        joined = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
    if status.phase == 2 and lobbyStep == #keys and not chosen then
        assert(lobbyChanged, "Local lobby setting was not selected")
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
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    local tick = status.verified
    if status.phase == 3 and status.prepared and tick >= 50 and not finished then
        local nextPhase = math.min(4, (tick - 50) // 100)
        if phase ~= nextPhase then
            if phase >= 0 then
                assert(hits[phase][localId], "Local heart panel missing " .. phase)
                assert(
                    (hits[phase][remoteId] == true) == (not host or phase ~= 1),
                    "Teammate heart visibility incorrect " .. phase
                )
            end
            setPhase(nextPhase)
            if phase == 0 then
                report("VISUAL_READY")
            end
        end
        if tick >= 570 then
            assert(hits[3][localId] and hits[3][remoteId], "Native panel did not return")
            local bodies = {}
            handle:WithLocalView(function()
                for _, body in ipairs(handle:GetHUDPlayers()) do
                    bodies[body.playerId] = body
                end
                assert(
                    Game():GetNumPlayers() == (host and 1 or 2),
                    "Team HUD query leaked its view"
                )
            end)
            assert(bodies["p2:1"].playerType == PlayerType.PLAYER_JACOB)
            assert(bodies["p2:2"].playerType == PlayerType.PLAYER_ESAU and bodies["p2:2"].health)
            local first, second = twins["p2:1"], twins["p2:2"]
            assert(first and bodies["p1:1"].ownerId == 1)
            -- Repentance draws only the main heart panel for a remote pair.
            if not host or _IsaacLan.presentation_assets.native_lobby then
                assert(
                    second and (first.x ~= second.x or first.y ~= second.y),
                    "Twin heart anchors overlap"
                )
            end
            Isaac.RunCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, mod)
            assert(not handle:IsAttached(), "Unloading the Mod kept its display registrations")
            assert(
                IsaacLAN:Attach(mod, "fixture.hud"):IsAttached(),
                "Could not reattach the display Mod"
            )
            finished = true
            report("PASS local HUD SDK")
        end
    end
    return status
end
_IsaacLan.net_gate = function(capture, before, ...)
    return gate(function()
        return _IsaacLanTestInput.neutral
    end, function(t, n, input)
        before(t, n, input)
        if t == 470 then
            assert(_IsaacLan.rooms_with_player(1, function()
                Isaac.GetPlayer(assert(_IsaacLan.rooms_heads()["1"]))
                    :ChangePlayerType(PlayerType.PLAYER_JACOB)
            end))
        elseif t == 25 then
            for i = 0, Game():GetNumPlayers() - 1 do
                local player = Isaac.GetPlayer(i)
                player:AddCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL, 3, false)
                player:SetCard(0, Card.CARD_FOOL)
            end
        end
    end, ...)
end
