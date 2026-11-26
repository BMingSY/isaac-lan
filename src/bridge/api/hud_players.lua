-- Copy display values from a borrowed roster before entering a third-party callback.
return function(bridge, native)
    local LAST_ACTIVE_SLOT, FIRST_POCKET_ACTIVE_SLOT = 3, 2
    local LAST_TRINKET_SLOT, LAST_POCKET_SLOT = 1, 3
    local function readHealth(panel, player)
        panel.unknown = Game():GetLevel():GetCurses() & LevelCurse.CURSE_OF_THE_UNKNOWN ~= 0
        panel.isGhost = player:IsCoopGhost()
        if not panel.unknown and not panel.isGhost then
            panel.health = {
                red = player:GetHearts(),
                maxRed = player:GetMaxHearts(),
                soul = player:GetSoulHearts(),
                blackMask = player:GetBlackHearts(),
                bone = player:GetBoneHearts(),
                broken = player:GetBrokenHearts(),
                rotten = player:GetRottenHearts(),
                eternal = player:GetEternalHearts(),
                golden = player:GetGoldenHearts(),
            }
        end
    end
    local function activeItem(player, slot)
        local id = player:GetActiveItem(slot)
        local chargeType, maxCharge
        if id ~= 0 then
            chargeType, maxCharge = native.items_active_charge(player:GetSprite(), slot)
        end
        return {
            slot = slot,
            id = id,
            maxCharge = maxCharge,
            chargeType = chargeType,
            charge = player:GetActiveCharge(slot),
            batteryCharge = player:GetBatteryCharge(slot),
        }
    end
    local function trinket(player, slot)
        return { slot = slot, id = player:GetTrinket(slot) }
    end
    -- The ordered records in actor_pockets also identify which pocket-active
    -- slot supplies an icon, even after cycling multiple pocket items.
    local PILL, CARD, ACTIVE = 0, 1, 2
    local pocketKinds = { [PILL] = "pill", [CARD] = "card" }
    local function pocketItems(player)
        local bytes = native.actor_pockets(player:GetSprite())
        local items, offset = {}, 1
        for slot = 0, LAST_POCKET_SLOT do
            local id, kind
            id, kind, offset = string.unpack(">I4I4", bytes, offset)
            local item = { slot = slot, kind = "empty", id = 0 }
            if id ~= 0 and pocketKinds[kind] then
                item.kind, item.id = pocketKinds[kind], id
            elseif
                kind == ACTIVE
                and (id == FIRST_POCKET_ACTIVE_SLOT + 1 or id == LAST_ACTIVE_SLOT + 1)
            then
                item.kind, item.activeSlot = "activeItem", id - 1
                item.id = player:GetActiveItem(item.activeSlot)
            end
            items[slot + 1] = item
        end
        return items
    end
    local function body(player, identity, localOwner)
        return {
            playerId = identity.id,
            ownerId = identity.owner,
            isLocal = identity.owner == localOwner,
            playerType = player:GetPlayerType(),
        }
    end
    local snapshots = {}
    local revision, catalog, passives
    function snapshots.reset()
        revision, catalog, passives = nil, nil, nil
    end
    function snapshots.players(options)
        assert(options == nil or type(options) == "table", "invalid_hud_options")
        local include = options and options.includeCollectibles
        assert(include == nil or type(include) == "boolean", "invalid_hud_options")
        local players = {}
        if not bridge.ready() then
            return players
        end
        local info = bridge.info()
        -- Copy values while the complete roster is borrowed, including inside a local callback.
        native.api_with_hud_players(function()
            for index = 0, Game():GetNumPlayers() - 1 do
                local player = Isaac.GetPlayer(index)
                local hash = GetPtrHash(player)
                local id = bridge.identities[hash]
                if id and info.connected & (1 << (id.owner - 1)) ~= 0 then
                    local panel = body(player, id, info.slot + 1)
                    readHealth(panel, player)
                    panel.activeItems = {}
                    for slot = 0, LAST_ACTIVE_SLOT do
                        panel.activeItems[slot + 1] = activeItem(player, slot)
                    end
                    panel.trinkets = { trinket(player, 0), trinket(player, 1) }
                    panel.pocketItems = pocketItems(player)
                    panel.resources = {
                        coins = player:GetNumCoins(),
                        bombs = player:GetNumBombs(),
                        keys = player:GetNumKeys(),
                        goldenBomb = player:HasGoldenBomb(),
                        goldenKey = player:HasGoldenKey(),
                        soulCharge = player:GetSoulCharge(),
                        bloodCharge = player:GetBloodCharge(),
                    }
                    if include then
                        if revision ~= bridge.context then
                            revision, catalog, passives = bridge.context, {}, {}
                        end
                        passives[hash] = passives[hash]
                            or bridge.readHUDCollectibles(player, catalog)
                        panel.collectibles = bridge.copy(passives[hash])
                    end
                    players[#players + 1] = panel
                end
            end
        end)
        return players
    end
    function snapshots.panel(name, index, x, y, scale, alpha, slot)
        -- Resolve the actual bound body before entering the local-only callback.
        local player = Isaac.GetPlayer(index)
        local identity = player and bridge.identities[GetPtrHash(player)]
        if not identity then
            return nil
        end
        local panel = body(player, identity, bridge.info().slot + 1)
        panel.component, panel.x, panel.y, panel.scale, panel.alpha = name, x, y, scale, alpha
        if name == "hearts" then
            readHealth(panel, player)
        elseif name == "activeItem" then
            if slot < 0 or slot > LAST_ACTIVE_SLOT then
                return nil
            end
            panel.activeItem = activeItem(player, slot)
            if panel.activeItem.id == 0 then
                return nil
            end
        elseif name == "trinket" then
            if slot < 0 or slot > LAST_TRINKET_SLOT then
                return nil
            end
            panel.trinket = trinket(player, slot)
            if panel.trinket.id == 0 then
                return nil
            end
        elseif name == "pocketItems" then
            panel.pocketItems = pocketItems(player)
        end
        return panel
    end
    return snapshots
end
