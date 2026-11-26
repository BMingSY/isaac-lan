-- Start with an empty owned host slot. After both peers report FLOOR_CAPTURE_READY,
-- terminate that host and run the same fixture again to exercise the lobby's Continue.
local native, host = _IsaacLan, _IsaacLanTest.host
local port = _IsaacLanTest.port
local hostItem = CollectibleType.COLLECTIBLE_BROTHER_BOBBY
local guestItem = CollectibleType.COLLECTIBLE_MOMS_KNIFE
local afterEntry = CollectibleType.COLLECTIBLE_SPOON_BENDER
local owner = { Name = "Isolated floor autosave regression" }
local continued, linked, chosen, started, advanced, changed, finished =
    false, false, false, false, false, false, false
local frames, arrived, firstCheckpoint = 0, nil, nil
local function checkpointHash()
    local file = io.open("./isaac-lan/session-1.floor.bin", "rb")
    if not file then
        return nil
    end
    file:seek("end", -8)
    local hash = file:read(8)
    file:close()
    return hash
end
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local originalRoom, sideRoom, floorHash, movedAt, rewindEpoch, returnedAt
local function verifySameFloor(tick)
    if not native.rooms_ready() then
        return
    end
    local room = native.rooms_positions()["0"].index
    if not sideRoom then
        local level = Game():GetLevel()
        originalRoom, floorHash = room, assert(checkpointHash())
        for i = 0, level:GetRooms().Size - 1 do
            local other = level:GetRooms():Get(i)
            if
                other.Data
                and other.Data.Type == RoomType.ROOM_DEFAULT
                and other.SafeGridIndex ~= room
            then
                sideRoom = other.SafeGridIndex
                break
            end
        end
        assert(sideRoom and native.rooms_move(0, sideRoom, 0, -1), "Cannot enter side room")
    elseif room == sideRoom and not rewindEpoch then
        movedAt = movedAt or tick
        if tick >= movedAt + 45 then
            assert(checkpointHash() == floorHash, "Ordinary room replaced the floor save")
            rewindEpoch = native.api_info().worldEpoch
            assert(native.rooms_with_player(0, function()
                Isaac.GetPlayer(0)
                    :UseActiveItem(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, 0, -1)
            end))
        end
    elseif rewindEpoch and room == originalRoom and native.api_info().worldEpoch > rewindEpoch then
        returnedAt = returnedAt or tick
        if tick >= returnedAt + 45 then
            assert(checkpointHash() == floorHash, "Same-floor rewind replaced the floor save")
            report("PASS floor autosave continue")
            finished = true
        end
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function(_, value)
    continued = value
end)
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and not started
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        started = true
        if native.net_saved_info() > 0 then
            _IsaacLanCommand("resume", "")
        else
            _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
        end
    end
    if not status.prepared or status.phase ~= 3 or status.verified < 90 or finished then
        return status
    end
    if originalRoom then
        verifySameFloor(status.verified)
        return status
    end
    local game = Game()
    local p1, p2 = Isaac.GetPlayer(0), Isaac.GetPlayer(1)
    local stage = game:GetLevel():GetStage()
    if not continued and host and not advanced and stage == LevelStage.STAGE1_1 then
        firstCheckpoint = checkpointHash()
        assert(
            firstCheckpoint and not p1:HasCollectible(afterEntry),
            "Missing first floor or dirty fixture"
        )
        advanced = true
        p1:AddCollectible(hostItem)
        p2:AddCollectible(guestItem)
        game:StartStageTransition(false, RoomTransitionAnim.FADE, p1)
    elseif stage == LevelStage.STAGE1_2 then
        arrived = arrived or status.verified
        if status.verified >= arrived + 90 then
            assert(
                game:GetNumPlayers() == 2
                    and p1:HasCollectible(hostItem)
                    and p2:HasCollectible(guestItem),
                "Floor checkpoint lost a player or their inventory"
            )
            if continued then
                assert(
                    not p1:HasCollectible(afterEntry),
                    "Continue loaded post-checkpoint progress"
                )
                if host then
                    verifySameFloor(status.verified)
                else
                    report("PASS floor autosave continue")
                    finished = true
                end
            elseif host and not changed then
                -- GetStage changes during the native transition, before the new
                -- room is adopted. Wait for the disk commit before altering it.
                local current = checkpointHash()
                if current and current ~= firstCheckpoint then
                    assert(not p1:HasCollectible(afterEntry), "Unexpected post-entry item")
                    p1:AddCollectible(afterEntry)
                    changed = true
                    report("FLOOR_POST_COMMIT_ITEM")
                end
            elseif p1:HasCollectible(afterEntry) then
                report("FLOOR_CAPTURE_READY")
                finished = true
            end
        end
    end
    return status
end
