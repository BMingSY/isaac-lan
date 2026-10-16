-- Follow native heart HUD anchors, whose order is local-view dependent.
return function(native, Phase)
    local white = KColor(1, 1, 1, 1)
    return function(status, font)
        if not status.prepared or status.phase ~= Phase.running then
            return
        end
        local huds = native.presentation_player_huds()
        local width, height = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
        for slot = 1, (status.players or 1) - 1 do
            local hud = huds[tostring(slot)]
            if hud and ((status.connected or 0) & (1 << slot)) ~= 0 then
                local ping = status["ping" .. slot] or -1
                local label = ping < 0 and "—" or ping .. " ms"
                local textWidth = font:GetStringWidthUTF8(label) * 0.6
                local x = math.floor(math.max(1, math.min(width - textWidth - 1, hud.x + 12)))
                local y = math.floor(math.max(1, math.min(height - 9, hud.y - 13)))
                font:DrawStringScaledUTF8(label, x, y, 0.6, 0.6, white, 0, false)
            end
        end
    end
end
