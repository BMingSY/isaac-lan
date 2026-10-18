local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/runtime/restart.lua")
local canRestart = true
local now, restarts, run = 0, 0, string.rep("a", 32)
local nodes = {}
local function setup(count)
    nodes, restarts, now = {}, 0, 0
    for slot = 0, count - 1 do
        local node = { inbox = {}, request = false }
        nodes[slot] = node
        node.status = {
            phase = 3,
            runId = run,
            hosting = slot == 0 and 1 or 0,
            slot = slot,
            players = count,
            connected = (1 << count) - 1,
            restarting = 0,
        }
        node.service = factory({
            running = 3,
            now = function()
                return now
            end,
            request = function()
                local v = node.request
                node.request = false
                return v
            end,
            send = function(destination, bytes)
                if node.blockSend then
                    return false
                end
                nodes[destination].inbox[#nodes[destination].inbox + 1] = { slot, bytes }
                return true
            end,
            receive = function()
                if #node.inbox > 0 then
                    return table.unpack(table.remove(node.inbox, 1))
                end
            end,
            restart = function()
                if not canRestart then
                    return false
                end
                restarts = restarts + 1
                return true
            end,
        })
    end
end
local function poll()
    for _ = 1, 3 do
        for slot = 0, #nodes do
            nodes[slot].service.poll(nodes[slot].status)
        end
    end
end
for count = 2, 4 do
    setup(count)
    poll()
    nodes[count - 1].request = true
    poll()
    assert(restarts == 0 and nodes[0].status.restartVotes == (1 << (count - 1)))
    nodes[count - 1].request = true
    poll()
    assert(restarts == 0, "Duplicate approval counted twice")
    for slot = 0, count - 2 do
        nodes[slot].request = true
    end
    poll()
    assert(restarts == 1, "Unanimous vote must commit exactly once")
    for slot = 0, count - 1 do
        nodes[slot].request = true
    end
    poll()
    assert(restarts == 1)
    -- Native Exit observes the new transport identity before the new game is
    -- ready. Its committed flag must not disable voting for the next run.
    for slot = 0, count - 1 do
        nodes[slot].status.runId = string.rep("c", 32)
        nodes[slot].status.restarting = 1
    end
    poll()
    for slot = 0, count - 1 do
        nodes[slot].status.restarting = 0
    end
    poll()
    for slot = 0, count - 1 do
        nodes[slot].request = true
    end
    poll()
    assert(restarts == 2, "Exit's committed state disabled the following run's vote")
end
setup(3)
poll()
nodes[1].request = true
nodes[1].service.poll(nodes[1].status)
local stale = nodes[0].inbox[1]
poll()
now = 20000
poll()
assert(nodes[0].status.restartVotes == 0 and nodes[2].status.restartVotes == 0)
nodes[0].inbox = { stale }
nodes[0].request = true
nodes[2].request = true
poll()
assert(restarts == 0, "Expired approval must not count in a new vote")
nodes[1].request = true
poll()
assert(restarts == 1)
-- The host retries initial state when a guest is still loading the new run.
setup(2)
nodes[0].blockSend = true
poll()
nodes[1].request = true
poll()
assert(restarts == 0 and nodes[0].status.restartVotes == 0)
nodes[0].blockSend = false
nodes[0].request = true
poll()
assert(restarts == 1, "A loading peer lost its pending approval or initial generation")
-- A checkpoint/floor boundary may temporarily prevent commit; retain consent.
setup(2)
poll()
canRestart = false
nodes[0].request, nodes[1].request = true, true
poll()
assert(restarts == 0 and nodes[0].status.restartVotes == 3)
canRestart = true
poll()
assert(restarts == 1)
-- Membership changes invalidate all approvals; departure alone cannot restart.
setup(3)
poll()
nodes[0].request, nodes[1].request = true, true
poll()
for slot = 0, 2 do
    nodes[slot].status.connected = 3
end
poll()
assert(restarts == 0 and nodes[0].status.restartVotes == 0)
nodes[0].request, nodes[1].request = true, true
poll()
assert(restarts == 1)
-- A new run, return to the menu, or an old packet cannot carry consent forward.
for slot = 0, 2 do
    nodes[slot].status.runId = string.rep("b", 32)
end
nodes[0].inbox = { stale }
poll()
assert(nodes[0].status.restartVotes == 0 and restarts == 1)
for slot = 0, 2 do
    nodes[slot].status.phase = 5
end
poll()
for slot = 0, 2 do
    nodes[slot].status.phase = 3
end
poll()
assert(nodes[0].status.restartVotes == 0)
print(
    "PASS restart consent: 2–4 seats, duplicates, expiry, stale packets, membership and new runs"
)
