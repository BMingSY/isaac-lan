-- Keep trigger de-duplication separate from the complete authority-owned pose.
-- Native overlays have multiple image layers, not just a Show(id) event.
return function(native, sample, captureSprite, applySprite)
    return {
        capture = function(slot)
            local sprite = sample()
            local mega = native.item_presentation_sprite(slot, sprite, 1)
            local book = native.item_presentation_sprite(slot, sprite, 0)
            return {
                native.item_presentation_events(slot),
                mega and captureSprite(mega) or false,
                book and captureSprite(book) or false,
                native.item_presentation_pose(slot),
            }
        end,
        apply = function(slot, value)
            assert(native.item_presentation_events(value[1]))
            assert(native.item_presentation_pose(slot, value[4]))
            for part = 0, 1 do
                local visual = value[part == 0 and 3 or 2]
                if visual then
                    applySprite(
                        assert(native.item_presentation_sprite(slot, sample(), part)),
                        visual
                    )
                end
            end
        end,
    }
end
