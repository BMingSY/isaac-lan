local api, wrapping = assert(IsaacLAN), _IsaacLanModules["compat/mods/wrapping"]
local debug = (_IsaacLan and _IsaacLan.debug) or debug
local authority = _IsaacLanModules["compat/mods/goodtrip/authority"]
local definition = {
    id = authority.id,
    adapterVersion = 1,
    modName = "goodtrip",
    authority = authority.install,
    targets = {
        {
            workshopId = "1630477831",
        },
    },
}
function definition.probe(target)
    if rawget(_G, "gt") ~= target.mod then
        return "pending", "exports_not_ready"
    end
    for _, name in ipairs({
        "teleport_to_grid_index",
        "prep",
        "new_room",
        "new_level",
        "step",
        "tab_action",
    }) do
        if type(target.mod[name]) ~= "function" then
            return "pending", "entry_points_not_ready"
        end
    end
    return "ready"
end
function definition.install(target)
    local cleanups, gt = {}, target.mod
    target.addCleanup(function()
        wrapping.cleanup(cleanups)
    end)
    -- UI and authority share the built-in action namespace, on either peer.
    local lan = assert(authority.integration)
    local travel = lan:Action("travel")
    local pending, initialized = nil, false
    local playerIndex
    for i = 1, 64 do
        local name = debug.getupvalue(gt.step, i)
        if not name then
            break
        end
        if name == "player" then
            playerIndex = i
            break
        end
    end
    assert(playerIndex, "missing_goodtrip_player_cache")
    target.preparePlayer = function(localView)
        local expected = localView and lan:GetLocalPlayers()[1] or Isaac.GetPlayer(0)
        if not expected then
            return false
        end
        local _, cached = debug.getupvalue(gt.step, playerIndex)
        if not cached or GetPtrHash(cached) ~= GetPtrHash(expected) then
            -- Loading may overwrite the native upvalue after the lifecycle
            -- notification. Repair it in the committed local view before UI
            -- callbacks use it; leave valid minimap caches untouched.
            gt:prep()
        end
        return true
    end
    wrapping.patch(cleanups, gt, "teleport_to_grid_index", function(original)
        return function(self, index)
            if not lan:IsActive() then
                return original(self, index)
            end
            if pending and pending.status == "pending" or not lan:IsReady() then
                return
            end
            local room = lan:GetLocalRoom()
            pending = travel:Request({ index = index, dimension = room.dimension }, {
                onResult = function(result)
                    target.lastResult = result
                    if result.status ~= "applied" then
                        self:tele_failed()
                    end
                end,
            })
        end
    end)
    wrapping.patch(cleanups, gt, "tab_action", function(original)
        local restartIndex
        for i = 1, 64 do
            local name = debug.getupvalue(original, i)
            if not name then
                break
            end
            if name == "fastrestartenable" then
                restartIndex = i
                break
            end
        end
        return function(self, ...)
            if not lan:IsActive() or not restartIndex then
                return original(self, ...)
            end
            local _, restart = debug.getupvalue(original, restartIndex)
            debug.setupvalue(original, restartIndex, false)
            local result = table.pack(pcall(original, self, ...))
            debug.setupvalue(original, restartIndex, restart)
            if not result[1] then
                error(result[2], 0)
            end
            return table.unpack(result, 2, result.n)
        end
    end)
    cleanups[#cleanups + 1] = lan:On("StateReset", function()
        initialized, pending = false, false
    end)
    cleanups[#cleanups + 1] = lan:On("LocalPlayersChanged", function()
        gt:prep()
    end)
    cleanups[#cleanups + 1] = lan:On("LocalRoomChanged", function()
        if not initialized then
            gt:prep()
            gt:new_level()
            initialized = true
        end
        gt:new_room()
    end)
    return function()
        target.preparePlayer = nil
        wrapping.cleanup(cleanups)
        pending = false
    end
end
function definition.dispatch(target, record, ...)
    local lan = authority.integration
    local callbacks = ModCallbacks
    local ticking = record.id == callbacks.MC_POST_RENDER or record.id == callbacks.MC_POST_UPDATE
    if not lan or not lan:IsActive() then
        -- Failed startup can return to native gameplay before any committed
        -- LAN view prepared Goodtrip. Recover its ordinary player-zero cache.
        if ticking and target.preparePlayer and not target.preparePlayer(false) then
            return
        end
        return record.original(...)
    end
    if
        record.id == callbacks.MC_POST_RENDER
        or record.id == callbacks.MC_POST_UPDATE
        or record.id == callbacks.MC_POST_NEW_ROOM
        or record.id == callbacks.MC_POST_NEW_LEVEL
        or record.id == callbacks.MC_POST_GAME_STARTED
    then
        if not lan:IsReady() then
            return
        end
        local args = table.pack(...)
        return lan:WithLocalView(function()
            if ticking and not target.preparePlayer(true) then
                return
            end
            return record.original(table.unpack(args, 1, args.n))
        end)
    end
    return record.original(...)
end
api:RegisterAdapter(definition)
return definition
