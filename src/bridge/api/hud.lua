-- All registrations belong to this Lua VM. Only the three audience masks and
-- presence of a renderer cross the native boundary.
return function(bridge, native)
    local audiences = { ["local"] = 1, teammates = 2, all = 3 }
    local hidden = { hearts = {}, activeItem = {}, pocketItems = {} }
    local renderers = {}
    local function mask(entries)
        local value = 0
        for _, bits in pairs(entries) do
            value = value | bits
        end
        return value
    end
    local function changed()
        native.presentation_hud_filters(
            mask(hidden.hearts),
            mask(hidden.activeItem),
            mask(hidden.pocketItems),
            #renderers > 0
        )
    end
    local hud = {}
    function hud.hide(component, audience)
        local entries = assert(hidden[component], "invalid_hud_component")
        local token = {}
        entries[token] = assert(audiences[audience], "invalid_hud_audience")
        changed()
        return function()
            entries[token] = nil
            changed()
        end
    end
    function hud.subscribe(id, audience, fn)
        local bits = assert(audiences[audience], "invalid_hud_audience")
        assert(type(fn) == "function", "invalid_heart_renderer")
        local entry = { id = id, bits = bits, fn = fn }
        renderers[#renderers + 1] = entry
        changed()
        function entry.remove()
            entry.fn = nil
            -- A renderer may close its handle or register another renderer while drawing.
            local remaining = {}
            for _, other in ipairs(renderers) do
                if other ~= entry then
                    remaining[#remaining + 1] = other
                end
            end
            renderers = remaining
            changed()
        end
        return entry.remove
    end
    local function snapshot(player, identity, isLocal, x, y, scale)
        local unknown = Game():GetLevel():GetCurses() & LevelCurse.CURSE_OF_THE_UNKNOWN ~= 0
        local ghost = player:IsCoopGhost()
        return {
            playerId = identity.id,
            ownerId = identity.owner,
            isLocal = isLocal,
            playerType = player:GetPlayerType(),
            x = x,
            y = y,
            scale = scale,
            unknown = unknown,
            isGhost = ghost,
            health = not unknown and not ghost and {
                red = player:GetHearts(),
                maxRed = player:GetMaxHearts(),
                soul = player:GetSoulHearts(),
                blackMask = player:GetBlackHearts(),
                bone = player:GetBoneHearts(),
                broken = player:GetBrokenHearts(),
                rotten = player:GetRottenHearts(),
                eternal = player:GetEternalHearts(),
                golden = player:GetGoldenHearts(),
            } or nil,
        }
    end
    function hud.players()
        local players = {}
        if bridge.ready() then
            local info = bridge.info()
            -- Collect values synchronously, even if the caller is already inside a
            -- local-only render callback. Never let a borrowed team actor escape.
            native.api_with_hud_players(function()
                for index = 0, Game():GetNumPlayers() - 1 do
                    local player = Isaac.GetPlayer(index)
                    local id = bridge.identities[GetPtrHash(player)]
                    if id and info.connected & (1 << (id.owner - 1)) ~= 0 then
                        players[#players + 1] = snapshot(player, id, id.owner == info.slot + 1)
                    end
                end
            end)
        end
        return players
    end
    function hud.render(index, x, y, scale)
        if #renderers == 0 or not bridge.ready() then
            return false
        end
        -- Resolve the actual bound body before switching to the local-only Lua view.
        local player = Isaac.GetPlayer(index)
        local identity = player and bridge.identities[GetPtrHash(player)]
        if not identity then
            return false
        end
        local isLocal = identity.owner == bridge.info().slot + 1
        local bit = isLocal and audiences["local"] or audiences.teammates
        local current, panel = renderers, nil
        for i = 1, #current do
            local entry = current[i]
            if entry.fn and entry.bits & bit ~= 0 then
                panel = panel or snapshot(player, identity, isLocal, x, y, scale)
                local ok, claimed = pcall(bridge.withView, function()
                    return entry.fn(bridge.copy(panel))
                end)
                if not ok then
                    entry.remove()
                    bridge.log(entry.id .. " heart_renderer_disabled=" .. tostring(claimed))
                elseif claimed == true then
                    return true
                end
            end
        end
        return false
    end
    return hud
end
