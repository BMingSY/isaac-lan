-- Both arrival orders must deliver the same in-progress boss introduction.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host = config.host
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local boss, tick = nil, 0
local samples, starts, active = { 0, 0 }, { 0, 0 }, false
local checked = {}
local startedAt, endedAt = {}, {}
local function report(text)
    Isaac.DebugString("LAN_NETWORK SHARED_INTRO " .. text)
end
local function phase(t)
    return t >= 600 and 2 or 1
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "04QHQ43B:0:0:0:0:0")
    end
    tick = s.verified
    if s.prepared and native.rooms_ready() then
        local current = phase(tick)
        local playing = native.presentation_active()
        if playing then
            samples[current] = samples[current] + 1
            if not active then
                starts[current] = starts[current] + 1
                startedAt[current] = tick
                report("START phase=" .. current .. " tick=" .. tick)
            end
        elseif active then
            endedAt[current] = tick
            report("END phase=" .. current .. " tick=" .. tick)
        end
        active = playing
        if tick >= 100 and tick < 105 and not host then
            assert(not playing, "Host intro appeared in an unrelated guest room")
        elseif tick >= 600 and tick < 605 and host then
            assert(not playing, "Guest intro appeared in an unrelated host room")
        end
        if not checked[current] and ((tick >= 400 and tick < 430) or tick >= 900) then
            assert(samples[current] > 5, "Late entrant never saw the shared boss intro")
            assert(starts[current] == 1, "Shared intro was restarted or replayed")
            assert(not playing, "Shared intro did not finish")
            assert(
                native.rooms_with_player(host and 0 or 1, function()
                    local p = Isaac.GetPlayer(native.rooms_heads()[host and "0" or "1"])
                    assert(
                        p.ControlsEnabled and p:AreControlsEnabled(),
                        "Intro left controls locked"
                    )
                    assert(Game():GetLevel():GetCurrentRoomIndex() == boss, "Intro changed rooms")
                end, 1),
                "Intro control check could not enter the local room at tick " .. tick
            )
            checked[current] = true
            report("RECOVERED phase=" .. current .. " tick=" .. tick)
        end
    end
    if tick >= 950 and not finished then
        assert(checked[1] and checked[2], "Both arrival orders must complete their checks")
        local first, late = host and 1 or 2, host and 2 or 1
        local full = endedAt[first] - startedAt[first]
        local shortened = endedAt[late] - startedAt[late]
        assert(shortened < full - 20, "Late viewer extended the intro instead of skipping its tail")
        report("DURATIONS full=" .. full .. " late=" .. shortened)
        finished = true
        report("PASS both arrival orders and control recovery")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        if d.Data.Type == RoomType.ROOM_BOSS then
            boss = d.SafeGridIndex
            break
        end
    end
    assert(boss, "Boss room missing from fixture seed")
    return gate(capture, function(t, n, b)
        before(t, n, b)
        if t == 0 then
            for i = 0, Game():GetNumPlayers() - 1 do
                Isaac.GetPlayer(i):SetMinDamageCooldown(10000)
            end
        end
        if t == 140 or t == 640 then
            assert(
                #native.presentation_events(t == 140 and 0 or 1) > 0,
                "First intro already ended"
            )
        end
        if t == 100 or t == 640 then
            assert(native.rooms_move(0, boss, 0, -1))
        elseif t == 140 or t == 600 then
            assert(native.rooms_move(1, boss, 0, -1))
        elseif t == 450 then
            assert(native.rooms_move(0, 84, 0, -1))
            assert(native.rooms_move(1, 84, 0, -1))
        end
    end, collect, restore, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
