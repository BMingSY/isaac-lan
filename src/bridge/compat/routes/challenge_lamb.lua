-- Authority-only route and reward policy. State lives in the native room and
-- pickup, so checkpoints and hourglass restores carry the same objective.
return function(deps)
    local game, enums = deps.game, deps.enums
    local pickup = enums.pickup
    local function lambRoom()
        local level = game():GetLevel()
        if
            level:GetStage() ~= enums.stage.STAGE6
            or level:GetStageType() ~= enums.stageType.STAGETYPE_ORIGINAL
        then
            return false
        end
        local data = level:GetCurrentRoomDesc().Data
        if not data or data.Type ~= enums.room.ROOM_BOSS then
            return false
        end
        for i = 0, data.SpawnCount - 1 do
            local spawn = data.Spawns:Get(i)
            for j = 0, spawn.EntryCount - 1 do
                if spawn.Entries:Get(j).Type == enums.entity.ENTITY_THE_LAMB then
                    return true
                end
            end
        end
        return false
    end
    local function eligible()
        return lambRoom() and game():GetRoom():IsClear()
    end
    local function reward(p)
        if p.Variant == pickup.PICKUP_BIGCHEST and eligible() then
            p:Morph(enums.entity.ENTITY_PICKUP, pickup.PICKUP_TROPHY, 0, true, true, false)
            p.Wait = 30
        end
    end
    return {
        handles = function(p)
            return p.Variant == pickup.PICKUP_TROPHY or p.Variant == pickup.PICKUP_BIGCHEST
        end,
        pickup = reward,
        collide = function(p, player)
            if p.Variant == pickup.PICKUP_TROPHY then
                if
                    eligible()
                    and p.Wait <= 0
                    and not player:IsCoopGhost()
                    and not player:IsDead()
                then
                    assert(deps.finish(), "Challenge completion was rejected")
                end
                -- Never execute native trophy code with an unregistered Challenge ID.
                return true
            end
            if p.Variant ~= pickup.PICKUP_BIGCHEST then
                return
            end
            if lambRoom() then
                reward(p)
                return true
            end
            -- Ordinary progression may stop at Mom/Heart/Satan on this save.
            -- A challenge goal must remain reachable without granting inventory.
            local level = game():GetLevel()
            local stage = level:GetStage()
            local target
            if stage == enums.stage.STAGE3_2 then
                target = enums.stage.STAGE4_1
            elseif stage == enums.stage.STAGE4_2 or stage == enums.stage.STAGE4_3 then
                target = enums.stage.STAGE5
            elseif stage == enums.stage.STAGE5 then
                target = enums.stage.STAGE6
            end
            if target and p.Wait <= 0 and not player:IsCoopGhost() and not player:IsDead() then
                level:SetStage(target, enums.stageType.STAGETYPE_ORIGINAL)
                game():StartStageTransition(true, 0, player)
            end
            return true
        end,
        onEnding = function()
            -- An optional terminal route (e.g. Mega Satan/Beast) cannot win this
            -- challenge or strand the party after its native exit is intercepted.
            game():GetLevel():SetStage(enums.stage.STAGE6, enums.stageType.STAGETYPE_ORIGINAL)
            game():StartStageTransition(true, 0)
        end,
        level = function()
            local level = game():GetLevel()
            local stage = level:GetStage()
            -- The final two ordinary floors follow Sheol -> Dark Room.
            if
                (stage == enums.stage.STAGE5 or stage == enums.stage.STAGE6)
                and level:GetStageType() == enums.stageType.STAGETYPE_WOTL
            then
                level:SetStage(stage, enums.stageType.STAGETYPE_ORIGINAL)
                game():StartStageTransition(true, 0)
            end
        end,
    }
end
