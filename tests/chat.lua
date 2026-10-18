local root = assert(arg[1])
local wire = dofile(root .. "/src/bridge/runtime/chat_wire.lua")
local factory = dofile(root .. "/src/bridge/runtime/chat.lua")
local emoteCount = 59
local limits = { characters = 60, commandBytes = 2048, history = 200, dice = 1000000000 }
local now, rolls, executions = 100, 0, {}
local blocked, executeHook = {}, nil
local peers, inbox, packets = {}, { {}, {}, {} }, {}
for slot = 0, 2 do
    local info = {
        slot = slot,
        hosting = slot == 0 and 1 or 0,
        ready = 1,
        players = 3,
        connected = 7,
        runId = string.rep("r", 32),
        worldEpoch = 1,
    }
    local context = { index = 84, dimension = 0 }
    local function send(target, bytes)
        if blocked[slot .. ":" .. target] then
            return false
        end
        if slot ~= 0 and target ~= 0 then
            return false
        end
        local packet = { slot, bytes }
        inbox[target + 1][#inbox[target + 1] + 1] = packet
        packets[#packets + 1] = { target, packet }
        return true
    end
    local chat = factory({
        limits = limits,
        emotes = emoteCount,
        info = function()
            return info
        end,
        context = function()
            return context
        end,
        clock = function()
            return now
        end,
        nonce = function()
            return string.rep(tostring(slot), 32)
        end,
        send = send,
        receive = function()
            local packet = table.remove(inbox[slot + 1], 1)
            if packet then
                return table.unpack(packet)
            end
        end,
        execute = function(owner, text)
            executions[#executions + 1] = { owner, text }
            if executeHook then
                return executeHook(owner, text)
            end
            return "结果：" .. text
        end,
        roll = function(n)
            rolls = rolls + 1
            return n
        end,
        bot = function(args)
            return "bot " .. args
        end,
    }, wire)
    peers[slot + 1] = { chat = chat, info = info, context = context }
end
local function poll()
    for _, peer in ipairs(peers) do
        peer.chat.poll()
    end
end
local host, guest, other = peers[1].chat, peers[2].chat, peers[3].chat
assert(guest.submit("/e 只有我看到"))
assert(#guest.messages == 2 and #host.messages == 0 and #other.messages == 0)
assert(guest.messages[1].command and guest.messages[1].text == "/e 只有我看到")
assert(next(guest.bubbles) == nil)
assert(guest.submit("你好，队友"))
poll()
assert(#host.messages == 1 and #guest.messages == 3 and #other.messages == 1)
assert(guest.bubbles[1].text == "你好，队友" and host.bubbles[1].text == "你好，队友")
assert(guest.submit("/d20"))
local replay = packets[#packets][2]
poll()
inbox[1][#inbox[1] + 1] = replay
poll()
assert(rolls == 1 and host.bubbles[1].text == "2P掷出 D20 : 20")
assert(
    guest.bubbles[1].text == host.bubbles[1].text and other.bubbles[1].text == host.bubbles[1].text
)
local before = #other.messages
host.output("私有结果", { owner = 1, audience = "self", bubble = false })
poll()
assert(guest.messages[#guest.messages].text == "私有结果" and #other.messages == before)
host.output("共同结果", { owner = 1, audience = "party", bubble = true })
poll()
assert(
    other.messages[#other.messages].text == "共同结果"
        and other.bubbles[1].text == "共同结果"
)
assert(not guest.output("伪造广播", { audience = "party" }))
assert(guest.submit("/console unknown_native_command arbitrary arguments"))
poll()
host.step()
poll()
assert(executions[1][1] == 1 and executions[1][2] == "unknown_native_command arbitrary arguments")
assert(
    guest.messages[#guest.messages].text == "结果：unknown_native_command arbitrary arguments"
)
assert(#other.messages == before + 1)
assert(not guest.submit("/giveitem c1"))
assert(not guest.submit("/console"))
assert(guest.submit("/c giveitem c1"))
poll()
peers[1].info.worldEpoch = 2
host.step()
poll()
assert(#executions == 1 and guest.messages[#guest.messages].text:find("房间已变化"))
peers[2].info.worldEpoch = 2
local old = #guest.messages
assert(guest.sendEmote(1))
poll()
assert(#guest.messages == old and host.emotes[1].id == 1 and other.emotes[1].id == 1)
assert(not guest.sendEmote(emoteCount + 1))
assert(guest.submit(string.rep("中", 60)))
assert(not guest.submit(string.rep("中", 61)))
assert(
    not guest.submit("/d0") and not guest.submit("/d1000000001") and not guest.submit("/d20 extra")
)
assert(not guest.submit("bad\0text") and not guest.submit("\xc0\xaf"))
assert(guest.parse("/console lua " .. string.rep("x", 1000)).kind == "native")
assert(guest.parse('/console lua print("a  b", "/e hi")').text == 'lua print("a  b", "/e hi")')
assert(guest.parse("one\ntwo").text == "one two")
local encoded = wire.encodeRequest({
    sequence = 1,
    epoch = 1,
    room = 84,
    dimension = 0,
    nonce = string.rep("n", 32),
    run = string.rep("r", 32),
    text = "测试",
})
for i = 0, #encoded - 1 do
    assert(not pcall(wire.decode, encoded:sub(1, i)))
end
assert(not pcall(wire.decode, encoded .. "trailing"))
assert(wire.decode(encoded).text == "测试")
poll()
-- A congested recipient must see shared output in sequence when it recovers.
blocked["0:1"] = true
local guestBefore = #guest.messages
assert(host.output("queued first", { audience = "party" }))
assert(host.output("queued second", { audience = "party" }))
poll()
assert(#guest.messages == guestBefore)
assert(other.messages[#other.messages - 1].text == "queued first")
assert(other.messages[#other.messages].text == "queued second")
blocked["0:1"] = nil
poll()
assert(guest.messages[#guest.messages - 1].text == "queued first")
assert(guest.messages[#guest.messages].text == "queued second")
blocked["0:1"] = true
assert(host.output("expired result", { owner = 1 }))
now = now + 5001
poll()
blocked["0:1"] = nil
poll()
assert(guest.messages[#guest.messages].text == "queued second")
-- A room move invalidates a queued native command even within the same floor.
assert(guest.submit("/c giveitem c2"))
poll()
local executed = #executions
peers[1].context.index = 85
host.step()
poll()
assert(#executions == executed and guest.messages[#guest.messages].text:find("房间已变化"))
peers[1].context.index = 84
-- Synchronous output inherits the sender; failures must release that context.
executeHook = function()
    assert(host.output("command broadcast", { audience = "party", bubble = true }))
    error("native failure")
end
assert(guest.submit("/c failing command"))
poll()
host.step()
poll()
assert(other.bubbles[1].text == "command broadcast")
assert(guest.messages[#guest.messages].text:find("native failure"))
assert(host.output("after command"))
assert(host.messages[#host.messages].owner == 0)
executeHook = nil
assert(guest.parse("/d1").sides == 1 and guest.parse("/d1000000000").sides == 1000000000)
-- Silent native commands still leave an exact, private, non-bubble submission record.
executeHook = function()
    return ""
end
for _, peer in ipairs(peers) do
    peer.chat.clearBubbles()
end
local hostBefore, otherBefore = #host.messages, #other.messages
local guestBefore = #guest.messages
assert(guest.submit("/c g c333"))
local command = guest.messages[#guest.messages]
assert(
    command.command and command.text == "/c g c333" and command.owner == 1 and not command.bubble
)
assert(#guest.messages == guestBefore + 1)
local repeatedCommand = packets[#packets][2]
poll()
inbox[1][#inbox[1] + 1] = repeatedCommand
poll()
local executionsBefore = #executions
host.step()
host.step()
poll()
assert(#executions == executionsBefore + 1 and guest.messages[#guest.messages] == command)
assert(#host.messages == hostBefore and #other.messages == otherBefore)
assert(next(guest.bubbles) == nil and next(host.bubbles) == nil and next(other.bubbles) == nil)
local longestCommand = "/c " .. string.rep("x", limits.commandBytes - 3)
assert(host.submit(longestCommand))
host.step()
poll()
assert(
    host.messages[#host.messages].command and host.messages[#host.messages].text == longestCommand
)
assert(#guest.messages == guestBefore + 1 and #other.messages == otherBefore)
assert(host.submit("/d6"))
poll()
for _, peer in ipairs(peers) do
    assert(peer.chat.messages[#peer.chat.messages].text == "1P掷出 D6 : 6")
    assert(peer.chat.bubbles[0].text == "1P掷出 D6 : 6")
end
executeHook = nil
host.clearBubbles()
assert(next(host.bubbles) == nil and next(host.emotes) == nil and #host.messages > 0)
guest.reset()
assert(#guest.messages == 0 and next(guest.bubbles) == nil)
-- Help stays local, is available before game readiness, and never executes native commands.
local packetCount, executionCount = #packets, #executions
local hostCount, otherCount = #host.messages, #other.messages
local help
peers[2].info.ready = 0
for _, alias in ipairs({ "/h", "/help" }) do
    local first = #guest.messages + 1
    assert(guest.submit(alias))
    assert(guest.messages[first].command and guest.messages[first].text == alias)
    local lines = {}
    for index = first + 1, #guest.messages do
        local message = guest.messages[index]
        assert(message.kind == "system" and not message.bubble and message.owner == 1)
        lines[#lines + 1] = message.text
    end
    local result = table.concat(lines, "\n")
    for _, command in ipairs({
        "/h",
        "/help",
        "/e",
        "/echo",
        "/dN",
        "/c",
        "/console",
        "/c help",
        "/lanbot help",
    }) do
        assert(result:find(command, 1, true), "Help omitted " .. command)
    end
    assert(not help or help == result, "Help aliases returned different content")
    help = result
end
poll()
assert(#packets == packetCount and #executions == executionCount)
assert(#host.messages == hostCount and #other.messages == otherCount and next(guest.bubbles) == nil)
peers[2].info.ready = 1
local layout = dofile(root .. "/src/bridge/presentation/chat_layout.lua")
local function measure(text)
    return utf8.len(text) * 10
end
assert(table.concat(layout.wrap("你好世界abc", 20, measure), "|") == "你好|世界|ab|c")
local lines = layout.bubble(string.rep("中", 60), 100, measure)
assert(#lines == 3 and lines[3]:sub(-3) == "…")
local x, y = layout.anchor(1, 1, 100, 30, 480, 270)
assert(x == 4 and y == 4)
x, y = layout.anchor(480, 270, 100, 30, 480, 270)
assert(x + 100 <= 476 and y + 30 <= 266)
local occupied = {}
for _ = 1, 4 do
    local previous = #occupied
    local bx, by = layout.avoidOverlap(190, 140, 100, 30, 480, 270, occupied)
    assert(bx >= 4 and by >= 4 and bx + 100 <= 476 and by + 30 <= 266)
    for index = 1, previous do
        local other = occupied[index]
        assert(
            bx + 100 <= other.x
                or bx >= other.x + other.width
                or by + 30 <= other.y
                or by >= other.y + other.height
        )
    end
end
print(
    "PASS private command history, player dice labels, visibility, deduplication, native dispatch, stale world, emotes, bounds and layout"
)
