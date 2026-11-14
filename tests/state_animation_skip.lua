-- One owned pair, one connection, native confirmation inputs throughout.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, slot = config.host, config.host and 0 or 1
local kinds = native.animation_skip_kinds()
local cases = {
    { name = "host-solo", kind = kinds.boss, members = 1, first = 0 },
    { name = "guest-solo", kind = kinds.boss, members = 2, first = 1 },
    { name = "shared-space", kind = kinds.boss, members = 3, first = 0, keyboard = "SPACE" },
    { name = "shared-enter", kind = kinds.boss, members = 3, first = 0, keyboard = "ENTER" },
    { name = "floor", kind = kinds.floor, members = 3, first = 1 },
    { name = "natural", kind = kinds.boss, members = 3, natural = true },
}
local function read(name)
    local f = io.open(skipCoordination .. "/" .. name .. ".txt")
    if not f then
        return
    end
    local value = f:read("*a")
    f:close()
    return value
end
local function write(name, value)
    local f = assert(io.open(skipCoordination .. "/" .. name .. ".txt", "w"))
    f:write(tostring(value))
    f:close()
end
local function report(text)
    Isaac.DebugString("LAN_NETWORK SKIP " .. text)
end
local function actor(seat, fn)
    assert(native.rooms_with_player(seat, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(seat)])))
    end, 1))
end
local current, case, mode, changedAt = 0, nil, "init", 0
local renders, joined, chosen, started, complete = 0, false, false, false, false
local initial = Isaac.GetTime()
local seen, ended, voted, firstVote, voteAt, pressUntil, began, announced
local latestStatus, hudSeen = {}, false
local lastTick = 0
local frame, gate = _IsaacLanFrame, native.net_gate
local render = _IsaacLanMenuRender
function _IsaacLanMenuRender(...)
    local visible = render(...)
    if
        not visible
        and case
        and not hudSeen
        and (latestStatus.skipVotes or 0) ~= 0
        and native.animation_skip_view().kind == case.kind
    then
        hudSeen = true
        report("HUD case=" .. current .. " votes=" .. latestStatus.skipVotes)
    end
    return visible
end
function _IsaacLanFrame()
    renders = renders + 1
    if renders == 1 then
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    latestStatus = s
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if not joined and Isaac.GetTime() - initial > 15000 then
        joined = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
    end
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and not started
        and s.phase == 2
        and s.players == 2
        and s.ready0 == 1
        and s.ready1 == 1
    then
        started = true
        _IsaacLanCommand("start", "04QHQ43B:0:0:0:0:0")
    end
    local nextCase = tonumber(read("case") or "0")
    if nextCase ~= current then
        current, case = nextCase, cases[nextCase]
        seen, ended, voted, firstVote, voteAt, pressUntil, announced =
            nil, nil, nil, nil, nil, nil, nil
        began = Isaac.GetTime()
        hudSeen = false
    end
    local buttons = 0
    if case and s.prepared then
        assert(Isaac.GetTime() - began < 25000, "Animation case timed out: " .. case.name)
        local view = native.animation_skip_view()
        local watching = (case.members & (1 << slot)) ~= 0
        if not watching then
            assert(view.kind == kinds.none, "Unrelated room received an animation")
            write("done-" .. current .. "-" .. slot, 1)
        elseif view.kind == case.kind then
            if not seen then
                seen = renders
                write("seen-" .. current .. "-" .. slot, 1)
                report("BEGIN case=" .. current .. " kind=" .. view.kind .. " epoch=" .. view.epoch)
            end
            local allSeen = true
            for seat = 0, 1 do
                if
                    (case.members & (1 << seat)) ~= 0
                    and not read("seen-" .. current .. "-" .. seat)
                then
                    allSeen = false
                end
            end
            if not case.natural and allSeen and not voted then
                if case.first == slot and renders - seen >= 10 then
                    if case.keyboard then
                        if not announced then
                            announced = true
                            write("keyboard-" .. current, case.keyboard)
                            report("KEYBOARD case=" .. current .. " key=" .. case.keyboard)
                        end
                        voted = (s.skipVotes or 0) & (1 << slot) ~= 0
                    else
                        voted, pressUntil = true, renders + 8
                    end
                elseif case.first ~= slot and (s.skipVotes or 0) == (1 << case.first) then
                    firstVote = firstVote or renders
                    assert(view.kind == case.kind, "One approval skipped the animation")
                    if renders - firstVote >= 25 then
                        report("ONE_VOTE_WAIT case=" .. current)
                        voted, pressUntil, voteAt = true, renders + 12, renders
                    end
                end
            end
            if (s.skipVotes or 0) ~= 0 then
                firstVote = firstVote or renders
                if not voteAt then
                    report("VOTE case=" .. current .. " mask=" .. s.skipVotes)
                    voteAt = renders
                end
            end
        elseif seen and not ended then
            ended = renders
            assert(
                case.natural or voted or (case.members == 3 and firstVote),
                "Animation ended without consent"
            )
            assert(case.natural or case.members ~= 3 or hudSeen, "Animation vote HUD was not drawn")
            report("END case=" .. current .. " frames=" .. (renders - seen))
        end
        if pressUntil and renders <= pressUntil then
            buttons = 0x1000
        end
        if ended and renders - ended >= 20 and not read("done-" .. current .. "-" .. slot) then
            local controls
            actor(slot, function(player)
                controls = player.ControlsEnabled and player:AreControlsEnabled()
                assert(player:GetActiveCharge() == 6, "Confirmation used the active item")
            end)
            assert((s.skipVotes or 0) == 0, "Ended animation left its vote indicator")
            -- Nightmare completion precedes the native floor landing animation.
            -- Wait for its normal cleanup without forcing either control flag.
            local ready = controls and (case.kind ~= kinds.floor or view.floorReady)
            assert(ready or renders - ended < 300, "Skip left controls locked after landing")
            if ready then
                if case.kind == kinds.floor then
                    assert(Game():GetLevel():GetStage() == 2, "Skip changed the floor destination")
                end
                write("done-" .. current .. "-" .. slot, 1)
                report("RECOVERED case=" .. current .. " frames=" .. (renders - ended))
            end
        end
        if renders % 120 == 0 then
            report(
                "STATE case="
                    .. current
                    .. " kind="
                    .. view.kind
                    .. " votes="
                    .. (s.skipVotes or 0)
                    .. " members="
                    .. (s.skipMembers or 0)
                    .. " tick="
                    .. lastTick
            )
        end
    end
    if read("finished") and not complete then
        complete = true
        report("PASS native keyboard, controller, solo, shared and floor skips")
    end
    native.test_gamepad(buttons)
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(tick, players, bytes)
        before(tick, players, bytes)
        lastTick = tick
        if not host or not native.rooms_ready() then
            return
        end
        for seat = 0, 1 do
            actor(seat, function(player)
                player:SetMinDamageCooldown(10000)
                if not player:HasCollectible(CollectibleType.COLLECTIBLE_D6) then
                    player:AddCollectible(CollectibleType.COLLECTIBLE_D6, 6, false)
                end
                player.Position, player.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
            end)
        end
        if mode == "init" and tick > 45 then
            mode, changedAt = "next", tick
        elseif
            mode == "watch"
            and read("done-" .. current .. "-0")
            and read("done-" .. current .. "-1")
        then
            for seat = 0, 1 do
                assert(native.rooms_move(seat, 84, 0, -1))
            end
            mode, changedAt = "next", tick
        elseif mode == "next" and tick - changedAt > 35 then
            local upcoming = current + 1
            local scenario = cases[upcoming]
            if not scenario then
                mode = "complete"
                write("finished", 1)
                return
            end
            write("case", upcoming)
            mode = "watch"
            if scenario.kind == kinds.floor then
                Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
            else
                local boss
                local rooms = Game():GetLevel():GetRooms()
                for index = 0, rooms.Size - 1 do
                    local room = rooms:Get(index)
                    if room.Data and room.Data.Type == RoomType.ROOM_BOSS then
                        boss = room.SafeGridIndex
                        break
                    end
                end
                assert(boss, "Missing fixture boss room")
                for seat = 0, 1 do
                    if (scenario.members & (1 << seat)) ~= 0 then
                        assert(native.rooms_move(seat, boss, 0, -1))
                    end
                end
            end
        end
    end, collect, restore, present, beginFloor)
end
