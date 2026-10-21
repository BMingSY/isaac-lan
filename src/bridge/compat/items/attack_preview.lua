-- Weapon-specific display rules. No attacks, RNG or item effects run here.
return function(weapons, items, fields, flags, forms, players)
    local chargeMultipliers = {
        [weapons.WEAPON_BRIMSTONE] = 1,
        [weapons.WEAPON_KNIFE] = 4,
        [weapons.WEAPON_TECH_X] = 3,
    }
    local excluded = {}
    for _, name in ipairs({
        "COLLECTIBLE_INNER_EYE",
        "COLLECTIBLE_MUTANT_SPIDER",
        "COLLECTIBLE_20_20",
        "COLLECTIBLE_MOMS_EYE",
        "COLLECTIBLE_LOKIS_HORNS",
        "COLLECTIBLE_THE_WIZ",
        "COLLECTIBLE_CHOCOLATE_MILK",
        "COLLECTIBLE_CURSED_EYE",
        "COLLECTIBLE_ANTI_GRAVITY",
        "COLLECTIBLE_LEAD_PENCIL",
        "COLLECTIBLE_EYE_SORE",
        "COLLECTIBLE_ALMOND_MILK",
        "COLLECTIBLE_SOY_MILK",
        "COLLECTIBLE_NEPTUNUS",
        "COLLECTIBLE_MONSTROS_LUNG",
        "COLLECTIBLE_MARKED",
        "COLLECTIBLE_ANALOG_STICK",
        "COLLECTIBLE_TRACTOR_BEAM",
    }) do
        if items[name] then
            excluded[#excluded + 1] = items[name]
        end
    end
    return {
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
            local multiplier = chargeMultipliers[weapon.kind]
            if multiplier then
                return { charge = math.max(0, weapon.maximum * multiplier) }
            end
            return { tears = weapon.kind == weapons.WEAPON_TEARS }
        end,
        singleTear = function(player)
            for _, item in ipairs(excluded) do
                if player:HasCollectible(item) then
                    return false
                end
            end
            return true
        end,
    }
end
