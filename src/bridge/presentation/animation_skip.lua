return function(drawProgress)
    return function(status, font, message)
        local votes, members = status.skipVotes or 0, status.skipMembers or 0
        if status.bossIntro and votes == 0 then
            local hint = message("按确认键跳过")
            local scale = 0.8
            local x =
                math.floor((Isaac.GetScreenWidth() - font:GetStringWidthUTF8(hint) * scale) / 2)
            local y = Isaac.GetScreenHeight() - 25
            font:DrawStringScaledUTF8(
                hint,
                x + 1,
                y + 1,
                scale,
                scale,
                KColor(0.08, 0.06, 0.05, 0.9),
                0,
                false
            )
            font:DrawStringScaledUTF8(
                hint,
                x,
                y,
                scale,
                scale,
                KColor(0.91, 0.87, 0.78, 1),
                0,
                false
            )
            return
        end
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
        end, message("跳过 "))
    end
end
