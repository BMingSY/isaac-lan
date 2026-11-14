-- Owned dual-peer visual check; keyboard events are covered by the native input test.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local function report(value)
    Isaac.DebugString("LAN_NETWORK CHAT_COMPLETION " .. value)
end
local cases = {
    { name = "commands", text = "/", tabs = 0, expected = "/" },
    { name = "cycle", text = "/", tabs = 7, expected = "/e " },
    { name = "teleport", text = "/tp bo", tabs = 1, expected = "/tp boss " },
    { name = "native", text = "/c g", tabs = 2, expected = "/c goto " },
    { name = "arguments", text = "/c giveitem c333", tabs = 0, expected = "/c giveitem c333" },
    { name = "mode", text = "/lanbot mode ", tabs = 1, expected = "/lanbot mode run " },
    { name = "ime", text = "/tp bo", tabs = 1, expected = "/tp bo", composing = true },
    { name = "selection", text = "/op", tabs = 1, expected = "/op", selected = true },
    { name = "text", text = "普通聊天 /tp bo", tabs = 0, expected = "普通聊天 /tp bo" },
}
local originalState = native.chat_ui_state
local frame = _IsaacLanFrame
report("LOADED")
local frames, chosen, linked, started, done = 0, false, false, false, false
local current, age, tabPending, baseline = 1, 0, false, nil
native.chat_ui_state = function()
    local value = originalState()
    if baseline and not done then
        local case = cases[current]
        if case.composing then
            value.composing, value.composition = true, "中"
        end
        if case.selected then
            value.anchor = 0
        end
        if tabPending then
            value.complete, tabPending = true, false
        end
    end
    return value
end
function _IsaacLanFrame()
    frames = frames + 1
    if frames == 1 then
        report("FIRST_FRAME")
    end
    if not linked and frames >= (host and 30 or 60) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
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
        and not started
    then
        started = true
        _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
    end
    assert(status.phase ~= 4, "Session failed during chat completion")
    if done or not status.prepared or status.phase ~= 3 or status.verified < 40 then
        return status
    end
    baseline = baseline or #_IsaacLanChatMessages()
    local case = cases[current]
    age = age + 1
    if age == 1 then
        native.chat_ui_open(false)
        Options.FoundHUD, Options.ExtraHUDStyle = false, 0
    elseif age == 3 then
        native.chat_ui_text(case.text)
        native.chat_ui_open(true)
        report("BEGIN case=" .. case.name)
    end
    if age >= 6 and age < 6 + case.tabs * 4 and (age - 6) % 4 == 0 then
        tabPending = true
    end
    if age == 12 + case.tabs * 4 then
        assert(originalState().text == case.expected, "Unexpected completed draft: " .. case.name)
        assert(#_IsaacLanChatMessages() == baseline, "Completion submitted a message or command")
        report("CHECKED case=" .. case.name .. " text=" .. case.expected)
    end
    if age == 80 then
        native.chat_ui_open(false)
        current, age = current + 1, 0
        if current > #cases then
            done = true
            native.chat_ui_state = originalState
            Isaac.DebugString("LAN_NETWORK PASS chat completion")
        end
    end
    return status
end
