local root = assert(arg[1])
local combat = dofile(root .. "/src/bridge/runtime/room_entry.lua")
local items = dofile(root .. "/src/bridge/compat/items/room_entry.lua")
local types = { ROOM_DEFAULT = 1, ROOM_BOSS = 5, ROOM_TREASURE = 4 }
local collectibles = { COLLECTIBLE_MERCURIUS = 590 }
local flags = { STATE_SLOWER_ENEMIES = 24 }
local function room(kind)
    local result = { kind = kind, doors = {}, slow = 0, watch = 0, bossClosed = false }
    for slot, target in ipairs({ types.ROOM_DEFAULT, types.ROOM_BOSS, types.ROOM_TREASURE }) do
        local door = { TargetRoomType = target, opened = false }
        function door:Close(force)
            assert(force)
            self.opened = false
        end
        function door:Open()
            self.opened = true
        end
        result.doors[slot - 1] = door
    end
    function result:IsClear()
        return false
    end
    function result:GetType()
        return self.kind
    end
    function result:GetDoor(slot)
        return self.doors[slot]
    end
    function result:SetBrokenWatchState(value)
        self.watch = value
    end
    function result:SetSlowDown(value)
        self.slow = value
    end
    return result
end
local function enter(destination, holders, slowFloor)
    -- The real lifecycle closes combat exits before applying item exceptions.
    combat(destination, types.ROOM_BOSS, function(r)
        r.bossClosed = true
    end, 17)
    local game = {
        GetRoom = function()
            return destination
        end,
        GetNumPlayers = function()
            return #holders
        end,
        GetLevel = function()
            return {
                GetStateFlag = function(_, flag)
                    assert(flag == flags.STATE_SLOWER_ENEMIES)
                    return slowFloor
                end,
            }
        end,
    }
    items(game, function(index)
        return {
            HasCollectible = function(_, id)
                assert(id == collectibles.COLLECTIBLE_MERCURIUS)
                return holders[index + 1]
            end,
        }
    end, types, collectibles)
end
local ordinary, boss, other =
    room(types.ROOM_DEFAULT), room(types.ROOM_BOSS), room(types.ROOM_DEFAULT)
enter(ordinary, { false, true }, false)
assert(ordinary.doors[0].opened, "Mercurius was overwritten by generic combat entry")
assert(not ordinary.doors[1].opened and not ordinary.doors[2].opened, "Special exits were unlocked")
enter(boss, { true }, false)
assert(not boss.doors[0].opened and boss.bossClosed, "Mercurius bypassed a boss seal")
enter(other, { false }, false)
assert(not other.doors[0].opened, "Mercurius leaked into a teammate's other room")
enter(ordinary, { false }, false)
assert(not ordinary.doors[0].opened, "Removing Mercurius retained its entry exception")
for _ = 1, 3 do
    enter(ordinary, { true }, true)
    enter(other, { false }, true)
    assert(ordinary.slow == 0x7fffffff and ordinary.watch == 1)
    assert(
        other.slow == ordinary.slow and other.watch == ordinary.watch,
        "Floor slow lost on reentry"
    )
end
local nextFloor = room(types.ROOM_DEFAULT)
enter(nextFloor, { false }, false)
assert(
    nextFloor.slow == 0 and nextFloor.watch == 0,
    "Previous-floor pill effect survived a new floor"
)
print("PASS item room entry: combat doors, scoped holder, repeated entry and floor slow lifetime")
