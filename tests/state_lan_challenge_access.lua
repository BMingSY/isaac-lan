-- Startup profiles: qualified, no Negative, no Tainted Cain, neither.
-- Host and guest roles rotate while the same four native processes stay open.
local native, port = assert(_IsaacLan), _IsaacLanTest.port
local handle = assert(io.open("./lan-test-role.txt", "r"))
local ordinal = assert(({ host = 0, client = 1, client2 = 2, client3 = 3 })[handle:read("*l")])
handle:close()
local cases = {
    { name = "guest-no-negative", members = { 0, 1 } },
    { name = "guest-no-cain", members = { 0, 2 } },
    { name = "guest-neither", members = { 0, 3 } },
    { name = "host-no-negative", members = { 1, 0 } },
    { name = "host-no-cain", members = { 2, 0 } },
    { name = "host-neither", members = { 3, 0 } },
    { name = "ordinary-all-profiles", members = { 0, 1, 2, 3 }, ordinary = true },
}
local current, case, member, renders = 0, nil, nil, 0
local linked, chosen, checked, closing, done, reported = false, false, false, false, false, false
local startAt, closedAt, exitedAt, participated = 0, nil, nil, false
local owner = { Name = "LAN challenge access acceptance" }
local function read(path)
    local file = io.open(challengeCoordination .. "/" .. path, "r")
    if not file then
        return nil
    end
    local result = file:read("*a")
    file:close()
    return result
end
local function write(path, value)
    local file = assert(io.open(challengeCoordination .. "/" .. path, "w"))
    file:write(value)
    file:close()
end
local function report(value)
    Isaac.DebugString(
        "LAN_NETWORK LAN_CHALLENGE case=" .. (case and case.name or "boot") .. " " .. value
    )
end
local function checkLocal()
    local characters, seen = native.net_characters(), {}
    for _, id in ipairs(characters) do
        assert(not seen[id], "Personal character list contains duplicates")
        seen[id] = true
    end
    assert(seen[0], "Isaac is missing from the personal character list")
    assert(not seen[22], "Personal character list exposed locked Tainted Magdalene")
    assert(not not seen[23] == (ordinal < 2), "Tainted Cain differs from this peer's own save")
    local challenge = assert(native.net_challenges()["1001"])
    assert(challenge.version == 2, "Unexpected challenge definition version")
    assert(challenge.available == (ordinal == 0), "Local challenge access differs from own save")
    report(
        "PERSONAL_ACCESS ordinal="
            .. ordinal
            .. " cain="
            .. tostring(not not seen[23])
            .. " qualified="
            .. tostring(challenge.available)
            .. " characters="
            .. table.concat(characters, ",")
    )
end
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    exitedAt = native.api_info().nowMs
end)
local frame, gate = _IsaacLanFrame, native.net_gate
function _IsaacLanFrame()
    renders = renders + 1
    local status = frame()
    local now = native.api_info().nowMs
    native.test_gamepad(0)
    if renders == 60 then
        write("boot-" .. ordinal .. ".txt", "ready")
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    for slot = 0, 3 do
        if not read("boot-" .. slot .. ".txt") then
            return status
        end
    end
    local requested = tonumber(read("case.txt"))
    if not requested then
        return status
    end
    if requested > #cases then
        if not reported then
            reported = true
            Isaac.DebugString("LAN_NETWORK PASS concentrated LAN challenges")
        end
        return status
    end
    if requested ~= current then
        if status.phase ~= 0 or status.scene ~= 1 or status.prepared then
            return status
        end
        current, case, member = requested, assert(cases[requested]), nil
        for index, slot in ipairs(case.members) do
            if ordinal == slot then
                member = index
            end
        end
        linked, chosen, checked, closing, done = false, false, false, false, false
        startAt, closedAt, exitedAt, participated = now + 2000, nil, nil, false
        checkLocal()
        report("BEGIN ordinal=" .. ordinal)
    end
    if not member then
        return status
    end
    local closeRequested = read("close-" .. current .. ".txt")
    if not closing and closeRequested then
        closing, closedAt = true, now
        _IsaacLanCommand("close", "")
    end
    if not closing and (status.phase == 4 or (status.phase == 9 and status.error ~= "")) then
        Isaac.DebugString("LAN_NETWORK FAILED " .. status.error)
        return status
    end
    if not linked and now >= startAt + (member - 1) * 1000 and status.scene == 1 then
        linked = true
        _IsaacLanCommand(
            member == 1 and "host" or "join",
            member == 1 and port or "127.0.0.1:" .. port
        )
    end
    if status.phase == 2 and not closing then
        if not chosen then
            chosen = true
            assert(not native.net_choose(22, 1), "Locked local character choice was accepted")
            assert(native.net_choose(0, 1), "Ordinary Isaac choice was rejected")
            report("LOCKED_CHARACTER_REJECTED character=22")
        end
        local ready = status.players == #case.members
        for slot = 0, #case.members - 1 do
            ready = ready and status["ready" .. slot] == 1
            if status.players == #case.members then
                assert(status["eligible" .. slot] == true, "Ordinary rules rejected a peer")
            end
        end
        if member == 1 and ready and not checked then
            checked = true
            assert(
                native.net_challenges()["1001"].team_available == false,
                "Unqualified team enabled challenge"
            )
            assert(not native.net_challenge(1001), "Unqualified team selected challenge")
            report("CHALLENGE_REJECTED host_ordinal=" .. case.members[1])
            if case.ordinary then
                _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
            else
                write("close-" .. current .. ".txt", "close")
            end
        end
    end
    if case.ordinary and native.api_info().ready == 1 then
        participated = true
    end
    if
        case.ordinary
        and participated
        and exitedAt
        and not status.prepared
        and status.phase == 0
    then
        closing, closedAt = true, exitedAt
    end
    if closing and not done and status.phase == 0 and now - closedAt > 1000 then
        done = true
        checkLocal()
        write("done-" .. current .. "-" .. ordinal .. ".txt", "done")
        report("PASS menu_cleanup=true")
    end
    if ordinal == 0 and done then
        local all = true
        for _, slot in ipairs(case.members) do
            all = all and read("done-" .. current .. "-" .. slot .. ".txt") ~= nil
        end
        if all then
            write("case.txt", tostring(current + 1))
        end
    end
    assert(now - startAt < 60000 or done, "Access case stalled: " .. case.name)
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local stopped = false
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if t >= 120 and not stopped and native.rooms_connected() == 15 then
            local info = native.api_info()
            assert(info.challenge == 0 and info.restrictedBags == 0 and info.players == 4)
            for slot = 0, 3 do
                assert(native.rooms_with_player(slot, function()
                    local player = Isaac.GetPlayer(native.rooms_heads()[tostring(slot)])
                    assert(player:GetPlayerType() == PlayerType.PLAYER_ISAAC)
                end))
            end
            stopped = true
            report("ORDINARY_ALL_PROFILES_USABLE")
            assert(native.net_command(3))
        end
    end, collect, restore, present, beginFloor)
end
