return function(drawProgress)
    return function(status, font)
        local votes, members = status.skipVotes or 0, status.skipMembers or 0
        -- One viewer skips immediately and never needs a consent indicator.
        if members == 0 or (members & (members - 1)) == 0 then
            return
        end
        drawProgress(votes, members, font, function(cx, cy)
            local glyph, scale = ">>", 1.2
            local x = math.floor(cx - font:GetStringWidthUTF8(glyph) * scale / 2)
            font:DrawStringScaledUTF8(
                glyph,
                x,
                cy - 7,
                scale,
                scale,
                KColor(0.91, 0.87, 0.78, 1),
                0,
                false
            )
        end, "跳过 ")
    end
end
