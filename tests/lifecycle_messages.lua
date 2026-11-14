local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/runtime/lifecycle_messages.lua")
local inbox, sent, allow = {}, {}, true
local messages = factory(function(slot, bytes)
    if not allow then
        return false
    end
    sent[#sent + 1] = { slot, bytes }
    inbox[#inbox + 1] = { slot, bytes }
    return true
end, function()
    if #inbox > 0 then
        return table.unpack(table.remove(inbox, 1))
    end
end)
assert(messages.restart.send(1, "restart") and messages.animation.send(2, "skip"))
inbox[#inbox + 1] = { 3, "" }
inbox[#inbox + 1] = { 3, string.char(99) .. "unknown" }
messages.poll()
local sender, bytes = messages.animation.receive()
assert(sender == 2 and bytes == "skip" and messages.animation.receive() == nil)
sender, bytes = messages.restart.receive()
assert(sender == 1 and bytes == "restart" and messages.restart.receive() == nil)
allow = false
assert(not messages.animation.send(0, "retry") and #sent == 2)
allow = true
assert(messages.restart.send(2, "next") and messages.restart.send(3, "last"))
messages.poll()
sender, bytes = messages.restart.receive()
assert(sender == 2 and bytes == "next")
sender, bytes = messages.restart.receive()
assert(sender == 3 and bytes == "last")
assert(messages.restart.receive() == nil)
print("PASS lifecycle ports preserve sender, order, retry and consumer isolation")
