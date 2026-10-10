-- Rules for the fingerprinted original GoodTrip 1.2.8, independent of its UI.
local bridge, native = _IsaacLanModules["api/public"], _IsaacLan
local authority = { id = "isaac-lan.compat.goodtrip" }
local entrances, previous, epoch = {}, {}, nil
local function roomMap(level, dimension)
    local rooms = {}
    for index = 0, 168 do
        local desc = level:GetRoomByIdx(index, dimension)
        if desc and desc.Data then
            rooms[index] = desc
        end
    end
    return rooms
end
function authority.observe()
    local info = bridge.info()
    if info.authority ~= 1 or info.ready ~= 1 then
        return
    end
    if epoch ~= info.worldEpoch then
        entrances, previous, epoch = {}, {}, info.worldEpoch
    end
    local positions = native.rooms_positions()
    for slot = 0, info.players - 1 do
        if positions[tostring(slot)] then
            native.api_with_owner(slot, function()
                local level, room = Game():GetLevel(), Game():GetRoom()
                local position = positions[tostring(slot)]
                local dimension = position.dimension
                entrances[dimension] = entrances[dimension] or {}
                local known = entrances[dimension]
                local current = level:GetCurrentRoomDesc()
                local prior = previous[slot]
                if prior and prior.dimension == dimension and prior.index ~= current.GridIndex then
                    local old = level:GetRoomByIdx(prior.index, dimension)
                    if
                        old
                        and old.Data
                        and (old.Data.Type == 7 or (old.Data.Type == 8 and Game():IsGreedMode()))
                        and not known[prior.index]
                    then
                        for _, neighbor in ipairs({
                            prior.index + 1,
                            prior.index - 1,
                            prior.index + 13,
                            prior.index - 13,
                        }) do
                            local desc = level:GetRoomByIdx(neighbor, dimension)
                            if desc and desc.Data and desc.ListIndex == current.ListIndex then
                                known[prior.index] = neighbor
                                break
                            end
                        end
                    end
                end
                previous[slot] = { dimension = dimension, index = current.GridIndex }
                if
                    current.Data
                    and (
                        current.Data.Type == 7 or (current.Data.Type == 8 and Game():IsGreedMode())
                    )
                then
                    for doorSlot = 0, 7 do
                        local door = room:GetDoor(doorSlot)
                        if door and door.Desc.Variant == 8 then
                            local target = level:GetRoomByIdx(door.TargetRoomIndex, dimension)
                            if target and target.Data then
                                if door.TargetRoomType == 10 then
                                    known[current.GridIndex] = known[current.GridIndex]
                                        or door.TargetRoomIndex
                                else
                                    known[current.GridIndex] = door.TargetRoomIndex
                                    if target.VisitedCount > 0 then
                                        break
                                    end
                                end
                            end
                        end
                    end
                elseif current.Data and current.Data.Type == 10 then
                    for doorSlot = 0, 7 do
                        local door = room:GetDoor(doorSlot)
                        if door and door.Desc.Variant == 8 and door.TargetRoomType == 7 then
                            known[current.GridIndex] = door.TargetRoomIndex
                            if
                                known[door.TargetRoomIndex]
                                and known[door.TargetRoomIndex] ~= current.GridIndex
                            then
                                break
                            end
                        end
                    end
                end
            end)
        end
    end
end
function authority.install(api)
    local lan = api:RegisterMod(
        { Name = "Isaac LAN GoodTrip authority" },
        { id = authority.id, integrationVersion = 1 }
    )
    local function reject(code)
        return { status = "rejected", code = code }
    end
    local unregister = lan:RegisterAction("travel", {
        version = 1,
        cooldownTicks = 45,
        validate = function(payload)
            return type(payload) == "table"
                and math.type(payload.index) == "integer"
                and payload.index >= 0
                and payload.index < 169
                and math.type(payload.dimension) == "integer"
                and payload.dimension >= 0
                and payload.dimension <= 2
        end,
        execute = function(context, payload)
            local game, player = Game(), context.player
            local level, room = game:GetLevel(), game:GetRoom()
            if player:IsDead() then
                return reject("player_dead")
            end
            if payload.dimension ~= context.room.dimension then
                return reject("dimension_mismatch")
            end
            local rooms = roomMap(level, payload.dimension)
            local source, target = level:GetCurrentRoomDesc(), rooms[payload.index]
            if not source.Data or not rooms[source.SafeGridIndex] or not source.Clear then
                return reject("source_not_clear")
            end
            if level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0 then
                return reject("map_hidden")
            end
            if
                not target
                or target.ListIndex == source.ListIndex
                or target.VisitedCount == 0
                or not target.Clear
            then
                return reject("destination_unavailable")
            end
            if source.Data.Type == 6 or source.Data.Type == 11 then
                local open = false
                for slot = 0, 7 do
                    local door = room:GetDoor(slot)
                    if door and door:IsOpen() then
                        open = true
                    end
                end
                if not open then
                    return reject("source_locked")
                end
            end
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == 867 then
                    return reject("chase_active")
                end
            end
            if source.Data.Name == "Mom" then
                return reject("mom_locked")
            end
            if target.Data.Type == 11 and not target.ChallengeDone then
                local health = player:GetHearts() + player:GetSoulHearts() + player:GetBlackHearts()
                local stage = level:GetStage()
                if stage % 2 == 0 and stage ~= 10 then
                    if health > 2 then
                        return reject("challenge_health")
                    end
                elseif health < player:GetMaxHearts() then
                    return reject("challenge_health")
                end
            end
            local known = entrances[payload.dimension] or {}
            local sourceIndex, destinationIndex = source.GridIndex, payload.index
            local flat = player:HasTrinket(151)
                or player:HasCollectible(276)
                or player:HasCollectible(663)
            local damage, route = 0, {}
            local function safeCurse(index, other)
                return known[index]
                    and (
                        known[index] == other
                        or (known[known[index]] and known[known[index]] ~= index)
                    )
            end
            if not flat then
                if source.Data.Type == 10 and not safeCurse(sourceIndex, destinationIndex) then
                    damage = damage + 1
                elseif
                    target.Data.Type == 10
                    and not player:IsFlying()
                    and not safeCurse(destinationIndex, sourceIndex)
                then
                    damage = damage + 1
                end
            end
            local function intermediate(index)
                local desc = rooms[index]
                if not desc then
                    return false
                end
                if route[#route] ~= desc.SafeGridIndex then
                    route[#route + 1] = desc.SafeGridIndex
                end
                return true
            end
            if source.Data.Type == 7 then
                local entrance = known[sourceIndex]
                if not entrance or not rooms[entrance] then
                    return reject("secret_path_unknown")
                end
                if rooms[entrance].ListIndex == target.ListIndex then
                    destinationIndex = entrance
                elseif not (target.Data.Type == 10 and known[destinationIndex] == sourceIndex) then
                    if rooms[entrance].Data.Type == 10 and not flat then
                        damage = damage + 1
                    end
                    intermediate(entrance)
                end
            end
            if target.Data.Type == 7 and known[destinationIndex] then
                local entrance = known[destinationIndex]
                if not rooms[entrance] then
                    return reject("secret_path_unknown")
                end
                if rooms[entrance].ListIndex == source.ListIndex then
                    if source.Data.Shape > 3 then
                        intermediate(entrance)
                    end
                elseif not (source.Data.Type == 10 and known[sourceIndex] == destinationIndex) then
                    if rooms[entrance].Data.Type == 10 and not player:IsFlying() and not flat then
                        damage = damage + 1
                    end
                    intermediate(entrance)
                end
            end
            intermediate(destinationIndex)
            local index = 1
            local move, code =
                lan:MovePlayer(context, { index = route[index], dimension = payload.dimension })
            if not move then
                return reject(code)
            end
            -- Charge exactly once, after the initial migration has been accepted.
            for _ = 1, damage do
                player:TakeDamage(
                    1,
                    DamageFlag.DAMAGE_CURSED_DOOR | DamageFlag.DAMAGE_NO_PENALTIES,
                    EntityRef(player),
                    0
                )
            end
            if player:IsDead() then
                move.cancel()
                return { status = "cancelled", code = "player_dead" }
            end
            -- Native migration uses an explicit destination, so maze never needs
            -- to be removed globally while another participant is simulating.
            return lan:CreateOperation({
                poll = function()
                    if player:IsDead() then
                        return { status = "cancelled", code = "player_dead" }
                    end
                    local result = move.poll()
                    if not result then
                        return
                    end
                    if result.status ~= "applied" or index == #route then
                        return result
                    end
                    index = index + 1
                    local info = bridge.info()
                    if info.worldEpoch ~= context.worldEpoch then
                        return { status = "cancelled", code = "stale_world" }
                    end
                    local nextMove, nextCode = lan:MovePlayer(
                        context,
                        { index = route[index], dimension = payload.dimension }
                    )
                    if not nextMove then
                        return { status = "unknown", code = nextCode or "route_interrupted" }
                    end
                    move = nextMove
                end,
                cancel = function()
                    if move.cancel then
                        move.cancel()
                    end
                end,
            })
        end,
    })
    return function()
        unregister()
        lan:Unregister()
        entrances, previous, epoch = {}, {}, nil
    end
end
return authority
