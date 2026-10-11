local root = arg[1] or "."
local checks = 0
local function fixture(count, host, landing, collision)
    local owner, now, mask, capturedMask, hostSteps, peerSteps = 0, 0, 0, 0, 0, 0
    local locations, players, heads, changes, messages = {}, {}, {}, {}, {}
    for slot = 0, count - 1 do
        locations[tostring(slot)], heads[tostring(slot)] = { index = 84 }, slot
        players[slot] = { Position = { X = 320, Y = 360 } }
        changes[slot] = 0
    end
    local status = { phase = 3, scene = 2, players = count }
    local native = {
        api_info = function()
            return {
                slot = host and 0 or count - 1,
                nowMs = now,
                ready = status.scene == 2 and 1 or 0,
            }
        end,
        rooms_ready = function()
            return status.scene == 2
        end,
        rooms_positions = function()
            return locations
        end,
        rooms_heads = function()
            return heads
        end,
        rooms_with_player = function(slot, fn, actorOnly)
            assert(actorOnly == 1, "Native ChangeRoom must resolve one arriving actor")
            local saved = owner
            owner = slot
            local ok, err = pcall(fn)
            owner = saved
            assert(ok, err)
            return true
        end,
        net_gate = function(_, before)
            before()
        end,
        input_bot = function(active, value)
            assert(
                (active == 0 or active == 1) and value < 16,
                "Entry fixture used attack or a non-movement input"
            )
            mask = value
        end,
        test_gamepad = function(value)
            assert(value == 0)
        end,
    }
    local level = {
        GetStage = function()
            return 1
        end,
        GetStartingRoomIndex = function()
            return 84
        end,
        GetCurrentRoomIndex = function()
            return locations[tostring(owner)].index
        end,
        GetRoomByIdx = function(_, index)
            return {
                SafeGridIndex = index == 71 and 70 or index,
                Data = { Type = index == 71 and 2 or 1 },
            }
        end,
    }
    local room = {
        GetDoor = function(_, slot)
            if locations[tostring(owner)].index == 84 and slot == 1 then
                return { TargetRoomIndex = 71, Position = { X = 320, Y = 120 } }
            elseif locations[tostring(owner)].index == 70 and slot == 7 then
                return { TargetRoomIndex = 84, Position = { X = 840, Y = 440 } }
            end
        end,
        GetGridIndex = function(_, position)
            assert(position == players[owner].Position)
            return 203
        end,
        GetGridCollision = function()
            return collision or 0
        end,
    }
    local game = {
        IsGreedMode = function()
            return true
        end,
        GetLevel = function()
            return level
        end,
        GetRoom = function()
            return room
        end,
        ChangeRoom = function(_, index)
            assert(host and index == 71 and locations[tostring(owner)].index == 84)
            changes[owner] = changes[owner] + 1
            assert(changes[owner] <= (owner == count - 1 and 2 or 1))
            locations[tostring(owner)].index = 70
            players[owner].Position = changes[owner] == 2 and landing or { X = 580, Y = 280 }
        end,
    }
    local env = setmetatable({
        _IsaacLan = native,
        _IsaacLanTest = { host = host, port = 31006, players = count },
        _IsaacLanCommand = function()
            error("Unexpected lobby action")
        end,
        _IsaacLanFrame = function()
            native.input_bot(0, 0) -- Inactive production LANBOT before input capture.
            capturedMask = mask
            return status
        end,
        Game = function()
            return game
        end,
        RoomType = { ROOM_SHOP = 2 },
        GridCollisionClass = { COLLISION_NONE = 0 },
        Isaac = {
            GetPlayer = function(slot)
                assert(slot == owner)
                return players[slot]
            end,
            DebugString = function(text)
                messages[#messages + 1] = text
            end,
        },
    }, { __index = _G })
    assert(loadfile(root .. "/tests/state_room_entry.lua", "t", env))()
    local function step()
        now = now + 100
        env._IsaacLanFrame()
        native.net_gate(nil, function() end)
    end
    return {
        runHost = function()
            for _ = 1, 30 do
                step()
                if capturedMask ~= 0 and locations["0"].index == 70 then
                    hostSteps = hostSteps + 1
                    if hostSteps == 2 then
                        locations["0"].index = 84
                    end
                elseif
                    locations["0"].index == 84
                    and changes[0] == 1
                    and changes[count - 1] == 1
                then
                    peerSteps = peerSteps + 1
                    if peerSteps == 2 then
                        locations[tostring(count - 1)].index = 84
                    end
                end
                if table.concat(messages, "\n"):find("PASS corrected_reentry", 1, true) then
                    assert(changes[count - 1] == 2)
                    return
                end
            end
            error("Entry fixture never completed")
        end,
        runGuest = function()
            step() -- Do not learn a shop before both actors have arrived.
            assert(mask == 0)
            locations["0"].index = 70
            step()
            assert(mask == 0)
            locations[tostring(count - 1)].index = 70
            players[count - 1].Position = { X = 840, Y = 400 }
            step()
            assert(mask == 0)
            locations["0"].index = 84
            step()
            assert(mask == 8)
            locations[tostring(count - 1)].index = 84
            step()
            assert(mask == 0)
            locations[tostring(count - 1)].index = 70
            step() -- Corrected re-entry must not trigger a second walk out.
            assert(mask == 0)
            status.phase, status.scene, status.prepared = 0, 1, false
            step()
            assert(table.concat(messages, "\n"):find("PASS peer_returned", 1, true))
        end,
    }
end
for _, count in ipairs({ 2, 4 }) do
    fixture(count, true, { X = 840, Y = 400 }):runHost()
    fixture(count, false):runGuest()
    for _, bad in ipairs({
        { position = { X = 315, Y = 140 }, error = "different actor" },
        { position = { X = 840, Y = 400 }, collision = 3, error = "blocked terrain" },
    }) do
        local ok, err = pcall(function()
            fixture(count, true, bad.position, bad.collision):runHost()
        end)
        assert(not ok and tostring(err):find(bad.error, 1, true), tostring(err))
    end
    checks = checks + 4
end
print("Native room-entry fixture offline checks passed: " .. checks)
