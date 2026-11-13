-- The host owns generation, contacts and awards. Replicas receive one floor's
-- value data; the runtime stores the complete history with saves and rewinds.
return function(deps)
    local native, rules, enums = deps.native, deps.rules, deps.enums
    local F, S = rules.fields, rules.stateFields
    local model, current, revision, lastFrame, installed, remote
    local flags = {}
    for _, option in ipairs(native.net_room_options()) do
        flags[option.key] = option.flag
    end
    local function reset()
        model, current, revision, lastFrame, installed, remote = nil, nil, nil, nil, nil, nil
    end
    local function persist()
        revision =
            assert(native.net_run_state(deps.encode(model.snapshot())), "Cannot save Jericho state")
    end
    local function restore()
        local bytes, nextRevision = native.net_run_state()
        if nextRevision ~= revision then
            model = rules.new(bytes ~= "" and deps.decode(bytes) or nil)
            revision, current, installed, lastFrame = nextRevision, nil, nil, nil
        end
    end
    local function identity()
        local game = deps.game()
        local level = game:GetLevel()
        return table.concat({
            game:GetSeeds():GetStartSeed(),
            level:GetStage(),
            level:GetStageType(),
            level:GetDungeonPlacementSeed(),
        }, ":"),
            level:GetStage()
    end
    local function supported(info)
        local game, level = deps.game(), deps.game():GetLevel()
        return not game:IsGreedMode()
            and not level:IsAscent()
            and level:GetStage() < enums.stage.STAGE8
            and info.challenge == 0
            and game.Challenge == 0
    end
    local function floor(info)
        restore()
        if not supported(info) then
            current = nil
            return
        end
        local game, level = deps.game(), deps.game():GetLevel()
        local key, depth = identity()
        current = model.find(key)
        if not current then
            current = model.enter(key, depth)
            local random = rules.random(key .. ":jericho")
            if random(rules.maximumChance) <= model.state[S.chance] then
                local pair = deps.map.select(level, random)
                if pair and deps.map.install(level, pair, false) then
                    local pool = game:GetItemPool()
                    local items = {}
                    for side = 1, 2 do
                        items[side] =
                            pool:GetCollectible(enums.pool.POOL_TREASURE, true, random(2147483646))
                    end
                    model.generate(current, pair, items)
                    installed = key
                end
            end
            persist()
        end
        if current[F.first] >= 0 and installed ~= key then
            assert(
                deps.map.install(level, { current[F.first], current[F.second] }, true),
                "Cannot restore Jericho rooms"
            )
            installed = key
        end
        return current
    end
    local function roomSide()
        if not current then
            return
        end
        local level = deps.game():GetLevel()
        local desc = level:GetCurrentRoomDesc()
        local index = desc.SafeGridIndex
        local main = level:GetRoomByIdx(index, 0)
        local dimension = main and main.ListIndex == desc.ListIndex and 0 or 1
        local mirror = level:GetRoomByIdx(index, 1)
        if dimension ~= 0 and (not mirror or mirror.ListIndex ~= desc.ListIndex) then
            return
        end
        return rules.side(current, index), dimension
    end
    local function walls(room, present)
        local center = room:GetCenterPos()
        for _, point in ipairs(deps.layout.walls) do
            local position = center + deps.vector(point[1], point[2])
            local index = room:GetGridIndex(position)
            local grid = room:GetGridEntity(index)
            if present then
                if not grid then
                    room:SpawnGridEntity(
                        index,
                        enums.grid.GRID_PILLAR,
                        0,
                        room:GetDecorationSeed(),
                        0
                    )
                end
            elseif grid and grid:GetType() == enums.grid.GRID_PILLAR then
                room:RemoveGridEntity(index, 0, false)
            end
        end
    end
    local function prepare(side, dimension)
        local room = deps.game():GetRoom()
        if dimension ~= 0 then
            return
        end -- The mirror's empty template is the ruin.
        local mask = 1 << (side - 1)
        if not current[F.complete] then
            walls(room, true)
            if current[F.prepared] & mask == 0 then
                current[F.prepared] = current[F.prepared] | mask
                persist()
            end
        elseif current[F.released] & mask == 0 then
            walls(room, false)
            local item = side == 1 and current[F.firstItem] or current[F.secondItem]
            local pickup = deps.spawn(
                enums.entity.ENTITY_PICKUP,
                enums.pickup.PICKUP_COLLECTIBLE,
                item,
                room:GetCenterPos(),
                deps.vector(0, 0),
                nil
            ):ToPickup()
            pickup.Wait = 15
            current[F.released] = current[F.released] | mask
            persist()
        end
    end
    local function entered()
        local info = native.api_info()
        if info.active ~= 1 or info.authority ~= 1 or not model or not supported(info) then
            return
        end
        -- A native rewind can restore the payload before Lua sees another tick.
        restore()
        current = model.find(identity())
        local side, dimension = roomSide()
        if side then
            prepare(side, dimension)
        end
    end
    local function step()
        local info = native.api_info()
        if info.active ~= 1 or info.authority ~= 1 or info.ready ~= 1 or info.challenge ~= 0 then
            return
        end
        local game = deps.game()
        if game:IsPaused() then
            return
        end
        restore()
        local frame = game:GetFrameCount()
        if lastFrame == frame then
            return
        end
        lastFrame = frame
        local value = floor(info)
        if not value or value[F.first] < 0 then
            return
        end
        local positions, contacts, owners = native.rooms_positions(), {}, { {}, {} }
        for _, seat in ipairs(deps.party(info)) do
            local position = positions[tostring(seat.slot)]
            local side = position and position.dimension == 0 and rules.side(value, position.index)
            if side then
                owners[side][seat.slot] = true
                deps.scoped(seat, function()
                    prepare(side, 0)
                    local room = game:GetRoom()
                    local center = room:GetCenterPos()
                    local contact = { slot = seat.slot, side = side }
                    for _, player in ipairs(seat.actors) do
                        local offset, shot = player.Position - center, player:GetShootingInput()
                        local plate, horn =
                            deps.layout.contact(offset.X, offset.Y, shot.X, shot.Y, side)
                        contact.plate = contact.plate or plate
                        contact.horn = contact.horn or horn
                    end
                    contacts[#contacts + 1] = contact
                end)
            end
        end
        local event = model.step(value, contacts)
        if event then
            persist()
            for _, seat in ipairs(deps.party(info)) do
                if owners[1][seat.slot] or owners[2][seat.slot] then
                    deps.scoped(seat, function()
                        deps.sound(event)
                    end)
                end
            end
        end
        if value[F.complete] then
            local shared = info.roomOptions & flags.sharedClearCharge ~= 0
            for side = 1, 2 do
                local mask = 1 << (side - 1)
                if value[F.charged] & mask == 0 then
                    local recipients = not shared and owners[side] or nil
                    deps.charge.award(info, recipients, 1)
                    value[F.charged] = value[F.charged] | mask
                    persist()
                end
            end
        end
    end
    local function snapshot()
        return current and current[F.first] >= 0 and { table.unpack(current) } or false
    end
    return {
        reset = reset,
        restore = restore,
        entered = entered,
        step = step,
        snapshot = snapshot,
        level = function()
            current, installed, lastFrame = nil, nil, nil
        end,
        resume = function()
            local info = native.api_info()
            if info.authority == 1 and info.challenge == 0 then
                floor(info)
            end
        end,
        apply = function(value)
            remote = value
                    and rules.read({
                        rules.version,
                        rules.repeatChance,
                        true,
                        value[F.depth],
                        { value },
                    })[S.floors][1]
                or nil
        end,
        view = function()
            local info = native.api_info()
            return info.authority == 1 and snapshot() or remote
        end,
        separate = function(position)
            return current
                and position
                and position.dimension == 0
                and rules.side(current, position.index) ~= nil
        end,
    }
end
