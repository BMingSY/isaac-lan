-- Native per-body movement queries and the directions actually used by prediction.
local native = assert(_IsaacLan)
local file = assert(io.open("./lan-test-role.txt", "r"))
local host = file:read("*l") == "host"
file:close()
file = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = file:read("*l")
file:close()
local owner = { Name = "Multi-actor prediction regression" }
local function report(s)
    Isaac.DebugString("LAN_NETWORK MULTI_ACTOR " .. s)
end
local frame, gate = _IsaacLanFrame, native.net_gate
local linked, chosen, finished = false, false, false
local renders, verified, samples = 0, 0, 0
local seen, steps = {}, {}
local makePrediction = _IsaacLanPrediction.new
_IsaacLanPrediction.new = function(position)
    local model = makePrediction(position)
    local step = model.step
    model.step = function(self, direction, ...)
        steps[#steps + 1] = direction
        return step(self, direction, ...)
    end
    return model
end
local function phase(t)
    if t < 330 then
        return "jacob"
    elseif t < 750 then
        return "soul-jacob"
    elseif t < 1320 then
        return "forgotten"
    end
    return "soul-forgotten"
end
local function buttons(t)
    if t < 60 or t >= 1700 then
        return 0, false
    end
    local movement = 1 << (math.floor(t / 15) % 2)
    local drop = t >= 180 and t < 300
        or t >= 540 and t < 660
        or t >= 960 and t < 966
        or t >= 1120 and t < 1126
        or t >= 1520 and t < 1640
    return movement, drop
end
function _IsaacLanBotFrame()
    local s = _IsaacLanStatus()
    local move = buttons(s.verified)
    native.input_bot(not host and s.phase == 3 and 1 or 0, move)
end
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function()
    if host and not finished then
        return false
    end
end, EntityType.ENTITY_PLAYER)
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    verified = s.verified
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", (host and "0" or "19") .. ":1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:19:0:0")
    end
    local move, drop = buttons(s.verified)
    native.input_bot(not host and s.phase == 3 and 1 or 0, move)
    native.test_gamepad(0, 0, not host and drop and 255 or 0)
    if s.phase == 4 or s.phase == 9 then
        Isaac.DebugString("LAN_NETWORK FAILED " .. s.error)
    end
    if s.verified >= 1800 and not finished then
        if not host then
            for _, key in ipairs({
                "jacob:2",
                "jacob:1",
                "soul-jacob:2",
                "soul-jacob:1",
                "forgotten:16",
                "forgotten:17",
                "soul-forgotten:2",
                "soul-forgotten:1",
            }) do
                assert((seen[key] or 0) >= 10, "Missing movement coverage " .. key)
            end
            assert(samples > 500, "Prediction was not exercised")
        end
        native.input_bot(0, 0)
        native.test_gamepad(0)
        finished = true
        report("PASS native multi-actor prediction")
    end
    return s
end
local first, other
local function guest(fn)
    assert(native.rooms_with_player(1, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()["1"])))
    end))
end
native.net_gate = function(capture, apply, collect, restore, present, beginFloor)
    return gate(
        capture,
        function(t, n, b)
            apply(t, n, b)
            if not host then
                return
            end
            if t == 0 then
                first = Game():GetLevel():GetCurrentRoomIndex()
                for i = 0, Game():GetLevel():GetRooms().Size - 1 do
                    local desc = Game():GetLevel():GetRooms():Get(i)
                    if desc.SafeGridIndex ~= first and desc.Data.Type == RoomType.ROOM_DEFAULT then
                        other = desc.SafeGridIndex
                        break
                    end
                end
                assert(other)
            end
            if t == 330 or t == 1320 then
                guest(function(p)
                    p:ChangePlayerType(PlayerType.PLAYER_ISAAC)
                    p:UseCard(
                        t == 330 and Card.CARD_SOUL_JACOB or Card.CARD_SOUL_FORGOTTEN,
                        UseFlag.USE_NOANIM
                    )
                end)
            elseif t == 750 then
                guest(function(p)
                    p:ChangePlayerType(PlayerType.PLAYER_THEFORGOTTEN)
                end)
            elseif t == 690 or t == 1670 then
                assert(native.rooms_move(1, t == 690 and other or first, 0, -1))
            end
            if t % 120 == 0 then
                guest(function()
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:ToNPC() and e:IsActiveEnemy(false) then
                            e:Remove()
                        end
                    end
                end)
            end
        end,
        collect,
        restore,
        function(input, sequence)
            steps = {}
            present(input, sequence)
            if verified < 60 or verified > 1690 then
                return
            end
            local expected, moving, types = {}, 0, {}
            guest(function()
                for i = 0, Game():GetNumPlayers() - 1 do
                    local p = Isaac.GetPlayer(i)
                    if p.ControllerIndex == 2 then
                        local d = p.ControlsEnabled
                                and p:AreControlsEnabled()
                                and p:IsExtraAnimationFinished()
                                and p:GetMovementInput()
                            or Vector.Zero
                        if d:Length() > 1 then
                            d = d:Normalized()
                        end
                        expected[#expected + 1] = d
                        moving = moving + (d:Length() > 0.1 and 1 or 0)
                        types[p:GetPlayerType()] = true
                    end
                end
            end)
            assert(#steps == #expected, "A controlled body did not enter prediction")
            for _, d in ipairs(steps) do
                local matched
                for i, target in ipairs(expected) do
                    if (d - target):Length() < 0.001 then
                        matched = i
                        break
                    end
                end
                assert(matched, "Prediction ignored native per-body movement")
                table.remove(expected, matched)
            end
            samples = samples + 1
            local name = phase(verified)
            local key = name .. ":" .. moving
            seen[key] = (seen[key] or 0) + 1
            if name == "forgotten" then
                for kind in pairs(types) do
                    key = name .. ":" .. kind
                    seen[key] = (seen[key] or 0) + 1
                end
            end
            if samples % 120 == 0 then
                report("SAMPLE phase=" .. name .. " moving=" .. moving .. " bodies=" .. #steps)
            end
        end,
        beginFloor
    )
end
