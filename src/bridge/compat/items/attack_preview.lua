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
        "COLLECTIBLE_THE_WIZ",
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
    return {
        freeAim = function(player)
            return items.COLLECTIBLE_ANALOG_STICK
                and player:HasCollectible(items.COLLECTIBLE_ANALOG_STICK)
        end,
        normalTear = function(player)
            return player.TearFlags == flags.TEAR_NORMAL
                and not player:HasPlayerForm(forms.PLAYERFORM_BOOK_WORM)
        end,
        defaultTear = function(player, inventory)
            for _, item in ipairs(inventory[fields.inventory.items]) do
                if item[fields.item.id] ~= items.COLLECTIBLE_D6 then
                    return false
                end
            end
            return inventory[fields.inventory.type] == players.PLAYER_ISAAC
                and player.Damage == 3.5
                and player.TearFlags == flags.TEAR_NORMAL
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
