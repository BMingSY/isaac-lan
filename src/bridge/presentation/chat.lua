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
    local colors =
        { { 0.60, 0.16, 0.12 }, { 0.16, 0.35, 0.59 }, { 0.55, 0.40, 0.10 }, { 0.21, 0.45, 0.24 } }
    local scale = 0.85
    local shownEmotes = {}
    local completion = {
        "/e",
        "/echo",
        "/d6",
        "/d20",
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
    local function text(value, x, y, color, alpha)
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
    local function panel(x, y, width, height, alpha, fillColor, edgeColor)
        if assets.background then
            local padding = 6
            assets.background.Scale = Vector(
                (width + padding * 2) / style.image_width,
                (height + padding * 2) / style.image_height
            )
            assets.background.Color = Color(1, 1, 1, alpha)
            assets.background:Render(Vector(x - padding, y - padding))
            return
        end
        -- Border strips avoid stacking translucent fills into an opaque panel.
        rect(x - 1, y + 1, 1, height - 2, edgeColor, alpha)
        rect(x + width, y + 1, 1, height - 2, edgeColor, alpha)
        rect(x + 1, y - 1, width - 2, 1, edgeColor, alpha)
        rect(x + 1, y + height, width - 2, 1, edgeColor, alpha)
        rect(x, y, width, height, fillColor, alpha)
    end
    function ui.step(status)
        local available = status.phase == deps.phase.lobby
            or status.phase == deps.phase.running
            or status.phase == deps.phase.waiting
        native.chat_ui_available(available)
        if not available then
            native.emote_poll(0, false)
            native.chat_ui_modal(false)
            ui.wheel = false
            ui.input = native.chat_ui_state()
            return
        end
        ui.input = native.chat_ui_state()
        local controls = native.chat_controls()
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
                                    ink,
                                    alpha
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
        local x, bottom, panelWidth = 12, height - 16, math.min(210, width * 0.42)
        local inputHeight = 20
        if lastRevision ~= chat.revision or lastOpen ~= ui.input.open then
            local previousCount = #lines
            lines = {}
            for _, message in ipairs(chat.messages) do
                local prefix = message.kind == "team" and ((message.owner + 1) .. "P：") or ""
                for _, line in ipairs(layout.wrap(prefix .. message.text, panelWidth - 16, measure)) do
                    lines[#lines + 1] = { text = line, message = message }
                end
            end
            if ui.scroll > 0 then
                ui.scroll = ui.scroll + math.max(0, #lines - previousCount)
            end
            lastRevision, lastOpen = chat.revision, ui.input.open
        end
        if ui.input.open then
            local panelHeight = layout.expandedLines * layout.lineHeight + inputHeight + 10
            panel(
                x,
                bottom - panelHeight,
                panelWidth,
                panelHeight,
                backgroundAlpha,
                background,
                border
            )
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
                rows[#rows + 1] = { text = row.text, alpha = alpha }
            end
        end
        local y = bottom - (ui.input.open and inputHeight + 4 or 0) - #rows * layout.lineHeight
        if not ui.input.open and #rows > 0 then
            panel(
                x,
                y - 4,
                panelWidth,
                #rows * layout.lineHeight + 8,
                backgroundAlpha * backgroundFade,
                background,
                border
            )
        end
        for _, row in ipairs(rows) do
            text(row.text, x + 8, y, foreground, row.alpha)
            y = y + layout.lineHeight
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
                    input.limit and colors[1] or foreground
                )
            end
            native.chat_ui_caret(cursorX, bottom - 3, width, height)
        end
    end
    function ui.reset()
        native.emote_poll(0, false)
        native.chat_ui_reset()
        shownEmotes = {}
        ui.wheel, ui.scroll, lastRevision, lastEpoch = false, 0, -1, nil
        ui.input = { open = false, text = "", cursor = 0, anchor = 0 }
    end
    return ui
end
