local root = assert(arg[1])
local tick, shape, kind, scoped = 1, 1, 1, nil
local info = {
    active = 1,
    authority = 1,
    ready = 1,
    runId = "one",
    worldEpoch = 1,
    roomOptions = 2,
    players = 3,
    connected = 7,
}
local players = {}
local grants = {}
for slot = 0, 2 do
    local p = {
        slot = slot,
        charges = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 },
        trinkets = {},
        volt = false,
    }
    function p:HasTrinket(id)
        return (self.trinkets[id] or 0) > 0
    end
    function p:HasCollectible()
        return self.volt
    end
    function p:GetTrinketMultiplier(id)
        return self.trinkets[id] or 0
    end
    function p:GetTrinketRNG()
        return {
            RandomInt = function()
                return 0
            end,
        }
    end
    function p:GetActiveItem(s)
        return s < 3 and 1 or 0
    end
    function p:GetActiveCharge(s)
        return self.charges[s]
    end
    function p:GetSprite()
        return self
    end
    function p:FullCharge(s, forced)
        assert(scoped == self.slot and not forced)
        self.charges[s] = 6
    end
    players[slot] = p
end
local native = {
    api_info = function()
        return info
    end,
    net_room_options = function()
        return { { key = "sharedClearCharge", flag = 2 }, { key = "lootRoll", flag = 4 } }
    end,
    items_active_charge = function(p, s)
        assert(scoped == p.slot)
        return s == 1 and 1 or s == 2 and 2 or 0, 6
    end,
    items_add_active_charge = function(p, s, n)
        assert(scoped == p.slot)
        p.charges[s] = p.charges[s] + n
        grants[#grants + 1] = { slot = p.slot, n = n }
        return n
    end,
}
local clear = dofile(root .. "/src/bridge/compat/rules/clear_charge.lua")({
    native = native,
    game = function()
        return {
            GetFrameCount = function()
                return tick
            end,
            GetRoom = function()
                return {
                    GetRoomShape = function()
                        return shape
                    end,
                    GetType = function()
                        return kind
                    end,
                }
            end,
        }
    end,
    party = function(i)
        local seats = {}
        for slot = 0, 2 do
            if (i.connected & (1 << slot)) ~= 0 then
                seats[#seats + 1] = { slot = slot, actors = { players[slot] } }
            end
        end
        return seats
    end,
    scoped = function(seat, fn)
        scoped = seat.slot
        fn()
        scoped = nil
    end,
    enums = {
        shape = { ROOMSHAPE_2x2 = 8, ROOMSHAPE_LBR = 12 },
        room = { ROOM_BOSSRUSH = 17 },
        trinket = {
            TRINKET_OLD_CAPACITOR = 143,
            TRINKET_WATCH_BATTERY = 72,
            TRINKET_AAA_BATTERY = 3,
        },
        collectible = { COLLECTIBLE_4_5_VOLT = 647 },
        active = { SLOT_PRIMARY = 0, SLOT_POCKET2 = 3 },
        charge = { CHARGE_NORMAL = 0, CHARGE_TIMED = 1, CHARGE_SPECIAL = 2 },
    },
})
local rules = dofile(root .. "/src/bridge/runtime/room_rules.lua")({
    native = native,
    charge = clear,
    allocation = {
        reset = function() end,
        step = function()
            error("Dice disabled")
        end,
    },
})
rules.cleared(0, 0, 5)
rules.cleared(0, 0, 5) -- linked native body
rules.cleared(1, 0, 5) -- second occupant
rules.step()
assert(#grants == 1 and grants[1].slot == 2 and grants[1].n == 1)
assert(players[2].charges[1] == 6 and players[2].charges[2] == 0)
rules.step()
assert(#grants == 1, "Repeated step duplicated clear")
-- Two different rooms cleared on the same tick each contribute once.
shape = 8
tick = 2
rules.cleared(0, 0, 6)
rules.cleared(1, 0, 7)
rules.step()
assert(players[0].charges[0] == 2 and players[1].charges[0] == 2 and players[2].charges[0] == 5)
-- Recipient-specific native-clear modifiers; damage charging is not room charging.
players[1].volt = true
players[2].trinkets[3] = 1
shape = 1
tick = 3
rules.cleared(0, 0, 8)
rules.step()
assert(players[1].charges[0] == 2 and players[2].charges[0] == 7)
players[2].trinkets[143] = 1
local count = #grants
tick = 4
rules.cleared(0, 0, 8)
rules.step()
assert(#grants == count)
players[1].volt = false
players[2].trinkets = {}
-- Disconnected recipients, rewind and replica callbacks never create grants.
info.connected = 1
tick = 5
rules.cleared(0, 0, 9)
rules.step()
assert(#grants == count)
info.connected = 7
tick = 6
rules.cleared(0, 0, 9)
info.worldEpoch = 2
rules.step()
assert(#grants == count)
info.authority = 0
rules.cleared(0, 0, 9)
rules.step()
assert(#grants == count)
info.authority = 1
info.roomOptions = 0
rules.cleared(0, 0, 9)
rules.step()
assert(#grants == count)
-- A subsequent real wave/clear is eligible again, without persistent room dedup.
info.roomOptions = 2
tick = 7
rules.cleared(0, 0, 9)
rules.step()
assert(#grants == count + 2)
players[2].trinkets[72] = 2
tick = 8
rules.cleared(0, 0, 10)
rules.step()
assert(grants[#grants].n == 5, "Watch Battery uses recipient RNG and multiplier")
players[2].trinkets = {}
tick, shape, kind = 9, 8, 17
rules.cleared(0, 0, 10)
rules.step()
assert(grants[#grants].n == 1, "Boss Rush uses one charge despite its room shape")
print("PASS clear charge event dedup, separate rooms, slots, modifiers, waves and lifecycle")
