return function(deps, layout)
    local native, chat = deps.native, deps.chat
    local ui = {
        input = { open = false, text = "", cursor = 0, anchor = 0 },
        wheel = false,
        scroll = 0,
    }
    local assets, lastRevision, lines, lastOpen, lastEpoch = nil, -1, {}, false, nil
    local style = native.chat_style
    local function rgb(value)
        return { (value >> 16 & 255) / 255, (value >> 8 & 255) / 255, (value & 255) / 255 }
    end
    local background, border, foreground = rgb(style.background), rgb(style.border), rgb(style.text)
    local backgroundAlpha = style.opacity / 100
    local playerColors = {
        { text = rgb(0xf0a7a0), bubble = rgb(0x722f2b) },
        { text = rgb(0x9dc8f0), bubble = rgb(0x244b70) },
        { text = rgb(0xe6ce85), bubble = rgb(0x665018) },
        { text = rgb(0xa8d3a3), bubble = rgb(0x305b35) },
    }
    local scale = 0.85
    local shownEmotes = {}
    local position, drag, mouseDown, lastWidth
    local copyPressed, copyFeedback
    local copyWidth, copyFeedbackDuration = 16, 700
    local completion = {
        "/h",
        "/help",
        "/e",
        "/echo",
        "/d6",
        "/d20",
        "/d100",
        "/2d6",
        "/d100b",
        "/d100p",
        "/console",
        "/c",
        "/lanbot",
    }
    local function load()
        if assets then
            return
        end
        local font, fill, bubble = Font(), Sprite(), Sprite()
        font:Load("font/TeamMeatEx/TeamMeatEx10.fnt")
        fill:Load("gfx/ui/bossoverlay_whiteout.anm2", true)
        fill:SetFrame("Fade", 15)
        bubble:Load("gfx/OnlineEmotes.anm2", true)
        bubble:SetFrame("Bubble", 0)
        assets = { font = font, fill = fill, bubble = bubble }
        if
            style.image
            and style.image ~= ""
            and style.image_width > 0
            and style.image_height > 0
        then
            local backgroundSprite = Sprite()
            local loaded = pcall(function()
                backgroundSprite:Load(style.image, true)
                backgroundSprite:SetFrame("Idle", 0)
            end)
            if loaded and backgroundSprite:IsLoaded() then
                assets.background = backgroundSprite
            end
        end
    end
    local function measure(text)
        return assets.font:GetStringWidthUTF8(text) * scale
    end
    local shadowInk = { 0.10, 0.08, 0.07 }
    local function text(value, x, y, color, alpha, shadow)
        if assets.background and shadow ~= false then
            text(value, x + 1, y + 1, shadowInk, alpha, false)
        end
        assets.font:DrawStringScaledUTF8(
            value,
            x,
            y,
            scale,
            scale,
            KColor(color[1], color[2], color[3], alpha or 1),
            0,
            false
        )
    end
    local ink = { 0.22, 0.17, 0.15 }
    local function rect(x, y, width, height, color, alpha)
        assets.fill.Scale = Vector(width / 480, height / 270)
        -- This native sprite uses a white additive offset in its animation.
        assets.fill.Color = Color(0, 0, 0, alpha or 1, color[1] - 1, color[2] - 1, color[3] - 1)
        assets.fill:Render(Vector(x, y))
    end
    local function panel(bounds, y, height, alpha, fillColor, edgeColor)
        local x, width = bounds.x, bounds.width
        if assets.background then
            local padding = 6
            local imageScale = Vector(
                (width + padding * 2) / style.image_width,
                (bounds.height + padding * 2) / style.image_height
            )
            assets.background.Scale = imageScale
            assets.background.Color = Color(1, 1, 1, alpha)
            -- Render clamps are distances before Sprite.Scale. Keep the full
            -- image anchored to the expanded panel and reveal only its bottom.
            assets.background:Render(
                Vector(x - padding, bounds.y - padding),
                Vector(0, math.max(0, y - bounds.y) / imageScale.Y),
                Vector(0, 0)
            )
            return
        end
        -- Border strips avoid stacking translucent fills into an opaque panel.
        rect(x - 1, y + 1, 1, height - 2, edgeColor, alpha)
        rect(x + width, y + 1, 1, height - 2, edgeColor, alpha)
        rect(x + 1, y - 1, width - 2, 1, edgeColor, alpha)
        rect(x + 1, y + height, width - 2, 1, edgeColor, alpha)
        rect(x, y, width, height, fillColor, alpha)
    end
    local function copyIcon(x, y, color, alpha, copied, shadow)
        if assets.background and not shadow then
            copyIcon(x + 1, y + 1, shadowInk, alpha, copied, true)
        end
        if copied then
            rect(x + 1, y + 4, 1, 2, color, alpha)
            for step = 0, 4 do
                rect(x + 2 + step, y + 5 - step, 1, 2, color, alpha)
            end
        else
            rect(x, y, 6, 1, color, alpha)
            rect(x, y + 1, 1, 5, color, alpha)
            rect(x + 2, y + 2, 6, 1, color, alpha)
            rect(x + 2, y + 7, 6, 1, color, alpha)
            rect(x + 2, y + 3, 1, 4, color, alpha)
            rect(x + 7, y + 3, 1, 4, color, alpha)
        end
    end
    function ui.step(status)
        local available = status.phase == deps.phase.lobby
            or status.phase == deps.phase.running
            or status.phase == deps.phase.waiting
        native.chat_ui_available(available)
        if not available then
            copyPressed, copyFeedback = nil, nil
            drag, mouseDown = nil, false
            native.emote_poll(0, false)
            native.chat_ui_modal(false)
            ui.wheel = false
            ui.input = native.chat_ui_state()
            return
        end
        ui.input = native.chat_ui_state()
        local controls = native.chat_controls()
        if controls.restart and status.prepared then
            native.chat_ui_open(false)
            native.emote_poll(0, false)
            native.chat_ui_modal(false)
            ui.wheel, ui.input.open = false, false
            return
        end
        if controls.chat then
            native.chat_ui_open(not ui.input.open)
            ui.input = native.chat_ui_state()
        end
        if controls.emote and ui.input.open and not ui.input.composing then
            native.chat_ui_open(false)
            ui.input.open = false
        end
        local emotes = native.emote_poll(
            controls.controller or 0,
            status.prepared == true and not ui.input.open
        )
        ui.wheel = emotes.open
        native.chat_ui_modal(ui.wheel)
        if emotes.selected > 0 then
            chat.sendEmote(emotes.selected)
        end
        if status.prepared then
            for owner, value in pairs(chat.emotes) do
                if shownEmotes[owner] ~= value then
                    if native.emote_show(owner, value.id) then
                        shownEmotes[owner] = value
                    end
                end
            end
        end
        if ui.wheel then
            return
        end
        if ui.input.open then
            if ui.input.submit or (controls.confirm and not ui.input.composing) then
                if chat.submit(ui.input.text) then
                    native.chat_ui_accept()
                    ui.input.text, ui.input.cursor, ui.input.anchor = "", 0, 0
                    ui.scroll = 0
                end
            elseif controls.back and not ui.input.composing then
                native.chat_ui_open(false)
                ui.input.open = false
            elseif ui.input.complete then
                for _, command in ipairs(completion) do
                    if command:sub(1, #ui.input.text) == ui.input.text then
                        native.chat_ui_text(command .. " ")
                        break
                    end
                end
            end
            ui.scroll = math.max(0, ui.scroll + ui.input.scroll)
        end
        local info = native.api_info()
        local epoch = (info.runId or "") .. ":" .. tostring(info.worldEpoch)
        if lastEpoch and epoch ~= lastEpoch then
            chat.clearBubbles()
        end
        lastEpoch = epoch
    end
    local function renderBubbles(status, width, height, now)
        if not status.prepared or native.api_info().ready ~= 1 then
            return
        end
        local positions = native.rooms_positions()
        local localRoom = positions[tostring(status.slot)]
        if not localRoom then
            return
        end
        local actors = native.api_actors()
        for _, actor in ipairs(actors) do
            actor.player = Isaac.GetPlayer(actor.index)
        end
        local occupied = {}
        native.api_with_local_view(function()
            for _, actor in ipairs(actors) do
                local owner = actor.owner - 1
                local room = positions[tostring(owner)]
                if
                    actor.role == 1
                    and room
                    and room.index == localRoom.index
                    and room.dimension == localRoom.dimension
                    and (status.connected & (1 << owner)) ~= 0
                then
                    local player = actor.player
                    local point = Isaac.WorldToScreen(player.Position)
                    local message, gesture = chat.bubbles[owner], chat.emotes[owner]
                    if
                        message
                        and (
                            not gesture
                            or gesture.time <= message.time
                            or now - gesture.time >= 3000
                        )
                    then
                        local age, duration = now - message.time, layout.duration(message.text)
                        if age < duration then
                            local alpha = math.min(1, (duration - age) / 400)
                            local bubbleLines = layout.bubble(message.text, 132, measure)
                            local bubbleWidth = 24
                            for _, line in ipairs(bubbleLines) do
                                bubbleWidth = math.max(bubbleWidth, measure(line) + 12)
                            end
                            local bubbleHeight = #bubbleLines * layout.lineHeight + 7
                            local x, y = layout.anchor(
                                point.X,
                                point.Y,
                                bubbleWidth,
                                bubbleHeight,
                                width,
                                height
                            )
                            -- J460 Bubble: body spans x=-19..18, y=-18..11;
                            -- the original tail extends below the text body.
                            local sx, sy = bubbleWidth / 38, bubbleHeight / 30
                            x, y = layout.avoidOverlap(
                                x,
                                y,
                                bubbleWidth,
                                bubbleHeight + 11 * sy,
                                width,
                                height,
                                occupied
                            )
                            assets.bubble.Scale = Vector(sx, sy)
                            assets.bubble.Color = Color(1, 1, 1, alpha * 0.68)
                            assets.bubble:Render(Vector(x + 19 * sx, y + 18 * sy))
                            for index, line in ipairs(bubbleLines) do
                                text(
                                    line,
                                    x + 6,
                                    y + 3 + (index - 1) * layout.lineHeight,
                                    playerColors[owner + 1] and playerColors[owner + 1].bubble
                                        or ink,
                                    alpha,
                                    false
                                )
                            end
                        end
                    end
                end
            end
        end)
    end
    function ui.render(status)
        if
            status.phase ~= deps.phase.lobby
            and status.phase ~= deps.phase.running
            and status.phase ~= deps.phase.waiting
        then
            return
        end
        load()
        local width, height, now = Isaac.GetScreenWidth(), Isaac.GetScreenHeight(), deps.clock()
        renderBubbles(status, width, height, now)
        local options = deps.options
        local hud = {
            stats = status.prepared and options.FoundHUD,
            items = status.prepared and options.ExtraHUDStyle > 0,
            offset = status.prepared and options.HUDOffset or 0,
        }
        local bounds = layout.panel(width, height, hud, position)
        local inputHeight = 20
        local mouse = native.chat_ui_pointer(width, height)
        local pressed, released = mouse.down and not mouseDown, not mouse.down and mouseDown
        if not ui.input.open then
            copyPressed, copyFeedback = nil, nil
        end
        if not ui.input.open or not mouse.down then
            drag = nil
        elseif
            pressed
            and mouse.x >= bounds.x
            and mouse.x < bounds.x + bounds.width - copyWidth - 4
            and mouse.y >= bounds.y
            and mouse.y < bounds.bottom - inputHeight
        then
            drag = { x = mouse.x - bounds.x, y = mouse.y - bounds.bottom }
        end
        if drag then
            position = { x = mouse.x - drag.x, bottom = mouse.y - drag.y }
            bounds = layout.panel(width, height, hud, position)
            position = { x = bounds.x, bottom = bounds.bottom }
        end
        mouseDown = mouse.down
        local x, bottom, panelWidth = bounds.x, bounds.bottom, bounds.width
        if
            lastRevision ~= chat.revision
            or lastOpen ~= ui.input.open
            or lastWidth ~= panelWidth
        then
            local previousCount = #lines
            lines = {}
            for _, message in ipairs(chat.messages) do
                local prefix = message.command and "system: "
                    or (message.kind == "team" and ((message.owner + 1) .. "P：") or "")
                local textWidth = panelWidth - 16 - (ui.input.open and copyWidth or 0)
                for _, line in ipairs(layout.wrap(prefix .. message.text, textWidth, measure)) do
                    lines[#lines + 1] = { text = line, message = message }
                end
            end
            if ui.scroll > 0 then
                ui.scroll = ui.scroll + math.max(0, #lines - previousCount)
            end
            lastRevision, lastOpen = chat.revision, ui.input.open
            lastWidth = panelWidth
        end
        if ui.input.open then
            panel(bounds, bounds.y, bounds.height, backgroundAlpha, background, border)
            rect(x + 6, bottom - inputHeight, panelWidth - 12, 1, border, backgroundAlpha)
        end
        local shown = ui.input.open and layout.expandedLines or layout.recentLines
        ui.scroll = math.min(ui.scroll, math.max(0, #lines - shown))
        local ending = #lines - (ui.input.open and ui.scroll or 0)
        local first = math.max(1, ending - shown + 1)
        local rows, backgroundFade = {}, 0
        for index = first, ending do
            local row = lines[index]
            local age = now - row.message.time
            if ui.input.open or (row.message.kind == "team" and age < 6000) then
                local alpha = ui.input.open and 1 or math.min(1, (6000 - age) / 700)
                backgroundFade = math.max(backgroundFade, alpha)
                if row.message.kind ~= "team" then
                    alpha = alpha * 0.8
                end
                local player = playerColors[row.message.owner + 1]
                local color = player
                        and (row.message.kind == "team" or row.message.bubble)
                        and player.text
                    or foreground
                rows[#rows + 1] = {
                    text = row.text,
                    message = row.message,
                    alpha = alpha,
                    color = color,
                }
            end
        end
        local y = bottom - (ui.input.open and inputHeight or 0) - 4 - #rows * layout.lineHeight
        if not ui.input.open and #rows > 0 then
            panel(
                bounds,
                y - 4,
                #rows * layout.lineHeight + 8,
                backgroundAlpha * backgroundFade,
                background,
                border
            )
        end
        for index, row in ipairs(rows) do
            text(row.text, x + 8, y, row.color, row.alpha)
            -- A wrapped message has one action, on its last visible line.
            if
                ui.input.open and (not rows[index + 1] or rows[index + 1].message ~= row.message)
            then
                local buttonX = x + panelWidth - copyWidth - 4
                local hovered = mouse.x >= buttonX
                    and mouse.x < buttonX + copyWidth
                    and mouse.y >= y
                    and mouse.y < y + layout.lineHeight
                if hovered and pressed then
                    copyPressed = row.message
                elseif hovered and released and copyPressed == row.message then
                    copyFeedback = {
                        message = row.message,
                        success = native.chat_ui_copy(row.message.text),
                        untilTime = now + copyFeedbackDuration,
                    }
                end
                local feedback = copyFeedback
                    and copyFeedback.message == row.message
                    and now < copyFeedback.untilTime
                local color = feedback and not copyFeedback.success and playerColors[1].text
                    or foreground
                copyIcon(
                    buttonX + 4,
                    y + 1,
                    color,
                    hovered and 1 or (feedback and 0.9 or 0.45),
                    feedback and copyFeedback.success
                )
            end
            y = y + layout.lineHeight
        end
        if released then
            copyPressed = nil
        end
        if ui.input.open then
            local input = ui.input
            local command = input.text:sub(1, 1) == "/"
            local used = command and #input.text or (utf8.len(input.text) or 0)
            local limit = command and deps.limits.commandBytes or deps.limits.characters
            local counter = (used >= limit - (command and 128 or 10) or input.limit)
                    and (used .. "/" .. limit)
                or nil
            local budget = panelWidth - 24 - (counter and measure(counter) + 6 or 0)
            local start = 1
            local prefix = input.text:sub(1, input.cursor)
            while measure(prefix:sub(start)) > budget do
                start = utf8.offset(prefix, 2, start) or (#prefix + 1)
            end
            local visible = layout.fit(input.text:sub(start), budget, measure)
            text(">", x + 6, bottom - 15, foreground, 0.7)
            local cursorX = x + 17 + measure(prefix:sub(start))
            if input.cursor ~= input.anchor then
                local left = math.max(start - 1, math.min(input.cursor, input.anchor))
                local right = math.max(left, math.max(input.cursor, input.anchor))
                local selectionX = x + 17 + measure(input.text:sub(start, left))
                rect(
                    selectionX,
                    bottom - 16,
                    math.min(budget, measure(input.text:sub(left + 1, right))),
                    12,
                    foreground,
                    0.3
                )
            end
            text(visible, x + 17, bottom - 15, foreground)
            if input.composition ~= "" then
                text(
                    layout.fit(input.composition, budget, measure),
                    cursorX,
                    bottom - 28,
                    foreground
                )
            elseif now % 1000 < 600 then
                rect(cursorX, bottom - 15, 1, 10, foreground, 1)
            end
            if counter then
                text(
                    counter,
                    x + panelWidth - measure(counter) - 5,
                    bottom - 15,
                    input.limit and playerColors[1].text or foreground
                )
            end
            native.chat_ui_caret(cursorX, bottom - 3, width, height)
        end
    end
    function ui.reset()
        native.emote_poll(0, false)
        native.chat_ui_reset()
        shownEmotes = {}
        drag, mouseDown = nil, false
        copyPressed, copyFeedback = nil, nil
        ui.wheel, ui.scroll, lastRevision, lastEpoch = false, 0, -1, nil
        ui.input = { open = false, text = "", cursor = 0, anchor = 0 }
    end
    return ui
end
