local root = assert(arg[1])
local combat = dofile(root .. "/src/bridge/runtime/room_entry.lua")
local items = dofile(root .. "/src/bridge/compat/items/room_entry.lua")
local types = { ROOM_DEFAULT = 1, ROOM_BOSS = 5, ROOM_TREASURE = 4 }
local collectibles = { COLLECTIBLE_MERCURIUS = 590 }
local trinkets = { TRINKET_DOOR_STOP = 124 }
local flags = { STATE_SLOWER_ENEMIES = 24 }
local function room(kind)
    local result = { kind = kind, doors = {}, slow = 0, watch = 0, bossClosed = false }
    for slot, target in ipairs({ types.ROOM_DEFAULT, types.ROOM_BOSS, types.ROOM_TREASURE }) do
        local door = {
            TargetRoomType = target,
            opened = false,
            Position = {
                DistanceSquared = function(_, position)
                    return position == slot - 1 and 99 * 99 or 100 * 100
                end,
            },
        }
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
local function enter(destination, holders, slowFloor, stoppers, entry, nearDoor)
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
                EnterDoor = entry or -1,
                GetStateFlag = function(_, flag)
                    assert(flag == flags.STATE_SLOWER_ENEMIES)
                    return slowFloor
                end,
            }
        end,
    }
    items(game, function(index)
        return {
            Position = nearDoor,
            HasTrinket = function(_, id)
                assert(id == trinkets.TRINKET_DOOR_STOP)
                return stoppers and stoppers[index + 1] or false
            end,
            HasCollectible = function(_, id)
                assert(id == collectibles.COLLECTIBLE_MERCURIUS)
                return holders[index + 1]
            end,
        }
    end, types, collectibles, trinkets)
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
enter(ordinary, { false }, false, { true }, 2)
assert(ordinary.doors[2].opened, "Door Stop entry was overwritten by combat sealing")
assert(
    not ordinary.doors[0].opened and not ordinary.doors[1].opened,
    "Door Stop opened unrelated exits"
)
enter(boss, { false }, false, { true }, 0)
assert(boss.doors[0].opened, "Door Stop did not preserve the boss entrance")
enter(other, { false }, false, { false }, 0)
assert(not other.doors[0].opened, "Door Stop leaked into the resident's room")
enter(ordinary, { false }, false, { true }, -1)
assert(not ordinary.doors[2].opened, "A teleport reused a stale entrance")
enter(ordinary, { false }, false, { true }, -1, 1)
assert(ordinary.doors[1].opened, "A non-door arrival lost the native nearby-door exception")
assert(not ordinary.doors[0].opened and not ordinary.doors[2].opened)
enter(ordinary, { false }, false, { false }, -1, 1)
assert(not ordinary.doors[1].opened, "Removing Door Stop retained its entry exception")
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
