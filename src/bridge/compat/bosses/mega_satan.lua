-- The boss changes the native floor sprite when the summoning circle lights up.
return function(arena, floorSprite)
    return {
        capture = function(backdrop)
            if backdrop ~= arena then
                return false
            end
            local floor = floorSprite()
            return { floor:GetAnimation(), floor:GetFrame() }
        end,
        apply = function(backdrop, pose)
            if backdrop ~= arena then
                assert(pose == false, "Unexpected Mega Satan floor animation")
                return
            end
            assert(type(pose) == "table" and #pose == 2, "Missing Mega Satan floor animation")
            local animation, frame = table.unpack(pose)
            assert(
                type(animation) == "string" and math.type(frame) == "integer" and frame >= 0,
                "Invalid Mega Satan floor animation"
            )
            local floor = floorSprite()
            if floor:GetAnimation() ~= animation or floor:GetFrame() ~= frame then
                floor:SetFrame(animation, frame)
            end
        end,
    }
end
