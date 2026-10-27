-- Chat travel owns target selection and the short-lived arrival transaction.
-- Room allocation, follower migration and native entry remain in the backend.
return function(deps)
    local native, rooms, shapes = deps.native, deps.enums.room, deps.enums.shape
    local mapWidth, arrivalTimeout, listingColumns = 13, 3000, 4
    local pending = {}
    local service = {}
    local definitions = {
        { enum = "ROOM_DEFAULT", name = "普通房" },
        { enum = "ROOM_SHOP", name = "商店", aliases = { "shop", "sh" } },
        { enum = "ROOM_ERROR", name = "错误房", aliases = { "error", "e" } },
        { enum = "ROOM_TREASURE", name = "宝箱房", aliases = { "treasure", "t" } },
        { enum = "ROOM_BOSS", name = "Boss房", aliases = { "boss", "b" } },
        { enum = "ROOM_MINIBOSS", name = "小Boss房" },
        { enum = "ROOM_SECRET", name = "一秘", aliases = { "secret", "s" } },
        { enum = "ROOM_SUPERSECRET", name = "二秘", aliases = { "supersecret", "ss" } },
        { enum = "ROOM_ARCADE", name = "赌博房" },
        { enum = "ROOM_CURSE", name = "诅咒房" },
        { enum = "ROOM_CHALLENGE", name = "挑战房" },
        { enum = "ROOM_LIBRARY", name = "图书馆" },
        { enum = "ROOM_SACRIFICE", name = "献祭房" },
        { enum = "ROOM_DEVIL", name = "恶魔房", aliases = { "devil", "d" } },
        { enum = "ROOM_ANGEL", name = "天使房", aliases = { "angel", "a" } },
        { enum = "ROOM_DUNGEON", name = "地下室" },
        { enum = "ROOM_BOSSRUSH", name = "Boss Rush" },
        { enum = "ROOM_ISAACS", name = "干净卧室" },
        { enum = "ROOM_BARREN", name = "脏卧室" },
        { enum = "ROOM_CHEST", name = "宝库" },
        { enum = "ROOM_DICE", name = "骰子房" },
        { enum = "ROOM_BLACK_MARKET", name = "黑市" },
        { enum = "ROOM_GREED_EXIT", name = "贪婪出口" },
        { enum = "ROOM_PLANETARIUM", name = "星象房" },
        { enum = "ROOM_TELEPORTER", name = "传送房" },
        { enum = "ROOM_TELEPORTER_EXIT", name = "传送出口" },
        { enum = "ROOM_SECRET_EXIT", name = "隐藏出口" },
        { enum = "ROOM_BLUE", name = "蓝色房间" },
        { enum = "ROOM_ULTRASECRET", name = "红隐", aliases = { "ultrasecret", "us" } },
    }
    local names, aliases = {}, {}
    for _, definition in ipairs(definitions) do
        local kind = rooms[definition.enum]
        if kind then
            names[kind] = definition.name
            for _, alias in ipairs(definition.aliases or {}) do
                aliases[alias] = kind
            end
        end
    end
    local footprints = {
        [shapes.ROOMSHAPE_1x1] = { { 0, 0 } },
        [shapes.ROOMSHAPE_IH] = { { 0, 0 } },
        [shapes.ROOMSHAPE_IV] = { { 0, 0 } },
        [shapes.ROOMSHAPE_1x2] = { { 0, 0 }, { 0, 1 } },
        [shapes.ROOMSHAPE_IIV] = { { 0, 0 }, { 0, 1 } },
        [shapes.ROOMSHAPE_2x1] = { { 0, 0 }, { 1, 0 } },
        [shapes.ROOMSHAPE_IIH] = { { 0, 0 }, { 1, 0 } },
        [shapes.ROOMSHAPE_2x2] = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } },
        [shapes.ROOMSHAPE_LTL] = { { 1, 0 }, { 0, 1 }, { 1, 1 } },
        [shapes.ROOMSHAPE_LTR] = { { 0, 0 }, { 0, 1 }, { 1, 1 } },
        [shapes.ROOMSHAPE_LBL] = { { 0, 0 }, { 1, 0 }, { 1, 1 } },
        [shapes.ROOMSHAPE_LBR] = { { 0, 0 }, { 1, 0 }, { 0, 1 } },
    }
    local usage = "用法：/tp r x y（右、上为正）；/tp 2p；/tp l；/tp help"
    function service.parse(text)
        local args = {}
        for arg in text:lower():gmatch("%S+") do
            args[#args + 1] = arg
        end
        if #args == 0 or #args == 1 and (args[1] == "help" or args[1] == "h") then
            return { kind = "help" }
        end
        if args[1] == "r" or args[1] == "room" then
            if #args == 3 and args[2]:match("^[+-]?%d+$") and args[3]:match("^[+-]?%d+$") then
                local x, y = tonumber(args[2]), tonumber(args[3])
                if x and y and math.abs(x) < mapWidth and math.abs(y) < mapWidth then
                    return { kind = "room", x = math.tointeger(x), y = math.tointeger(y) }
                end
            end
            return nil, "坐标无效；用法：/tp r x y（右、上为正）"
        end
        if #args ~= 1 then
            return nil, usage
        end
        local player = args[1]:match("^([1-4])p$")
        if player then
            return { kind = "player", slot = tonumber(player) - 1 }
        end
        if args[1] == "list" or args[1] == "l" then
            return { kind = "list" }
        end
        if args[1] == "start" or args[1] == "st" then
            return { kind = "room", x = 0, y = 0 }
        end
        if aliases[args[1]] then
            return { kind = "type", roomType = aliases[args[1]] }
        end
        return nil, usage
    end
    function service.help()
        local lines = { usage, "起始房坐标为 (0, 0)；仅传送本层已生成的房间。" }
        lines[#lines + 1] = "start/st：起始房；list/l：房间列表"
        for _, definition in ipairs(definitions) do
            if definition.aliases then
                lines[#lines + 1] = table.concat(definition.aliases, "/")
                    .. "："
                    .. definition.name
            end
        end
        return table.concat(lines, "\n")
    end
    local function connected(info, slot)
        return slot >= 0 and slot < info.players and (info.connected & (1 << slot)) ~= 0
    end
    local function sameRoom(a, b)
        return a and b and a.index == b.index and a.dimension == b.dimension
    end
    local function inspect(slot, fn)
        local result
        if
            native.api_with_owner(slot, function()
                result = fn(deps.game(), deps.player(0))
            end)
        then
            return result
        end
    end
    local function catalog(level, dimension)
        local list, cells, seen = {}, {}, {}
        local descriptors = level:GetRooms()
        local function add(desc)
            if not desc or not desc.Data or seen[desc.ListIndex] then
                return
            end
            seen[desc.ListIndex] = true
            local index = desc.SafeGridIndex
            local entry = {
                index = index,
                dimension = index < 0 and 0 or dimension,
                roomType = desc.Data.Type,
                visited = desc.VisitedCount > 0,
                clear = desc.Clear,
            }
            list[#list + 1] = entry
            if index >= 0 then
                local left, top = desc.GridIndex % mapWidth, desc.GridIndex // mapWidth
                for _, offset in ipairs(footprints[desc.Data.Shape] or {}) do
                    local x, y = left + offset[1], top + offset[2]
                    if x >= 0 and x < mapWidth and y >= 0 and y < mapWidth then
                        cells[y * mapWidth + x] = entry
                    end
                end
            end
        end
        for i = 0, descriptors.Size - 1 do
            local desc = descriptors:Get(i)
            if desc.Data then
                local actual = level:GetRoomByIdx(desc.SafeGridIndex, dimension)
                if actual and actual.Data and deps.hash(actual) == deps.hash(desc) then
                    add(desc)
                end
            end
        end
        -- These generated off-map rooms are addressable even if GetRooms omits them.
        for _, index in ipairs({ deps.enums.grid.ROOM_DEVIL_IDX, deps.enums.grid.ROOM_ERROR_IDX }) do
            add(level:GetRoomByIdx(index, dimension))
        end
        table.sort(list, function(a, b)
            return a.index < b.index
        end)
        return list, cells
    end
    local function describe(entry, origin)
        local name = names[entry.roomType] or "特殊房间"
        if entry.index < 0 then
            return name .. "（地图外）"
        end
        return string.format(
            "%s (%d, %d)",
            name,
            entry.index % mapWidth - origin % mapWidth,
            origin // mapWidth - entry.index // mapWidth
        )
    end
    local function listing(list, origin)
        local lines, row = {}, {}
        for _, entry in ipairs(list) do
            row[#row + 1] = describe(entry, origin)
                .. (
                    not entry.visited and " 未探索"
                    or entry.clear and " 已清理"
                    or " 已探索"
                )
            if #row == listingColumns then
                lines[#lines + 1], row = table.concat(row, "；"), {}
            end
        end
        if #row > 0 then
            lines[#lines + 1] = table.concat(row, "；")
        end
        return table.concat(lines, "\n")
    end
    local function cancel(slot, task)
        local info = native.api_info()
        if info.authority == 1 and info.runId == task.run and info.worldEpoch == task.epoch then
            native.api_cancel_move(slot, task.destination.index, task.destination.dimension)
        end
        pending[slot] = nil
    end
    local placeNear = deps.placeNear
    local function playerTarget(slot)
        local position = native.rooms_positions()[tostring(slot)]
        if not position then
            return nil
        end
        return inspect(slot, function(_, player)
            return {
                index = position.index,
                dimension = position.dimension,
                identity = deps.hash(player),
                x = player.Position.X,
                y = player.Position.Y,
            }
        end)
    end
    function service.execute(slot, selection)
        if selection.kind == "help" then
            return service.help()
        end
        local info = native.api_info()
        if info.authority ~= 1 or info.ready ~= 1 or not connected(info, slot) then
            return "传送未执行：游戏尚未就绪"
        end
        if pending[slot] then
            return "传送尚未完成"
        end
        local source = playerTarget(slot)
        if not source then
            return "传送未执行：角色不可用"
        end
        local destination, label, target
        if selection.kind == "player" then
            if selection.slot == slot then
                return "已经在自己身边"
            end
            if connected(info, selection.slot) then
                target = playerTarget(selection.slot)
            end
            if not target then
                return "目标玩家不在线或角色不可用"
            end
            destination, label = target, (selection.slot + 1) .. "P 身边"
        else
            local result = inspect(slot, function(game)
                local level = game:GetLevel()
                local origin = level:GetStartingRoomIndex()
                local list, cells = catalog(level, source.dimension)
                if selection.kind == "list" then
                    return { text = listing(list, origin) }
                end
                local matches = {}
                if selection.kind == "room" then
                    local x, y = origin % mapWidth + selection.x, origin // mapWidth - selection.y
                    local entry = x >= 0
                        and x < mapWidth
                        and y >= 0
                        and y < mapWidth
                        and cells[y * mapWidth + x]
                    if not entry then
                        return { text = "该坐标没有已生成的房间" }
                    end
                    matches[1] = entry
                else
                    for _, entry in ipairs(list) do
                        if entry.roomType == selection.roomType then
                            matches[#matches + 1] = entry
                        end
                    end
                end
                if #matches == 0 then
                    return {
                        text = "本层尚未生成" .. (names[selection.roomType] or "该房间"),
                    }
                elseif #matches > 1 then
                    return {
                        text = "存在多个目标，请用 /tp r x y 选择：\n"
                            .. listing(matches, origin),
                    }
                end
                return { destination = matches[1], label = describe(matches[1], origin) }
            end)
            if not result then
                return "传送未执行：角色不可用"
            end
            if result.text then
                return result.text
            end
            destination, label = result.destination, result.label
        end
        if sameRoom(source, destination) then
            if not target then
                return "已在" .. label
            end
            return placeNear(slot, target) and "已传送至 " .. label
                or "目标附近没有可站立位置"
        end
        if not native.rooms_teleport(slot, destination.index, destination.dimension) then
            return "传送未执行：目标房间不可用"
        end
        pending[slot] = {
            run = info.runId,
            epoch = info.worldEpoch,
            started = info.nowMs,
            source = source,
            destination = destination,
            targetSlot = selection.kind == "player" and selection.slot or nil,
            targetIdentity = target and target.identity,
            label = label,
        }
        return ""
    end
    local function arrival(slot, task, info)
        local position = playerTarget(slot)
        local target = task.targetSlot
            and connected(info, task.targetSlot)
            and playerTarget(task.targetSlot)
        if not position or position.identity ~= task.source.identity then
            return "传送已取消：角色已变化"
        elseif
            task.targetSlot
            and (
                not target
                or target.identity ~= task.targetIdentity
                or not sameRoom(target, task.destination)
            )
        then
            return "传送已取消：目标玩家已离开"
        elseif sameRoom(position, task.destination) then
            return (not target or placeNear(slot, target)) and "已传送至 " .. task.label
                or "已到达目标房间，但没有可站立位置"
        elseif not sameRoom(position, task.source) then
            return "传送已取消：所在房间已变化"
        elseif info.nowMs - task.started >= arrivalTimeout then
            return "传送未完成，请重试"
        end
    end
    function service.step()
        if not next(pending) then
            return
        end
        local info = native.api_info()
        for slot, task in pairs(pending) do
            local message
            if info.authority ~= 1 or info.runId ~= task.run or info.worldEpoch ~= task.epoch then
                pending[slot] = nil
                message = "传送已取消：局次或楼层已变化"
            elseif info.ready ~= 1 or not connected(info, slot) then
                cancel(slot, task)
                message = "传送已取消：角色不可用"
            else
                local ok, result = pcall(arrival, slot, task, info)
                message = ok and result or nil
                if not ok then
                    message = "传送已取消：无法读取角色或房间状态"
                end
                if message then
                    cancel(slot, task)
                end
            end
            if message then
                deps.output(message, { owner = slot })
            end
        end
    end
    function service.reset()
        for slot, task in pairs(pending) do
            cancel(slot, task)
        end
    end
    return service
end
