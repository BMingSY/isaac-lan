-- The bag's native HUD reads private materials and its authoritative preview.
return function(native, items)
    local bag = assert(items.COLLECTIBLE_BAG_OF_CRAFTING)
    local empty = string.rep("\0", 12)
    return {
        capture = function(p)
            if p:IsCoopGhost() then
                return false
            end
            for slot = 0, 3 do
                if p:GetActiveItem(slot) == bag then
                    return {
                        assert(native.actor_crafting_bag(p:GetSprite())),
                        p:GetItemState() == bag,
                    }
                end
            end
            return false
        end,
        apply = function(p, value)
            assert(value ~= nil, "Missing crafting bag state")
            assert(
                value == false or (type(value) == "table" and type(value[2]) == "boolean"),
                "Invalid crafting bag state"
            )
            if not p:IsCoopGhost() then
                assert(
                    native.actor_crafting_bag(p:GetSprite(), value and value[1] or empty),
                    "Cannot restore crafting bag materials and preview"
                )
            end
        end,
    }
end
