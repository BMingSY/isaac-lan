-- Weapon-specific display rules. No attacks, RNG or item effects run here.
return function(weapons, items, fields, flags, forms, players)
    local chargeWeapons = {
        [weapons.WEAPON_BRIMSTONE] = true,
        [weapons.WEAPON_KNIFE] = true,
        [weapons.WEAPON_TECH_X] = true,
    }
    local excluded = {}
    for _, name in ipairs({
        "COLLECTIBLE_MOMS_EYE",
        "COLLECTIBLE_LOKIS_HORNS",
        "COLLECTIBLE_CHOCOLATE_MILK",
        "COLLECTIBLE_CURSED_EYE",
        "COLLECTIBLE_ANTI_GRAVITY",
        "COLLECTIBLE_LEAD_PENCIL",
        "COLLECTIBLE_EYE_SORE",
        "COLLECTIBLE_ALMOND_MILK",
        "COLLECTIBLE_NEPTUNUS",
        "COLLECTIBLE_MONSTROS_LUNG",
        "COLLECTIBLE_MARKED",
        "COLLECTIBLE_TRACTOR_BEAM",
    }) do
        if items[name] then
            excluded[#excluded + 1] = items[name]
        end
    end
    local diagonal = math.sqrt(0.5)
    local wizPattern = {
        { along = diagonal, across = -diagonal, eye = 0 },
        { along = diagonal, across = diagonal, eye = 0 },
    }
    local function wiz(player)
        return items.COLLECTIBLE_THE_WIZ and player:HasCollectible(items.COLLECTIBLE_THE_WIZ)
    end
    return {
        freeAim = function(player)
            return items.COLLECTIBLE_ANALOG_STICK
                and player:HasCollectible(items.COLLECTIBLE_ANALOG_STICK)
        end,
        normalTear = function(player)
            return (
                player.TearFlags == flags.TEAR_NORMAL
                or (wiz(player) and player.TearFlags == flags.TEAR_SPECTRAL)
            )
                and not player:HasPlayerForm(forms.PLAYERFORM_BOOK_WORM)
        end,
        initialAnimation = function(player, inventory)
            if inventory[fields.inventory.type] ~= players.PLAYER_ISAAC then
                return
            end
            -- These stock loadouts have a known first sprite. Other appearances
            -- are learned from the first host tear, including Modded sprites.
            local pentagram = false
            for _, item in ipairs(inventory[fields.inventory.items]) do
                local id = item[fields.item.id]
                if id == items.COLLECTIBLE_PENTAGRAM and item[fields.item.count] == 1 then
                    pentagram = true
                elseif id ~= items.COLLECTIBLE_D6 and id ~= items.COLLECTIBLE_THE_WIZ then
                    return
                end
            end
            return pentagram and "RegularTear7" or "RegularTear6"
        end,
        initialPattern = function(player, count)
            if count == 2 and wiz(player) then
                return wizPattern
            end
        end,
        spectral = function(player)
            return wiz(player) and player.TearFlags == flags.TEAR_SPECTRAL
        end,
        mode = function(weapon)
            if chargeWeapons[weapon.kind] and weapon.chargeLimit and weapon.chargeLimit > 0 then
                return { charge = weapon.chargeLimit }
            end
            return { tears = weapon.kind == weapons.WEAPON_TEARS }
        end,
        tearCount = function(player)
            for _, item in ipairs(excluded) do
                if player:HasCollectible(item) then
                    return nil
                end
            end
            local count = 1
            for name, amount in pairs({
                COLLECTIBLE_THE_WIZ = 2,
                COLLECTIBLE_20_20 = 2,
                COLLECTIBLE_INNER_EYE = 3,
                COLLECTIBLE_MUTANT_SPIDER = 4,
            }) do
                local item = items[name]
                if item and player:HasCollectible(item) then
                    if count ~= 1 or player:GetCollectibleNum(item) ~= 1 then
                        return nil
                    end
                    count = amount
                end
            end
            return count
        end,
    }
end
