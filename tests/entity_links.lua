local root = assert(arg[1])
local function entity(kind, index, stable)
    return {
        Type = kind,
        Index = index,
        stable = stable,
        Exists = function(self)
            return not self.removed
        end,
        GetSprite = function(self)
            return self
        end,
    }
end
local rider, source = entity(906, 8, 11), entity(965, 41, 12)
local replica, target = entity(906, 60, 11), entity(965, 13, 12)
local objects, writes = { rider, source }, 0
rider.cart = source
local component = dofile(root .. "/src/bridge/sync/entity_links.lua")({
    actor_held_entity = function(owner, held)
        if held == nil then
            return owner.held and owner.held.Index or -1
        end
        writes = writes + 1
        owner.held = held or nil
        return true
    end,
    entity_minecart = function(owner, cart)
        if cart == nil then
            return owner.cart and owner.cart.Index or -1
        end
        writes = writes + 1
        owner.cart = cart or nil
        return true
    end,
}, function()
    return objects
end)
local id = function(e)
    return e.stable
end
local ref = function(identifier)
    return identifier == 12 and target or nil
end
local value = component.capture(rider, id)
assert(value == 12 and value ~= source.Index)
component.apply(replica, value, ref)
assert(replica.cart == target and replica.cart.Index ~= source.Index)
component.apply(replica, value, ref)
source.removed = true
assert(component.capture(rider, id) == 0, "Retired cart escaped the room view")
component.apply(replica, 0, ref)
assert(replica.cart == nil)
local before = writes
assert(not pcall(component.apply, replica, 13, ref))
target.Type = 4
assert(not pcall(component.apply, replica, 12, ref))
assert(not pcall(component.apply, replica, -1, ref))
assert(writes == before, "Invalid reference changed the owner")
target.Type, target.Index = 965, 77
replica = entity(1, 99, 11) -- Players use the same link contract.
component.apply(replica, value, ref)
assert(replica.cart.Index == 77, "Room recreation reused the old allocation")
component.apply(replica, 0, ref)
print("PASS stable minecart links, repeat, retirement, recreated room, actors and validation")

local soul, skeleton = entity(1, 8, 21), entity(1, 41, 22)
local remoteSoul, remoteSkeleton = entity(1, 60, 21), entity(1, 13, 22)
objects = { soul, skeleton }
soul.held = skeleton
local lookup = function(identifier)
    return identifier == 22 and remoteSkeleton or nil
end
assert(component.captureHeld(soul, id) == 22)
component.applyHeld(remoteSoul, 22, lookup)
component.applyHeld(remoteSoul, 22, lookup)
assert(remoteSoul.held == remoteSkeleton)
skeleton.removed = true
assert(component.captureHeld(soul, id) == 0)
component.applyHeld(remoteSoul, 0, lookup)
assert(remoteSoul.held == nil)
assert(not pcall(component.applyHeld, remoteSoul, 21, function()
    return remoteSoul
end))
assert(not pcall(component.applyHeld, remoteSoul, 99, lookup))
assert(not pcall(component.applyHeld, remoteSoul, -1, lookup))
assert(not pcall(component.applyHeld, target, 22, lookup))
remoteSkeleton = entity(1, 77, 22)
component.applyHeld(remoteSoul, 22, lookup)
assert(remoteSoul.held.Index == 77)
component.applyHeld(remoteSoul, 0, lookup)
print("PASS held entity identity, repeat, retirement, release, recreated room and validation")
