local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/runtime/animation_skip.lua")
local kinds = { none = 0, boss = 1, floor = 2, personal = 3 }
local nodes, authority, sent, count
local function setup(players)
    nodes, authority, sent, count = {}, {}, {}, players
    for slot = 0, players - 1 do
        local node = {
            inbox = {},
            skips = {},
            status = {
                phase = 3,
                hosting = slot == 0 and 1 or 0,
                slot = slot,
                players = players,
                connected = (1 << players) - 1,
                runId = string.rep("a", 32),
            },
            view = { kind = kinds.none, id = 0, epoch = 1, events = {}, floorReady = true },
        }
        nodes[slot] = node
        node.service = factory({
            running = 3,
            kinds = kinds,
            view = function()
                node.view.events = slot == 0 and authority or {}
                return node.view
            end,
            request = function()
                local requested = node.request
                node.request = false
                return requested
            end,
            skip = function(kind, id, epoch)
                if node.view.kind == kind and node.view.id == id and node.view.epoch == epoch then
                    node.skips[#node.skips + 1] = { kind, id, epoch }
                    node.view.kind, node.view.floorReady = kinds.none, true
                elseif slot ~= 0 or kind ~= kinds.boss then
                    return false
                end
                if slot == 0 and kind == kinds.boss then
                    for index = #authority, 1, -1 do
                        if authority[index].id == id then
                            table.remove(authority, index)
                        end
                    end
                end
                return true
            end,
            send = function(destination, bytes)
                if node.blockSend then
                    return false
                end
                sent[#sent + 1] = { sender = slot, destination = destination, bytes = bytes }
                nodes[destination].inbox[#nodes[destination].inbox + 1] = { slot, bytes }
                return true
            end,
            receive = function()
                if #node.inbox > 0 then
                    return table.unpack(table.remove(node.inbox, 1))
                end
            end,
        })
    end
end
local function watch(kind, id, members)
    authority[#authority + 1] = { kind = kind, id = id, members = members }
    for slot = 0, count - 1 do
        if (members & (1 << slot)) ~= 0 then
            nodes[slot].view.kind, nodes[slot].view.id = kind, id
            nodes[slot].view.floorReady = false
        end
    end
end
local function poll()
    for _ = 1, 3 do
        for slot = 0, count - 1 do
            nodes[slot].service.poll(nodes[slot].status)
        end
    end
end
for players = 2, 4 do
    for _, kind in ipairs({ kinds.boss, kinds.floor }) do
        setup(players)
        watch(kind, 1, (1 << players) - 1)
        poll()
        nodes[players - 1].request = true
        poll()
        assert(nodes[0].status.skipVotes == 1 << (players - 1))
        assert(#nodes[0].skips == 0, "One vote skipped a shared animation")
        nodes[players - 1].request = true
        poll()
        assert(#nodes[0].skips == 0, "Duplicate vote counted as another player")
        for slot = 0, players - 2 do
            nodes[slot].request = true
        end
        poll()
        for slot = 0, players - 1 do
            assert(#nodes[slot].skips == 1, "Unanimous consent did not skip every viewer")
            assert(nodes[slot].status.skipVotes == 0, "Finished animation retained its HUD")
        end
        poll()
        assert(#nodes[0].skips == 1, "Completion repeated")
    end
end
-- One guest in its own Boss room never needs the host's consent.
setup(4)
watch(kinds.boss, 8, 4)
nodes[2].request = true
poll()
assert(#nodes[2].skips == 1 and #nodes[0].skips == 0)
-- Simultaneous intros and non-viewers cannot share approvals.
setup(4)
watch(kinds.boss, 10, 3)
watch(kinds.boss, 11, 12)
poll()
nodes[0].request, nodes[2].request = true, true
poll()
assert(nodes[1].status.skipVotes == 1 and nodes[3].status.skipVotes == 4)
nodes[1].request = true
poll()
assert(#nodes[0].skips == 1 and #nodes[1].skips == 1 and #nodes[2].skips == 0)
nodes[3].request = true
poll()
assert(#nodes[2].skips == 1 and #nodes[3].skips == 1)
-- Joining viewers must vote; disconnected viewers no longer block the screen.
setup(3)
watch(kinds.boss, 20, 3)
poll()
nodes[0].request = true
poll()
authority[1].members = 7
nodes[2].view.kind, nodes[2].view.id = kinds.boss, 20
nodes[1].request = true
poll()
assert(#nodes[0].skips == 0 and nodes[0].status.skipMembers == 7)
for slot = 0, 2 do
    nodes[slot].status.connected = 3
end
poll()
assert(#nodes[0].skips == 1 and #nodes[1].skips == 1)
-- A finished viewer does not block a slower peer's floor skip.
setup(2)
watch(kinds.floor, 1, 3)
poll()
nodes[0].view.kind, nodes[0].view.floorReady = kinds.none, true
authority = {}
nodes[1].request = true
poll()
assert(#nodes[1].skips == 1 and #nodes[0].skips == 0)
-- A peer that has not received its floor transaction must not count as finished.
setup(2)
watch(kinds.floor, 1, 3)
nodes[1].view.kind, nodes[1].view.epoch, nodes[1].view.floorReady = kinds.none, 0, true
nodes[0].request = true
poll()
assert(#nodes[0].skips == 0)
nodes[1].view.kind, nodes[1].view.id, nodes[1].view.epoch = kinds.floor, 1, 1
nodes[1].view.floorReady, nodes[1].request = false, true
poll()
assert(#nodes[0].skips == 1 and #nodes[1].skips == 1)
-- Local intent survives a failed reliable send, but not an animation change.
setup(2)
watch(kinds.boss, 30, 3)
poll()
nodes[1].blockSend, nodes[1].request = true, true
nodes[0].request = true
poll()
assert(#nodes[0].skips == 0)
nodes[1].blockSend = false
poll()
assert(#nodes[0].skips == 1 and #nodes[1].skips == 1)
setup(2)
watch(kinds.boss, 40, 3)
poll()
nodes[1].request = true
nodes[1].service.poll(nodes[1].status)
local stale = nodes[0].inbox[1]
authority = {}
watch(kinds.boss, 41, 3)
poll()
nodes[0].request = true
poll()
assert(#nodes[0].skips == 0, "Old event approval skipped the following animation")
for slot = 0, 1 do
    nodes[slot].view.epoch = 2
end
authority = {}
watch(kinds.boss, 40, 3)
nodes[0].inbox = { stale }
nodes[0].request = true
poll()
assert(#nodes[0].skips == 0, "Old floor approval was reused")
for slot = 0, 1 do
    nodes[slot].view.epoch = 1
    nodes[slot].status.runId = string.rep("b", 32)
end
nodes[0].inbox = { stale }
nodes[0].request = true
poll()
assert(#nodes[0].skips == 0, "Old run approval was reused")
-- An unrelated peer cannot impersonate a viewer or publish an authority state.
setup(3)
watch(kinds.boss, 50, 3)
poll()
nodes[0].request = true
poll()
nodes[1].request = true
nodes[1].service.poll(nodes[1].status)
local spoof = table.remove(nodes[0].inbox, 1)
spoof[1] = 2
nodes[0].inbox = { spoof, { 1, "invalid" } }
poll()
assert(#nodes[0].skips == 0)
-- Native personal scenes use the same button without sending a team vote.
setup(2)
nodes[1].view.kind, nodes[1].view.id = kinds.personal, 1
nodes[1].request = true
poll()
assert(#nodes[1].skips == 1 and #sent == 0)
print(
    "PASS animation skip: viewers, unanimous 2/3/4, floors, late arrival, disconnect, stale consent"
)
