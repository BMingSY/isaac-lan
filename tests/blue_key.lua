local root = assert(arg[1])
local leave = dofile(root .. "/src/bridge/compat/items/blue_key.lua")
local redirect, unrelated = 1 << 18, 1 << 4
local rooms = {
    [84] = { Flags = redirect | unrelated, Data = true },
    [85] = { Flags = redirect, Data = true },
    [86] = { Flags = redirect, Data = true },
}
local doors = { [0] = { TargetRoomIndex = 84 }, [2] = { TargetRoomIndex = 85 } }
local game = {
    GetRoom = function()
        return {
            GetDoor = function(_, slot)
                return doors[slot]
            end,
        }
    end,
    GetLevel = function()
        return {
            GetRoomByIdx = function(_, index)
                return rooms[index]
            end,
        }
    end,
}
leave(game, redirect)
assert(rooms[84].Flags == unrelated and rooms[85].Flags == 0)
assert(rooms[86].Flags == redirect, "Another room's Blue Key door was consumed")
leave(game, redirect)
assert(rooms[84].Flags == unrelated and rooms[85].Flags == 0)
-- A later unlock creates a new redirect; leaving that source consumes only it.
rooms[85].Flags = redirect
doors = { [1] = { TargetRoomIndex = 85 } }
leave(game, redirect)
assert(rooms[85].Flags == 0 and rooms[86].Flags == redirect)
-- New floors supply new descriptors; the compatibility component retains none.
rooms = { [85] = { Flags = unrelated, Data = true } }
leave(game, redirect)
assert(rooms[85].Flags == unrelated)
print("PASS Blue Key redirect consumption, other rooms, repeats, new unlocks and floor cleanup")
