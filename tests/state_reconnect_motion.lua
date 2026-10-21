-- Keep both processes alive while a new guest input stream replaces the old one.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, gates = 0, 0
local linked, chosen, requested, departed, finished = false, false, false, false, false
local resumedAt, minimum, maximum
local function report(message)
    Isaac.DebugString("LAN_NETWORK RECONNECT_MOTION " .. message)
end
local function sample(tick)
    if not resumedAt or tick - resumedAt < 45 then
        return
    end
    local player = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
    minimum = math.min(minimum or player.Position.X, player.Position.X)
    maximum = math.max(maximum or player.Position.X, player.Position.X)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= 4, status.error)
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
    if host and status.prepared and status.connected == 1 then
        departed = true
    end
    local buttons = 0
    if status.prepared and native.api_info().ready == 1 and not status.recovering then
        if not host and gates == 1 and status.verified >= 300 and not requested then
            requested = true
            _IsaacLanCommand("reconnect")
        end
        if (host and departed or not host and gates == 2) and status.connected == 3 then
            resumedAt = resumedAt or status.verified
            local age = status.verified - resumedAt
            if not host and age >= 45 then
                buttons = math.floor((age - 45) / 60) % 2 == 0 and 8 or 4
            end
            if age >= 240 and not finished then
                assert(
                    minimum and maximum - minimum > 250,
                    "Rejoined actor cannot move across the room"
                )
                finished = true
                report(
                    string.format(
                        "PASS ordinary input after reconnect travel=%.2f",
                        maximum - minimum
                    )
                )
            end
        end
    end
    native.test_gamepad(buttons)
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    gates = gates + 1
    return gate(
        capture,
        function(t, n, bytes)
            before(t, n, bytes)
            if t == 30 then
                for slot = 0, 1 do
                    assert(native.rooms_with_player(slot, function()
                        local player = Isaac.GetPlayer(native.rooms_heads()[tostring(slot)])
                        player:SetMinDamageCooldown(10000)
                        player:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK)
                        player.Position = Vector(260, 220 + slot * 100)
                    end))
                end
            end
            sample(t)
        end,
        collect,
        restore,
        function(...)
            local result = table.pack(present(...))
            sample(_IsaacLanStatus().verified)
            return table.unpack(result, 1, result.n)
        end,
        beginFloor
    )
end
return {
    done = function()
        return finished
    end,
}
