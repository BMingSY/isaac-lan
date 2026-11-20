-- Collect both rewards from one native co-op Boss pedestal in the reported order.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local frame, gate = _IsaacLanFrame, native.net_gate
local phase = native.net_phases()
local latch = CollectibleType.COLLECTIBLE_LATCH_KEY
local renders, linked, chosen, done = 0, false, false, false
local origin, firstItem, firstTaken, taken
local before, after, moved, pickedKeys
local initialPause, rewardPause, resumeAt, pauseSamples = false, false, nil, 0
local sawBeforePause, sawRewardPause
local function report(message)
    Isaac.DebugString("LAN_NETWORK BOSS_REWARD " .. message)
end
local function player(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
local function sample(label)
    local guest = player(1)
    local state = {
        count = guest:GetCollectibleNum(latch, true),
        luck = guest.Luck,
        souls = guest:GetSoulHearts(),
        keys = guest:GetNumKeys(),
        floorKeys = #Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_KEY),
    }
    report(
        ("%s count=%d luck=%.1f soulHearts=%d keys=%d floorKeys=%d"):format(
            label,
            state.count,
            state.luck,
            state.souls,
            state.keys,
            state.floorKeys
        )
    )
    return state
end
native.net_gate = function(capture, update, collect, restore, present, beginFloor)
    return gate(capture, function(t, ...)
        update(t, ...)
        local p1, p2 = player(0), player(1)
        p1:SetMinDamageCooldown(90)
        p2:SetMinDamageCooldown(90)
        local level = Game():GetLevel()
        if t == 30 then
            level:SetStage(LevelStage.STAGE2_2, StageType.STAGETYPE_ORIGINAL)
            Game():StartStageTransition(true, 0, p1)
        end
        if
            t > 165
            and not origin
            and native.rooms_ready()
            and level:GetStage() == LevelStage.STAGE2_2
        then
            origin = level:GetStartingRoomIndex()
            local list = level:GetRooms()
            for i = 0, list.Size - 1 do
                local d = list:Get(i)
                if d.Data.Type == RoomType.ROOM_BOSS then
                    assert(native.rooms_move(0, d.SafeGridIndex, 0, -1))
                    assert(native.rooms_move(1, d.SafeGridIndex, 0, -1))
                    break
                end
            end
        end
        if
            not origin
            or t < 305
            or Game():IsPaused()
            or Game():GetRoom():GetType() ~= RoomType.ROOM_BOSS
        then
            return
        end
        for _, enemy in ipairs(Isaac.GetRoomEntities()) do
            if enemy:IsActiveEnemy(false) then
                enemy:Kill()
            end
        end
        local center = Game():GetRoom():GetCenterPos()
        if firstItem and not firstTaken and p1:HasCollectible(firstItem, true) then
            firstTaken = t
            p1.Position = center + Vector(-90, 60)
            report("first collected " .. firstItem)
        end
        if not taken and p2:HasCollectible(latch, true) then
            taken = t
            p2.Position = center + Vector(90, 60)
            sample("second collected")
        end
        if not taken then
            for _, e in
                ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE))
            do
                local pickup = e:ToPickup()
                if pickup.SubType > 0 and pickup.Wait <= 0 then
                    if not firstTaken then
                        firstItem = firstItem or pickup.SubType
                        p1.Position, p1.Velocity = pickup.Position, Vector.Zero
                    elseif t < firstTaken + 100 then
                        break
                    elseif not before then
                        if pickup.SubType ~= latch then
                            report(
                                "second native reward " .. pickup.SubType .. " fixed to " .. latch
                            )
                            pickup:Morph(
                                EntityType.ENTITY_PICKUP,
                                PickupVariant.PICKUP_COLLECTIBLE,
                                latch,
                                true
                            )
                        end
                        before = sample("before")
                    else
                        p2.Position, p2.Velocity = pickup.Position, Vector.Zero
                    end
                end
            end
        elseif t >= taken + 25 and not after then
            after = sample("after")
            assert(
                after.count == 1
                    and after.luck == before.luck + 1
                    and after.souls == before.souls + 2
            )
            assert(after.keys == before.keys and after.floorKeys == before.floorKeys + 2)
        elseif after and t >= taken + 115 and not pickedKeys then
            local keys = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_KEY)
            if #keys > 0 then
                p2.Position, p2.Velocity = keys[1].Position, Vector.Zero
            end
            if p2:GetNumKeys() == before.keys + 2 then
                pickedKeys = t
                report("collected both floor keys")
            end
        elseif pickedKeys and t > pickedKeys + 20 and not moved then
            assert(native.rooms_move(1, origin, 0, -1))
            moved = true
        end
    end, collect, restore, present, beginFloor)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (config.host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= phase.failed, s.error)
    if s.phase == phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        config.host
        and s.phase == phase.lobby
        and s.players == 2
        and s.ready0 == 1
        and s.ready1 == 1
    then
        _IsaacLanCommand("start", "RA4P08PL:0:0:0:0:0")
    end
    if s.prepared and s.verified > 180 and native.rooms_ready() and not done then
        if not config.host then
            if
                not initialPause
                and s.verified >= 310
                and Game():GetRoom():GetType() == RoomType.ROOM_BOSS
            then
                initialPause = true
                assert(native.net_command(native.net_commands().pause))
            elseif taken and not rewardPause and s.verified > taken + 27 then
                rewardPause = true
                assert(native.net_command(native.net_commands().pause))
            end
            if Game():IsPaused() and native.pause_menu_state().page == 1 then
                pauseSamples = pauseSamples + 1
                if pauseSamples == 1 then
                    assert(native.pause_menu_state().controller == 2)
                    sawRewardPause = sawRewardPause or rewardPause
                    sawBeforePause = sawBeforePause or not rewardPause
                    report("guest pause " .. (rewardPause and "after" or "before"))
                    resumeAt = renders + 90
                end
                if renders == resumeAt then
                    assert(native.net_command(native.net_commands().resume))
                end
            else
                pauseSamples = 0
            end
            if not taken and player(1):HasCollectible(latch, true) then
                taken = s.verified
                sample("second collected")
            elseif taken and not after and s.verified >= taken + 45 then
                after = sample("after")
                assert(
                    after.luck == 1
                        and after.souls == 2
                        and after.keys == 0
                        and after.floorKeys == 2
                )
            end
            moved = native.rooms_positions()["0"].index ~= native.rooms_positions()["1"].index
        end
        if moved and taken and s.verified >= taken + 145 then
            assert(config.host or (sawBeforePause and sawRewardPause and after))
            assert(
                player(1):GetNumKeys() == 2
                    and player(1):GetSoulHearts() == 2
                    and player(1).Luck == 1
            )
            assert(
                player(1):GetCollectibleNum(latch, true) == 1
                    and not player(0):HasCollectible(latch, true)
            )
            done = true
            report("PASS guest kept second Boss reward")
        end
        assert(
            s.verified < 1500 or done,
            "Second Boss reward was never collected or transfer failed"
        )
    end
    return s
end
return {
    done = function()
        return done
    end,
}
