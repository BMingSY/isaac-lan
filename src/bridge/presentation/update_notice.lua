-- Process-level dismissal lives in the native notice; this component owns only
-- the paper dialog's selection and input arming, using the existing menu assets.
return function(keys, native)
    local selection, armed, shown = 1, false, false
    local failed = false
    return function(input, draw)
        if not shown then
            shown = true
        elseif not armed then
            armed = input.released and input.key == 0 and not input.clicked
        else
            if input.key == keys.escape then
                native.update_continue()
                return
            end
            if
                input.key == keys.up
                or input.key == keys.down
                or input.key == keys.left
                or input.key == keys.right
                or input.key == keys.tab
            then
                selection = 3 - selection
            end
            for index, y in ipairs({ 174, 200 }) do
                if (input.moved or input.clicked) and draw.hit(165, y - 3, 150, 22) then
                    selection = index
                    if input.clicked then
                        input.key = keys.enter
                    end
                end
            end
            if input.key == keys.enter or input.key == keys.space then
                if selection == 1 then
                    failed = not native.update_exit()
                else
                    native.update_continue()
                end
            end
        end
        local assets = draw.assets
        assets.fill.Scale = Vector(draw.width / 480, draw.height / 270)
        assets.fill.Color = Color(0, 0, 0, 0.6)
        assets.fill:Render(Vector.Zero)
        draw.layer(assets.lobby, 9, 137, 39)
        draw.centered("新版 Isaac LAN 已下载", 240, 77, 12, nil, 190)
        draw.centered("退出后重新启动游戏，", 240, 115, 12, nil, 190)
        draw.centered("即可生效。", 240, 133, 12)
        draw.centered("退出游戏", 240, 174, 16)
        draw.centered("继续", 240, 200, 16)
        draw.pointer(178, selection == 1 and 181 or 207)
        if failed then
            draw.centered("退出失败，请重试", 240, 151, 10)
        end
    end
end
