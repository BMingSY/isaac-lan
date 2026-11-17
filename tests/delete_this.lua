local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/compat/challenges/delete_this.lua")
local tmtrainer, scoped, calls = 721, nil, { 0, 0 }
local seats = {}
for slot = 0, 1 do
    local player = { held = false }
    function player:HasCollectible(id)
        assert(id == tmtrainer)
        return self.held
    end
    function player:AddCollectible(id, charge, first)
        assert(id == tmtrainer and charge == 0 and first == false and scoped == slot)
        self.held = true
        calls[slot + 1] = calls[slot + 1] + 1
    end
    seats[slot + 1] = { slot = slot, player = player }
end
local failScope = false
local effect = factory({
    tmtrainer = tmtrainer,
    party = function(info)
        return info.connected == 1 and { seats[1] } or seats
    end,
    scoped = function(seat, fn)
        assert(not failScope, "fixture scope unavailable")
        scoped = seat.slot
        fn()
        scoped = nil
    end,
})
local info = { authority = 0, connected = 3 }
effect.initialize(info)
assert(calls[1] == 0 and calls[2] == 0, "Replica granted starting items")
info.authority, info.connected = 1, 1
effect.step(info)
effect.step(info)
assert(calls[1] == 1 and calls[2] == 0)
seats[1].player.held = false
effect.level(info)
effect.step(info)
assert(not seats[1].player.held, "A floor/repeated view undid a native item removal")
info.connected = 3
failScope = true
assert(not pcall(effect.step, info))
failScope = false
effect.step(info)
assert(calls[2] == 1, "Failed initialization could not retry the uninitialized seat")
effect.reset()
effect.initialize(info)
assert(calls[1] == 2 and calls[2] == 1, "Restart/checkpoint duplicated an existing starting item")
info.authority = 0
effect.reset()
seats[1].player.held = false
effect.initialize(info)
assert(not seats[1].player.held)
print("PASS Challenge 45 authority, independent seats, removal, floor, retry and reset boundaries")
