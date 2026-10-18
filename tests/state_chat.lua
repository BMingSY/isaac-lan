-- Two owned peers; exercise the production service, native executor and renderer.
local native = assert(_IsaacLan)
local file = assert(io.open("./lan-test-role.txt", "r"))
local host = file:read("*l") == "host"
file:close()
file = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = file:read("*l")
file:close()
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local frame = _IsaacLanFrame
local frames, playing, linked, chosen, done = 0, 0, false, false, false
local originalEmotePoll, originalEmoteShow = native.emote_poll, native.emote_show
local openedWheel, receivedEmotes = false, {}
local originalPointer, originalCaret = native.chat_ui_pointer, native.chat_ui_caret
local lastCaret, dragStart, dragDelta, wasDown
native.chat_ui_caret = function(x, y, ...)
    lastCaret = { x = x, y = y }
    return originalCaret(x, y, ...)
end
native.chat_ui_pointer = function(...)
    local value = originalPointer(...)
    if value.down and not wasDown then
        dragStart = lastCaret
    elseif wasDown and not value.down and dragStart and lastCaret then
        dragDelta = { x = lastCaret.x - dragStart.x, y = lastCaret.y - dragStart.y }
        report("CHAT drag delta=" .. dragDelta.x .. "," .. dragDelta.y)
    end
    wasDown = value.down
    return value
end
native.emote_poll = function(...)
    local value = originalEmotePoll(...)
    openedWheel = openedWheel or value.open
    return value
end
native.emote_show = function(owner, id)
    receivedEmotes[owner] = id
    assert(originalEmoteShow(owner, id), "Original player emote could not be applied")
    report("CHAT native emote owner=" .. owner .. " id=" .. id)
    return true
end
local function has(text)
    for _, message in ipairs(_IsaacLanChatMessages()) do
        if not message.command and message.text:find(text, 1, true) then
            return message
        end
    end
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    if status.phase == 4 or status.phase == 9 then
        report("FAILED " .. status.error)
    end
    if not status.prepared or status.phase ~= 3 or status.verified < 40 then
        return status
    end
    playing = playing + 1
    if playing == 1 then
        Options.FoundHUD, Options.ExtraHUDStyle, Options.HUDOffset = true, 1, 1
        for _, id in ipairs({ 2, 4, 5, 6, 7, 8, 9, 10 }) do
            assert(_IsaacLanChatSubmit("/c giveitem c" .. id))
        end
    end
    native.test_gamepad(0)
    if playing >= 570 and playing <= 635 then
        -- Aim inside the original D6 sector after the controller's axis deadzone.
        native.test_gamepad(playing == 630 and 4096 or 0, 0, 0, 29200, 21000)
    end
    if playing == 30 then
        local style = native.chat_style
        if style.image ~= "" then
            assert(
                style.image_width > 0 and style.image_height > 0,
                "Background preparation failed"
            )
            local background = Sprite()
            background:Load(style.image, true)
            assert(background:IsLoaded(), "Background ANM2 could not be loaded by the game")
            background:SetFrame("Idle", 0)
            local center = background:GetTexel(
                Vector(style.image_width / 2, style.image_height / 2),
                Vector.Zero
            )
            assert(center.Alpha > 0, "Background PNG is not visible in the native Sprite")
        else
            assert(
                style.image_width == 0 and style.image_height == 0,
                "Unexpected image dimensions"
            )
        end
        report(
            "CHAT background="
                .. style.image_width
                .. "x"
                .. style.image_height
                .. " opacity="
                .. style.opacity
        )
        assert(_IsaacLanChatSubmit(host and "/e HOST_PRIVATE" or "/echo GUEST_PRIVATE"))
        native.chat_ui_open(true)
        native.chat_ui_text("中文输入 /console help")
        report("VISUAL_READY")
    elseif playing == 180 and not host then
        assert(_IsaacLanChatSubmit("/c giveitem c1"))
        assert(_IsaacLanChatSubmit("/console lua Isaac.ConsoleOutput('NATIVE_PRIVATE_RESULT\\n')"))
    elseif playing == 300 then
        assert(
            _IsaacLanChatSubmit(
                host and "你好，准备出发！" or "队友已到，先去找宝箱。"
            )
        )
    elseif playing == 360 then
        assert(has(host and "HOST_PRIVATE" or "GUEST_PRIVATE"))
        assert(not has(host and "GUEST_PRIVATE" or "HOST_PRIVATE"))
        assert(has("你好，准备出发！") and has("队友已到，先去找宝箱。"))
        assert(
            Isaac.GetPlayer(0):GetCollectibleNum(1) == 0,
            "Native command changed host inventory"
        )
        assert(Isaac.GetPlayer(1):GetCollectibleNum(1) == 1, "Native command did not target guest")
        assert(
            (has("NATIVE_PRIVATE_RESULT") ~= nil) == not host,
            "Native console output visibility"
        )
        if not host then
            assert(_IsaacLanChatSubmit("/d20"))
        end
        report("CHAT native command and private output verified")
    elseif playing == 450 then
        local dice = assert(has("2P掷出 D20 : "), "Shared dice result missing")
        assert(dice.bubble and dice.owner == 1)
        report("CHAT dice=" .. dice.text)
        native.chat_ui_open(false)
    elseif playing == 540 then
        native.test_gamepad(128) -- Original R3 emote key.
    elseif playing == 600 then
        assert(openedWheel, "Original emote wheel did not open")
    elseif playing == 700 then
        assert(
            receivedEmotes[0]
                and receivedEmotes[1]
                and receivedEmotes[0] >= 23
                and receivedEmotes[0] <= 28
                and receivedEmotes[1] >= 23
                and receivedEmotes[1] <= 28,
            "Original D6 wheel did not send result IDs for both peers"
        )
    elseif playing == 720 then
        native.test_gamepad(64) -- L3 opens text input.
    elseif playing == 750 then
        assert(native.chat_ui_state().open, "L3 did not open chat")
        native.chat_ui_text("手柄打开聊天，键盘输入文字")
    elseif playing == 800 then
        native.chat_ui_open(false)
        native.chat_ui_text("")
        report("CHAT KEYBOARD_READY")
    elseif playing >= 900 and playing % 15 == 0 and not done then
        assert(playing < 5400, "Keyboard and drag check did not finish")
        local ready = io.open("./isaac-lan/chat-interaction.done", "r")
        if not ready then
            return status
        end
        ready:close()
        local typed = {}
        for _, message in ipairs(_IsaacLanChatMessages()) do
            if message.text == "a" or message.text == "A" then
                typed[message.owner] = true
            end
        end
        for _, message in ipairs(_IsaacLanChatMessages()) do
            if message.kind == "team" then
                report("CHAT typed owner=" .. message.owner .. " text=" .. message.text)
            end
        end
        assert(typed[0] and typed[1], "Keyboard chat was not submitted by both peers")
        assert(not native.chat_ui_state().open, "Tilde did not close chat")
        if host then
            assert(
                dragDelta and dragDelta.x >= 30 and dragDelta.y <= -10,
                "Real pointer did not move the chat panel"
            )
        end
        done = true
        report("PASS chat console")
    end
    return status
end
