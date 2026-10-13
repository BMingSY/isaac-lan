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
        if
            (p.Variant ~= pickup.PICKUP_BIGCHEST and p.Variant ~= pickup.PICKUP_TROPHY)
            or not eligible()
        then
            return
        end
        if p.Variant == pickup.PICKUP_BIGCHEST then
            p:Morph(enums.entity.ENTITY_PICKUP, pickup.PICKUP_TROPHY, 0, true, true, false)
            p.Wait = 30
        end
        -- A native Void portal can appear after the reward is initialized.
        -- Pickup updates run in this reward's room, including remote rooms and
        -- restored trophies. Keep only the trophy as the endpoint's floor exit.
        local room = game():GetRoom()
        for index = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(index)
            if
                grid
                and (
                    grid:GetType() == enums.grid.GRID_TRAPDOOR
                    or grid:GetType() == enums.grid.GRID_STAIRS
                )
            then
                room:RemoveGridEntity(index, 0, false)
            end
        end
        for _, entity in ipairs(deps.entities()) do
            if
                entity:Exists()
                and entity.Type == enums.entity.ENTITY_EFFECT
                and entity.Variant == enums.effect.HEAVEN_LIGHT_DOOR
            then
                entity:Remove()
            end
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
            -- Keep native floor progression, but stop terminal chests before
            -- their collector animation changes the room/session lifecycle.
            if deps.chestEnding() ~= 0 then
                return true
            end
        end,
    }
end
