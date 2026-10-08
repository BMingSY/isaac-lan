local bridge, wrapping = _IsaacLanModules["api/public"], _IsaacLanModules["compat/wrapping"]
local definition = {
    id = "isaac-lan.compat.eid",
    adapterVersion = 1,
    modName = "External Item Descriptions",
    targets = {
        {
            workshopId = "836319872",
            metadataVersion = "5.23",
            sourceHash = "8f2614a6a4cd58d60345dd0a33072a0bc7822ecf06ad9106234a6a9b2380b3fc",
        },
    },
}
function definition.probe(target)
    local eid = rawget(_G, "EID")
    if eid ~= target.mod then
        return "pending", "exports_not_ready"
    end
    if tostring(eid.ModVersion) ~= "5.24" or eid.ModVersionCommit ~= "980bb0b" then
        return "unsupported", "runtime_version_mismatch"
    end
    if type(eid.setPlayer) ~= "function" or type(eid.OnRender) ~= "function" then
        return "pending", "entry_points_not_ready"
    end
    return "ready"
end
function definition.install(target, api)
    local cleanups, eid = {}, target.mod
    target.addCleanup(function()
        wrapping.cleanup(cleanups)
    end)
    local lan = api:RegisterMod(eid, { id = definition.id, integrationVersion = 1 })
    wrapping.patch(cleanups, eid, "setPlayer", function(original)
        return function(self, ...)
            if not lan:IsActive() then
                return original(self, ...)
            end
            if not lan:IsReady() then
                self.player, self.players, self.coopMainPlayers, self.coopAllPlayers, self.controllerIndexes =
                    nil, {}, {}, {}, {}
                return
            end
            local args = table.pack(...)
            return lan:WithLocalView(function()
                return original(self, table.unpack(args, 1, args.n))
            end)
        end
    end)
    local function clear()
        eid.lastDescriptionEntity = nil
        if type(eid.ResetDescCache) == "function" then
            eid:ResetDescCache()
        end
        eid.CachedIndicators = {}
        eid.player, eid.players, eid.coopMainPlayers, eid.coopAllPlayers, eid.controllerIndexes =
            nil, {}, {}, {}, {}
    end
    cleanups[#cleanups + 1] = lan:On("StateReset", clear)
    cleanups[#cleanups + 1] = lan:On("LocalRoomChanged", clear)
    cleanups[#cleanups + 1] = lan:On("ViewUpdated", function()
        eid:setPlayer()
    end)
    return function()
        wrapping.cleanup(cleanups)
        lan:Unregister()
        clear()
    end
end
function definition.dispatch(target, record, ...)
    local lan = bridge.handles[definition.id]
    if not lan then
        return record.original(...)
    end
    local callbacks = ModCallbacks
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
            target.mod:setPlayer()
            return record.original(table.unpack(args, 1, args.n))
        end)
    end
    return record.original(...)
end
bridge.api:RegisterCompatibility(definition)
return definition
