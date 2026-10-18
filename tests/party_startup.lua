local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/runtime/party.lua")
local players = { { ControllerIndex = 0 }, { ControllerIndex = 0 } }
local assigned, spawned = {}, {}
local heads = { ["0"] = 0, ["1"] = 2 }
local bind = factory({
    rooms_heads = function(restoredOrder)
        if restoredOrder then
            return { ["0"] = 0, ["1"] = 2 }
        end
        return heads
    end,
    input_assign = function(index, controller)
        assert(players[index + 1])
        players[index + 1].ControllerIndex = controller
        assigned[#assigned + 1] = { index, controller }
        return true
    end,
    players_spawn = function(kind, controller)
        assert(kind == 9 and controller == 2)
        spawned[#spawned + 1] = kind
        players[3] = { ControllerIndex = controller }
        return 2
    end,
}, function(index)
    return players[index + 1] or players[1]
end)
local status = { players = 2, character0 = 19, character1 = 9 }
bind(status, false)
assert(#spawned == 1 and players[1].ControllerIndex == 1 and players[3].ControllerIndex == 2)
-- A twin's native index is not a LAN slot; Continue can restore physical IDs.
players[1].ControllerIndex, players[3].ControllerIndex = 8, 11
bind(status, true, true)
assert(#spawned == 1 and assigned[2][1] == 0 and assigned[3][1] == 2)
assert(players[1].ControllerIndex == 1 and players[3].ControllerIndex == 2)
heads = { ["0"] = 0, ["1"] = 0 }
assert(not pcall(bind, status, true), "Duplicate guest reused the host actor")
heads = { ["0"] = 0 }
assert(not pcall(bind, status, true), "An absent guest was accepted through GetPlayer fallback")
print("PASS fresh party, companion indices, restored physical IDs and invalid owners")
