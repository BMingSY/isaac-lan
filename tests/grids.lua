local root = assert(arg[1])
local reconcile = dofile(root .. "/src/bridge/state/grids.lua")
local grids, events = {}, {}
local function grid(kind)
    return {
        GetType = function()
            return kind
        end,
    }
end
local env = {
    get = function(index)
        return grids[index]
    end,
    size = function()
        return 10
    end,
    remove = function(index)
        events[#events + 1] = "remove:" .. index
        grids[index] = nil
    end,
    spawn = function(value)
        assert(not grids[value[1]], "Replacement attempted before native removal")
        events[#events + 1] = "spawn:" .. value[1]
        grids[value[1]] = grid(value[2])
    end,
    apply = function(actual, value)
        actual.state = value[3]
    end,
}
grids[1], grids[2], grids[3] = grid(2), grid(2), grid(16)
local retained = grids[3]
reconcile({ { 1, 7, 4 }, { 3, 16, 1 } }, env)
assert(table.concat(events, ",") == "remove:1,spawn:1,remove:2")
assert(grids[1]:GetType() == 7 and grids[1].state == 4 and grids[2] == nil)
assert(grids[3] == retained, "Door allocation was replaced despite matching type")
events = {}
local replacement = grids[1]
reconcile({ { 1, 7, 5 }, { 3, 16, 2 } }, env)
assert(#events == 0 and grids[1] == replacement and grids[1].state == 5)
reconcile({}, env)
assert(next(grids) == nil)
env.spawn = function() end
assert(not pcall(reconcile, { { 1, 2, 0 } }, env), "Missing grid spawn silently accepted")
print("PASS grid replacement, retained door ownership, idempotency and removal")
