-- Keep trigger de-duplication separate from the complete authority-owned pose.
-- Native overlays have multiple image layers, not just a Show(id) event.
return function(native, sample, captureSprite, applySprite)
    return {
        capture = function(slot)
            local sprite = sample()
            local mega = native.item_presentation_sprite(slot, sprite, 1)
            local book = native.item_presentation_sprite(slot, sprite, 0)
            local scene = native.home_scene_sprite(sprite)
            return {
                native.item_presentation_events(slot),
                mega and captureSprite(mega) or false,
                book and captureSprite(book) or false,
                native.item_presentation_pose(slot),
                native.home_scene_pose(),
                scene and captureSprite(scene) or false,
            }
        end,
        apply = function(slot, value)
            assert(native.item_presentation_events(value[1]))
            assert(native.item_presentation_pose(slot, value[4]))
            assert(native.home_scene_pose(value[5]))
            for part = 0, 1 do
                local visual = value[part == 0 and 3 or 2]
                if visual then
                    applySprite(
                        assert(native.item_presentation_sprite(slot, sample(), part)),
                        visual
                    )
                end
            end
            if value[6] then
                applySprite(assert(native.home_scene_sprite(sample())), value[6])
            end
        end,
    }
end
