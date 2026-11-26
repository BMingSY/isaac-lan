-- One host and four to seven independent clients. Each client sends its own
-- actions through the normal transport, including pairs sharing a native pad.
local native, config, input = _IsaacLan, _IsaacLanTest, _IsaacLanTestInput
local phase = native.net_phases()
local count = config.players
assert(count > 4 and count <= native.max_players)
local memberMask = (1 << count) - 1
local owner = { Name = "LAN expanded party regression" }
local item = CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL
local marker = CollectibleType.COLLECTIBLE_BREAKFAST
local starts, shots, uses = {}, {}, {}
local slot, tick, renders = -1, -1, 0
local linked, chosen, started, actionsChecked, roomChecked, floorRequested, finished
local function report(message)
    Isaac.DebugString("LAN_NETWORK " .. message)
end
local function left(seat)
    return (seat < 4) == (seat % 2 == 0)
end
local function player(seat)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(seat)]))
end
Isaac.AddCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
    local p = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if config.host and p and tick >= 110 and tick < 210 then
        local seat = native.player_owner(p) - 1
        shots[seat] = (shots[seat] or 0) + 1
    end
end)
Isaac.AddCallback(owner, ModCallbacks.MC_USE_ITEM, function(_, _, _, p)
    if config.host and tick >= 110 and tick < 210 then
        local seat = native.player_owner(p) - 1
        uses[seat] = (uses[seat] or 0) + 1
    end
end, item)
local leaving, departed, sawMissing = false, false, false
Isaac.AddCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, function()
    if leaving and not departed then
        departed, linked, chosen, renders = true, false, false, 0
    end
end)
local previous = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (departed and 120 or config.host and 240 or 320) then
        linked = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        report("MENU_READY")
    end
    local status = previous()
    slot, tick = status.slot, status.verified or -1
    assert(status.phase ~= phase.failed, status.error)
    if status.phase == phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if config.host and status.phase == phase.lobby and status.players == count and not started then
        local ready = true
        for i = 0, count - 1 do
            ready = ready and status["ready" .. i] == 1
        end
        if ready then
            started = true
            _IsaacLanCommand("start", "YV039KQF:0" .. string.rep(":0", count))
        end
    end
    if status.prepared and tick > 350 and Game():GetLevel():GetStage() == 2 then
        if slot == count - 1 and not leaving and tick >= 390 then
            leaving = true
            assert(native.net_command(native.net_commands().leave))
            report("LEAVE slot=" .. slot)
        elseif status.connected == (memberMask >> 1) then
            sawMissing = true
        end
    end
    if
        status.prepared
        and not finished
        and tick >= 520
        and status.connected == memberMask
        and native.rooms_ready()
        and native.rooms_connected() == memberMask
        and Game():GetLevel():GetStage() == 2
        and (slot == count - 1 and departed or slot ~= count - 1 and sawMissing)
    then
        assert(status.connected == memberMask and status.players == count)
        for seat = 0, count - 1 do
            local p = player(seat)
            assert(
                native.player_owner(p) == seat + 1,
                "Seat lost its player after the floor change"
            )
            assert(
                p:GetCollectibleNum(marker, true) == seat + 1,
                "Wrong inventory for P" .. (seat + 1) .. ": " .. p:GetCollectibleNum(marker, true)
            )
        end
        local panels = native.presentation_player_huds()
        if panels[tostring(slot)] then
            local visible = 0
            for _ in pairs(panels) do
                visible = visible + 1
            end
            assert(visible == 1, "A teammate's HUD is visible")
            assert(not config.host or (actionsChecked and roomChecked))
            finished = true
            report("PASS independent LAN seats slot=" .. slot .. " members=" .. status.connected)
        end
    end
    return status
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    local previousButtons = 0
    return gate(function()
        local buttons = 0
        if tick >= 120 and tick < 150 then
            local move = left(slot) and ButtonAction.ACTION_LEFT or ButtonAction.ACTION_RIGHT
            local shoot = left(slot) and ButtonAction.ACTION_SHOOTLEFT
                or ButtonAction.ACTION_SHOOTRIGHT
            buttons = (1 << move) | (1 << shoot)
        end
        if (slot == 0 or slot == count - 1) and tick >= 165 and tick < 174 then
            buttons = buttons | (1 << ButtonAction.ACTION_ITEM)
        end
        local sample = input.buttons(buttons, buttons & ~previousButtons)
        previousButtons = buttons
        return sample
    end, function(t, n, bytes)
        before(t, n, bytes)
        if t == 65 then
            for seat = 0, count - 1 do
                local p = player(seat)
                assert(native.player_owner(p) == seat + 1)
                for _ = 1, seat + 1 do
                    p:AddCollectible(marker, 0, false)
                end
                p:AddCollectible(item, 3, false)
                p:SetActiveCharge(3)
                p:SetMinDamageCooldown(10000)
                p.Position = Game():GetRoom():GetCenterPos() + Vector(0, (seat % 4) * 12 - 36)
                p.Velocity = Vector.Zero
                starts[seat] = p.Position.X
            end
        elseif t == 210 then
            for seat = 0, count - 1 do
                local dx = player(seat).Position.X - starts[seat]
                report(
                    string.format(
                        "SEAT %d movement=%.1f tears=%d uses=%d",
                        seat + 1,
                        dx,
                        shots[seat] or 0,
                        uses[seat] or 0
                    )
                )
                assert(left(seat) and dx < -8 or not left(seat) and dx > 8, "Wrong movement owner")
                assert((shots[seat] or 0) > 0, "Missing player's shot")
                assert(
                    (uses[seat] or 0) == ((seat == 0 or seat == count - 1) and 1 or 0),
                    "Wrong active item owner"
                )
            end
            actionsChecked = true
            local level = Game():GetLevel()
            for i = 0, level:GetRooms().Size - 1 do
                local room = level:GetRooms():Get(i)
                if
                    room.SafeGridIndex ~= level:GetCurrentRoomIndex()
                    and room.Data.Type == RoomType.ROOM_DEFAULT
                then
                    assert(native.rooms_move(count - 1, room.SafeGridIndex, 0, 0))
                    break
                end
            end
        elseif t == 242 then
            local locations = native.rooms_positions()
            assert(
                locations[tostring(count - 1)].index ~= locations["0"].index,
                "Last seat did not travel independently"
            )
            roomChecked = true
        elseif t == 280 and not floorRequested then
            floorRequested = true
            assert(native.rooms_with_player(0, function()
                Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
            end))
        end
    end, collect, restore, present, beginFloor)
end
