-- Personal discovery is independent of the floor's authoritative room state.
-- Native visibility runs with one owner and a borrowed copy of their map flags.
return function(deps)
    local Map = deps.fields.map
    local personal, effects, stack = {}, {}, {}
    local F = deps.levelFlags
    local flags = {
        F.STATE_COMPASS_EFFECT,
        F.STATE_MAP_EFFECT,
        F.STATE_BLUE_MAP_EFFECT,
        F.STATE_FULL_MAP_EFFECT,
    }
    local function descriptors()
        local result, level = {}, deps.game():GetLevel()
        local rooms = level:GetRooms()
        for index = 0, rooms.Size - 1 do
            local room = rooms:Get(index)
            if room.Data then
                for dimension = 0, 2 do
                    local match = level:GetRoomByIdx(room.SafeGridIndex, dimension)
                    if match and match.Data and match.ListIndex == room.ListIndex then
                        result[#result + 1] = {
                            room = match,
                            key = dimension .. ":" .. room.SafeGridIndex,
                        }
                        break
                    end
                end
            end
        end
        return result
    end
    local function swap(values, visits)
        local saved = {}
        for _, entry in ipairs(descriptors()) do
            local room = entry.room
            saved[entry.key] = { room.DisplayFlags, room.VisitedCount }
            local own = values[entry.key] or { 0, 0 }
            room.DisplayFlags = own[1]
            if visits then
                room.VisitedCount = own[2]
            end
        end
        return saved
    end
    local function levelState(value)
        local level = deps.game():GetLevel()
        local previous = { everything = level:GetCanSeeEverything() }
        for _, flag in ipairs(flags) do
            previous[flag] = level:GetStateFlag(flag)
        end
        if value then
            for _, flag in ipairs(flags) do
                level:SetStateFlag(flag, value[flag] or false)
            end
            level:SetCanSeeEverything(value.everything or false)
        end
        return previous
    end
    local function borrow(slot, visits)
        return {
            slot = slot,
            visits = visits,
            map = swap(personal[slot] or {}, visits),
            effects = levelState(effects[slot] or {}),
        }
    end
    local function restore(saved)
        swap(saved.map, saved.visits)
        levelState(saved.effects)
    end
    local function remember(slot, visits)
        local own = personal[slot] or {}
        personal[slot] = own
        for _, entry in ipairs(descriptors()) do
            local previous = own[entry.key]
            own[entry.key] = {
                entry.room.DisplayFlags,
                visits and entry.room.VisitedCount or (previous and previous[2] or 0),
            }
        end
        effects[slot] = levelState()
    end
    local function observe(slot)
        assert(deps.native.rooms_with_player(slot, function()
            local level = deps.game():GetLevel()
            local saved = borrow(slot, true)
            local ok, reason = pcall(function()
                level:GetRoomByIdx(level:GetCurrentRoomIndex()).VisitedCount = 1
                level:UpdateVisibility()
                remember(slot, true)
            end)
            restore(saved)
            if not ok then
                error(reason)
            end
        end, 1))
    end
    local function project(map, slot)
        local result, own = {}, personal[slot] or {}
        for _, entry in ipairs(map) do
            local copy = { table.unpack(entry) }
            local flags = own[entry[Map.dimension] .. ":" .. entry[Map.index]] or { 0, 0 }
            copy[Map.display], copy[Map.visited] = flags[1], flags[2]
            result[#result + 1] = copy
        end
        return result
    end
    local function present(slot, begin, record)
        if begin then
            stack[#stack + 1] = borrow(slot, not record)
        elseif #stack > 0 then
            local saved = table.remove(stack)
            assert(saved.slot == slot, "Personal map owner mismatch")
            if record then
                -- Native player updates include pickups, card/item use and
                -- damage effects. Retain their discovery for that owner only;
                -- gameplay visit counts were never borrowed during the update.
                remember(slot, false)
            end
            restore(saved)
        else
            return
        end
        if not record then
            assert(deps.native.map_refresh())
        end
    end
    return {
        observe = observe,
        project = project,
        present = present,
        reset = function()
            while #stack > 0 do
                restore(table.remove(stack))
            end
            personal, effects = {}, {}
        end,
    }
end
