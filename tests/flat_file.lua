local root = assert(arg[1])
local make = dofile(root .. "/src/bridge/compat/items/flat_file.lua")
local info = { active = 1, authority = 1, ready = 1, connected = 3, players = 2 }
local positions = {
    ["0"] = { dimension = 0, index = 10 },
    ["1"] = { dimension = 0, index = 10 },
}
local holders = { [0] = false, [1] = true }
local rooms, current, roster = {}, nil, nil
local curse, normal, flatFile = 10, 1, 151
local function door(source, target)
    local value = {
        CurrentRoomType = source,
        TargetRoomType = target,
        VarData = 0,
        locked = true,
        target = 23,
        refreshes = 0,
    }
    function value:IsRoomType(kind)
        return self.CurrentRoomType == kind or self.TargetRoomType == kind
    end
    function value:SetRoomTypes(sourceType, targetType)
        assert(sourceType == self.CurrentRoomType and targetType == self.TargetRoomType)
        self.refreshes = self.refreshes + 1
        self.spikes = self.VarData == 0
    end
    return value
end
local function room(key, source, target)
    local value = { doors = { [0] = door(source, target), [1] = door(normal, normal) } }
    function value:GetDoor(slot)
        return self.doors[slot]
    end
    rooms[key] = value
    return value.doors[0]
end
local outside, inside, mirror =
    room("0:10", normal, curse), room("0:11", curse, normal), room("1:11", curse, normal)
local scopes = 0
local refresh = make({
    native = {
        api_info = function()
            return info
        end,
        rooms_positions = function()
            return positions
        end,
        rooms_with_player = function(slot, fn)
            assert(current == nil, "Nested room scope")
            local at = positions[tostring(slot)]
            current, roster = rooms[at.dimension .. ":" .. at.index], {}
            for actor = 0, info.players - 1 do
                local position = positions[tostring(actor)]
                if
                    (info.connected & (1 << actor)) ~= 0
                    and position.dimension == at.dimension
                    and position.index == at.index
                then
                    roster[#roster + 1] = actor
                end
            end
            scopes = scopes + 1
            fn()
            current, roster = nil, nil
            return true
        end,
    },
    game = function()
        return {
            GetNumPlayers = function()
                return #roster
            end,
            GetRoom = function()
                return current
            end,
        }
    end,
    player = function(index)
        return {
            HasTrinket = function(_, id)
                assert(id == flatFile)
                return holders[roster[index + 1]]
            end,
        }
    end,
    trinket = flatFile,
    curseRoom = curse,
    doorSlots = 8,
})
refresh()
assert(outside.VarData == 1 and not outside.spikes and scopes == 1)
refresh()
assert(outside.refreshes == 1, "Identical state restarted the door's animation")
-- The holder enters first; the source regains spikes and the destination loses them.
positions["1"].index = 11
refresh()
assert(outside.spikes and not inside.spikes, "Flat File leaked across rooms")
positions["0"].index = 11
refresh()
assert(not inside.spikes, "The second arrival overwrote the resident holder")
holders[0] = true
positions["1"].index = 10
refresh()
assert(not inside.spikes and not outside.spikes, "One holder leaving hid the remaining holder")
holders[0] = false
positions["1"].index = 11
refresh()
-- The non-holder can leave without restoring spikes for the remaining holder.
positions["0"].index = 10
refresh()
assert(not inside.spikes and outside.spikes)
positions["0"].index = 11
positions["1"].index = 10
refresh()
assert(inside.spikes and not outside.spikes, "Leaving holder did not restore the curse exit")
-- Same room index in another dimension is a separate audience.
positions["1"] = { dimension = 1, index = 11 }
refresh()
assert(inside.spikes and not mirror.spikes)
holders[1] = false
refresh()
assert(mirror.spikes, "Dropping Flat File retained its effect")
holders[0] = true
refresh()
assert(not inside.spikes)
info.connected = 2
positions["1"] = { dimension = 0, index = 11 }
refresh()
assert(inside.spikes, "A disconnected holder flattened the resident's doors")
-- New native doors after a floor/rewind must not reuse a previous door's cache.
inside = room("0:11", curse, normal)
holders[1] = true
refresh()
assert(not inside.spikes and inside.refreshes == 1)
for _, value in pairs(rooms) do
    assert(value.doors[1].refreshes == 0 and value.doors[1].VarData == 0)
    assert(value.doors[0].locked and value.doors[0].target == 23)
end
for _, field in ipairs({ "active", "authority", "ready" }) do
    local before = scopes
    info[field] = 0
    refresh()
    assert(scopes == before, "Inactive or replica execution changed gameplay")
    info[field] = 1
end
print("PASS Flat File: room holders, both directions, dimensions, inventory and reconnect cleanup")
