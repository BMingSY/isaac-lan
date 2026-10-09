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
        {
            workshopId = "836319872",
            metadataVersion = "5.24",
            sourceHash = "705a61422ffc09c683d4250dedf2a569b6d76d4eee884dec70b705eedfa898f5",
        },
    },
}
function definition.probe(target)
    local eid = rawget(_G, "EID")
    if eid ~= target.mod then
        return "pending", "exports_not_ready"
    end
    local expected = target.metadataVersion == "5.24" and { "5.25", "d7aab88" }
        or { "5.24", "980bb0b" }
    if tostring(eid.ModVersion) ~= expected[1] or eid.ModVersionCommit ~= expected[2] then
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
