-- Pause/resume must not release an extrapolation accumulated while hidden.
local native = assert(_IsaacLan)
local file = assert(io.open("./lan-test-role.txt", "r"))
local host = file:read("*l") == "host"
file:close()
file = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = file:read("*l")
file:close()
local originalFrame = _IsaacLanFrame
local renders, linked, chosen, finished = 0, false, false, false
local requested, resumed, pausedAt, previous, wasPaused
local pausedFrames, resumedFrames, maxResumeStep, maxPauseDrift = 0, 0, 0, 0
local authorityX, authorityY = 0, 0
local digest = assert(io.open("./lan-test-digest-pause.csv", "w"))
digest:write("time,tick,pause,x,y,authority_x,authority_y\n")
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = originalFrame()
    if status.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    if host and status.prepared and status.verified >= 40 and not requested then
        assert(native.net_command(1))
        requested = true
    end
    if host and requested and status.pause ~= 0 then
        pausedAt = pausedAt or Isaac.GetTime()
        if not resumed and Isaac.GetTime() - pausedAt >= 700 then
            assert(native.net_command(2))
            resumed = true
        end
    end
    native.test_gamepad(
        host and status.verified >= 20 and status.verified < 80 and status.pause == 0 and 8 or 0
    )
    if status.verified >= 170 and not finished then
        if not host then
            assert(
                pausedFrames >= 20 and resumedFrames >= 20,
                "Pause/resume display was not exercised"
            )
            Isaac.DebugString(
                "LAN_NETWORK PAUSE_TRAJECTORY paused="
                    .. pausedFrames
                    .. " resumed="
                    .. resumedFrames
                    .. " max_step="
                    .. maxResumeStep
                    .. " max_pause_drift="
                    .. maxPauseDrift
            )
            assert(maxPauseDrift < 0.1, "Paused display drifted beyond authoritative movement")
            assert(maxResumeStep < 12, "Resume released stale remote movement")
        end
        finished = true
        Isaac.DebugString("LAN_NETWORK PASS pause trajectory")
    end
    return status
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, bytes)
            before(t, n, bytes)
            if t == 0 then
                for i = 0, 1 do
                    local p = Isaac.GetPlayer(i)
                    p.Position, p.Velocity = Vector(180, 200 + i * 80), Vector(0, 0)
                    p:SetMinDamageCooldown(10000)
                end
            end
        end,
        collect,
        function(bytes, tick, ack, betweenUpdates)
            if restore(bytes, tick, ack, betweenUpdates) == false then
                return false
            end
            local value = _IsaacLanState.decode(bytes)
            authorityX, authorityY = table.unpack(value[9][1][3][6])
            return true
        end,
        present,
        beginFloor
    )
end
Isaac.AddCallback({ Name = "Response pause trajectory" }, ModCallbacks.MC_POST_RENDER, function()
    local status = _IsaacLanStatus()
    if finished or not status.prepared or not native.rooms_ready() then
        return
    end
    local p = Isaac.GetPlayer(native.rooms_heads()["0"])
    digest:write(table.concat({
        Isaac.GetTime(),
        status.verified,
        status.pause,
        p.Position.X,
        p.Position.Y,
        authorityX,
        authorityY,
    }, ",") .. "\n")
    digest:flush()
    if host then
        return
    end
    if previous then
        if status.pause ~= 0 then
            pausedFrames = pausedFrames + 1
            if wasPaused and pausedFrames > 3 then
                -- The local pause menu's closing animation can outlive the
                -- host pause. Authoritative movement during that interval is
                -- valid; only additional extrapolated movement is forbidden.
                maxPauseDrift =
                    math.max(maxPauseDrift, p.Position:Distance(Vector(authorityX, authorityY)))
            end
        elseif pausedFrames > 0 then
            resumedFrames = resumedFrames + 1
            maxResumeStep = math.max(maxResumeStep, p.Position:Distance(previous))
        end
    end
    previous, wasPaused = p.Position, status.pause ~= 0
end)
