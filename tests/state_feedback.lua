-- Both owned peers submit /feedback through the production chat path; the
-- runner's local receiver checks what was uploaded.
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
local description = host and "实机反馈 主机" or "实机反馈 客机"
local function count(text)
    local found, total = nil, 0
    for _, message in ipairs(_IsaacLanChatMessages()) do
        if not message.command and message.text:find(text, 1, true) then
            found, total = message, total + 1
        end
    end
    return found, total
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
    if playing == 30 and not host then
        -- The vanilla console has no feedback command; the runner checks
        -- that this reaches the host without an upload.
        assert(_IsaacLanChatSubmit("/c feedback 控制台不应上传"))
    elseif playing == 60 then
        assert(_IsaacLanChatSubmit("/feedback " .. description))
        local messages = _IsaacLanChatMessages()
        assert(
            count("正在收集日志并上传反馈"),
            "Submission was not acknowledged: " .. tostring(messages[#messages].text)
        )
        report("FEEDBACK submitted")
    elseif playing == 75 then
        assert(_IsaacLanChatSubmit("/fb 第二条应被拒绝"))
        assert(
            count("上一条反馈仍在上传") or count("反馈提交过于频繁"),
            "A second submission was not limited"
        )
    elseif playing >= 120 and playing % 15 == 0 and not done then
        assert(playing < 3600, "Feedback result did not arrive")
        for _, text in ipairs({
            "反馈未",
            "无法连接",
            "反馈打包失败",
            "反馈服务器",
        }) do
            local failed = count(text)
            assert(not failed, failed and failed.text)
        end
        local accepted, total = count("反馈已提交，编号 ")
        if not accepted then
            return status
        end
        assert(total == 1, "Another peer's result reached this chat")
        local id = assert(accepted.text:match("编号 (%d+%-%w+)"), "Feedback id missing")
        assert(accepted.owner == (host and 0 or 1) and not accepted.bubble)
        done = true
        report("FEEDBACK id=" .. id)
        report("PASS feedback")
    end
    return status
end
