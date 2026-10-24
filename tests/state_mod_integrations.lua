-- Actual supported Mods are copied unchanged by --mod / --client-mod.
local native, api = assert(_IsaacLan), assert(IsaacLAN)
local testInput = assert(_IsaacLanTestInput)
local modules = _IsaacLanModules
local host, port
if _IsaacLanTest then
    host, port = _IsaacLanTest.host, _IsaacLanTest.port
else
    local f = assert(io.open("./lan-test-role.txt", "r"))
    host = f:read("*l") == "host"
    f:close()
    f = assert(io.open("./lan-test-menu-port.txt", "r"))
    port = f:read("*l")
    f:close()
end
local character = _IsaacLanTest and _IsaacLanTest.integrationDual and PlayerType.PLAYER_JACOB or 0
local owner = { Name = "Isolated third-party integration contract" }
function owner:AddCallback(id, fn)
    Isaac.AddCallback(self, id, fn)
end
function owner:RemoveCallback(id, fn)
    Isaac.RemoveCallback(self, id, fn)
end
local lan = api:Attach(owner, "test.integration.views")
local function report(message)
    Isaac.DebugString("LAN_NETWORK " .. message)
end
local frame, count, linked, chosen, finished = _IsaacLanFrame, 0, false, false, false
local travel, result, requestCount, replayed = false, nil, 0, false
local playerService, checks = nil, 0
local sdkRequest, sdkResult, sdkExecutions
sdkExecutions = 0
local bodyAction = lan:Action("selected-body", {
    execute = function(context)
        local role = character == PlayerType.PLAYER_JACOB and 2 or 1
        assert(context.ownerId == 2 and context.playerId == "p2:" .. role)
        assert(lan:GetPlayerId(context.player) == context.playerId)
        sdkExecutions = sdkExecutions + 1
        return {
            status = "applied",
            code = "selected_body",
            data = { playerId = context.playerId, executions = sdkExecutions },
        }
    end,
})
local codec = modules["api/codec"]
local send, receive = native.api_send, native.api_receive
native.api_send = function(slot, bytes)
    local message = codec.decode(bytes)
    if
        not host
        and message.kind == "request"
        and message.key == "isaac-lan.compat.goodtrip/travel"
    then
        requestCount = requestCount + 1
        local sent = send(slot, bytes)
        assert(send(slot, bytes), "Duplicate request transport failed")
        replayed = true
        return sent
    end
    return send(slot, bytes)
end
native.api_receive = function()
    local sender, bytes = receive()
    if bytes and not host then
        local message = codec.decode(bytes)
        if message.kind == "result" and message.code == "arrived" then
            result = message
            report("ACTION_RESULT " .. message.status .. " " .. message.code)
        end
    end
    return sender, bytes
end
function _IsaacLanFrame()
    count = count + 1
    if not linked and count >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", character .. ":1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand(
            "start",
            string.format("LBCD0G4M:0:%d:%d:%d:%d", character, character, character, character)
        )
    end
    if status.phase == 4 then
        report("FAILED " .. status.error)
    end
    if status.prepared and status.verified >= 160 and not host and not travel then
        assert(gt, "Guest GoodTrip fixture missing")
        travel = true
        gt:teleport_to_grid_index(71)
    end
    if status.prepared and status.verified >= 270 and not host and not sdkRequest then
        local players = lan:GetLocalPlayers()
        sdkRequest = bodyAction:Request(nil, {
            player = players[#players],
            onResult = function(value)
                sdkResult = value
                report("SDK_RESULT " .. value.status .. " " .. value.code)
            end,
        })
    end
    if status.prepared and status.verified >= 350 and not finished then
        assert(checks >= 30, "Local render checks did not run or were disabled by an error")
        if not host then
            assert(
                travel and replayed and requestCount == 1 and result and result.status == "applied",
                "GoodTrip action did not complete exactly once"
            )
            assert(
                sdkResult and sdkResult.status == "applied" and sdkResult.data.executions == 1,
                "API 2 selected-body result missing"
            )
            assert(
                sdkResult.data.playerId
                    == "p2:" .. (character == PlayerType.PLAYER_JACOB and 2 or 1)
            )
        else
            assert(sdkExecutions == 1, "API 2 action did not execute exactly once")
        end
        local positions = native.rooms_positions()
        assert(
            positions["0"].index == 84 and positions["1"].index == 71,
            "Authoritative GoodTrip arrival wrong"
        )
        finished = true
        report("PASS third-party integration views and actions")
    end
    return status
end
local gate = native.net_gate
native.net_gate = function(capture, apply, collect, restore, present, beginFloor)
    local function neutral()
        return testInput.neutral
    end
    return gate(neutral, function(t, n, bytes)
        apply(t, n, bytes)
        if t == 20 then
            assert(native.rooms_move(1, 71, 0, -1))
        end
        if t == 50 then
            assert(native.rooms_with_player(1, function()
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    if entity:IsActiveEnemy(false) then
                        entity:Kill()
                    end
                end
                Game():GetRoom():SetClear(true)
            end))
        end
        if t == 70 then
            local heads = native.rooms_heads()
            Isaac.GetPlayer(heads["0"]):AddCollectible(CollectibleType.COLLECTIBLE_SOY_MILK)
            Isaac.GetPlayer(heads["1"]):AddCollectible(CollectibleType.COLLECTIBLE_POLYPHEMUS)
            assert(native.rooms_move(1, 84, 0, -1))
        end
        -- A wrapped require must still install the Stats+ integration before
        -- its stat probes see a native companion. Transfer Found Soul between
        -- peers, including the guest's arrival in an occupied room.
        if t == 60 or t == 80 or t == 90 or t == 100 then
            local slot = t <= 80 and 1 or 0
            assert(native.rooms_with_player(slot, function()
                local player = Isaac.GetPlayer(native.rooms_heads()[tostring(slot)])
                if t == 60 or t == 90 then
                    player:AddTrinket(TrinketType.TRINKET_FOUND_SOUL, false)
                else
                    assert(player:TryRemoveTrinket(TrinketType.TRINKET_FOUND_SOUL))
                end
            end))
        end
        if t == 110 then
            for slot = 0, 1 do
                assert(native.rooms_with_player(slot, function()
                    local player = Isaac.GetPlayer(native.rooms_heads()[tostring(slot)])
                    Isaac.Spawn(
                        5,
                        100,
                        slot == 0 and 1 or 2,
                        player.Position + Vector(30, 0),
                        Vector.Zero,
                        nil
                    )
                end))
            end
        end
        if t == 340 then
            assert(native.rooms_positions()["1"].index == 71, "Host did not execute guest request")
        end
    end, collect, restore, present, beginFloor)
end
lan:OnLocalRender(function()
    if not lan:IsReady() or lan:View().tick < 120 then
        return
    end
    local localPlayers = lan:GetLocalPlayers()
    local expectedActors = character == PlayerType.PLAYER_JACOB and 2 or 1
    assert(
        #localPlayers == expectedActors and localPlayers[1].ControllerIndex == (host and 1 or 2),
        "Public API local actors differ: count="
            .. #localPlayers
            .. " expected="
            .. expectedActors
            .. " controller="
            .. tostring(localPlayers[1] and localPlayers[1].ControllerIndex)
            .. " signature="
            .. lan:View().playerSignature
    )
    local visibleMod = false
    for _, status in ipairs(api:GetAdapters()) do
        if status.target then
            assert(
                status.state == "active",
                "Built-in compatibility did not install: " .. status.id .. " " .. status.state
            )
            if status.id == "isaac-lan.compat.stats-plus" then
                visibleMod = true
            end
        end
    end
    if visibleMod then
        if not playerService then
            for _, callback in ipairs(Isaac.GetCallbacks(ModCallbacks.MC_POST_UPDATE)) do
                if callback.Mod.Name == "stats-plus" then
                    playerService = modules["compat/mods/wrapping"].find(
                        callback.Function,
                        function(value)
                            return type(value.getAllEntityPlayers) == "function"
                                and type(value.getPlayers) == "function"
                        end
                    )
                    if playerService then
                        break
                    end
                end
            end
        end
        assert(playerService, "Stats+ service not reachable")
        local players = playerService:getPlayers()
        assert(
            #players == expectedActors
                and players[1].index == 0
                and players[1].entityPlayer.ControllerIndex == (host and 1 or 2),
            "Stats+ cached teammate or multiplayer layout"
        )
        for index, player in ipairs(players) do
            assert(
                player.index == index - 1
                    and lan:GetOwnerId(player.entityPlayer) == (host and 1 or 2),
                "Stats+ used teammate identity or layout"
            )
            assert(
                lan:GetPlayerId(player.entityPlayer) == "p" .. (host and 1 or 2) .. ":" .. index,
                "Logical role identity changed"
            )
        end
    end
    if EID then
        EID:setPlayer()
        assert(
            #EID.coopAllPlayers == expectedActors
                and EID.player.ControllerIndex == (host and 1 or 2)
                and not EID.isMultiplayer,
            "EID retained remote player context"
        )
    end
    checks = checks + 1
    if checks == 30 then
        report("VIEWS_CHECKED Stats+=" .. tostring(visibleMod) .. " EID=" .. tostring(EID ~= nil))
    end
end)

-- Explicit test-only lifecycle consumed by both suite coordinators.
return {
    done = function()
        return finished
    end,
    cleanup = function()
        native.api_send, native.api_receive = send, receive
        lan:Close()
    end,
}
