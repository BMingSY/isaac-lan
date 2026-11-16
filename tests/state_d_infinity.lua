local native, input = assert(_IsaacLan), assert(_IsaacLanTestInput)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local baseFrame, baseGate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished, tick = 0, false, false, false, 0
local observed, floorChecked, checks = {}, false, 0
local dropHeld = false
local focusSetting = Options.PauseOnFocusLost
Options.PauseOnFocusLost = false
local infinity, d6, book =
    CollectibleType.COLLECTIBLE_D_INFINITY,
    CollectibleType.COLLECTIBLE_D6,
    CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL
local function report(text)
    Isaac.DebugString("LAN_NETWORK D_INFINITY " .. text)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end, 1))
end
local function data(player, slot)
    local bytes = assert(native.items_active_data(player:GetSprite()))
    local id, value = string.unpack(">i4i4", bytes, slot * 8 + 1)
    assert(id == player:GetActiveItem(slot), "Active state does not describe its slot")
    return value
end
local function expect(name, id, selected)
    actor(1, function(p)
        local value = data(p, 0)
        assert(
            p:GetActiveItem(0) == id and value >> 16 == selected,
            name .. " id=" .. p:GetActiveItem(0) .. " data=" .. value
        )
        report(
            "CHECK "
                .. name
                .. " id="
                .. id
                .. " data="
                .. value
                .. " charge="
                .. p:GetActiveCharge(0)
        )
    end)
    checks = checks + 1
end
local function give(slot, selected)
    actor(slot, function(p)
        local previous = p:GetActiveItem(0)
        if previous ~= 0 then
            p:RemoveCollectible(previous, true, 0)
        end
        p:AddCollectible(infinity, 12, false, 0, (selected << 16) | 12)
    end)
end
local function step(t)
    if t == 40 then
        give(0, 5)
        give(1, 0)
    elseif t >= 125 and t <= 485 and (t - 125) % 40 == 0 then
        expect("native-drop-" .. ((t - 125) // 40 + 1), infinity, ((t - 125) // 40 + 1) % 10)
        actor(0, function(p)
            assert(data(p, 0) >> 16 == 5, "Guest changed the host's die")
        end)
    elseif t == 560 then
        give(1, 9)
        actor(1, function(p)
            p:AddCollectible(CollectibleType.COLLECTIBLE_SCHOOLBAG, 0, false)
            p:AddCollectible(book, 6, false, 1)
        end)
    elseif t == 625 then
        expect("schoolbag-away", book, 0)
        actor(1, function(p)
            assert(p:GetActiveItem(1) == infinity and data(p, 1) >> 16 == 0)
        end)
    elseif t == 685 then
        expect("schoolbag-back", infinity, 0)
    elseif t == 720 then
        give(1, 7)
        local target
        actor(1, function()
            local door = Game():GetRoom():GetDoor(0)
                or Game():GetRoom():GetDoor(1)
                or Game():GetRoom():GetDoor(2)
                or Game():GetRoom():GetDoor(3)
            target = assert(door).TargetRoomIndex
        end)
        assert(native.rooms_move(1, target, 0, -1))
    elseif t == 800 then
        expect("different-room", infinity, 7)
    elseif t == 840 then
        Game():GetLevel():SetStage(2, 0)
        Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
    elseif t == 1100 then
        assert(floorChecked, "D Infinity floor transition was not verified")
        actor(1, function(p)
            for slot = 0, 3 do
                local id = p:GetActiveItem(slot)
                if id ~= 0 then
                    p:RemoveCollectible(id, true, slot)
                end
            end
            p:AddCollectible(d6, 6, false)
        end)
    elseif t == 1200 then
        expect("replacement", d6, 0)
        finished = true
        report("PASS authority checks=" .. checks)
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = baseFrame()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
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
    native.test_gamepad(0)
    tick = status.verified
    if
        status.phase == 3
        and native.rooms_ready()
        and tick > 900
        and tick < 1100
        and Game():GetLevel():GetStage() == 2
        and not floorChecked
    then
        expect("next-floor", infinity, 7)
        floorChecked = true
    end
    if not host and status.phase == 3 and native.rooms_ready() then
        if tick >= 125 and tick < 500 then
            local cycle = (tick - 125) // 40
            if (tick - 125) % 40 < 10 and not observed[cycle] then
                expect("replica-drop-" .. (cycle + 1), infinity, (cycle + 1) % 10)
                observed[cycle] = true
            end
        elseif tick >= 625 and tick < 640 and not observed.away then
            expect("schoolbag-away", book, 0)
            observed.away = true
        elseif tick >= 685 and tick < 700 and not observed.back then
            expect("schoolbag-back", infinity, 0)
            observed.back = true
        elseif tick >= 800 and tick < 820 and not observed.room then
            expect("different-room", infinity, 7)
            observed.room = true
        elseif tick >= 1200 and not finished then
            expect("replacement", d6, 0)
            assert(floorChecked and observed.away and observed.back and observed.room)
            for cycle = 0, 9 do
                assert(observed[cycle], "Guest missed a die selection")
            end
            finished = true
            report("PASS replica checks=" .. checks)
        end
    end
    return status
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return baseGate(function()
        local drop = not host
            and (
                tick >= 100 and tick < 464 and (tick - 100) % 40 < 4
                or tick >= 600 and tick < 604
                or tick >= 660 and tick < 664
            )
        local mask = 1 << ButtonAction.ACTION_DROP
        local triggered = drop and not dropHeld and mask or 0
        dropHeld = drop
        return input.buttons(drop and mask or 0, triggered)
    end, function(t, ...)
        before(t, ...)
        if host then
            step(t)
        end
    end, collect, restore, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        Options.PauseOnFocusLost = focusSetting
    end,
}
