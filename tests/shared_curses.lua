local root = assert(arg[1])
local curses = dofile(root .. "/src/bridge/sync/curses.lua")
local candle = dofile(root .. "/src/bridge/compat/items/black_candle.lua")
local function level(value)
    local result = { value = value, additions = 0, removals = 0 }
    function result:GetCurses()
        return self.value
    end
    function result:AddCurse(mask, sound)
        assert(sound == false, "Replica must not replay pill or curse audio")
        self.value, self.additions = self.value | mask, self.additions + 1
    end
    function result:RemoveCurses(mask)
        self.value, self.removals = self.value & ~mask, self.removals + 1
    end
    return result
end
local host, guest = level(0), level(0)
for _, mask in ipairs({ 4, 32, 1 | 4 | 32 | 64, 0, 128, 0xffffffff, 0 }) do
    host.value = mask
    local captured, previous = curses.capture(host), guest.value
    assert(curses.apply(guest, captured) == (previous ~= captured))
    assert(guest.value == mask, "All peers must share the complete floor curse mask")
    local additions, removals = guest.additions, guest.removals
    assert(not curses.apply(guest, captured), "Repeated snapshots must be idempotent")
    assert(guest.additions == additions and guest.removals == removals)
end
-- A candle held by the remote owner must clear curses outside the host room.
local actors = { { [4] = { [2] = { { 1, 1 } } } }, { [4] = { [2] = { { 260, 1 } } } } }
host.value = 4 | 32 | 64
candle(host, actors, 260)
assert(host.value == 0)
curses.apply(guest, curses.capture(host))
assert(guest.value == 0)
host.value = 32
candle(host, actors, 260)
assert(host.value == 0, "A teammate's candle must also suppress later shared pill curses")
actors[2][4][2] = {}
host.value = 4
candle(host, actors, 260)
assert(host.value == 4, "Removing the candle must release its protection")
-- A native replica inventory setter can clear curses; authoritative state wins.
guest.value = 0
assert(curses.apply(guest, 4 | 32))
assert(guest.value == (4 | 32))
for _, bad in ipairs({ -1, 0x100000000, 1.5, math.huge, "4" }) do
    local before = guest.value
    assert(not pcall(curses.apply, guest, bad))
    assert(guest.value == before, "Invalid masks must not partially mutate the floor")
end
print("PASS shared floor curses, remote Black Candle and repeated snapshots")
